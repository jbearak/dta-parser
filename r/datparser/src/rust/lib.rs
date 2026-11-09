//! datparser's bridge from R to the dta core's fixed-width reader.
//!
//! Rust never calls R here. `datparser_read` reads a file into a
//! [`Table`] and hands init.c a pointer to it; init.c keeps the pointer
//! in an external pointer whose finalizer frees it, makes the R vectors
//! and asks for their values through the functions below, which fill
//! memory init.c owns. So an R error (out of memory, Ctrl-C) never
//! passes through a Rust frame, and the table is freed either way.

use std::borrow::Cow;
use std::ffi::{c_char, c_int, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{missing, threads, FixedWidth, FixedWidthSetup, Recodes, StorageType, ValueLabel};

/// R's NA_real_: a NaN whose low word is 1954.
const NA_BITS: u64 = 0x7ff0_0000_0000_07a2;
/// R's NA_integer_.
const NA_INTEGER: i32 = i32::MIN;

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

/// A file read through its setup, and its warnings' messages.
pub struct Table {
    fw: FixedWidth<'static>,
    warnings: Vec<String>,
    /// Per variable, its value labels in code order (numbers, then `.a`
    /// to `.z`), for the variables read.
    labels: Vec<Vec<ValueLabel>>,
}

/// A parsed setup, and its variables' names.
pub struct Setup {
    setup: FixedWidthSetup,
    names: Vec<String>,
}

unsafe fn c_str(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

/// Copy `msg` into the C buffer `err` of `len` bytes, NUL-terminated.
unsafe fn set_err(err: *mut c_char, len: usize, msg: &str) {
    if err.is_null() || len == 0 {
        return;
    }
    let bytes = msg.as_bytes();
    let n = bytes.len().min(len - 1);
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), err as *mut u8, n);
    *err.add(n) = 0;
}

/// Run `f`, turning an error or a panic into 1 and a message in `err`.
unsafe fn guard(err: *mut c_char, err_len: usize, f: impl FnOnce() -> Result<(), String>) -> c_int {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(msg)) => {
            set_err(err, err_len, &msg);
            1
        }
        Err(_) => {
            set_err(err, err_len, "internal error in datparser's Rust code");
            1
        }
    }
}

unsafe fn read_setups(setups: *const *const c_char, n: usize) -> Result<Vec<Vec<u8>>, String> {
    std::slice::from_raw_parts(setups, n).iter().map(|&s| read_file(&c_str(s))).collect()
}

fn read_file(p: &str) -> Result<Vec<u8>, String> {
    std::fs::read(p).map_err(|e| format!("{p}: {e}"))
}

/// Parse the setup files, as a new [`Setup`] at `out`.
///
/// # Safety
/// The pointers come from init.c; `setups` holds `nsetups` strings.
#[no_mangle]
pub unsafe extern "C" fn datparser_setup(
    setups: *const *const c_char,
    nsetups: usize,
    commented_formats: c_int,
    out: *mut *mut Setup,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    guard(err, err_len, || {
        let bytes = read_setups(setups, nsetups)?;
        let refs: Vec<&[u8]> = bytes.iter().map(Vec::as_slice).collect();
        let setup = FixedWidthSetup::parse(&refs, commented_formats != 0).map_err(|e| e.to_string())?;
        let names = setup.names().map(str::to_string).collect();
        *out = Box::into_raw(Box::new(Setup { setup, names }));
        Ok(())
    })
}

