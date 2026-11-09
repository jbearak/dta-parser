//! The `.dta` exports of the npm package's wasm module (feature
//! `wasm-dta`); what they share with the Parquet module is in
//! `wasm_common.rs`.
//!
//! The module reads files through one import, `host_read(file, ptr, len,
//! offset)`, which JavaScript implements over `fs.readSync` or a
//! `Uint8Array`, so a file never has to fit in wasm memory. Offsets and
//! counts that may exceed 2^32 cross as `f64`.

use std::cell::RefCell;

use dta::{Column, Encoding, Options, Reader, StorageType};

use crate::json;
use crate::strings::{self, Dict, Strings};
use crate::wasm_common::{
    call, copy, ensure_room, result, too_large, Fail, HostFile, HostSink, State, CLOSED, STATE,
};

struct Handle {
    reader: Reader<HostFile>,
    columns: Vec<Column>,
    /// Per read column: its dictionary over the current read, and what
    /// the last call hands JavaScript for it (None for numbers).
    dicts: Vec<Dict>,
    strings: Vec<Option<Strings>>,
}

/// The open readers and the read settings, in the shared `State`.
pub(crate) struct DtaState {
    handles: Vec<Option<Handle>>,
    /// Most decoded bytes a read call holds (`BUDGET`; tests lower it).
    budget: usize,
    /// Bytes per decoded chunk for readers opened from now (0: the
    /// core's default; tests lower it).
    chunk_bytes: usize,
    /// Longest string JavaScript can make, in UTF-16 units, for readers
    /// opened from now (tests lower it).
    string_limit: usize,
}

impl Default for DtaState {
    fn default() -> Self {
        DtaState { handles: Vec::new(), budget: BUDGET, chunk_bytes: 0, string_limit: STRING_LIMIT }
    }
}

/// Test builds only (`--features test-hooks`): lower the read budget, and
/// the chunk size and string limit of readers opened from now, so small
/// files exercise what large ones do.
#[cfg(feature = "test-hooks")]
#[no_mangle]
pub extern "C" fn dta_test_set(budget: usize, chunk_bytes: usize, string_limit: usize) {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        state.dta.budget = budget;
        state.dta.chunk_bytes = chunk_bytes;
        state.dta.string_limit = string_limit;
    })
}

fn handle(state: &mut State, h: u32) -> Result<&mut Handle, Fail> {
    state
        .dta
        .handles
        .get_mut(h.wrapping_sub(1) as usize)
        .and_then(Option::as_mut)
        .ok_or_else(|| Fail { kind: CLOSED, message: "the file is closed".into() })
}

/// Open host file `file` of `len` bytes. `encoding` is 0 for
/// Windows-1252, 1 for Latin-1, 2 for UTF-8 (files before 118 only).
/// Returns a handle, or 0.
#[no_mangle]
pub extern "C" fn dta_open(file: u32, len: f64, encoding: u32) -> u32 {
    call(0, |state| {
        let encoding = match encoding {
            0 => Encoding::Windows1252,
            1 => Encoding::Latin1,
            2 => Encoding::Utf8,
            _ => return Err("unknown encoding".into()),
        };
        let source = HostFile { id: file, len: len as u64 };
        let defaults = Options::default();
        let chunk_bytes = if state.dta.chunk_bytes > 0 { state.dta.chunk_bytes } else { defaults.chunk_bytes };
        let max_text_units = Some(state.dta.string_limit);
        let reader = Reader::open(source, Options { encoding, chunk_bytes, max_text_units, ..defaults })?;
        state.dta.handles.push(Some(Handle { reader, columns: Vec::new(), dicts: Vec::new(), strings: Vec::new() }));
        Ok(state.dta.handles.len() as u32)
    })
}

#[no_mangle]
pub extern "C" fn dta_close(h: u32) {
    // Frees, so it runs even when memory is too short for the reserve.
    STATE.with(|cell| {
        if let Some(slot) = cell.borrow_mut().dta.handles.get_mut(h.wrapping_sub(1) as usize) {
            *slot = None;
        }
    })
}

