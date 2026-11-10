//! The R binding of `dta_arrow` (plan 0025, stage 3): datakit's `read_parquet_pl()`,
//! `read_dta_pl()`, `read_fixed_width_pl()` and the polars methods of
//! `save_parquet()` and `save_dta()` reach these through the C callables
//! in init.c.
//!
//! A read builds its table in Rust, then the metadata list through the
//! shims of lib.rs (which never let an R error jump through a Rust
//! frame), and last moves the table into the `ArrowArrayStream` structs
//! R allocated with nanoarrow. Any failure before that drops the table
//! here and leaves the structs with a null `release`.
//!
//! A write takes the stream out of the struct nanoarrow allocated
//! (`import_stream` sets its `release` to null, so nanoarrow's finalizer
//! does nothing) and releases it once, whether the write succeeds or
//! fails.
//!
//! R strings are read as UTF-8: datakit passes them through
//! `enc2utf8()`.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_int, c_void};

use dta_arrow::dta::{dta_read, dta_write, CATEGORICAL_MARK, FACTOR_MARK};
use dta_arrow::error::Error;
use dta_arrow::ffi::{export_stream, import_stream, ArrowArrayStream, Imported};
use dta_arrow::meta::{repeats_a_code, Code, ColumnEntry, GivenSet, LabelKey, LabelSet, ReadMeta, ReadOutput, WriteMeta};
use dta_arrow::parquet::Input;
use dta_arrow::read::{parquet_read, Stamps};
use dta_arrow::write::{parquet_options, parquet_write};

use super::parquet_r::{optional_string_elt, optional_strings_elt};
use super::{
    alloc_attr, alloc_elt, c_str, doubles_elt, guard, named_list, r_double, set_strs, strings_elt, Fail, Res, Sexp,
    LGLSXP, LOGICAL, NA_INTEGER, REAL, REALSXP, Rf_xlength, R_CHAR, R_NaString, STRING_ELT, STRSXP, TYPEOF, VECTOR_ELT,
};

extern "C" {
    fn R_ExternalPtrAddr(s: Sexp) -> *mut c_void;
}

/// An error of `dta_arrow` as R's: its message. (R has one kind of error,
/// so the variant is not kept.)
fn fail(e: Error) -> Fail {
    Fail::Message(e.to_string())
}

/// `x[i]` of a character vector, None for `NA`.
///
/// # Safety
/// `x` is a character vector with more than `i` elements.
unsafe fn string_at(x: Sexp, i: usize) -> Option<String> {
    let s = STRING_ELT(x, i as isize);
    if s == R_NaString {
        return None;
    }
    let bytes = std::slice::from_raw_parts(R_CHAR(s) as *const u8, Rf_xlength(s).max(0) as usize);
    Some(String::from_utf8_lossy(bytes).into_owned())
}

/// Every element of `x` (a character vector, or anything else as none),
/// `NA` as None.
///
/// # Safety
/// `x` is an R object.
unsafe fn strings(x: Sexp) -> Vec<Option<String>> {
    if TYPEOF(x) != STRSXP {
        return Vec::new();
    }
    (0..Rf_xlength(x).max(0) as usize).map(|i| string_at(x, i)).collect()
}

/// The first element of `x`, None for `NULL`, an empty vector or `NA`.
///
/// # Safety
/// `x` is an R object.
unsafe fn string_or_null(x: Sexp) -> Option<String> {
    strings(x).into_iter().next().flatten()
}

/// The window of a read: `skip` rows (R has floored it), then `n_max`
/// (`Inf` for all).
fn window(skip: f64, n_max: f64) -> (u64, Option<u64>) {
    let n = if n_max.is_finite() { Some(n_max.max(0.0) as u64) } else { None };
    (skip.max(0.0) as u64, n)
}

