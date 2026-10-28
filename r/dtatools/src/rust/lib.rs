//! dtatools' bridge from R to the dta core.
//!
//! Rust never calls an R function that can raise an error: allocation,
//! building strings and setting attributes go through the C shims in
//! init.c, which turn an R error into a status. A failing shim makes us
//! return `Fail::R`, dropping everything we hold, and init.c then
//! resumes R's error. Every object is stored into an R object that is
//! already reachable (a list element or an attribute) as soon as it is
//! made, so nothing here needs PROTECT.

use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void, CStr};
use std::hash::{BuildHasherDefault, Hasher};
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{
    missing, Characteristic, Column, Dataset, Encoding, FileSource, Options, Reader, StorageType, ValueLabel,
    ValueLabelSet, Values, Variable, WriteVariable,
};

type Sexp = *mut c_void;

const STRSXP: c_int = 16;
const REALSXP: c_int = 14;
const VECSXP: c_int = 19;
const INTSXP: c_int = 13;
const LGLSXP: c_int = 10;

extern "C" {
    // R functions that cannot raise an error.
    fn REAL(x: Sexp) -> *mut f64;
    fn VECTOR_ELT(x: Sexp, i: isize) -> Sexp;
    fn STRING_ELT(x: Sexp, i: isize) -> Sexp;
    fn R_CHAR(x: Sexp) -> *const c_char;
    fn Rf_xlength(x: Sexp) -> isize;
    fn TYPEOF(x: Sexp) -> c_int;
    fn INTEGER(x: Sexp) -> *mut c_int;
    fn LOGICAL(x: Sexp) -> *mut c_int;
    static R_NaString: Sexp;
    // The shims in init.c; each returns 0, or 1 if R raised an error.
    fn dtatools_alloc_elt(parent: Sexp, i: isize, kind: c_int, n: isize, out: *mut Sexp) -> c_int;
    fn dtatools_alloc_attr(x: Sexp, name: *const c_char, kind: c_int, n: isize, out: *mut Sexp) -> c_int;
    fn dtatools_set_strings(x: Sexp, first: isize, bytes: *const u8, ends: *const usize, n: isize) -> c_int;
    #[allow(clippy::too_many_arguments)]
    fn dtatools_packed_elt(
        parent: Sexp,
        i: isize,
        nbytes: isize,
        n: isize,
        rows: isize,
        out: *mut Sexp,
        bytes: *mut Sexp,
        ends: *mut Sexp,
        codes: *mut Sexp,
    ) -> c_int;
    fn RAW(x: Sexp) -> *mut u8;
    fn dtatools_interrupted() -> c_int;
}

/// Why a call failed: our own message, or an R error waiting in init.c.
enum Fail {
    Message(String),
    R,
}

type Res<T> = Result<T, Fail>;

impl From<dta::Error> for Fail {
    fn from(e: dta::Error) -> Self {
        Fail::Message(e.to_string())
    }
}

fn status(code: c_int) -> Res<()> {
    if code == 0 {
        Ok(())
    } else {
        Err(Fail::R)
    }
}

/// A new vector, stored as element `i` of the list `parent`.
fn alloc_elt(parent: Sexp, i: usize, kind: c_int, n: usize) -> Res<Sexp> {
    let mut out = std::ptr::null_mut();
    status(unsafe { dtatools_alloc_elt(parent, i as isize, kind, n as isize, &mut out) })?;
    Ok(out)
}

/// A packed string column (see strings.c), as element `i` of the list
/// `parent`, holding the gathered strings.
fn packed_elt(parent: Sexp, i: usize, s: &Strings) -> Res<Sexp> {
    let (mut x, mut b, mut e, mut c) =
        (std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut());
    let n = s.ends.len();
    let rows = s.dict.as_ref().map_or(-1, |d| d.codes.len() as isize);
    status(unsafe {
        dtatools_packed_elt(parent, i as isize, s.bytes.len() as isize, n as isize, rows, &mut x, &mut b, &mut e, &mut c)
    })?;
    unsafe {
        std::slice::from_raw_parts_mut(RAW(b), s.bytes.len()).copy_from_slice(&s.bytes);
        for (d, &end) in std::slice::from_raw_parts_mut(REAL(e), n).iter_mut().zip(&s.ends) {
            *d = end as f64;
        }
        if let Some(d) = &s.dict {
            std::slice::from_raw_parts_mut(INTEGER(c), d.codes.len()).copy_from_slice(&d.codes);
        }
    }
    Ok(x)
}

