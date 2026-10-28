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