/// The columns a read asks for: `NULL` for all, else names.
///
/// # Safety
/// `cols` is `NULL` or a character vector without `NA` (init.c checks).
unsafe fn selectors(cols: Sexp) -> Option<Vec<String>> {
    (TYPEOF(cols) == STRSXP).then(|| strings(cols).into_iter().map(Option::unwrap_or_default).collect())
}

// ---------------------------------------------------------------- reads

/// A logical vector of `v` (`NA` for None), as element `i` of `parent`.
fn logicals_elt(parent: Sexp, i: usize, v: &[Option<bool>]) -> Res<()> {
    let x = alloc_elt(parent, i, LGLSXP, v.len())?;
    // SAFETY: x is a new logical vector of v.len() elements.
    let out = unsafe { std::slice::from_raw_parts_mut(LOGICAL(x), v.len()) };
    for (o, b) in out.iter_mut().zip(v) {
        *o = match b {
            Some(b) => c_int::from(*b),
            None => NA_INTEGER,
        };
    }
    Ok(())
}

/// The R double of a value label's code: the number, `NA` for `.`, a
/// tagged `NA` for `.a` to `.z`.
fn code_double(key: &LabelKey) -> f64 {
    match key {
        LabelKey::Int(v) => *v as f64,
        LabelKey::Float(v) => *v,
        LabelKey::Missing(c) => r_double(0.0, *c),
    }
}

/// `labels` by `dta_arrow::meta`'s rule for keyed entries: a code given twice keeps its
/// first place and its last text.
fn as_dict<'a, 'b>(labels: &'b LabelSet<'a>) -> Vec<(&'b LabelKey, &'b str)> {
    if !repeats_a_code(labels) {
        return labels.iter().map(|(k, t)| (k, t.as_ref())).collect();
    }
    let mut out: Vec<(&LabelKey, &str)> = Vec::with_capacity(labels.len());
    let mut at: HashMap<dta_arrow::meta::CanonicalKey, usize> = HashMap::with_capacity(labels.len());
    for (k, t) in labels {
        match at.get(&k.canonical()) {
            Some(&j) => out[j] = (out[j].0, t.as_ref()),
            None => {
                at.insert(k.canonical(), out.len());
                out.push((k, t.as_ref()));
            }
        }
    }
    out
}