/// Read the fixed-width file `data` through `setup`, which this takes
/// and frees, the variables at the 0-based `cols` only, as a new
/// [`Table`] at `out`. `recodes` is "setup", "tagged" or "none".
///
/// # Safety
/// The pointers come from init.c; `setup` came from `datparser_setup`
/// and is not used again; `cols` holds `ncols` ints.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn datparser_read(
    setup: *mut Setup,
    data: *const c_char,
    recodes: *const c_char,
    cols: *const c_int,
    ncols: usize,
    out: *mut *mut Table,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let setup = Box::from_raw(setup);
    guard(err, err_len, || {
        let recodes = c_str(recodes);
        let mode = Recodes::from_name(&recodes)
            .ok_or_else(|| format!("recodes must be \"setup\", \"tagged\" or \"none\", not \"{recodes}\""))?;
        let data = read_file(&c_str(data))?;
        let cols: Vec<usize> = std::slice::from_raw_parts(cols, ncols)
            .iter()
            .map(|&c| usize::try_from(c).map_err(|_| "negative column index".to_string()))
            .collect::<Result<_, _>>()?;
        let (fw, warnings) = FixedWidth::read(setup.setup, Cow::Owned(data), mode, Some(&cols))
            .map_err(|e| e.to_string())?;
        let mut labels = vec![Vec::new(); fw.ncols()];
        for &k in &cols {
            if let Some(set) = fw.value_labels(k) {
                let mut l = set.labels.clone();
                l.sort_by(|a, b| match (a.missing, b.missing) {
                    (0, 0) => a.value.total_cmp(&b.value),
                    (x, y) => x.cmp(&y),
                });
                labels[k] = l;
            }
        }
        let warnings = warnings.into_iter().map(|w| w.message).collect();
        *out = Box::into_raw(Box::new(Table { fw, warnings, labels }));
        Ok(())
    })
}

/// # Safety
/// `s` came from `datparser_setup`, or is null.
#[no_mangle]
pub unsafe extern "C" fn datparser_free_setup(s: *mut Setup) {
    if !s.is_null() {
        drop(Box::from_raw(s));
    }
}

/// # Safety
/// `t` came from `datparser_read`, or is null.
#[no_mangle]
pub unsafe extern "C" fn datparser_free_table(t: *mut Table) {
    if !t.is_null() {
        drop(Box::from_raw(t));
    }
}

/// # Safety
/// `s` came from `datparser_setup`.
#[no_mangle]
pub unsafe extern "C" fn datparser_setup_ncols(s: *const Setup) -> usize {
    (&*s).names.len()
}

/// Variable `i`'s name, as bytes at `*ptr` and their length at `*len`.
///
/// # Safety
/// `s` came from `datparser_setup`; `i` is below its column count.
#[no_mangle]
pub unsafe extern "C" fn datparser_setup_name(s: *const Setup, i: usize, ptr: *mut *const u8, len: *mut usize) {
    text_out(&(&*s).names[i], ptr, len);
}

/// Text up to its first NUL, which R strings cannot hold (a release 118
/// file ends a string there too).
unsafe fn text_out(s: &str, ptr: *mut *const u8, len: *mut usize) {
    let b = s.as_bytes();
    let n = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    *ptr = b.as_ptr();
    *len = n;
}

/// # Safety
/// `t` came from `datparser_read`.
#[no_mangle]
pub unsafe extern "C" fn datparser_nrows(t: *const Table) -> usize {
    (&*t).fw.nrows()
}

/// # Safety
/// `t` came from `datparser_read`.
#[no_mangle]
pub unsafe extern "C" fn datparser_nwarnings(t: *const Table) -> usize {
    (&*t).warnings.len()
}

/// # Safety
/// `t` came from `datparser_read`; `i` is below its warning count.
#[no_mangle]
pub unsafe extern "C" fn datparser_warning(t: *const Table, i: usize, ptr: *mut *const u8, len: *mut usize) {
    text_out(&(&*t).warnings[i], ptr, len);
}

/// Variable `k`'s label, empty for none.
///
/// # Safety
/// `t` came from `datparser_read`; `k` is a variable it read.
#[no_mangle]
pub unsafe extern "C" fn datparser_label(t: *const Table, k: usize, ptr: *mut *const u8, len: *mut usize) {
    text_out((&*t).fw.label(k), ptr, len);
}

/// What R vector variable `k` becomes for rows `first..first + n`: 0 for
/// integers, 1 for doubles, 2 for strings. A variable whose values are
/// whole numbers within long's range is integers, unless those rows hold
/// `.a` to `.z`, which only a double can keep; this is the type R's
/// `read_dta` gives the same variable in a release 118 file.
///
/// # Safety
/// `t` came from `datparser_read`; `k` is a variable it read and the rows
/// are within it.
#[no_mangle]
pub unsafe extern "C" fn datparser_kind(t: *const Table, k: usize, first: usize, n: usize) -> c_int {
    let fw = &(&*t).fw;
    if fw.is_string(k) {
        return 2;
    }
    let integer = matches!(fw.storage(k), StorageType::Byte | StorageType::Int | StorageType::Long);
    if integer && !letters_in(fw, k, first, n) {
        0
    } else {
        1
    }
}

