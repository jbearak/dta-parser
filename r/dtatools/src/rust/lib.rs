//! dtatools' bridge from R to the dta core: builds R vectors through R's
//! C API. Each entry point returns R's NULL and fills `err` on failure;
//! the C wrappers in init.c raise the R error after we have returned, so
//! R never unwinds through Rust frames.

use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{missing, Column, Encoding, FileSource, Options, Reader};

type Sexp = *mut c_void;

const STRSXP: c_uint = 16;
const REALSXP: c_uint = 14;
const INTSXP: c_uint = 13;
const VECSXP: c_uint = 19;
const CE_UTF8: c_uint = 1;

extern "C" {
    static R_NilValue: Sexp;
    fn Rf_allocVector(kind: c_uint, n: isize) -> Sexp;
    fn Rf_protect(x: Sexp) -> Sexp;
    fn Rf_unprotect(n: c_int);
    fn REAL(x: Sexp) -> *mut f64;
    fn INTEGER(x: Sexp) -> *mut c_int;
    fn SET_STRING_ELT(x: Sexp, i: isize, v: Sexp);
    fn SET_VECTOR_ELT(x: Sexp, i: isize, v: Sexp) -> Sexp;
    fn STRING_ELT(x: Sexp, i: isize) -> Sexp;
    fn Rf_mkCharLenCE(s: *const c_char, len: c_int, enc: c_uint) -> Sexp;
    fn Rf_translateCharUTF8(x: Sexp) -> *const c_char;
    fn Rf_setAttrib(x: Sexp, name: Sexp, value: Sexp) -> Sexp;
    fn Rf_install(name: *const c_char) -> Sexp;
    fn Rf_xlength(x: Sexp) -> isize;
    fn TYPEOF(x: Sexp) -> c_int;
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

/// Counts protections and releases them when dropped.
struct Protect(c_int);

impl Protect {
    fn new() -> Self {
        Protect(0)
    }
    fn keep(&mut self, x: Sexp) -> Sexp {
        self.0 += 1;
        unsafe { Rf_protect(x) }
    }
}

impl Drop for Protect {
    fn drop(&mut self) {
        unsafe { Rf_unprotect(self.0) }
    }
}

fn mkchar(s: &[u8]) -> Sexp {
    unsafe { Rf_mkCharLenCE(s.as_ptr() as *const c_char, s.len() as c_int, CE_UTF8) }
}

fn strings<S: AsRef<str>>(p: &mut Protect, v: &[S]) -> Sexp {
    let x = p.keep(unsafe { Rf_allocVector(STRSXP, v.len() as isize) });
    for (i, s) in v.iter().enumerate() {
        unsafe { SET_STRING_ELT(x, i as isize, mkchar(s.as_ref().as_bytes())) };
    }
    x
}

fn doubles(p: &mut Protect, v: impl ExactSizeIterator<Item = f64>) -> Sexp {
    let x = p.keep(unsafe { Rf_allocVector(REALSXP, v.len() as isize) });
    let out = unsafe { std::slice::from_raw_parts_mut(REAL(x), v.len()) };
    for (o, d) in out.iter_mut().zip(v) {
        *o = d;
    }
    x
}

/// A named list of `items`.
fn list(p: &mut Protect, items: Vec<(&str, Sexp)>) -> Sexp {
    let x = p.keep(unsafe { Rf_allocVector(VECSXP, items.len() as isize) });
    let names: Vec<&str> = items.iter().map(|(n, _)| *n).collect();
    let names = strings(p, &names);
    for (i, (_, v)) in items.into_iter().enumerate() {
        unsafe { SET_VECTOR_ELT(x, i as isize, v) };
    }
    unsafe { Rf_setAttrib(x, Rf_install(c"names".as_ptr()), names) };
    x
}

fn set_attr(x: Sexp, name: &CStr, value: Sexp) {
    unsafe { Rf_setAttrib(x, Rf_install(name.as_ptr()), value) };
}

/// The attributes `read_dta` documents: `label` and `format` on every
/// column; `storage`, `labels`, `label_set` and class `dta_num` on
/// numeric ones. Set here rather than in R so R does not copy the
/// column to change them.
fn set_attributes(p: &mut Protect, x: Sexp, var: &dta::Variable, set: Option<&dta::ValueLabelSet>) {
    if !var.label.is_empty() {
        set_attr(x, c"label", strings(p, &[&var.label]));
    }
    set_attr(x, c"format", strings(p, &[&var.format]));
    if var.storage.is_numeric() {
        set_attr(x, c"storage", strings(p, &[var.storage.name()]));
        if let Some(set) = set {
            let codes = doubles(p, set.labels.iter().map(|l| r_double(l.value, l.missing)));
            let texts: Vec<&str> = set.labels.iter().map(|l| l.text.as_str()).collect();
            set_attr(codes, c"names", strings(p, &texts));
            set_attr(x, c"labels", codes);
            set_attr(x, c"label_set", strings(p, &[&set.name]));
        }
        set_attr(x, c"class", strings(p, &["dta_num"]));
    }
}

/// The first element of a character vector, as UTF-8.
fn string_arg(x: Sexp) -> Result<String, String> {
    unsafe {
        if TYPEOF(x) != STRSXP as c_int || Rf_xlength(x) < 1 {
            return Err("expected a string".into());
        }
        Ok(CStr::from_ptr(Rf_translateCharUTF8(STRING_ELT(x, 0))).to_string_lossy().into_owned())
    }
}

fn open(path: Sexp, encoding: Sexp) -> Result<Reader<FileSource>, String> {
    let path = string_arg(path)?;
    let encoding = if unsafe { TYPEOF(encoding) } == STRSXP as c_int {
        let name = string_arg(encoding)?;
        Encoding::from_name(&name).ok_or_else(|| format!("unknown encoding \"{name}\""))?
    } else {
        Encoding::default()
    };
    let source = FileSource::open(&path).map_err(|e| format!("{path}: {e}"))?;
    Reader::open(source, Options { encoding }).map_err(|e| format!("{path}: {e}"))
}

/// Run `f`, turning an error or a panic into a message in `err`.
fn guard(err: *mut c_char, err_len: usize, f: impl FnOnce() -> Result<Sexp, String>) -> Sexp {
    let message = match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(x)) => return x,
        Ok(Err(m)) => m,
        Err(_) => "internal error in dtatools".to_string(),
    };
    let bytes = message.as_bytes();
    let n = bytes.len().min(err_len.saturating_sub(1));
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), err as *mut u8, n);
        *err.add(n) = 0;
        R_NilValue
    }
}