/// A new vector, attached to `x` as attribute `name`.
fn alloc_attr(x: Sexp, name: &CStr, kind: c_int, n: usize) -> Res<Sexp> {
    let mut out = std::ptr::null_mut();
    status(unsafe { dtatools_alloc_attr(x, name.as_ptr(), kind, n as isize, &mut out) })?;
    Ok(out)
}

/// Fill `x[first..]` with strings given as bytes and end offsets.
fn set_strings(x: Sexp, first: usize, bytes: &[u8], ends: &[usize]) -> Res<()> {
    status(unsafe { dtatools_set_strings(x, first as isize, bytes.as_ptr(), ends.as_ptr(), ends.len() as isize) })
}

fn set_strs<S: AsRef<str>>(x: Sexp, v: &[S]) -> Res<()> {
    let mut bytes = Vec::new();
    let mut ends = Vec::with_capacity(v.len());
    for s in v {
        bytes.extend_from_slice(s.as_ref().as_bytes());
        ends.push(bytes.len());
    }
    set_strings(x, 0, &bytes, &ends)
}

fn strings_elt<S: AsRef<str>>(parent: Sexp, i: usize, v: &[S]) -> Res<()> {
    let x = alloc_elt(parent, i, STRSXP, v.len())?;
    set_strs(x, v)
}

fn doubles_elt(parent: Sexp, i: usize, v: &[f64]) -> Res<()> {
    let x = alloc_elt(parent, i, REALSXP, v.len())?;
    unsafe { std::slice::from_raw_parts_mut(REAL(x), v.len()) }.copy_from_slice(v);
    Ok(())
}

fn string_attr(x: Sexp, name: &CStr, value: &str) -> Res<()> {
    let a = alloc_attr(x, name, STRSXP, 1)?;
    set_strs(a, &[value])
}

/// A list of `names.len()` elements, named, as element `i` of `parent`.
fn named_list(parent: Sexp, i: usize, names: &[&str]) -> Res<Sexp> {
    let x = alloc_elt(parent, i, VECSXP, names.len())?;
    let n = alloc_attr(x, c"names", STRSXP, names.len())?;
    set_strs(n, names)?;
    Ok(x)
}

/// R's NA_real_: a NaN whose low word is 1954.
const NA_BITS: u64 = 0x7ff0_0000_0000_07a2;

/// The R double for a value and its missing code: `.` is NA_real_, and
/// `.a` to `.z` are NA_real_ with the letter in bits 32 to 39, the
/// layout haven's `tagged_na()` uses.
fn r_double(value: f64, code: u8) -> f64 {
    match code {
        0 => value,
        missing::SYSTEM => f64::from_bits(NA_BITS),
        _ => f64::from_bits(NA_BITS | (((b'a' + code - 2) as u64) << 32)),
    }
}

/// # Safety
/// `s` is NULL or a NUL-terminated string.
unsafe fn c_str(s: *const c_char) -> Option<String> {
    (!s.is_null()).then(|| CStr::from_ptr(s).to_string_lossy().into_owned())
}

fn open(path: &str, encoding: Option<String>) -> Res<Reader<FileSource>> {
    let encoding = match encoding {
        Some(name) => {
            Encoding::from_name(&name).ok_or_else(|| Fail::Message(format!("unknown encoding \"{name}\"")))?
        }
        None => Encoding::default(),
    };
    let source = FileSource::open(path).map_err(|e| Fail::Message(format!("{path}: {e}")))?;
    Reader::open(source, Options { encoding }).map_err(|e| Fail::Message(format!("{path}: {e}")))
}

