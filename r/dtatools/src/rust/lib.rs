//! dtatools' bridge from R to the dta core.
//!
//! Rust never calls an R function that can raise an error: allocation,
//! building strings and setting attributes go through the C shims in
//! init.c, which turn an R error into a status. A failing shim makes us
//! return `Fail::R`, dropping everything we hold, and init.c then
//! resumes R's error. Every object is stored into an R object that is
//! already reachable (a list element or an attribute) as soon as it is
//! made, so nothing here needs PROTECT.

use std::ffi::{c_char, c_int, c_void, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{missing, Column, Encoding, FileSource, Options, Reader, ValueLabelSet, Variable};

type Sexp = *mut c_void;

const STRSXP: c_int = 16;
const REALSXP: c_int = 14;
const VECSXP: c_int = 19;

extern "C" {
    // An R function that cannot raise an error.
    fn REAL(x: Sexp) -> *mut f64;
    // The shims in init.c; each returns 0, or 1 if R raised an error.
    fn dtatools_alloc_elt(parent: Sexp, i: isize, kind: c_int, n: isize, out: *mut Sexp) -> c_int;
    fn dtatools_alloc_attr(x: Sexp, name: *const c_char, kind: c_int, n: isize, out: *mut Sexp) -> c_int;
    fn dtatools_set_strings(x: Sexp, first: isize, bytes: *const u8, ends: *const usize, n: isize) -> c_int;
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
        let mut targets = Vec::with_capacity(cols.len());
        for (k, &c) in cols.iter().enumerate() {
            let var = meta.variables.get(c).ok_or_else(|| Fail::Message(format!("there is no column {}", c + 1)))?;
            let kind = if var.storage.is_numeric() { REALSXP } else { STRSXP };
            let x = alloc_elt(out, k, kind, nobs)?;
            set_attributes(x, var, sets.iter().find(|s| s.name == var.value_labels))?;
            targets.push((x, var.name.as_str()));
        }
        // A failure inside the chunk callback, kept so an R error stays one.
        let mut failed: Option<Fail> = None;
        let result = reader.read_chunks(&cols, 0, meta.nobs, None, |first, chunk| {
            if unsafe { dtatools_interrupted() } != 0 {
                failed = Some(Fail::Message("interrupted".into()));
                return Err(dta::Error::new("interrupted"));
            }
            for ((x, name), column) in targets.iter().zip(chunk) {
                let step = match column {
                    Column::Numbers { values, missing } => {
                        let dst = unsafe { std::slice::from_raw_parts_mut(REAL(*x).add(first), values.len()) };
                        for ((d, &v), &m) in dst.iter_mut().zip(values).zip(missing) {
                            *d = r_double(v, m);
                        }
                        Ok(())
                    }
                    Column::Strings { bytes, ends, binary } => {
                        if binary.iter().any(|&b| b) {
                            Err(Fail::Message(format!("{name} holds binary strLs, which dtatools does not read")))
                        } else {
                            set_strings(*x, first, bytes, ends)
                        }
                    }
                };
                if let Err(fail) = step {
                    failed = Some(fail);
                    return Err(dta::Error::new("stopped"));
                }
            }
            Ok(())
        });
        match (result, failed) {
            (_, Some(fail)) => Err(fail),
            (Err(e), None) => Err(e.into()),
            (Ok(_), None) => Ok(()),
        }
    })
}