/// The header and descriptors as JSON.
#[no_mangle]
pub extern "C" fn dta_metadata(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let meta = handle(state, h)?.reader.metadata();
        // JSON escapes a byte into at most six.
        let texts = meta.label.len() + meta.timestamp.len()
            + meta.variables.iter().map(|v| v.name.len() + v.format.len() + v.label.len() + v.value_labels.len() + 24).sum::<usize>();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        let bytes = json::metadata(handle(state, h)?.reader.metadata()).into_bytes();
        Ok(result(state, bytes))
    })
}

/// Every value label set as JSON.
#[no_mangle]
pub extern "C" fn dta_value_labels(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let sets = handle(state, h)?.reader.value_labels()?;
        let texts: usize = sets.iter().map(|s| s.name.len() + s.labels.iter().map(|l| l.text.len() + 12).sum::<usize>() + 16).sum();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        Ok(result(state, json::value_labels(&sets).into_bytes()))
    })
}

/// Every characteristic as JSON.
#[no_mangle]
pub extern "C" fn dta_characteristics(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let chars = handle(state, h)?.reader.characteristics()?;
        let texts: usize = chars.iter().map(|c| c.variable.len() + c.name.len() + c.value.len() + 12).sum();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        Ok(result(state, json::characteristics(&chars).into_bytes()))
    })
}

/// The strL index as bytes (see `dta::Reader::strl_index_bytes`).
#[no_mangle]
pub extern "C" fn dta_strl_index(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let bytes = handle(state, h)?.reader.strl_index_bytes()?;
        Ok(result(state, bytes))
    })
}

/// Adopt the `len` bytes at `index` as the strL index (see
/// `dta::Reader::adopt_strl_index`); they are copied first. Returns 1, or
/// 0 on failure.
///
/// # Safety
/// `index` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_adopt_strl_index(h: u32, index: *const u8, len: usize) -> u32 {
    call(0, |state| {
        let bytes = std::slice::from_raw_parts(index, len);
        handle(state, h)?.reader.adopt_strl_index(bytes)?;
        Ok(1)
    })
}

/// Read up to `count` rows from `start` of the `ncols` variables listed
/// (u32 indices) at `cols`, stopping after the row at which the decoded
/// output reaches 64 MiB, so module memory stays bounded. The columns
/// stay in the handle for `dta_column_part` until the next read. Returns
/// the number of rows read, or -1 on failure.
///
/// `flags`: `NEW_READ` starts a read (dictionaries begin again);
/// `DICTIONARY` codes string columns while they repeat enough (see
/// `strings.rs`). See `dta_column_mode` for what each column holds.
/// `max_string_bytes` (negative for none) keeps at most that many
/// stored bytes of each string, and records each one's full stored
/// length (part 6).
///
/// # Safety
/// `cols` must point to `ncols` u32 values.
#[no_mangle]
pub unsafe extern "C" fn dta_read(
    h: u32,
    cols: *const u32,
    ncols: usize,
    start: f64,
    count: f64,
    flags: u32,
    max_string_bytes: f64,
) -> f64 {
    let cols: Vec<usize> = std::slice::from_raw_parts(cols, ncols).iter().map(|&c| c as usize).collect();
    read_call(h, &cols, count as usize, flags, max_string_bytes, |reader, budget, columns| {
        Ok(reader.read_into(&cols, start as u64, count as u64, Some(budget), columns)? as usize)
    })
}

/// `dta_read` for the `nrows` rows listed at `rows` (little-endian f64
/// indices, unaligned), in their order: a sorted or filtered page in one
/// call. Returns how many of them were read (the 64 MiB limit applies),
/// or -1 on failure.
///
/// # Safety
/// `cols` must point to `ncols` u32 values, `rows` to `8 * nrows` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_read_at(
    h: u32,
    cols: *const u32,
    ncols: usize,
    rows: *const u8,
    nrows: usize,
    flags: u32,
    max_string_bytes: f64,
) -> f64 {
    let cols: Vec<usize> = std::slice::from_raw_parts(cols, ncols).iter().map(|&c| c as usize).collect();
    let rows = std::slice::from_raw_parts(rows, nrows.saturating_mul(8));
    read_call(h, &cols, nrows, flags, max_string_bytes, |reader, budget, columns| {
        let mut at = Vec::new();
        at.try_reserve_exact(nrows).map_err(|_| too_large(rows.len()))?;
        at.extend(rows.chunks_exact(8).map(|b| f64::from_le_bytes(b.try_into().unwrap_or_default()) as u64));
        Ok(reader.read_rows_into(&cols, &at, Some(budget), columns)?)
    })
}