/// Run `f`; 0 if it succeeded, 1 with a message in `err`, 2 if an R
/// error waits in init.c. A panic becomes a message.
fn guard(err: *mut c_char, err_len: usize, f: impl FnOnce() -> Res<()>) -> c_int {
    let message = match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => return 0,
        Ok(Err(Fail::R)) => return 2,
        Ok(Err(Fail::Message(m))) => m,
        Err(_) => "internal error in dtatools".to_string(),
    };
    let bytes = message.as_bytes();
    let n = bytes.len().min(err_len.saturating_sub(1));
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), err as *mut u8, n);
        *err.add(n) = 0;
    }
    1
}

/// The header, descriptors, notes and value label sets of a file, as
/// element 0 of `holder`.
///
/// # Safety
/// The pointers come from init.c.
#[no_mangle]
pub unsafe extern "C" fn dtatools_meta(
    path: *const c_char,
    encoding: *const c_char,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let encoding = c_str(encoding);
    guard(err, err_len, || {
        let mut reader = open(&path, encoding)?;
        let notes = reader.notes()?;
        let sets = reader.value_labels()?;
        let meta = reader.metadata();
        let vars = &meta.variables;
        let names = [
            "release", "nobs", "label", "timestamp", "names", "storage", "formats", "var_labels", "label_sets",
            "sort_order", "notes", "value_labels",
        ];
        let out = named_list(holder, 0, &names)?;
        doubles_elt(out, 0, &[meta.release as f64])?;
        doubles_elt(out, 1, &[meta.nobs as f64])?;
        strings_elt(out, 2, &[&meta.label])?;
        strings_elt(out, 3, &[&meta.timestamp])?;
        strings_elt(out, 4, &vars.iter().map(|v| v.name.as_str()).collect::<Vec<_>>())?;
        strings_elt(out, 5, &vars.iter().map(|v| v.storage.name()).collect::<Vec<_>>())?;
        strings_elt(out, 6, &vars.iter().map(|v| v.format.as_str()).collect::<Vec<_>>())?;
        strings_elt(out, 7, &vars.iter().map(|v| v.label.as_str()).collect::<Vec<_>>())?;
        strings_elt(out, 8, &vars.iter().map(|v| v.value_labels.as_str()).collect::<Vec<_>>())?;
        doubles_elt(out, 9, &meta.sort_order.iter().map(|&i| (i + 1) as f64).collect::<Vec<_>>())?;
        strings_elt(out, 10, &notes)?;
        let set_names: Vec<&str> = sets.iter().map(|s| s.name.as_str()).collect();
        let list = named_list(out, 11, &set_names)?;
        for (i, set) in sets.iter().enumerate() {
            let entry = named_list(list, i, &["codes", "texts"])?;
            let codes: Vec<f64> = set.labels.iter().map(|l| r_double(l.value, l.missing)).collect();
            doubles_elt(entry, 0, &codes)?;
            strings_elt(entry, 1, &set.labels.iter().map(|l| l.text.as_str()).collect::<Vec<_>>())?;
        }
        Ok(())
    })
}

/// The attributes `read_dta` documents: `label` and `format` on every
/// column; `storage`, `labels`, `label_set` and class `dta_num` on
/// numeric ones. Set here rather than in R so R does not copy the
/// column to change them.
fn set_attributes(x: Sexp, var: &Variable, set: Option<&ValueLabelSet>) -> Res<()> {
    if !var.label.is_empty() {
        string_attr(x, c"label", &var.label)?;
    }
    string_attr(x, c"format", &var.format)?;
    if var.storage.is_numeric() {
        string_attr(x, c"storage", &var.storage.name())?;
        if let Some(set) = set {
            let codes = alloc_attr(x, c"labels", REALSXP, set.labels.len())?;
            let values: Vec<f64> = set.labels.iter().map(|l| r_double(l.value, l.missing)).collect();
            unsafe { std::slice::from_raw_parts_mut(REAL(codes), values.len()) }.copy_from_slice(&values);
            let texts = alloc_attr(codes, c"names", STRSXP, set.labels.len())?;
            set_strs(texts, &set.labels.iter().map(|l| l.text.as_str()).collect::<Vec<_>>())?;
            string_attr(x, c"label_set", &set.name)?;
        }
        string_attr(x, c"class", "dta_num")?;
    }
    Ok(())
}