/// The metadata list of a read, as element 0 of `holder`, under these
/// names:
/// rows; names; columns, a list of vectors (name, label, format,
/// value_labels, ordered, storage, flag, eligible); value_labels, a named
/// list of named doubles (names the texts, values the codes, `.` as `NA`
/// and `.a` to `.z` as tagged `NA`s); label and timestamp (`NULL` when
/// absent); notes; characteristics, a list of vectors (variable, name,
/// value); sort; warnings; letter_columns; and release, for a `.dta`
/// read (`NULL` otherwise).
fn meta_list(holder: Sexp, m: &ReadMeta<'_>) -> Res<()> {
    let names = [
        "rows", "names", "columns", "value_labels", "label", "timestamp", "notes", "characteristics", "sort", "warnings",
        "letter_columns", "release",
    ];
    let out = named_list(holder, 0, &names)?;
    doubles_elt(out, 0, &[m.rows as f64])?;
    strings_elt(out, 1, &m.columns.iter().map(|c| c.name.as_ref()).collect::<Vec<&str>>())?;
    let fields = ["name", "label", "format", "value_labels", "ordered", "storage", "flag", "eligible"];
    let cols = named_list(out, 2, &fields)?;
    // Each field as it lies in the metadata, with no copy per column.
    fn text<'m>(m: &'m ReadMeta<'_>, f: impl Fn(&'m dta_arrow::meta::ColumnMeta<'_>) -> Option<&'m str>) -> Vec<Option<&'m str>> {
        m.columns.iter().map(f).collect()
    }
    optional_strings_elt(cols, 0, &text(m, |c| Some(c.name.as_ref())))?;
    optional_strings_elt(cols, 1, &text(m, |c| c.label.as_deref()))?;
    optional_strings_elt(cols, 2, &text(m, |c| c.format.as_deref()))?;
    optional_strings_elt(cols, 3, &text(m, |c| c.value_labels.as_deref()))?;
    logicals_elt(cols, 4, &m.columns.iter().map(|c| c.ordered).collect::<Vec<_>>())?;
    optional_strings_elt(cols, 5, &text(m, |c| c.storage.as_deref()))?;
    optional_strings_elt(cols, 6, &text(m, |c| c.flag.as_deref()))?;
    logicals_elt(cols, 7, &m.columns.iter().map(|c| Some(c.eligible)).collect::<Vec<_>>())?;
    let set_names: Vec<&str> = m.value_labels.iter().map(|(n, _)| n.as_ref()).collect();
    let sets = named_list(out, 3, &set_names)?;
    for (i, (_, labels)) in m.value_labels.iter().enumerate() {
        let labels = as_dict(labels);
        let x = alloc_elt(sets, i, REALSXP, labels.len())?;
        // SAFETY: x is a new double vector of labels.len() elements.
        let v = unsafe { std::slice::from_raw_parts_mut(REAL(x), labels.len()) };
        for (o, (k, _)) in v.iter_mut().zip(&labels) {
            *o = code_double(k);
        }
        let n = alloc_attr(x, c"names", STRSXP, labels.len())?;
        set_strs(n, &labels.iter().map(|(_, t)| *t).collect::<Vec<&str>>())?;
    }
    optional_string_elt(out, 4, m.label.as_deref())?;
    optional_string_elt(out, 5, m.timestamp.as_deref())?;
    strings_elt(out, 6, &m.notes)?;
    let chars = named_list(out, 7, &["variable", "name", "value"])?;
    strings_elt(chars, 0, &m.characteristics.iter().map(|c| c.0.as_str()).collect::<Vec<_>>())?;
    strings_elt(chars, 1, &m.characteristics.iter().map(|c| c.1.as_str()).collect::<Vec<_>>())?;
    strings_elt(chars, 2, &m.characteristics.iter().map(|c| c.2.as_str()).collect::<Vec<_>>())?;
    strings_elt(out, 8, &m.sort)?;
    strings_elt(out, 9, &m.warnings)?;
    strings_elt(out, 10, &m.letter_columns)?;
    if let Some(r) = m.release {
        doubles_elt(out, 11, &[f64::from(r)])?;
    }
    Ok(())
}

/// What a read gives R: the metadata list in `holder`, then, last, the
/// frame's stream in `data` and the letters' in `letters` (left
/// unreleased when no column read holds a letter).
///
/// # Safety
/// `data` and `letters` point at `ArrowArrayStream` structs whose
/// `release` is null (init.c checks).
unsafe fn give(out: ReadOutput<'_>, holder: Sexp, data: *mut ArrowArrayStream, letters: *mut ArrowArrayStream) -> Res<()> {
    meta_list(holder, &out.meta)?;
    data.write(export_stream(&out.frame));
    if let Some(table) = &out.letters {
        letters.write(export_stream(table));
    }
    Ok(())
}