/// The header, descriptors, notes and value label sets of a file.
#[no_mangle]
pub extern "C" fn dtatools_meta(path: Sexp, encoding: Sexp, err: *mut c_char, err_len: usize) -> Sexp {
    guard(err, err_len, || {
        let mut reader = open(path, encoding)?;
        let notes = reader.notes().map_err(|e| e.to_string())?;
        let sets = reader.value_labels().map_err(|e| e.to_string())?;
        let meta = reader.metadata();
        let vars = &meta.variables;
        let mut p = Protect::new();
        let set_list = {
            let items: Vec<(&str, Sexp)> = sets
                .iter()
                .map(|s| {
                    let codes = doubles(&mut p, s.labels.iter().map(|l| r_double(l.value, l.missing)));
                    let texts: Vec<&str> = s.labels.iter().map(|l| l.text.as_str()).collect();
                    let texts = strings(&mut p, &texts);
                    (s.name.as_str(), list(&mut p, vec![("codes", codes), ("texts", texts)]))
                })
                .collect();
            list(&mut p, items)
        };
        let sort: Vec<f64> = meta.sort_order.iter().map(|&i| (i + 1) as f64).collect();
        let items = vec![
            ("release", doubles(&mut p, [meta.release as f64].into_iter())),
            ("nobs", doubles(&mut p, [meta.nobs as f64].into_iter())),
            ("label", strings(&mut p, &[&meta.label])),
            ("timestamp", strings(&mut p, &[&meta.timestamp])),
            ("names", strings(&mut p, &vars.iter().map(|v| v.name.as_str()).collect::<Vec<_>>())),
            ("storage", strings(&mut p, &vars.iter().map(|v| v.storage.name()).collect::<Vec<_>>())),
            ("formats", strings(&mut p, &vars.iter().map(|v| v.format.as_str()).collect::<Vec<_>>())),
            ("var_labels", strings(&mut p, &vars.iter().map(|v| v.label.as_str()).collect::<Vec<_>>())),
            ("label_sets", strings(&mut p, &vars.iter().map(|v| v.value_labels.as_str()).collect::<Vec<_>>())),
            ("sort_order", doubles(&mut p, sort.into_iter())),
            ("notes", strings(&mut p, &notes)),
            ("value_labels", set_list),
        ];
        Ok(list(&mut p, items))
    })
}