/// The columns at 0-based `cols`, all rows, as element 0 of `holder`
/// (a list). Checks for Ctrl-C between chunks.
///
/// # Safety
/// The pointers come from init.c; `cols` holds `ncols` ints.
#[no_mangle]
pub unsafe extern "C" fn dtatools_read(
    path: *const c_char,
    cols: *const c_int,
    ncols: isize,
    encoding: *const c_char,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let encoding = c_str(encoding);
    let cols = std::slice::from_raw_parts(cols, ncols.max(0) as usize).to_vec();
    guard(err, err_len, || {
        let cols: Vec<usize> = cols
            .iter()
            .map(|&i| usize::try_from(i).map_err(|_| Fail::Message("negative column index".into())))
            .collect::<Res<_>>()?;
        let mut reader = open(&path, encoding)?;
        let sets = reader.value_labels()?;
        let meta = reader.metadata().clone();
        let nobs = usize::try_from(meta.nobs).map_err(|_| Fail::Message("too many rows".into()))?;
        let out = alloc_elt(holder, 0, VECSXP, cols.len())?;
        let limits = DictLimits::from_env();
        let mut targets = Vec::with_capacity(cols.len());
        for (k, &c) in cols.iter().enumerate() {
            let var = meta.variables.get(c).ok_or_else(|| Fail::Message(format!("there is no column {}", c + 1)))?;
            // Numeric columns are filled in place; string columns gather
            // their text here and become packed columns after the read.
            let target = if var.storage.is_numeric() {
                let x = alloc_elt(out, k, REALSXP, nobs)?;
                set_attributes(x, var, sets.iter().find(|s| s.name == var.value_labels))?;
                Target::Numbers(x)
            } else {
                Target::Strings(Strings::new(limits, nobs))
            };
            targets.push((target, var));
        }
        // A failure inside the chunk callback, kept so an R error stays one.
        let mut failed: Option<Fail> = None;
        let result = reader.read_chunks(&cols, 0, meta.nobs, None, |first, chunk| {
            if unsafe { dtatools_interrupted() } != 0 {
                failed = Some(Fail::Message("interrupted".into()));
                return Err(dta::Error::new("interrupted"));
            }
            for ((target, var), column) in targets.iter_mut().zip(chunk) {
                let step = match (target, column) {
                    (Target::Numbers(x), Column::Numbers { values, missing }) => {
                        let dst = unsafe { std::slice::from_raw_parts_mut(REAL(*x).add(first), values.len()) };
                        for ((d, &v), &m) in dst.iter_mut().zip(values).zip(missing) {
                            *d = r_double(v, m);
                        }
                        Ok(())
                    }
                    (Target::Strings(s), Column::Strings { bytes, ends, binary }) => {
                        s.gather(&var.name, bytes, ends, binary)
                    }
                    _ => Err(Fail::Message("internal: column kinds differ".into())),
                };
                if let Err(fail) = step {
                    failed = Some(fail);
                    return Err(dta::Error::new("stopped"));
                }
            }
            Ok(())
        });
        match (result, failed) {
            (_, Some(fail)) => return Err(fail),
            (Err(e), None) => return Err(e.into()),
            (Ok(_), None) => {}
        }
        for (k, (target, var)) in targets.into_iter().enumerate() {
            if let Target::Strings(mut s) = target {
                if let Some(d) = &mut s.dict {
                    d.table = HashMap::default();
                    d.next = Vec::new();
                }
                let x = packed_elt(out, k, &s)?;
                drop(s);
                set_attributes(x, var, None)?;
            }
        }
        Ok(())
    })
}