/// Whether rows `first..first + n` of numeric variable `k` hold `.a` to
/// `.z`.
fn letters_in(fw: &FixedWidth, k: usize, first: usize, n: usize) -> bool {
    fw.has_letters(k) && (first..first + n).any(|row| fw.number(row, k).1 > missing::SYSTEM)
}

/// A numeric column's R vector, for the workers that fill it.
struct Target {
    k: usize,
    kind: c_int,
    out: *mut u8,
}

// Each target is a distinct R vector, written by one worker only.
unsafe impl Send for Target {}
unsafe impl Sync for Target {}

/// Fill rows `first..first + n` of the numeric variables `ks[j]` into
/// `outs[j]`, an int vector where `kinds[j]` is 0 and a double vector
/// where it is 1 (`.a` to `.z` as tagged NAs), on several threads.
/// Returns 0, or 1 if a worker panicked.
///
/// # Safety
/// As for `datparser_kind`, for each variable; each `outs[j]` holds `n`
/// values of its kind, and the arrays hold `m` entries.
#[no_mangle]
pub unsafe extern "C" fn datparser_fill(
    t: *const Table,
    m: usize,
    ks: *const usize,
    kinds: *const c_int,
    outs: *const *mut u8,
    first: usize,
    n: usize,
) -> c_int {
    catch_unwind(AssertUnwindSafe(|| fill_all(t, m, ks, kinds, outs, first, n))).map_or(1, |()| 0)
}

unsafe fn fill_all(t: *const Table, m: usize, ks: *const usize, kinds: *const c_int, outs: *const *mut u8, first: usize, n: usize) {
    let fw = &(&*t).fw;
    let ks = std::slice::from_raw_parts(ks, m);
    let kinds = std::slice::from_raw_parts(kinds, m);
    let outs = std::slice::from_raw_parts(outs, m);
    let targets: Vec<Target> = (0..m).map(|j| Target { k: ks[j], kind: kinds[j], out: outs[j] }).collect();
    let workers = threads::resolve(0).min(m).max(1);
    let fill = |chunk: &[Target]| {
        for target in chunk {
            if target.kind == 0 {
                let out = std::slice::from_raw_parts_mut(target.out as *mut i32, n);
                for (i, o) in out.iter_mut().enumerate() {
                    let (v, c) = fw.number(first + i, target.k);
                    *o = if c == 0 { v as i32 } else { NA_INTEGER };
                }
            } else {
                let out = std::slice::from_raw_parts_mut(target.out as *mut f64, n);
                for (i, o) in out.iter_mut().enumerate() {
                    let (v, c) = fw.number(first + i, target.k);
                    *o = r_double(v, c);
                }
            }
        }
    };
    if workers == 1 {
        fill(&targets);
        return;
    }
    let size = targets.len().div_ceil(workers);
    std::thread::scope(|scope| {
        for chunk in targets.chunks(size) {
            scope.spawn(move || fill(chunk));
        }
    });
}

/// Row `row` of string variable `k`.
///
/// # Safety
/// As for `datparser_kind`.
#[no_mangle]
pub unsafe extern "C" fn datparser_string(t: *const Table, k: usize, row: usize, ptr: *mut *const u8, len: *mut usize) {
    text_out((&*t).fw.string(row, k), ptr, len);
}

/// The number of value labels of variable `k`.
///
/// # Safety
/// `t` came from `datparser_read`; `k` is a variable it read.
#[no_mangle]
pub unsafe extern "C" fn datparser_nlabels(t: *const Table, k: usize) -> usize {
    (&*t).labels[k].len()
}

/// Value label `i` of variable `k`: its code as an R double (`.a` to `.z`
/// tagged) and its text.
///
/// # Safety
/// `t` came from `datparser_read`; `k` is a variable it read; `i` is
/// below its label count.
#[no_mangle]
pub unsafe extern "C" fn datparser_value_label(
    t: *const Table,
    k: usize,
    i: usize,
    code: *mut f64,
    ptr: *mut *const u8,
    len: *mut usize,
) {
    let l = &(&*t).labels[k][i];
    *code = r_double(l.value, l.missing);
    text_out(&l.text, ptr, len);
}