/// What `dta_read` and `dta_read_at` share: room for up to `count` rows,
/// the read itself, then each string column coded or made plain.
fn read_call(
    h: u32,
    cols: &[usize],
    count: usize,
    flags: u32,
    max_string_bytes: f64,
    read: impl FnOnce(&mut Reader<HostFile>, usize, &mut [Column]) -> Result<usize, Fail>,
) -> f64 {
    call(-1.0, |state| {
        let budget = state.dta.budget;
        let handle = handle(state, h)?;
        let Handle { reader, columns, dicts, strings } = handle;
        // Room for this call's columns and what it hands JavaScript.
        let meta = reader.metadata();
        let per_row: usize = cols
            .iter()
            .map(|&c| match meta.variables.get(c).map(|v| v.storage) {
                Some(StorageType::Str(w)) => 3 * w as usize + 16,
                Some(StorageType::StrL) => 32,
                _ => 9,
            })
            .sum();
        let rows_bytes = count.saturating_mul(per_row).min(budget.saturating_add(per_row));
        ensure_room(rows_bytes.saturating_mul(2))?;
        strings.clear();
        if flags & NEW_READ != 0 || dicts.len() != cols.len() {
            dicts.clear();
            dicts.resize_with(cols.len(), Dict::default);
        }
        columns.clear();
        // Room for the rows this call can return (the budget allows about
        // BUDGET / 9 numbers), so appending chunks does not regrow the
        // columns and leave freed copies in module memory.
        let rows = count.min(budget / (9 * cols.len()).max(1) + 1);
        *columns = cols
            .iter()
            .map(|&c| match meta.variables.get(c).map(|v| v.storage.is_numeric()) {
                Some(false) => Column::Strings { bytes: Vec::new(), ends: Vec::with_capacity(rows), binary: Vec::new() },
                _ => Column::Numbers { values: Vec::with_capacity(rows), missing: Vec::with_capacity(rows) },
            })
            .collect();
        reader.set_preview((max_string_bytes >= 0.0).then_some(max_string_bytes as usize));
        // Decoded straight into the call's columns, so a large strL is
        // not held twice.
        let n = read(reader, budget, columns)?;
        for (column, dict) in columns.iter().zip(dicts.iter_mut()) {
            strings.push(match column {
                Column::Numbers { .. } => None,
                Column::Strings { bytes, ends, binary } => Some(
                    match (flags & DICTIONARY != 0).then(|| dict.code(bytes, ends, binary)).flatten() {
                        Some((codes, new_bytes, new_utf16)) => Strings::Coded { codes, new_bytes, new_utf16 },
                        None => strings::plain(bytes, ends, binary).ok_or_else(|| too_large(bytes.len()))?,
                    },
                ),
            });
        }
        Ok(n as f64)
    })
}

const NEW_READ: u32 = 1;
const DICTIONARY: u32 = 2;

/// Free the dictionaries of the read that just ended.
#[no_mangle]
pub extern "C" fn dta_read_end(h: u32) {
    // Frees, so it runs even when memory is too short for the reserve.
    STATE.with(|cell| {
        if let Some(Some(handle)) = cell.borrow_mut().dta.handles.get_mut(h.wrapping_sub(1) as usize) {
            handle.dicts = Vec::new();
            handle.strings = Vec::new();
        }
    })
}

/// What read column `k` holds after `dta_read`: 0 numbers, 1 plain
/// strings, 2 dictionary codes.
#[no_mangle]
pub extern "C" fn dta_column_mode(h: u32, k: usize) -> u32 {
    call(0, |state| {
        Ok(match handle(state, h)?.strings.get(k).ok_or("no such column")? {
            None => 0,
            Some(Strings::Plain { .. }) => 1,
            Some(Strings::Coded { .. }) => 2,
        })
    })
}