/// Where a column read by `dtatools_read` goes.
enum Target {
    /// The R double vector it fills.
    Numbers(Sexp),
    /// The strings gathered so far.
    Strings(Strings),
}

/// When a string column stops building a dictionary (see `Strings`).
#[derive(Clone, Copy)]
struct DictLimits {
    /// Rows seen before the share of distinct values is judged.
    window: usize,
    /// The most distinct values a dictionary may hold.
    limit: usize,
}

impl DictLimits {
    /// The defaults, or smaller values from `DTATOOLS_DICT_WINDOW` and
    /// `DTATOOLS_DICT_LIMIT`, which the tests set.
    fn from_env() -> Self {
        let get = |name: &str, default: usize| {
            std::env::var(name).ok().and_then(|v| v.parse().ok()).map_or(default, |v: usize| v.min(default))
        };
        DictLimits { window: get("DTATOOLS_DICT_WINDOW", 65_536), limit: get("DTATOOLS_DICT_LIMIT", i32::MAX as usize) }
    }
}

/// A string column's text as it is read. While `dict` is set, `bytes`
/// and `ends` hold the distinct values in order of first appearance and
/// `dict.codes` each row's index among them, so R will make one string
/// per distinct value. A column whose values are mostly distinct gives
/// the dictionary up: `bytes` and `ends` then hold every row's value.
struct Strings {
    bytes: Vec<u8>,
    ends: Vec<usize>,
    dict: Option<Dict>,
    limits: DictLimits,
    /// The column's row count, to reserve per-row vectors once.
    rows: usize,
}

struct Dict {
    codes: Vec<i32>,
    /// Recently seen values by their quick hash's top bits: a hit skips
    /// the table (most rows, when there are few distinct values).
    front: Vec<Front>,
    /// A value's hash to the newest entry with that hash; `next` chains
    /// to older entries with the same hash (`NONE` ends a chain).
    table: HashMap<u64, u32, BuildHasherDefault<Mixed>>,
    next: Vec<u32>,
}

const NONE: u32 = u32::MAX;

/// A front cache slot: a dictionary index, and for a value of at most
/// eight bytes its bytes as a word, so a hit needs no other memory.
#[derive(Clone, Copy)]
struct Front {
    index: u32,
    len: u32,
    word: u64,
}
/// The longest chain a lookup may walk; a longer one (only a file built
/// to make values collide) makes the column give up its dictionary.
const MAX_CHAIN: usize = 32;
/// Slots in `Dict::front`.
const FRONT: usize = 4096;

impl Strings {
    fn new(limits: DictLimits, rows: usize) -> Self {
        let dict = Dict { codes: Vec::with_capacity(rows), front: vec![Front { index: NONE, len: 0, word: 0 }; FRONT], table: HashMap::default(), next: Vec::new() };
        Strings { bytes: Vec::new(), ends: Vec::new(), dict: Some(dict), limits, rows }
    }

    fn value(&self, i: usize) -> &[u8] {
        let from = if i == 0 { 0 } else { self.ends[i - 1] };
        &self.bytes[from..self.ends[i]]
    }

    fn push(&mut self, v: &[u8]) {
        self.bytes.extend_from_slice(v);
        self.ends.push(self.bytes.len());
    }