/// Read rows `skip..skip + n_max` of `cols` (names; all when `NULL`) of
/// a Parquet file, a path or the whole file in `raw`, into `data` and
/// `letters`, with the metadata list as element 0 of `holder`.
///
/// # Safety
/// The pointers come from init.c: `raw` is NULL or `raw_len` bytes, the
/// streams as for [`give`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_parquet_read_arrow_rs(
    path: *const c_char,
    raw: *const u8,
    raw_len: usize,
    cols: Sexp,
    prefer: *const c_char,
    skip: f64,
    n_max: f64,
    nested_skip: c_int,
    timestamps: *const c_char,
    threads: c_int,
    data: *mut ArrowArrayStream,
    letters: *mut ArrowArrayStream,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let input = if raw.is_null() {
        Input::Path(c_str(path).unwrap_or_default())
    } else if raw_len == 0 {
        Input::Bytes(&[])
    } else {
        Input::Bytes(std::slice::from_raw_parts(raw, raw_len))
    };
    let timestamps = c_str(timestamps).unwrap_or_default();
    let columns = selectors(cols);
    let prefer = c_str(prefer);
    guard(err, err_len, || {
        let mode = Stamps::from_name(&timestamps).map_err(fail)?;
        let (skip, n_max) = window(skip, n_max);
        let threads = threads.max(0) as usize;
        parquet_read(input, columns.as_deref(), prefer.as_deref(), skip, n_max, nested_skip != 0, mode, threads, &mut |out| {
            give(out, holder, data, letters)
        })
        .map_err(fail)?
    })
}

/// Read rows `skip..skip + n_max` of `cols` (names; all when `NULL`) of
/// the `.dta` file at `path`, as [`dtaparser_parquet_read_arrow_rs`]
/// does.
///
/// # Safety
/// As for [`dtaparser_parquet_read_arrow_rs`]; `encoding` is NULL or a
/// string.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_dta_read_arrow_rs(
    path: *const c_char,
    cols: Sexp,
    skip: f64,
    n_max: f64,
    encoding: *const c_char,
    timestamps: *const c_char,
    data: *mut ArrowArrayStream,
    letters: *mut ArrowArrayStream,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let encoding = c_str(encoding);
    let timestamps = c_str(timestamps).unwrap_or_default();
    let columns = selectors(cols);
    guard(err, err_len, || {
        let mode = Stamps::from_name(&timestamps).map_err(fail)?;
        let (skip, n_max) = window(skip, n_max);
        dta_read(&path, columns.as_deref(), skip, n_max, encoding.as_deref(), mode, &mut |out| {
            give(out, holder, data, letters)
        })
        .map_err(fail)?
    })
}

// ---------------------------------------------------------------- writes

/// The code of a value label as R holds it: `NA` is `.`, a tagged `NA`
/// `.a` to `.z`, anything else a number.
fn code_of(x: f64) -> Code {
    if !x.is_nan() {
        return Code::Number(x);
    }
    let bits = x.to_bits();
    let tag = ((bits >> 32) & 0xff) as u8;
    if bits as u32 == 1954 && tag.is_ascii_lowercase() {
        Code::Text(format!(".{}", tag as char))
    } else {
        Code::Text(".".into())
    }
}