/// Decoded bytes one read may hold in module memory (plus one row).
pub(crate) const BUDGET: usize = 64 << 20;

/// V8's longest string, in UTF-16 units: 2^29 - 24.
const STRING_LIMIT: usize = (1 << 29) - 24;

/// A buffer of read column `k`. Numbers: `part` 0 the f64 values, 1
/// the missing codes (u8). Plain strings: 0 the text bytes, 1 the
/// cumulative UTF-16 ends (u32, one per row), 2 the binary flags (u8,
/// strLs only), 3 every row's bytes as decoded (for the binary rows), 4
/// their cumulative byte ends (u32, one per row). Dictionary codes: 0
/// the new values' bytes, 1 their cumulative UTF-16 ends, 5 the codes
/// (u32, one per row). Previews (plain): 6 the stored lengths (u32, one
/// per row). Returns a pointer; `dta_result_len` gives the element count.
#[no_mangle]
pub extern "C" fn dta_column_part(h: u32, k: usize, part: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let handle = handle(state, h)?;
        let column = handle.columns.get(k).ok_or("no such column")?;
        let strings = handle.strings.get(k).and_then(Option::as_ref);
        let (ptr, len) = match (column, strings, part) {
            (Column::Numbers { values, .. }, _, 0) => (values.as_ptr() as *const u8, values.len()),
            (Column::Numbers { missing, .. }, _, 1) => (missing.as_ptr(), missing.len()),
            (Column::Strings { bytes, .. }, Some(Strings::Plain { text, .. }), 0) => {
                let text = text.as_ref().unwrap_or(bytes);
                (text.as_ptr(), text.len())
            }
            (_, Some(Strings::Plain { utf16: Some(utf16), .. }), 1) => (utf16.as_ptr() as *const u8, utf16.len()),
            // All ASCII: the byte ends are the UTF-16 ends.
            (Column::Strings { ends, .. }, Some(Strings::Plain { utf16: None, .. }), 1) => (ends.as_ptr() as *const u8, ends.len()),
            (Column::Strings { binary, .. }, Some(Strings::Plain { .. }), 2) => (binary.as_ptr() as *const u8, binary.len()),
            (Column::Strings { bytes, .. }, Some(Strings::Plain { .. }), 3) => (bytes.as_ptr(), bytes.len()),
            (Column::Strings { ends, .. }, Some(Strings::Plain { .. }), 4) => (ends.as_ptr() as *const u8, ends.len()),
            (_, Some(Strings::Coded { new_bytes, .. }), 0) => (new_bytes.as_ptr(), new_bytes.len()),
            (_, Some(Strings::Coded { new_utf16, .. }), 1) => (new_utf16.as_ptr() as *const u8, new_utf16.len()),
            (_, Some(Strings::Coded { codes, .. }), 5) => (codes.as_ptr() as *const u8, codes.len()),
            (Column::Strings { .. }, Some(_), 6) => {
                let stored = handle.reader.stored_lengths(k);
                (stored.as_ptr() as *const u8, stored.len())
            }
            _ => return Err("no such column part".into()),
        };
        state.result_len = len;
        Ok(ptr)
    })
}

// Writing. JavaScript builds a dataset with the calls below, copying
// each column into module memory, then `dta_write_finish` streams the
// file out through `host_write`.

enum WriteData {
    Numbers(Vec<f64>, Vec<u8>),
    Strings(Vec<u8>, Vec<u32>),
    /// strLs: bytes, ends, and per row 1 if binary.
    StrLs(Vec<u8>, Vec<u32>, Vec<u8>),
}

struct WriteColumn {
    name: String,
    storage: dta::StorageType,
    format: String,
    label: String,
    value_labels: String,
    data: WriteData,
}

#[derive(Default)]
struct WriteState {
    nobs: usize,
    columns: Vec<WriteColumn>,
    sets: Vec<dta::ValueLabelSet>,
    characteristics: Vec<dta::Characteristic>,
    sort_order: Vec<usize>,
}