    /// Append a chunk, checking that R can hold every value.
    fn gather(&mut self, name: &str, bytes: &[u8], ends: &[usize], binary: &[bool]) -> Res<()> {
        if binary.iter().any(|&b| b) {
            return Err(Fail::Message(format!("{name} holds binary strLs, which dtatools does not read")));
        }
        if bytes.contains(&0) {
            return Err(Fail::Message(format!("{name} holds a string with an embedded nul, which R cannot hold")));
        }
        let mut from = 0;
        for (k, &end) in ends.iter().enumerate() {
            if end - from > i32::MAX as usize {
                return Err(Fail::Message(format!("{name} holds a string longer than R allows")));
            }
            if self.dict.is_none() {
                // Plain: the rest of the chunk in one copy.
                let base = self.bytes.len() - from;
                for (j, &e) in ends[k..].iter().enumerate() {
                    let start = if k + j == 0 { 0 } else { ends[k + j - 1] };
                    if e - start > i32::MAX as usize {
                        return Err(Fail::Message(format!("{name} holds a string longer than R allows")));
                    }
                    self.ends.push(base + e);
                }
                self.bytes.extend_from_slice(&bytes[from..]);
                return Ok(());
            }
            let v = &bytes[from..end];
            from = end;
            if !self.add_coded(v) {
                self.push(v);
            }
        }
        Ok(())
    }

    /// Add a row through the dictionary; false if the dictionary was
    /// given up, leaving the row to be added plain.
    fn add_coded(&mut self, v: &[u8]) -> bool {
        let word = if v.len() <= 8 { short_word(v) } else { 0 };
        let quick = quick_hash(v, word);
        let slot = (quick.wrapping_mul(0x9e37_79b9_7f4a_7c15) >> (64 - FRONT.trailing_zeros())) as usize;
        let cached = self.dict.as_ref().expect("a dictionary").front[slot];
        let short = v.len() <= 8;
        if cached.index != NONE
            && cached.len as usize == v.len()
            && (if short { cached.word == word } else { self.value(cached.index as usize) == v })
        {
            self.dict.as_mut().expect("a dictionary").codes.push(cached.index as i32);
            return true;
        }
        let entry = |index: u32| Front { index, len: v.len() as u32, word };
        let hash = mix(quick);
        let found = match self.lookup(v, hash) {
            Some(found) => found,
            None => {
                self.give_up();
                return false;
            }
        };
        let d = self.dict.as_mut().expect("a dictionary");
        if let Some(index) = found {
            d.front[slot] = entry(index);
            d.codes.push(index as i32);
            return true;
        }
        // A new distinct value.
        let (rows, distinct) = (d.codes.len() + 1, self.ends.len() + 1);
        if distinct > self.limits.limit || (rows >= self.limits.window && distinct * 2 > rows) {
            self.give_up();
            return false;
        }
        let index = self.ends.len() as u32;
        d.next.push(d.table.insert(hash, index).unwrap_or(NONE));
        d.front[slot] = entry(index);
        d.codes.push(index as i32);
        self.push(v);
        true
    }

    /// The dictionary index of `v`: `Some(None)` if it is new, `None` if
    /// the chain to walk is too long.
    fn lookup(&self, v: &[u8], hash: u64) -> Option<Option<u32>> {
        let d = self.dict.as_ref().expect("a dictionary");
        let mut at = d.table.get(&hash).copied().unwrap_or(NONE);
        for _ in 0..=MAX_CHAIN {
            if at == NONE {
                return Some(None);
            }
            if self.value(at as usize) == v {
                return Some(Some(at));
            }
            at = d.next[at as usize];
        }
        None
    }

    /// Replace the dictionary by every row's value, written out plain.
    fn give_up(&mut self) {
        let d = self.dict.take().expect("a dictionary");
        let mut plain = Strings {
            bytes: Vec::new(),
            ends: Vec::with_capacity(self.rows),
            dict: None,
            limits: self.limits,
            rows: self.rows,
        };
        for &c in &d.codes {
            plain.push(self.value(c as usize));
        }
        self.bytes = plain.bytes;
        self.ends = plain.ends;
    }
}

/// A quick hash of a value, eight bytes at a time (multiply and rotate,
/// as rustc's FxHash, like the writer's). Its low bits are weak; `mix`
/// it for a table, or take its top bits after a multiply.
/// `word` is `short_word(v)` when `v` is at most eight bytes.
fn quick_hash(v: &[u8], word: u64) -> u64 {
    let mut h = v.len() as u64;
    let mut add = |w: u64| h = (h.rotate_left(5) ^ w).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    if v.len() <= 8 {
        add(word);
        return h;
    }
    let mut chunks = v.chunks_exact(8);
    for c in &mut chunks {
        add(u64::from_le_bytes(c.try_into().unwrap_or_default()));
    }
    add(short_word(chunks.remainder()));
    h
}