/// The columns at 0-based `cols` (an integer vector), all rows.
#[no_mangle]
pub extern "C" fn dtatools_read(path: Sexp, cols: Sexp, encoding: Sexp, err: *mut c_char, err_len: usize) -> Sexp {
    guard(err, err_len, || {
        let mut reader = open(path, encoding)?;
        let cols: Vec<usize> = unsafe {
            if TYPEOF(cols) != INTSXP as c_int {
                return Err("expected integer column indices".into());
            }
            std::slice::from_raw_parts(INTEGER(cols), Rf_xlength(cols) as usize)
                .iter()
                .map(|&i| usize::try_from(i).map_err(|_| "negative column index".to_string()))
                .collect::<Result<_, _>>()?
        };
        let sets = reader.value_labels().map_err(|e| e.to_string())?;
        let meta = reader.metadata();
        let nobs = meta.nobs;
        let n = isize::try_from(nobs).map_err(|_| "too many rows".to_string())?;
        let mut p = Protect::new();
        let out = p.keep(unsafe { Rf_allocVector(VECSXP, cols.len() as isize) });
        // One R vector per column, filled a chunk at a time.
        let mut targets = Vec::with_capacity(cols.len());
        for (k, &c) in cols.iter().enumerate() {
            let var = meta.variables.get(c).ok_or_else(|| format!("there is no column {}", c + 1))?;
            let kind = if var.storage.is_numeric() { REALSXP } else { STRSXP };
            let x = unsafe { Rf_allocVector(kind, n) };
            unsafe { SET_VECTOR_ELT(out, k as isize, x) };
            // x is reachable from `out` now; its attributes need protecting only while built.
            set_attributes(&mut Protect::new(), x, var, sets.iter().find(|s| s.name == var.value_labels));
            targets.push((x, var.name.clone()));
        }
        reader
            .read_chunks(&cols, 0, nobs, |first, chunk| {
                for ((x, name), column) in targets.iter().zip(chunk) {
                    match column {
                        Column::Numbers { values, missing } => {
                            let dst = unsafe { std::slice::from_raw_parts_mut(REAL(*x).add(first), values.len()) };
                            for ((d, &v), &m) in dst.iter_mut().zip(values).zip(missing) {
                                *d = r_double(v, m);
                            }
                        }
                        Column::Strings { binary, .. } => {
                            if binary.iter().any(|&b| b) {
                                return Err(dta::Error::new(format!(
                                    "{name} holds binary strLs, which dtatools does not read"
                                )));
                            }
                            for i in 0..column.len() {
                                unsafe { SET_STRING_ELT(*x, (first + i) as isize, mkchar(column.bytes(i))) };
                            }
                        }
                    }
                }
                Ok(())
            })
            .map_err(|e| e.to_string())?;
        Ok(out)
    })
}