thread_local! {
    static WRITE: RefCell<WriteState> = RefCell::new(WriteState::default());
}

/// Fields separated by NUL: name, format, label, value label set name.
fn fields(bytes: &[u8]) -> Result<Vec<String>, String> {
    std::str::from_utf8(bytes)
        .map(|s| s.split('\0').map(str::to_string).collect())
        .map_err(|_| "names and labels must be UTF-8".to_string())
}

/// Start a new dataset of `nobs` rows, dropping any half-built one.
#[no_mangle]
pub extern "C" fn dta_write_begin(nobs: f64) {
    WRITE.with(|w| *w.borrow_mut() = WriteState { nobs: nobs as usize, ..Default::default() });
}

/// Add a numeric column: `meta` holds NUL-separated name, format,
/// label, value label set; `storage` 0 to 4 is byte, int, long, float,
/// double; `values` and `missing` hold `nobs` elements each.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn dta_write_numbers(
    meta: *const u8,
    meta_len: usize,
    storage: u32,
    values: *const f64,
    missing: *const u8,
) -> u32 {
    call(0, |_| {
        let f = fields(&copy(meta, meta_len)?)?;
        let storage = [
            dta::StorageType::Byte,
            dta::StorageType::Int,
            dta::StorageType::Long,
            dta::StorageType::Float,
            dta::StorageType::Double,
        ]
        .get(storage as usize)
        .copied()
        .ok_or("unknown storage type")?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let n = w.nobs;
            let column = column(&f, storage, WriteData::Numbers(copy(values, n)?, copy(missing, n)?))?;
            w.columns.push(column);
            Ok(1)
        })
    })
}

/// Add a string column: `bytes` and `nobs` end offsets. With `binary`
/// null, the values are UTF-8 text, written as strN or, beyond 2045
/// bytes, strL. Otherwise the column is strL and `binary` holds `nobs`
/// flags: 1 where the value is binary bytes, 0 where it is UTF-8 text.
///
/// # Safety
/// The pointers hold the stated lengths; `binary` is null or holds
/// `nobs` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_strings(
    meta: *const u8,
    meta_len: usize,
    bytes: *const u8,
    bytes_len: usize,
    ends: *const u32,
    binary: *const u8,
) -> u32 {
    call(0, |_| {
        let f = fields(&copy(meta, meta_len)?)?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let ends = copy(ends, w.nobs)?;
            if ends.iter().any(|&e| e as usize > bytes_len) || ends.windows(2).any(|p| p[0] > p[1]) {
                return Err("string offsets out of order".into());
            }
            let bytes = copy(bytes, bytes_len)?;
            let (storage, data) = if binary.is_null() {
                (dta::StorageType::Str(1), WriteData::Strings(bytes, ends))
            } else {
                (dta::StorageType::StrL, WriteData::StrLs(bytes, ends, copy(binary, w.nobs)?))
            };
            let column = column(&f, storage, data)?;
            w.columns.push(column);
            Ok(1)
        })
    })
}

fn column(f: &[String], storage: dta::StorageType, data: WriteData) -> Result<WriteColumn, Fail> {
    let [name, format, label, value_labels] = f else { return Err("expected four fields".into()) };
    Ok(WriteColumn {
        name: name.clone(),
        storage,
        format: format.clone(),
        label: label.clone(),
        value_labels: value_labels.clone(),
        data,
    })
}

/// Add a value label set: `n` values with missing codes, and texts as
/// UTF-8 bytes with `n` end offsets.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn dta_write_labels(
    name: *const u8,
    name_len: usize,
    n: usize,
    values: *const f64,
    missing: *const u8,
    texts: *const u8,
    texts_len: usize,
    ends: *const u32,
) -> u32 {
    call(0, |_| {
        let name = String::from_utf8(copy(name, name_len)?).map_err(|_| "label set names must be UTF-8")?;
        let (values, codes, ends) = (copy(values, n)?, copy(missing, n)?, copy(ends, n)?);
        let texts = String::from_utf8(copy(texts, texts_len)?).map_err(|_| "labels must be UTF-8")?;
        let mut labels = Vec::with_capacity(n);
        let mut from = 0;
        for i in 0..n {
            let to = ends[i] as usize;
            let text = texts.get(from..to).ok_or("label offsets out of order")?.to_string();
            labels.push(dta::ValueLabel { value: values[i], missing: codes[i], text });
            from = to;
        }
        WRITE.with(|w| w.borrow_mut().sets.push(dta::ValueLabelSet { name, labels }));
        Ok(1)
    })
}