/// The bytes of `v` (at most eight) as a little-endian word, zero-padded:
/// two values of one length are equal exactly when their words are.
fn short_word(v: &[u8]) -> u64 {
    let n = v.len();
    let u16_at = |i: usize| u16::from_le_bytes([v[i], v[i + 1]]) as u64;
    let u32_at = |i: usize| u32::from_le_bytes([v[i], v[i + 1], v[i + 2], v[i + 3]]) as u64;
    match n {
        0 => 0,
        1 => v[0] as u64,
        2 => u16_at(0),
        3 => u16_at(0) | (v[2] as u64) << 16,
        // Two overlapping reads; the overlap holds the same bytes.
        4..=7 => u32_at(0) | u32_at(n - 4) << (8 * (n - 4)),
        _ => u64::from_le_bytes([v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]]),
    }
}

/// MurmurHash3's 64-bit finalizer: every bit of the result depends on
/// every bit of `h`.
fn mix(mut h: u64) -> u64 {
    h ^= h >> 33;
    h = h.wrapping_mul(0xff51_afd7_ed55_8ccd);
    h ^= h >> 33;
    h = h.wrapping_mul(0xc4ce_b9fe_1a85_ec53);
    h ^ (h >> 33)
}

/// A hasher for keys that are already hashes.
#[derive(Default)]
struct Mixed(u64);