/// The write meta datakit builds (`write_meta()` in datakit's R code), a
/// list of: label, timestamp (each a string or `NULL`), notes, sort,
/// characteristics (variable, name, value), columns (name, label, format,
/// value_labels, ordered), value_labels (names, a list of codes, a list
/// of texts) and missing (names, a list of nanoarrow streams). Only the
/// frame's columns are kept of `columns` and `missing`; for a `.dta`
/// file (`dta`) only the frame's columns and `_dta` of
/// `characteristics`, without the markers its writer makes.
///
/// # Safety
/// `meta` is that list, checked by init.c, whose streams are valid and
/// not taken; this takes those of the frame's columns.
unsafe fn write_meta(meta: Sexp, names: &[&str], missing_letters: bool, dta: bool) -> Res<WriteMeta> {
    let elt = |i: isize| VECTOR_ELT(meta, i);
    let present: HashSet<&str> = names.iter().copied().collect();
    let mut out = WriteMeta::default();
    let missing = elt(7);
    if missing_letters {
        let cols = strings(VECTOR_ELT(missing, 0));
        let streams = VECTOR_ELT(missing, 1);
        for (k, name) in cols.into_iter().enumerate() {
            let name = name.unwrap_or_default();
            if !present.contains(name.as_str()) {
                continue;
            }
            let p = R_ExternalPtrAddr(VECTOR_ELT(streams, k as isize)) as *mut ArrowArrayStream;
            let letters = import_stream(p).map_err(fail)?;
            out.missing.push((name, letters));
        }
    }
    out.label = string_or_null(elt(0));
    out.timestamp = string_or_null(elt(1));
    out.notes = strings(elt(2)).into_iter().flatten().collect();
    out.sort = strings(elt(3)).into_iter().flatten().collect();
    let chars = elt(4);
    let (vars, keys, values) = (strings(VECTOR_ELT(chars, 0)), strings(VECTOR_ELT(chars, 1)), strings(VECTOR_ELT(chars, 2)));
    for ((variable, name), value) in vars.into_iter().zip(keys).zip(values) {
        let (variable, name, value) = (variable.unwrap_or_default(), name.unwrap_or_default(), value.unwrap_or_default());
        if dta && variable != "_dta" && (!present.contains(variable.as_str()) || name == FACTOR_MARK || name == CATEGORICAL_MARK) {
            continue;
        }
        match out.characteristics.iter_mut().find(|(v, _)| *v == variable) {
            Some((_, list)) => match list.iter_mut().find(|(n, _)| *n == name) {
                Some(entry) => entry.1 = value,
                None => list.push((name, value)),
            },
            None => out.characteristics.push((variable, vec![(name, value)])),
        }
    }
    let cols = elt(5);
    let col_names = strings(VECTOR_ELT(cols, 0));
    let (labels, formats, sets) = (strings(VECTOR_ELT(cols, 1)), strings(VECTOR_ELT(cols, 2)), strings(VECTOR_ELT(cols, 3)));
    let ordered = VECTOR_ELT(cols, 4);
    let ordered: &[c_int] = if TYPEOF(ordered) == LGLSXP && Rf_xlength(ordered) as usize == col_names.len() {
        std::slice::from_raw_parts(LOGICAL(ordered), col_names.len())
    } else {
        &[]
    };
    let mut columns = HashMap::new();
    for (k, name) in col_names.into_iter().enumerate() {
        let Some(name) = name.filter(|n| present.contains(n.as_str())) else { continue };
        let entry = ColumnEntry {
            label: labels.get(k).cloned().flatten(),
            format: formats.get(k).cloned().flatten(),
            value_labels: sets.get(k).cloned().flatten(),
            ordered: ordered.get(k).and_then(|&b| (b != NA_INTEGER).then_some(b != 0)),
        };
        columns.insert(name, entry);
    }
    out.columns = columns;
    let sets = elt(6);
    let set_names = strings(VECTOR_ELT(sets, 0));
    let (codes, texts) = (VECTOR_ELT(sets, 1), VECTOR_ELT(sets, 2));
    let mut given: Vec<GivenSet> = Vec::with_capacity(set_names.len());
    for (k, name) in set_names.into_iter().enumerate() {
        let c = VECTOR_ELT(codes, k as isize);
        let n = Rf_xlength(c).max(0) as usize;
        let c: &[f64] = if TYPEOF(c) == REALSXP && n > 0 { std::slice::from_raw_parts(REAL(c), n) } else { &[] };
        let t = strings(VECTOR_ELT(texts, k as isize));
        let labels = c.iter().zip(t).map(|(&x, t)| (code_of(x), t.unwrap_or_default())).collect();
        given.push((name.unwrap_or_default(), labels));
    }
    out.value_labels = given;
    Ok(out)
}

/// The names of an imported frame's columns.
fn column_names(imported: &Imported) -> Vec<&str> {
    imported.schema.children.iter().map(|f| f.name.as_str()).collect()
}