/// Add characteristics: `text` holds NUL-separated variable, name and
/// value, three fields per characteristic.
///
/// # Safety
/// `text` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_characteristics(text: *const u8, len: usize) -> u32 {
    call(0, |_| {
        let f = fields(&copy(text, len)?)?;
        if f.len() % 3 != 0 {
            return Err("expected three fields per characteristic".into());
        }
        let chars = f.chunks_exact(3).map(|c| dta::Characteristic {
            variable: c[0].clone(),
            name: c[1].clone(),
            value: c[2].clone(),
        });
        WRITE.with(|w| w.borrow_mut().characteristics.extend(chars));
        Ok(1)
    })
}

/// Set the sort order: `n` 0-based variable indices.
///
/// # Safety
/// `indices` holds `n` u32 values.
#[no_mangle]
pub unsafe extern "C" fn dta_write_sort_order(indices: *const u32, n: usize) -> u32 {
    call(0, |_| {
        let order = copy(indices, n)?.into_iter().map(|i| i as usize).collect();
        WRITE.with(|w| w.borrow_mut().sort_order = order);
        Ok(1)
    })
}

/// Write the dataset to host file `file`. `info` holds NUL-separated
/// data label, timestamp, then the notes, which follow the
/// characteristics added. Returns 1, or 0 on failure.
///
/// # Safety
/// `info` holds `info_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_finish(file: u32, info: *const u8, info_len: usize) -> u32 {
    call(0, |_| {
        let info = fields(&copy(info, info_len)?)?;
        let state = WRITE.with(|w| std::mem::take(&mut *w.borrow_mut()));
        let notes: Vec<&String> = info.iter().skip(2).collect();
        let mut characteristics = state.characteristics;
        if !notes.is_empty() {
            let note = |n: usize, value: &str| dta::Characteristic {
                variable: "_dta".into(),
                name: format!("note{n}"),
                value: value.into(),
            };
            characteristics.push(note(0, &notes.len().to_string()));
            characteristics.extend(notes.iter().enumerate().map(|(i, v)| note(i + 1, v)));
        }
        let variables = state
            .columns
            .iter()
            .map(|c| dta::WriteVariable {
                name: c.name.clone(),
                storage: c.storage,
                format: c.format.clone(),
                label: c.label.clone(),
                value_labels: c.value_labels.clone(),
                values: match &c.data {
                    WriteData::Numbers(v, m) => dta::Values::numbers_by_row(move |i| (v[i], m[i])),
                    WriteData::Strings(b, e) => dta::Values::Strings(Box::new(move |i| {
                        let start = if i == 0 { 0 } else { e[i - 1] as usize };
                        &b[start..e[i] as usize]
                    })),
                    WriteData::StrLs(b, e, binary) => dta::Values::StrLs(Box::new(move |i| {
                        let start = if i == 0 { 0 } else { e[i - 1] as usize };
                        (&b[start..e[i] as usize], binary[i] != 0)
                    })),
                },
            })
            .collect();
        let data = dta::Dataset {
            nobs: state.nobs,
            label: info.first().cloned().unwrap_or_default(),
            timestamp: info.get(1).cloned().unwrap_or_default(),
            variables,
            value_labels: state.sets.clone(),
            characteristics,
            sort_order: state.sort_order,
        };
        // The writer's own tables: a row number per strL row, and one
        // entry per distinct strL.
        let strls = data.variables.iter().filter(|v| v.storage == StorageType::StrL).count();
        ensure_room(data.nobs.saturating_mul(strls).saturating_mul(64).saturating_add(4 << 20))?;
        dta::write(&data, HostSink(file))?;
        Ok(1)
    })
}