impl Hasher for Mixed {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0 << 8) | b as u64;
        }
    }

    fn write_u64(&mut self, n: u64) {
        self.0 = n;
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

/// The missing code of an R double: 0 for a number, 1 for `.` (NA_real_
/// or any other NaN), 2 to 27 for a tagged `.a` to `.z`.
fn r_code(x: f64) -> u8 {
    if !x.is_nan() {
        return 0;
    }
    let bits = x.to_bits();
    let tag = ((bits >> 32) & 0xff) as u8;
    if bits as u32 == 1954 && tag.is_ascii_lowercase() {
        tag - b'a' + 2
    } else {
        missing::SYSTEM
    }
}

/// The bytes of element `i` of a character vector; `""` for `NA`. R
/// strings hold no NUL. The writer checks they are UTF-8.
///
/// # Safety
/// `x` is a character vector with more than `i` elements, alive for 'a.
unsafe fn r_string<'a>(x: Sexp, i: usize) -> &'a [u8] {
    let s = STRING_ELT(x, i as isize);
    if s == R_NaString {
        b""
    } else {
        // R keeps each string's length, so no strlen over long texts.
        std::slice::from_raw_parts(R_CHAR(s) as *const u8, Rf_xlength(s).max(0) as usize)
    }
}

/// # Safety
/// `x` is a character vector, alive for 'a.
unsafe fn r_strings<'a>(x: Sexp) -> Vec<&'a str> {
    (0..Rf_xlength(x).max(0) as usize).map(|i| std::str::from_utf8(r_string(x, i)).unwrap_or("")).collect()
}

/// Write the data frame `spec` describes (see save_dta.R) to `path`.
///
/// # Safety
/// `spec` is the list save_dta builds; `path` a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn dtatools_write(path: *const c_char, spec: Sexp, err: *mut c_char, err_len: usize) -> c_int {
    let path = c_str(path).unwrap_or_default();
    guard(err, err_len, || {
        let elt = |i: isize| unsafe { VECTOR_ELT(spec, i) };
        let (columns, names, storage, formats, labels, label_sets) = (elt(0), elt(1), elt(2), elt(3), elt(4), elt(5));
        let (sets, data_label, timestamp, notes) = (elt(6), elt(7), elt(8), elt(9));
        let names = r_strings(names);
        let storage = r_strings(storage);
        let (formats, labels, label_sets) = (r_strings(formats), r_strings(labels), r_strings(label_sets));
        let nobs = if names.is_empty() { 0 } else { Rf_xlength(VECTOR_ELT(columns, 0)).max(0) as usize };

        let mut variables = Vec::with_capacity(names.len());
        for (i, name) in names.iter().enumerate() {
            let col = VECTOR_ELT(columns, i as isize);
            if Rf_xlength(col).max(0) as usize != nobs {
                return Err(Fail::Message("columns differ in length".into()));
            }
            let (storage, values) = if TYPEOF(col) == STRSXP {
                (StorageType::Str(1), Values::Strings(Box::new(move |r| unsafe { r_string(col, r) })))
            } else {
                let storage = match storage[i] {
                    "byte" => StorageType::Byte,
                    "int" => StorageType::Int,
                    "long" => StorageType::Long,
                    "float" => StorageType::Float,
                    "double" => StorageType::Double,
                    other => return Err(Fail::Message(format!("{name}: unknown storage type \"{other}\""))),
                };
                // Integers and logicals are read in place; their NA is `.`.
                let values: Values = match TYPEOF(col) {
                    INTSXP | LGLSXP => {
                        let p = if TYPEOF(col) == INTSXP { INTEGER(col) } else { LOGICAL(col) };
                        let x = std::slice::from_raw_parts(p, nobs);
                        Values::Numbers(Box::new(move |r| {
                            if x[r] == c_int::MIN { (f64::NAN, missing::SYSTEM) } else { (x[r] as f64, 0) }
                        }))
                    }
                    REALSXP => {
                        let x = std::slice::from_raw_parts(REAL(col), nobs);
                        Values::Numbers(Box::new(move |r| (x[r], r_code(x[r]))))
                    }
                    _ => return Err(Fail::Message(format!("{name}: cannot write this column type"))),
                };
                (storage, values)
            };
            variables.push(WriteVariable {
                name: name.to_string(),
                storage,
                format: formats[i].to_string(),
                label: labels[i].to_string(),
                value_labels: label_sets[i].to_string(),
                values,
            });
        }

        let mut value_labels = Vec::new();
        for s in 0..Rf_xlength(sets).max(0) {
            let set = VECTOR_ELT(sets, s);
            let name = r_strings(VECTOR_ELT(set, 0)).first().copied().unwrap_or("").to_string();
            let codes = VECTOR_ELT(set, 1);
            let codes = std::slice::from_raw_parts(REAL(codes), Rf_xlength(codes).max(0) as usize);
            let texts = r_strings(VECTOR_ELT(set, 2));
            let labels = codes
                .iter()
                .zip(texts)
                .map(|(&v, t)| ValueLabel { value: v, missing: r_code(v), text: t.to_string() })
                .collect();
            value_labels.push(ValueLabelSet { name, labels });
        }

        let notes = r_strings(notes);
        let mut characteristics = Vec::new();
        if !notes.is_empty() {
            let note = |n: usize, value: &str| Characteristic {
                variable: "_dta".into(),
                name: format!("note{n}"),
                value: value.into(),
            };
            characteristics.push(note(0, &notes.len().to_string()));
            characteristics.extend(notes.iter().enumerate().map(|(i, v)| note(i + 1, v)));
        }

        let data = Dataset {
            nobs,
            label: r_strings(data_label).first().copied().unwrap_or("").to_string(),
            timestamp: r_strings(timestamp).first().copied().unwrap_or("").to_string(),
            variables,
            value_labels,
            characteristics,
            sort_order: Vec::new(),
        };
        let file = std::fs::File::create(&path).map_err(|e| Fail::Message(format!("{path}: {e}")))?;
        if let Err(e) = dta::write(&data, file) {
            let _ = std::fs::remove_file(&path);
            return Err(Fail::Message(format!("{path}: {e}")));
        }
        Ok(())
    })
}