/// Write the frame in the stream at `stream` (polars' export, through
/// nanoarrow) as Parquet to `path`, with `meta` as [`write_meta`] reads
/// it.
///
/// # Safety
/// The pointers come from init.c: `stream` a valid stream not taken,
/// `meta` checked there.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_parquet_write_arrow_rs(
    stream: *mut ArrowArrayStream,
    path: *const c_char,
    meta: Sexp,
    compression: *const c_char,
    level: c_int,
    has_level: c_int,
    row_group_size: f64,
    missing_letters: c_int,
    timestamps: *const c_char,
    threads: c_int,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let compression = c_str(compression).unwrap_or_default();
    let timestamps = c_str(timestamps).unwrap_or_default();
    guard(err, err_len, || {
        // Taken first, so that the call consumes the stream whatever
        // else fails.
        let imported = import_stream(stream).map_err(fail)?;
        let mode = Stamps::from_name(&timestamps).map_err(fail)?;
        let rows = (row_group_size.is_finite() && row_group_size >= 1.0).then_some(row_group_size as usize);
        let level = (has_level != 0).then_some(level);
        let options =
            parquet_options(&compression, level, rows, missing_letters != 0, threads.max(0) as usize).map_err(fail)?;
        let meta = write_meta(meta, &column_names(&imported), missing_letters != 0, false)?;
        parquet_write(&imported, Some(&path), &meta, options, mode).map_err(fail)?;
        Ok(())
    })
}

/// Write the frame in the stream at `stream` as release 118 to `path`,
/// with `meta` as [`write_meta`] reads it.
///
/// # Safety
/// As for [`dtaparser_parquet_write_arrow_rs`].
#[no_mangle]
pub unsafe extern "C" fn dtaparser_dta_write_arrow_rs(
    stream: *mut ArrowArrayStream,
    path: *const c_char,
    meta: Sexp,
    missing_letters: c_int,
    timestamps: *const c_char,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let timestamps = c_str(timestamps).unwrap_or_default();
    guard(err, err_len, || {
        let imported = import_stream(stream).map_err(fail)?;
        let mode = Stamps::from_name(&timestamps).map_err(fail)?;
        let meta = write_meta(meta, &column_names(&imported), missing_letters != 0, true)?;
        dta_write(&imported, &path, &meta, missing_letters != 0, mode, None).map_err(fail)
    })
}

// ---------------------------------------------------------------- fixed width

/// Read the fixed-width file `data` as the SAS setup files `setups` (a
/// character vector, read in order) describe, and write it as release
/// 118 to the new file `out` (created here; an existing file is an
/// error). The setup's warnings,
/// a character vector, are element 0 of `holder`.
///
/// # Safety
/// The strings are NUL-terminated; `setups` a character vector.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_fixed_width_dta_rs(
    data: *const c_char,
    setups: Sexp,
    out: *const c_char,
    recodes: *const c_char,
    commented_formats: c_int,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let data = c_str(data).unwrap_or_default();
    let out = c_str(out).unwrap_or_default();
    let recodes = c_str(recodes).unwrap_or_default();
    let setups: Vec<String> = strings(setups).into_iter().flatten().collect();
    guard(err, err_len, || {
        let mode = dta::Recodes::from_name(&recodes).ok_or_else(|| {
            Fail::Message(format!("recodes must be \"setup\", \"tagged\" or \"none\", not \"{recodes}\""))
        })?;
        let read = |p: &str| std::fs::read(p).map_err(|e| Fail::Message(format!("{p}: {e}")));
        let setup_bytes = setups.iter().map(|p| read(p)).collect::<Res<Vec<Vec<u8>>>>()?;
        let data_bytes = read(&data)?;
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
        let file = options.open(&out).map_err(|e| Fail::Message(format!("{out}: {e}")))?;
        let setup_refs: Vec<&[u8]> = setup_bytes.iter().map(Vec::as_slice).collect();
        let warnings =
            dta::fixed_width_to_dta(&setup_refs, &data_bytes, mode, commented_formats != 0, std::io::BufWriter::new(file))?;
        let messages: Vec<String> = warnings.into_iter().map(|w| w.message).collect();
        strings_elt(holder, 0, &messages)
    })
}
