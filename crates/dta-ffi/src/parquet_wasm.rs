//! The Parquet half of the npm package's wasm module (plan 0018).
//!
//! Reading: `pq_open` reads a file's footer through `host_read` (as
//! `dta_open` does), and `pq_info` describes it as JSON: row groups,
//! codecs, and per column its types, the column kind the npm package
//! returns, its labels from the dta profile and its statistics per row
//! group. `pq_read` decodes a selection of columns over a window of rows
//! straight into buffers here, which JavaScript copies out through the
//! directory `pq_directory` gives; JavaScript keeps each call under the
//! 64 MiB the `.dta` reader allows, by the footer's sizes. `pq_plan`
//! gives the byte ranges a read needs, for the async reader to fetch
//! before it reads. Nothing reads a whole file into module memory.
//!
//! Writing: JavaScript copies each column in (`pq_write_numbers`, ...),
//! then `pq_write_finish` streams the file out through `host_write`.
//!
//! The rules of what each Parquet type becomes are plan 0018's
//! "Exactness" table, TypeScript column.

use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Write as _;

use dta::{Characteristic, ErrorKind, ValueLabel, ValueLabelSet};
use dta_parquet::format::{converted, Codec, FileMetaData, LogicalType, PhysicalType, TimeUnit};
use dta_parquet::{
    ColumnInfo, ColumnProfile, ColumnType, Compression, LevelsFrom, Logical, Nested, Numbers, Output, Profile, ReadOptions,
    Reader, Role, Table, TextChunk, Values, WriteColumn, WriteOptions,
};

use crate::json;
use crate::strings::{utf16_len, Dict};
use crate::wasm::{call, copy, ensure_room, result, Fail, HostFile, HostSink, State, CLOSED, INVALID};

/// The largest safe integer: every integer of at most this size is a
/// distinct double, and JavaScript's `Number.isSafeInteger` holds for it.
const SAFE: f64 = 9_007_199_254_740_991.0;

/// How a column reads.
#[derive(Clone, Debug)]
enum How {
    /// Into doubles with a missing code per row. `check`: an INT64 read as
    /// numbers, each value checked to be a safe integer.
    Number { check: bool },
    /// INT64 into 64-bit integers (`unsigned` for UINT64).
    BigInt { unsigned: bool },
    Text { binary: bool },
    /// A categorical, as level codes.
    Levels,
    /// Not read; the text says why.
    NotRead(String),
}

/// What a read call leaves for JavaScript, per selected column.
enum Out {
    Number { values: Vec<f64>, codes: Vec<u8> },
    BigInt { values: Vec<i64>, codes: Vec<u8>, unsigned: bool },
    /// Codes into the read's dictionary (`u32::MAX` for a null), and the
    /// values first seen in this call.
    Coded { codes: Vec<u32>, new_bytes: Vec<u8>, new_utf16: Vec<u32> },
    /// Every row's bytes, byte ends, null flags, and UTF-16 ends unless
    /// the text is all ASCII (or the column binary).
    Plain { bytes: Vec<u8>, ends: Vec<u32>, missing: Vec<u8>, utf16: Option<Vec<u32>>, binary: bool },
    /// Level codes from 0 (-1 for a null), and the levels found in the
    /// rows of this call, for a categorical whose levels come from the rows.
    Levels { codes: Vec<i32>, found_bytes: Vec<u8>, found_utf16: Vec<u32> },
}

struct PqHandle {
    reader: Reader<HostFile>,
    how: Vec<How>,
    /// Per reader column, its dictionary over the current read.
    dicts: HashMap<usize, Dict>,
    outs: Vec<Out>,
    directory: Vec<u32>,
}

thread_local! {
    static HANDLES: RefCell<Vec<Option<PqHandle>>> = const { RefCell::new(Vec::new()) };
}

fn closed() -> Fail {
    Fail { kind: CLOSED, message: "the file is closed".into() }
}

/// Run `f` on handle `h`.
fn with_handle<T>(h: u32, f: impl FnOnce(&mut PqHandle) -> Result<T, Fail>) -> Result<T, Fail> {
    HANDLES.with(|cell| {
        let mut handles = cell.borrow_mut();
        let handle = handles.get_mut(h.wrapping_sub(1) as usize).and_then(Option::as_mut).ok_or_else(closed)?;
        f(handle)
    })
}

// ---------------------------------------------------------------- JSON

fn push_str(o: &mut String, s: &str) {
    o.push('"');
    if s.bytes().all(|b| b >= 0x20 && b != b'"' && b != b'\\') {
        o.push_str(s);
        o.push('"');
        return;
    }
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
}

fn key(o: &mut String, k: &str) {
    if !o.ends_with('{') && !o.ends_with('[') {
        o.push(',');
    }
    push_str(o, k);
    o.push(':');
}

fn num(o: &mut String, x: f64) {
    if x.is_finite() {
        o.push_str(&format!("{x}"));
    } else {
        o.push_str("null");
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// ---------------------------------------------------------------- types

fn unit_name(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "ms",
        TimeUnit::Micros => "us",
        TimeUnit::Nanos => "ns",
    }
}

fn unit_upper(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "MILLIS",
        TimeUnit::Micros => "MICROS",
        TimeUnit::Nanos => "NANOS",
    }
}

/// Parquet's logical type (or else its converted type) as text.
fn logical_name(col: &ColumnInfo) -> String {
    if let Some(l) = &col.logical {
        return match l {
            LogicalType::String => "STRING".into(),
            LogicalType::Map => "MAP".into(),
            LogicalType::List => "LIST".into(),
            LogicalType::Enum => "ENUM".into(),
            LogicalType::Decimal { scale, precision } => format!("DECIMAL({precision}, {scale})"),
            LogicalType::Date => "DATE".into(),
            LogicalType::Time { utc, unit } => {
                format!("TIME({}, {})", unit.map_or("?", unit_upper), if *utc { "UTC" } else { "local" })
            }
            LogicalType::Timestamp { utc, unit } => {
                format!("TIMESTAMP({}, {})", unit.map_or("?", unit_upper), if *utc { "UTC" } else { "local" })
            }
            LogicalType::Integer { bits, signed } => {
                format!("INT({bits}, {})", if *signed { "signed" } else { "unsigned" })
            }
            LogicalType::Null => "NULL".into(),
            LogicalType::Json => "JSON".into(),
            LogicalType::Bson => "BSON".into(),
            LogicalType::Uuid => "UUID".into(),
            LogicalType::Float16 => "FLOAT16".into(),
            LogicalType::Other(id) => format!("logical type {id}"),
        };
    }
    let name = match col.converted {
        Some(converted::UTF8) => "UTF8",
        Some(converted::ENUM) => "ENUM",
        Some(converted::DECIMAL) => "DECIMAL",
        Some(converted::DATE) => "DATE",
        Some(converted::TIME_MILLIS) => "TIME_MILLIS",
        Some(converted::TIME_MICROS) => "TIME_MICROS",
        Some(converted::TIMESTAMP_MILLIS) => "TIMESTAMP_MILLIS",
        Some(converted::TIMESTAMP_MICROS) => "TIMESTAMP_MICROS",
        Some(converted::UINT_8) => "UINT_8",
        Some(converted::UINT_16) => "UINT_16",
        Some(converted::UINT_32) => "UINT_32",
        Some(converted::UINT_64) => "UINT_64",
        Some(converted::INT_8) => "INT_8",
        Some(converted::INT_16) => "INT_16",
        Some(converted::INT_32) => "INT_32",
        Some(converted::INT_64) => "INT_64",
        Some(converted::JSON) => "JSON",
        Some(converted::BSON) => "BSON",
        Some(converted::INTERVAL) => "INTERVAL",
        _ => "",
    };
    name.into()
}

fn codec_name(c: Codec) -> String {
    match c {
        Codec::Uncompressed => "none".into(),
        Codec::Snappy => "snappy".into(),
        Codec::Gzip => "gzip".into(),
        Codec::Lzo => "lzo".into(),
        Codec::Brotli => "brotli".into(),
        Codec::Lz4 => "lz4".into(),
        Codec::Zstd => "zstd".into(),
        Codec::Lz4Raw => "lz4_raw".into(),
        Codec::Other(v) => format!("codec {v}"),
    }
}

/// The type name the npm package gives a column (`Variable.type`).
fn type_name(col: &ColumnInfo) -> &'static str {
    if col.role == Role::Nested {
        return "nested";
    }
    match &col.kind {
        ColumnType::Int8 => "byte",
        ColumnType::Int16 => "int",
        ColumnType::Int32 => "long",
        ColumnType::Int64 => "int64",
        ColumnType::UInt8 => "uint8",
        ColumnType::UInt16 => "uint16",
        ColumnType::UInt32 => "uint32",
        ColumnType::UInt64 => "uint64",
        ColumnType::Float => "float",
        ColumnType::Double => match (col.profile_logical, col.storage) {
            (Some(Logical::Date), _) => "date",
            (Some(Logical::Timestamp), _) => "timestamp",
            (None, Some(s)) => s.name(),
            _ => "double",
        },
        ColumnType::Boolean => "bool",
        ColumnType::Text if col.levels.is_some() => "categorical",
        ColumnType::Text => "string",
        ColumnType::Binary => "binary",
        ColumnType::Date => "date",
        ColumnType::Timestamp { .. } => "timestamp",
        ColumnType::Time { .. } => "time",
        ColumnType::Decimal { .. } => "decimal",
        ColumnType::Unsupported(_) => "unsupported",
    }
}

/// Whether a column holds 64-bit integers that may not fit a double.
fn is_int64(col: &ColumnInfo) -> bool {
    matches!(col.physical, Some(PhysicalType::Int64 | PhysicalType::Int96))
        && matches!(
            col.kind,
            ColumnType::Int64 | ColumnType::UInt64 | ColumnType::Timestamp { .. } | ColumnType::Time { .. }
        )
}

/// A statistic's 8 bytes as an integer, signed or not.
fn as_i128(b: &[u8], unsigned: bool) -> Option<i128> {
    let b: [u8; 8] = b.try_into().ok()?;
    Some(if unsigned { u64::from_le_bytes(b) as i128 } else { i64::from_le_bytes(b) as i128 })
}

/// How `int64: "auto"` reads a 64-bit column, and why: numbers when every
/// row group's statistics put every value within the safe integers.
fn int64_auto(meta: &FileMetaData, col: &ColumnInfo) -> (bool, String) {
    if col.physical == Some(PhysicalType::Int96) {
        return (false, "INT96 timestamps have no statistics to show their range".into());
    }
    let unsigned = col.kind == ColumnType::UInt64;
    for (g, group) in meta.row_groups.iter().enumerate() {
        let Some(m) = group.columns.get(col.leaf()).and_then(|c| c.meta.as_ref()) else {
            return (false, format!("row group {} has no column metadata", g + 1));
        };
        let Some(s) = &m.statistics else {
            return (false, format!("row group {} has no statistics", g + 1));
        };
        if s.null_count.is_some_and(|n| n >= 0 && n == m.num_values) {
            continue;
        }
        // The deprecated fields are in signed order, wrong for UINT64.
        let pick = |new: &Option<Vec<u8>>, old: &Option<Vec<u8>>| match new {
            Some(v) => Some(v.clone()),
            None if !unsigned => old.clone(),
            None => None,
        };
        let (Some(lo), Some(hi)) = (
            pick(&s.min_value, &s.min).and_then(|b| as_i128(&b, unsigned)),
            pick(&s.max_value, &s.max).and_then(|b| as_i128(&b, unsigned)),
        ) else {
            return (false, format!("row group {} has no minimum and maximum", g + 1));
        };
        let safe = SAFE as i128;
        if lo < -safe || hi > safe {
            let v = if hi > safe { hi } else { lo };
            return (false, format!("row group {}'s statistics hold {v}, beyond the safe integers (±(2^53 − 1))", g + 1));
        }
    }
    (true, "the statistics of every row group put every value within the safe integers (±(2^53 − 1))".into())
}

/// How each column reads, for an `int64` mode (0 auto, 1 bigint, 2
/// number); with the reason for each 64-bit column's kind.
fn plan_columns(r: &Reader<HostFile>, int64: u32) -> (Vec<How>, Vec<Option<String>>) {
    let profile = r.profile();
    let levels: HashMap<&str, ()> = profile.map_or_else(HashMap::new, |p| {
        p.columns.iter().filter(|c| c.categorical.is_some()).map(|c| (c.name.as_str(), ())).collect()
    });
    let mut hows = Vec::with_capacity(r.columns().len());
    let mut reasons = Vec::with_capacity(r.columns().len());
    for col in r.columns() {
        let mut reason = None;
        let how = if col.role == Role::Nested {
            How::NotRead(format!("column \"{}\" is nested (a list, map or group), which is not read", col.name))
        } else {
            match &col.kind {
                ColumnType::Unsupported(why) => How::NotRead(format!("column \"{}\" is {why}", col.name)),
                ColumnType::Text if col.levels == Some(LevelsFrom::Profile) && levels.contains_key(col.name.as_str()) => How::Levels,
                ColumnType::Text if col.levels == Some(LevelsFrom::Rows) => How::Levels,
                ColumnType::Text => How::Text { binary: false },
                ColumnType::Binary => How::Text { binary: true },
                ColumnType::Decimal { precision, .. } if *precision > 15 => How::Text { binary: false },
                _ if is_int64(col) => {
                    let unsigned = col.kind == ColumnType::UInt64;
                    let (number, why) = match int64 {
                        1 => (false, "int64: \"bigint\" was asked for".to_string()),
                        2 => (true, "int64: \"number\" was asked for".to_string()),
                        _ => int64_auto(r.metadata(), col),
                    };
                    reason = Some(why);
                    if number {
                        How::Number { check: true }
                    } else {
                        How::BigInt { unsigned }
                    }
                }
                _ => How::Number { check: false },
            }
        };
        hows.push(how);
        reasons.push(reason);
    }
    (hows, reasons)
}

/// The zone a timestamp shows in: the profile's, else `ARROW:schema`'s,
/// else UTC. `None` for a clock time without zone.
fn zone_of(col: &ColumnInfo, entry: Option<&ColumnProfile>) -> Option<String> {
    let instant = match &col.kind {
        ColumnType::Timestamp { utc, .. } => *utc,
        ColumnType::Double => col.profile_logical == Some(Logical::Timestamp),
        _ => return None,
    };
    if !instant {
        return None;
    }
    let profile = entry.and_then(|e| e.tz.as_deref()).filter(|z| !z.is_empty());
    let arrow = col.zone.as_deref().filter(|z| !z.is_empty());
    Some(profile.or(arrow).unwrap_or("UTC").to_string())
}

fn unit_of(col: &ColumnInfo) -> Option<&'static str> {
    match &col.kind {
        ColumnType::Date => Some("day"),
        ColumnType::Timestamp { unit, .. } | ColumnType::Time { unit, .. } => Some(unit_name(*unit)),
        ColumnType::Double => match col.profile_logical {
            Some(Logical::Date) => Some("day"),
            Some(Logical::Timestamp) => Some("s"),
            None => None,
        },
        _ => None,
    }
}

/// One statistic as `["n", number]`, `["b", "digits"]` (a bigint),
/// `["s", text]` or `["x", hex]` (bytes); `null` when it cannot be
/// shown (decimals, INT96, an unknown layout).
fn stat(o: &mut String, col: &ColumnInfo, bytes: Option<&Vec<u8>>, how: &How) {
    let Some(b) = bytes else {
        o.push_str("null");
        return;
    };
    let int = |o: &mut String, v: i128| {
        if matches!(how, How::BigInt { .. }) {
            o.push_str(&format!("[\"b\",\"{v}\"]"));
        } else {
            o.push_str(&format!("[\"n\",{v}]"));
        }
    };
    match (col.physical, &col.kind) {
        (_, ColumnType::Decimal { .. }) | (Some(PhysicalType::Int96), _) => o.push_str("null"),
        (Some(PhysicalType::Boolean), _) if b.len() == 1 => o.push_str(&format!("[\"n\",{}]", b[0] & 1)),
        (Some(PhysicalType::Int32), kind) if b.len() == 4 => {
            let raw: [u8; 4] = b[..4].try_into().unwrap_or_default();
            let v = if matches!(kind, ColumnType::UInt8 | ColumnType::UInt16 | ColumnType::UInt32) {
                u32::from_le_bytes(raw) as i128
            } else {
                i32::from_le_bytes(raw) as i128
            };
            o.push_str(&format!("[\"n\",{v}]"));
        }
        (Some(PhysicalType::Int64), kind) if b.len() == 8 => match as_i128(b, *kind == ColumnType::UInt64) {
            Some(v) => int(o, v),
            None => o.push_str("null"),
        },
        (Some(PhysicalType::Float), _) if b.len() == 4 => {
            let v = f32::from_le_bytes(b[..4].try_into().unwrap_or_default()) as f64;
            o.push_str("[\"n\",");
            num(o, v);
            o.push(']');
        }
        (Some(PhysicalType::Double), _) if b.len() == 8 => {
            let v = f64::from_le_bytes(b[..8].try_into().unwrap_or_default());
            o.push_str("[\"n\",");
            num(o, v);
            o.push(']');
        }
        (Some(PhysicalType::ByteArray), ColumnType::Text) => match std::str::from_utf8(b) {
            Ok(s) => {
                o.push_str("[\"s\",");
                push_str(o, s);
                o.push(']');
            }
            Err(_) => o.push_str(&format!("[\"x\",\"{}\"]", hex(b))),
        },
        (Some(PhysicalType::ByteArray | PhysicalType::FixedLenByteArray), _) => {
            o.push_str(&format!("[\"x\",\"{}\"]", hex(b)))
        }
        _ => o.push_str("null"),
    }
}

/// Whether value labels apply to a column: numbers that are not dates,
/// times or categoricals.
fn labels_apply(col: &ColumnInfo, how: &How) -> bool {
    matches!(how, How::Number { .. } | How::BigInt { .. })
        && !matches!(
            col.kind,
            ColumnType::Date | ColumnType::Timestamp { .. } | ColumnType::Time { .. } | ColumnType::Boolean
        )
        && col.profile_logical.is_none()
}

fn info_json(r: &Reader<HostFile>, how: &[How], reasons: &[Option<String>], mut o: String) -> String {
    let profile = r.profile();
    let meta = r.metadata();
    o.push('{');
    key(&mut o, "nobs");
    num(&mut o, r.rows() as f64);
    key(&mut o, "label");
    push_str(&mut o, profile.and_then(|p| p.label.as_deref()).unwrap_or(""));
    key(&mut o, "notes");
    o.push_str(&json::strings(profile.map_or(&[][..], |p| &p.notes[..])));
    key(&mut o, "sortedBy");
    o.push_str(&json::strings(profile.map_or(&[][..], |p| &p.sort[..])));
    key(&mut o, "createdBy");
    push_str(&mut o, r.created_by().unwrap_or(""));
    key(&mut o, "compression");
    o.push_str(&json::strings(&r.codecs().into_iter().map(codec_name).collect::<Vec<_>>()));
    key(&mut o, "warnings");
    o.push_str(&json::strings(r.warnings()));
    key(&mut o, "keyValue");
    o.push('[');
    for kv in &meta.key_value {
        o.push('{');
        key(&mut o, "key");
        push_str(&mut o, &kv.key);
        key(&mut o, "bytes");
        num(&mut o, kv.value.as_ref().map_or(0, Vec::len) as f64);
        o.push('}');
        o.push(',');
    }
    if o.ends_with(',') {
        o.pop();
    }
    o.push(']');
    key(&mut o, "rowGroups");
    o.push('[');
    for (g, rg) in r.row_groups().iter().enumerate() {
        if g > 0 {
            o.push(',');
        }
        o.push_str(&format!(
            "{{\"firstRow\":{},\"rows\":{},\"compressedBytes\":{},\"uncompressedBytes\":{}}}",
            rg.first_row, rg.rows, rg.compressed_bytes, rg.uncompressed_bytes
        ));
    }
    o.push(']');
    // Where the offset indexes are, for the async reader to fetch at once.
    let mut span: Option<(i64, i64)> = None;
    for c in meta.row_groups.iter().flat_map(|g| &g.columns) {
        if let Some((off, len)) = c.offset_index {
            if off >= 0 && len > 0 {
                let (a, b) = span.unwrap_or((off, off + len as i64));
                span = Some((a.min(off), b.max(off + len as i64)));
            }
        }
    }
    key(&mut o, "indexSpan");
    match span {
        Some((a, b)) => o.push_str(&format!("[{a},{b}]")),
        None => o.push_str("null"),
    }
    let sets: HashMap<&str, ()> =
        profile.map_or_else(HashMap::new, |p| p.value_labels.iter().map(|s| (s.name.as_str(), ())).collect());
    let entries: HashMap<&str, &ColumnProfile> =
        profile.map_or_else(HashMap::new, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect());
    key(&mut o, "variables");
    o.push('[');
    for (k, col) in r.columns().iter().enumerate() {
        if k > 0 {
            o.push(',');
        }
        let entry = entries.get(col.name.as_str()).copied();
        let h = &how[k];
        o.push('{');
        key(&mut o, "name");
        push_str(&mut o, &col.name);
        key(&mut o, "type");
        push_str(&mut o, type_name(col));
        key(&mut o, "format");
        push_str(&mut o, entry.and_then(|e| e.format.as_deref()).unwrap_or(""));
        key(&mut o, "label");
        push_str(&mut o, entry.and_then(|e| e.label.as_deref()).unwrap_or(""));
        let set = entry
            .and_then(|e| e.value_labels.as_deref())
            .filter(|s| sets.contains_key(s) && labels_apply(col, h))
            .unwrap_or("");
        key(&mut o, "valueLabels");
        push_str(&mut o, set);
        key(&mut o, "role");
        push_str(&mut o, if col.role == Role::Data { "data" } else { "nested" });
        key(&mut o, "physicalType");
        push_str(&mut o, &col.physical.map(|p| p.name()).unwrap_or_default());
        key(&mut o, "logicalType");
        push_str(&mut o, &logical_name(col));
        key(&mut o, "columnKind");
        match h {
            How::Number { .. } => push_str(&mut o, "number"),
            How::BigInt { .. } => push_str(&mut o, "bigint"),
            How::Text { .. } => push_str(&mut o, "string"),
            How::Levels => push_str(&mut o, "dictionary"),
            How::NotRead(why) => {
                o.push_str("null");
                key(&mut o, "notRead");
                push_str(&mut o, why);
            }
        }
        if let Some(why) = &reasons[k] {
            key(&mut o, "int64");
            o.push('{');
            key(&mut o, "kind");
            push_str(&mut o, if matches!(h, How::BigInt { .. }) { "bigint" } else { "number" });
            key(&mut o, "reason");
            push_str(&mut o, why);
            o.push('}');
        }
        if let Some(u) = unit_of(col) {
            key(&mut o, "unit");
            push_str(&mut o, u);
        }
        if let Some(z) = zone_of(col, entry) {
            key(&mut o, "timeZone");
            push_str(&mut o, &z);
        }
        if let Some(s) = col.storage {
            key(&mut o, "storage");
            push_str(&mut o, s.name());
        }
        if matches!(h, How::Levels) {
            let cat = entry.and_then(|e| e.categorical.as_ref());
            key(&mut o, "categorical");
            o.push('{');
            key(&mut o, "levels");
            match cat.filter(|_| col.levels == Some(LevelsFrom::Profile)) {
                Some(c) => o.push_str(&json::strings(&c.levels)),
                None => o.push_str("null"),
            }
            key(&mut o, "ordered");
            o.push_str(if cat.is_some_and(|c| c.ordered) && col.levels == Some(LevelsFrom::Profile) { "true" } else { "false" });
            o.push('}');
        }
        key(&mut o, "chunks");
        o.push('[');
        if col.role == Role::Data {
            for (g, group) in meta.row_groups.iter().enumerate() {
                if g > 0 {
                    o.push(',');
                }
                let Some(m) = group.columns.get(col.leaf()).and_then(|c| c.meta.as_ref()) else {
                    o.push_str("null");
                    continue;
                };
                o.push('{');
                key(&mut o, "compressedBytes");
                num(&mut o, m.total_compressed_size.max(0) as f64);
                key(&mut o, "uncompressedBytes");
                num(&mut o, m.total_uncompressed_size.max(0) as f64);
                key(&mut o, "codec");
                push_str(&mut o, &codec_name(m.codec));
                key(&mut o, "encodings");
                o.push_str(&json::strings(&m.encodings.iter().map(|e| e.name()).collect::<Vec<_>>()));
                key(&mut o, "dictionaryPageBytes");
                match m.dictionary_page_offset.filter(|&d| d > 0 && d < m.data_page_offset) {
                    Some(d) => num(&mut o, (m.data_page_offset - d) as f64),
                    None => o.push_str("null"),
                }
                let s = m.statistics.as_ref();
                key(&mut o, "nullCount");
                match s.and_then(|s| s.null_count).filter(|&n| n >= 0) {
                    Some(n) => num(&mut o, n as f64),
                    None => o.push_str("null"),
                }
                // The deprecated fields only where their signed byte order
                // is right: signed integers and floats.
                let old_ok = matches!(
                    col.kind,
                    ColumnType::Int8
                        | ColumnType::Int16
                        | ColumnType::Int32
                        | ColumnType::Int64
                        | ColumnType::Float
                        | ColumnType::Double
                        | ColumnType::Date
                        | ColumnType::Timestamp { .. }
                );
                let min = s.and_then(|s| s.min_value.as_ref().or(s.min.as_ref().filter(|_| old_ok)));
                let max = s.and_then(|s| s.max_value.as_ref().or(s.max.as_ref().filter(|_| old_ok)));
                key(&mut o, "min");
                stat(&mut o, col, min, h);
                key(&mut o, "max");
                stat(&mut o, col, max, h);
                o.push('}');
            }
        }
        o.push(']');
        o.push('}');
    }
    o.push_str("]}");
    o
}

// ---------------------------------------------------------------- open

/// Open host file `file` of `len` bytes as Parquet. `flags`: bit 0 skips
/// nested columns; bits 1 and 2 are the `int64` mode (0 auto, 1 bigint,
/// 2 number). `cache_bytes` is the page cache's budget. Returns a handle,
/// or 0.
#[no_mangle]
pub extern "C" fn pq_open(file: u32, len: f64, flags: u32, cache_bytes: f64) -> u32 {
    call(0, |_| {
        let source = HostFile { id: file, len: len as u64 };
        let options = ReadOptions {
            threads: 1,
            nested: if flags & 1 != 0 { Nested::Skip } else { Nested::Error },
            ..ReadOptions::default()
        };
        let mut reader = Reader::open(source, options)?;
        reader.set_page_cache(cache_bytes.max(0.0) as usize);
        let (how, _) = plan_columns(&reader, (flags >> 1) & 3);
        HANDLES.with(|cell| {
            let mut handles = cell.borrow_mut();
            handles.push(Some(PqHandle { reader, how, dicts: HashMap::new(), outs: Vec::new(), directory: Vec::new() }));
            Ok(handles.len() as u32)
        })
    })
}

#[no_mangle]
pub extern "C" fn pq_close(h: u32) {
    // Frees, so it runs even when memory is too short for the reserve.
    HANDLES.with(|cell| {
        if let Some(slot) = cell.borrow_mut().get_mut(h.wrapping_sub(1) as usize) {
            *slot = None;
        }
    })
}

/// The footer as JSON (see `info_json`); `int64` as for `pq_open`.
#[no_mangle]
pub extern "C" fn pq_info(h: u32, int64: u32) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let text = with_handle(h, |handle| {
            let (_, reasons) = plan_columns(&handle.reader, int64);
            // About what the JSON takes: a few hundred bytes a column and
            // a hundred a column chunk (every row group's statistics).
            let chunks = handle.reader.columns().len() * handle.reader.row_groups().len().max(1);
            let estimate = (handle.reader.columns().len() * 400).saturating_add(chunks * 160).saturating_add(64 << 10);
            ensure_room(estimate)?;
            let mut text = String::new();
            text.try_reserve(estimate).map_err(|_| crate::wasm::too_large(estimate))?;
            Ok(info_json(&handle.reader, &handle.how, &reasons, text))
        })?;
        Ok(result(state, text.into_bytes()))
    })
}

/// The profile's value label sets as JSON (as `dta_value_labels`).
#[no_mangle]
pub extern "C" fn pq_value_labels(h: u32) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let text = with_handle(h, |handle| {
            Ok(json::value_labels(handle.reader.profile().map_or(&[][..], |p| &p.value_labels[..])))
        })?;
        Ok(result(state, text.into_bytes()))
    })
}

/// The profile's characteristics as JSON (as `dta_characteristics`).
#[no_mangle]
pub extern "C" fn pq_characteristics(h: u32) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let text = with_handle(h, |handle| {
            Ok(json::characteristics(handle.reader.profile().map_or(&[][..], |p| &p.characteristics[..])))
        })?;
        Ok(result(state, text.into_bytes()))
    })
}

/// The value of the key-value metadata entry named by the `len` bytes at
/// `name`; a null pointer and no error when there is none.
///
/// # Safety
/// `name` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pq_key_value(h: u32, name: *const u8, len: usize) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let name = String::from_utf8(copy(name, len)?).map_err(|_| "a key must be UTF-8")?;
        let value = with_handle(h, |handle| Ok(handle.reader.key_value(&name).map(<[u8]>::to_vec)))?;
        match value {
            Some(v) => Ok(result(state, v)),
            None => {
                state.result_len = 0;
                Ok(std::ptr::null())
            }
        }
    })
}

/// Cache use so far, for tests: three f64s, bytes held, hits and misses.
#[no_mangle]
pub extern "C" fn pq_cache_stats(h: u32) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let (bytes, hits, misses) = with_handle(h, |handle| Ok(handle.reader.page_cache_stats()))?;
        let out: Vec<u8> = [bytes as f64, hits as f64, misses as f64].iter().flat_map(|x| x.to_le_bytes()).collect();
        Ok(result(state, out))
    })
}

unsafe fn columns_at(cols: *const u32, ncols: usize) -> Vec<usize> {
    if ncols == 0 {
        return Vec::new();
    }
    std::slice::from_raw_parts(cols, ncols).iter().map(|&c| c as usize).collect()
}

/// The byte ranges a read of the `ncols` columns at `cols` over rows
/// `start` to `start + count` needs, as f64 pairs (start, end): for the
/// async reader. `dta_result_len` gives the number of f64s.
///
/// # Safety
/// `cols` holds `ncols` u32s.
#[no_mangle]
pub unsafe extern "C" fn pq_plan(h: u32, cols: *const u32, ncols: usize, start: f64, count: f64) -> *const u8 {
    let cols = columns_at(cols, ncols);
    call(std::ptr::null(), |state: &mut State| {
        let ranges = with_handle(h, |handle| {
            check_columns(handle, &cols)?;
            Ok(handle.reader.plan(&cols, start as u64, count as u64)?)
        })?;
        let mut out = Vec::with_capacity(ranges.len() * 16);
        for r in ranges {
            out.extend_from_slice(&(r.start as f64).to_le_bytes());
            out.extend_from_slice(&(r.end as f64).to_le_bytes());
        }
        state.result_len = out.len() / 8;
        let len = state.result_len;
        let p = result(state, out);
        state.result_len = len;
        Ok(p)
    })
}

fn check_columns(handle: &PqHandle, cols: &[usize]) -> Result<(), Fail> {
    for &c in cols {
        match handle.how.get(c) {
            None => return Err(Fail { kind: crate::wasm::OUT_OF_RANGE, message: format!("there is no column {c}") }),
            Some(How::NotRead(why)) => return Err(Fail { kind: INVALID, message: why.clone() }),
            Some(_) => {}
        }
    }
    Ok(())
}

// ---------------------------------------------------------------- read

const NEW_READ: u32 = 1;
const DICTIONARY: u32 = 2;
const NULL_CODE: u32 = u32::MAX;

/// A text column's rows over one call, gathered chunk by chunk.
struct TextAcc {
    column: usize,
    binary: bool,
    coded: bool,
    codes: Vec<u32>,
    bytes: Vec<u8>,
    ends: Vec<u32>,
    missing: Vec<u8>,
}

impl TextAcc {
    fn push_plain(&mut self, value: Option<&[u8]>) {
        match value {
            Some(v) => {
                self.bytes.extend_from_slice(v);
                self.missing.push(0);
            }
            None => self.missing.push(1),
        }
        self.ends.push(self.bytes.len() as u32);
    }

    /// Turn the coded rows so far into plain ones.
    fn give_up(&mut self, dict: &mut Dict) {
        dict.gave_up = true;
        self.coded = false;
        let codes = std::mem::take(&mut self.codes);
        for c in codes {
            if c == NULL_CODE {
                self.push_plain(None);
            } else {
                let v = dict.bytes_of(c).to_vec();
                self.push_plain(Some(&v));
            }
        }
    }

    fn add(&mut self, chunk: &TextChunk, dict: &mut Dict) {
        if self.coded {
            if let Some(cc) = &chunk.codes {
                // Each entry of the chunk's dictionary once.
                let mut map = Vec::with_capacity(chunk.ends.len());
                for i in 0..chunk.ends.len() {
                    match dict.add(chunk.value(i)) {
                        Some(c) => map.push(c),
                        None => break,
                    }
                }
                if map.len() == chunk.ends.len() && dict.note_rows(chunk.rows as u64) {
                    self.codes.extend(cc.iter().map(|&c| if c == TextChunk::NULL { NULL_CODE } else { map[c as usize] }));
                    return;
                }
                self.give_up(dict);
            } else {
                let mut r = 0;
                while r < chunk.rows {
                    match chunk.row(r) {
                        None => self.codes.push(NULL_CODE),
                        Some(v) => match dict.add(v) {
                            Some(c) => self.codes.push(c),
                            None => break,
                        },
                    }
                    r += 1;
                }
                if r == chunk.rows && dict.note_rows(chunk.rows as u64) {
                    return;
                }
                self.give_up(dict);
                for r in r..chunk.rows {
                    self.push_plain(chunk.row(r));
                }
                return;
            }
        }
        for r in 0..chunk.rows {
            self.push_plain(chunk.row(r));
        }
    }
}

/// The message of a read's error, naming the option that keeps a value
/// the core could not give as a number.
fn read_error(e: dta::Error, int64_names: &[String]) -> Fail {
    let mut f = Fail::from(e);
    if int64_names.iter().any(|n| f.message.starts_with(n.as_str()))
        && f.message.contains("cannot be held exactly as a double")
    {
        f.message.push_str("; read with int64: \"bigint\" to keep every digit");
    }
    f
}

/// Read rows `start` to `start + count` of the `ncols` columns at `cols`
/// into the handle; `pq_directory` then says where each column's buffers
/// are. `flags`: `NEW_READ` starts a read (dictionaries begin again),
/// `DICTIONARY` codes text columns while they repeat enough. Returns the
/// rows read, or -1.
///
/// # Safety
/// `cols` holds `ncols` u32s.
#[no_mangle]
pub unsafe extern "C" fn pq_read(h: u32, cols: *const u32, ncols: usize, start: f64, count: f64, flags: u32) -> f64 {
    let cols = columns_at(cols, ncols);
    call(-1.0, |_| {
        with_handle(h, |handle| {
            check_columns(handle, &cols)?;
            let PqHandle { reader, how, dicts, outs, directory } = handle;
            outs.clear();
            directory.clear();
            if flags & NEW_READ != 0 {
                dicts.clear();
            }
            let window = reader.window(start as u64, count as u64);
            let rows = (window.end - window.start) as usize;
            let width: usize = cols
                .iter()
                .map(|&c| match how[c] {
                    How::Number { .. } | How::BigInt { .. } => 9,
                    How::Levels => 4,
                    How::Text { .. } => 9,
                    How::NotRead(_) => 0,
                })
                .sum();
            ensure_room(width.saturating_mul(rows).saturating_mul(2))?;
            let mut texts: Vec<Option<TextAcc>> = Vec::with_capacity(cols.len());
            for &c in &cols {
                let (out, text) = match &how[c] {
                    How::Number { .. } => (Out::Number { values: vec![0.0; rows], codes: vec![0; rows] }, None),
                    How::BigInt { unsigned } => (Out::BigInt { values: vec![0; rows], codes: vec![0; rows], unsigned: *unsigned }, None),
                    How::Levels => (Out::Levels { codes: vec![0; rows], found_bytes: Vec::new(), found_utf16: Vec::new() }, None),
                    How::Text { binary } => {
                        let dict = dicts.entry(c).or_default();
                        let coded = flags & DICTIONARY != 0 && !*binary && !dict.gave_up;
                        let acc = TextAcc {
                            column: c,
                            binary: *binary,
                            coded,
                            codes: if coded { Vec::with_capacity(rows) } else { Vec::new() },
                            bytes: Vec::new(),
                            ends: if coded { Vec::new() } else { Vec::with_capacity(rows) },
                            missing: if coded { Vec::new() } else { Vec::with_capacity(rows) },
                        };
                        (Out::Coded { codes: Vec::new(), new_bytes: Vec::new(), new_utf16: Vec::new() }, Some(acc))
                    }
                    How::NotRead(why) => return Err(Fail { kind: INVALID, message: why.clone() }),
                };
                outs.push(out);
                texts.push(text);
            }
            let int64_names: Vec<String> = cols
                .iter()
                .filter(|&&c| matches!(how[c], How::Number { check: true }))
                .map(|&c| format!("column \"{}\":", reader.columns()[c].name))
                .collect();
            let report = {
                let mut outputs: Vec<Output> = outs
                    .iter_mut()
                    .map(|out| match out {
                        Out::Number { values, codes } => {
                            Output::Float64(Numbers::new(values, f64::NAN).with_codes(codes))
                        }
                        Out::BigInt { values, codes, unsigned: false } => {
                            Output::Int64(Numbers::new(values, 0).with_codes(codes))
                        }
                        Out::BigInt { values, codes, unsigned: true } => {
                            // The same bits, as u64.
                            let v = unsafe { std::slice::from_raw_parts_mut(values.as_mut_ptr() as *mut u64, values.len()) };
                            Output::UInt64(Numbers::new(v, 0).with_codes(codes))
                        }
                        Out::Levels { codes, .. } => Output::Levels { codes, base: 0, null: -1 },
                        _ => Output::Text,
                    })
                    .collect();
                let mut on_text = |k: usize, chunk: &TextChunk| -> dta::Result<()> {
                    if let Some(acc) = texts[k].as_mut() {
                        let dict = dicts.entry(acc.column).or_default();
                        acc.add(chunk, dict);
                    }
                    Ok(())
                };
                reader.read(&cols, start as u64, count as u64, &mut outputs, &mut on_text)
            }
            .map_err(|e| read_error(e, &int64_names))?;
            // INT64 read as numbers: every value a safe integer, whatever
            // the statistics said.
            for (k, &c) in cols.iter().enumerate() {
                if let (How::Number { check: true }, Out::Number { values, codes }) = (&how[c], &outs[k]) {
                    if let Some(r) = values.iter().zip(codes).position(|(v, &m)| m == 0 && v.abs() > SAFE) {
                        return Err(Fail {
                            kind: INVALID,
                            message: format!(
                                "column \"{}\": the value {} in row {} is beyond the safe integers a JavaScript number holds exactly; read with int64: \"bigint\" to keep every digit",
                                reader.columns()[c].name,
                                values[r] as i64,
                                window.start + r as u64
                            ),
                        });
                    }
                }
            }
            for (k, text) in texts.into_iter().enumerate() {
                if let Some(acc) = text {
                    outs[k] = if acc.coded {
                        let dict = dicts.entry(acc.column).or_default();
                        let (new_bytes, new_utf16) = dict.take_new();
                        Out::Coded { codes: acc.codes, new_bytes, new_utf16 }
                    } else {
                        let utf16 = if acc.binary || acc.bytes.is_ascii() {
                            None
                        } else {
                            let mut u = Vec::with_capacity(acc.ends.len());
                            let (mut from, mut units) = (0usize, 0u32);
                            for &e in &acc.ends {
                                let v = &acc.bytes[from..e as usize];
                                units += if v.is_ascii() { v.len() as u32 } else { utf16_len(v) as u32 };
                                u.push(units);
                                from = e as usize;
                            }
                            Some(u)
                        };
                        Out::Plain { bytes: acc.bytes, ends: acc.ends, missing: acc.missing, utf16, binary: acc.binary }
                    };
                }
            }
            for (k, out) in outs.iter_mut().enumerate() {
                if let (Out::Levels { found_bytes, found_utf16, .. }, Some(Some(levels))) = (out, report.levels.get(k)) {
                    let mut units = 0u32;
                    for l in levels {
                        found_bytes.extend_from_slice(l.as_bytes());
                        units += l.encode_utf16().count() as u32;
                        found_utf16.push(units);
                    }
                }
            }
            // The directory: per column, its mode and four (pointer,
            // length) pairs; lengths count elements.
            let p = |v: *const u8| v as usize as u32;
            for out in outs.iter() {
                let mut d = [0u32; 10];
                match out {
                    Out::Number { values, codes } => {
                        d[0] = 0;
                        d[2..6].copy_from_slice(&[p(values.as_ptr() as *const u8), values.len() as u32, p(codes.as_ptr()), codes.len() as u32]);
                    }
                    Out::BigInt { values, codes, unsigned } => {
                        d[0] = if *unsigned { 2 } else { 1 };
                        d[2..6].copy_from_slice(&[p(values.as_ptr() as *const u8), values.len() as u32, p(codes.as_ptr()), codes.len() as u32]);
                    }
                    Out::Coded { codes, new_bytes, new_utf16 } => {
                        d[0] = 3;
                        d[2..8].copy_from_slice(&[
                            p(codes.as_ptr() as *const u8),
                            codes.len() as u32,
                            p(new_bytes.as_ptr()),
                            new_bytes.len() as u32,
                            p(new_utf16.as_ptr() as *const u8),
                            new_utf16.len() as u32,
                        ]);
                    }
                    Out::Plain { bytes, ends, missing, utf16, binary } => {
                        d[0] = if *binary { 5 } else { 4 };
                        d[1] = utf16.is_some() as u32;
                        let (up, ul) = utf16.as_ref().map_or((0, 0), |u| (p(u.as_ptr() as *const u8), u.len() as u32));
                        d[2..10].copy_from_slice(&[
                            p(bytes.as_ptr()),
                            bytes.len() as u32,
                            p(ends.as_ptr() as *const u8),
                            ends.len() as u32,
                            p(missing.as_ptr()),
                            missing.len() as u32,
                            up,
                            ul,
                        ]);
                    }
                    Out::Levels { codes, found_bytes, found_utf16 } => {
                        d[0] = 6;
                        d[2..8].copy_from_slice(&[
                            p(codes.as_ptr() as *const u8),
                            codes.len() as u32,
                            p(found_bytes.as_ptr()),
                            found_bytes.len() as u32,
                            p(found_utf16.as_ptr() as *const u8),
                            found_utf16.len() as u32,
                        ]);
                    }
                }
                directory.extend_from_slice(&d);
            }
            Ok(report.rows as f64)
        })
    })
}

/// The last read's directory: ten u32s per column (see `pq_read`);
/// `dta_result_len` gives the count.
#[no_mangle]
pub extern "C" fn pq_directory(h: u32) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        let (ptr, len) = with_handle(h, |handle| Ok((handle.directory.as_ptr() as *const u8, handle.directory.len())))?;
        state.result_len = len;
        Ok(ptr)
    })
}

/// Free what the last read kept: its outputs and dictionaries.
#[no_mangle]
pub extern "C" fn pq_read_end(h: u32) {
    HANDLES.with(|cell| {
        if let Some(Some(handle)) = cell.borrow_mut().get_mut(h.wrapping_sub(1) as usize) {
            handle.outs = Vec::new();
            handle.directory = Vec::new();
            handle.dicts = HashMap::new();
        }
    })
}

// ---------------------------------------------------------------- write

/// What each written column's values are, as JavaScript gave them.
enum WData {
    /// Doubles and missing codes JavaScript hands over a block at a time
    /// as the writer asks for them (`host_fill`), so the numbers of a
    /// table are never all copied into module memory.
    Hosted(u32),
    BigInts(Vec<i64>, Vec<u8>),
    Texts { bytes: Vec<u8>, ends: Vec<u32>, missing: Vec<u8>, binary: bool },
    Levels { codes: Vec<i32>, levels: Vec<String>, ordered: bool },
}

struct WCol {
    name: String,
    format: String,
    label: String,
    value_labels: String,
    zone: Option<String>,
    /// For numbers and 64-bit integers: 0 byte, 1 int, 2 long, 3 float, 4
    /// double, 5 bool, 6 date, 7 timestamp, 8 int64.
    kind: u32,
    /// For timestamps: 0 s, 1 ms, 2 us, 3 ns.
    unit: u32,
    data: WData,
}

#[derive(Default)]
struct WState {
    rows: usize,
    columns: Vec<WCol>,
    sets: Vec<ValueLabelSet>,
    characteristics: Vec<Characteristic>,
    sort: Vec<String>,
}

thread_local! {
    static WRITE: RefCell<WState> = RefCell::new(WState::default());
}

/// Fields separated by NUL.
fn fields(bytes: &[u8]) -> Result<Vec<String>, Fail> {
    std::str::from_utf8(bytes)
        .map(|s| s.split('\0').map(str::to_string).collect())
        .map_err(|_| "names and labels must be UTF-8".into())
}

/// A column's name, format, label, value label set, and whether it has a
/// zone, then the zone.
fn column_meta(meta: &[u8], kind: u32, unit: u32, data: WData) -> Result<WCol, Fail> {
    let f = fields(meta)?;
    let [name, format, label, value_labels, has_zone, zone] = &f[..] else {
        return Err("expected six fields".into());
    };
    Ok(WCol {
        name: name.clone(),
        format: format.clone(),
        label: label.clone(),
        value_labels: value_labels.clone(),
        zone: (has_zone == "1").then(|| zone.clone()),
        kind,
        unit,
        data,
    })
}

/// Start a table of `rows` rows, dropping any half-built one.
#[no_mangle]
pub extern "C" fn pq_write_begin(rows: f64) {
    WRITE.with(|w| *w.borrow_mut() = WState { rows: rows as usize, ..Default::default() });
}

/// Add a column of doubles with missing codes (0 a value, 1 `.`, 2 to 27
/// `.a` to `.z`), which JavaScript's `host_fill` gives as source `id`
/// while the table is written; `kind` and `unit` as in `WCol` (kind 9:
/// days since 1970 as doubles, a date that DATE cannot hold).
///
/// # Safety
/// `meta` holds `meta_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pq_write_numbers(meta: *const u8, meta_len: usize, kind: u32, unit: u32, id: u32) -> u32 {
    call(0, |_| {
        let meta = copy(meta, meta_len)?;
        WRITE.with(|w| {
            let col = column_meta(&meta, kind, unit, WData::Hosted(id))?;
            w.borrow_mut().columns.push(col);
            Ok(1)
        })
    })
}

/// Add a column of 64-bit integers with missing codes (0 or 1).
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn pq_write_bigints(meta: *const u8, meta_len: usize, kind: u32, unit: u32, values: *const i64, codes: *const u8) -> u32 {
    call(0, |_| {
        let meta = copy(meta, meta_len)?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let n = w.rows;
            let col = column_meta(&meta, kind, unit, WData::BigInts(copy(values, n)?, copy(codes, n)?))?;
            w.columns.push(col);
            Ok(1)
        })
    })
}

/// Add a text (or, with `binary`, bytes) column: the values' bytes end
/// to end, `rows` end offsets, and `rows` null flags.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn pq_write_texts(
    meta: *const u8,
    meta_len: usize,
    binary: u32,
    bytes: *const u8,
    bytes_len: usize,
    ends: *const u32,
    missing: *const u8,
) -> u32 {
    call(0, |_| {
        let meta = copy(meta, meta_len)?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let n = w.rows;
            let ends = copy(ends, n)?;
            if ends.iter().any(|&e| e as usize > bytes_len) || ends.windows(2).any(|p| p[0] > p[1]) {
                return Err("string offsets out of order".into());
            }
            let data = WData::Texts { bytes: copy(bytes, bytes_len)?, ends, missing: copy(missing, n)?, binary: binary != 0 };
            let col = column_meta(&meta, 0, 0, data)?;
            w.columns.push(col);
            Ok(1)
        })
    })
}

/// Add a categorical: `rows` level codes from 0 (negative for a null),
/// and `nlevels` levels as UTF-8 bytes with end offsets.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn pq_write_categorical(
    meta: *const u8,
    meta_len: usize,
    ordered: u32,
    codes: *const i32,
    levels: *const u8,
    levels_len: usize,
    ends: *const u32,
    nlevels: usize,
) -> u32 {
    call(0, |_| {
        let meta = copy(meta, meta_len)?;
        let text = String::from_utf8(copy(levels, levels_len)?).map_err(|_| "levels must be UTF-8")?;
        let ends = copy(ends, nlevels)?;
        let mut lv = Vec::with_capacity(nlevels);
        let mut from = 0;
        for &e in &ends {
            lv.push(text.get(from..e as usize).ok_or("level offsets out of order")?.to_string());
            from = e as usize;
        }
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let n = w.rows;
            let data = WData::Levels { codes: copy(codes, n)?, levels: lv, ordered: ordered != 0 };
            let col = column_meta(&meta, 0, 0, data)?;
            w.columns.push(col);
            Ok(1)
        })
    })
}

/// Add a value label set, as `dta_write_labels`.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn pq_write_labels(
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
            labels.push(ValueLabel { value: values[i], missing: codes[i], text });
            from = to;
        }
        WRITE.with(|w| w.borrow_mut().sets.push(ValueLabelSet { name, labels }));
        Ok(1)
    })
}

/// Add characteristics: NUL-separated variable, name and value, three
/// fields each.
///
/// # Safety
/// `text` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pq_write_characteristics(text: *const u8, len: usize) -> u32 {
    call(0, |_| {
        let f = fields(&copy(text, len)?)?;
        if f.len() % 3 != 0 {
            return Err("expected three fields per characteristic".into());
        }
        let chars = f.chunks_exact(3).map(|c| Characteristic { variable: c[0].clone(), name: c[1].clone(), value: c[2].clone() });
        WRITE.with(|w| w.borrow_mut().characteristics.extend(chars));
        Ok(1)
    })
}

/// Set the names the data is sorted by, NUL-separated.
///
/// # Safety
/// `text` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn pq_write_sort(text: *const u8, len: usize) -> u32 {
    call(0, |_| {
        let f = fields(&copy(text, len)?)?;
        WRITE.with(|w| w.borrow_mut().sort = f.into_iter().filter(|s| !s.is_empty()).collect());
        Ok(1)
    })
}

fn bad(name: &str, r: usize, v: f64, what: &str) -> Fail {
    Fail { kind: INVALID, message: format!("column \"{name}\": row {r} holds {v}, which {what}") }
}

fn time_unit(u: u32) -> TimeUnit {
    match u {
        1 => TimeUnit::Millis,
        3 => TimeUnit::Nanos,
        _ => TimeUnit::Micros,
    }
}

#[link(wasm_import_module = "env")]
extern "C" {
    /// Write `n` values of number source `id`, from row `first`, to
    /// `values`, and their missing codes to `codes`; 0 on success.
    fn host_fill(id: u32, first: f64, n: u32, values: *mut f64, codes: *mut u8) -> i32;
}

/// Rows of one column fetched from JavaScript at once: as many as a row
/// group holds by default, at most 2.3 MB.
const WINDOW: usize = 262_144;

/// The window of one number source fetched last, its values checked.
/// The writer reads each column's blocks more than once (a scan for `.a`
/// to `.z`, then the encoding), one column at a time, so one window
/// serves the passes.
#[derive(Default)]
struct Window {
    id: u32,
    start: usize,
    values: Vec<f64>,
    codes: Vec<u8>,
    /// For an integer column, the values as `i32`, converted once.
    ints: Vec<i32>,
}

thread_local! {
    static STAGE: RefCell<Window> = RefCell::new(Window::default());
    /// The first value a write's fills found that its column cannot
    /// hold; the write is then an error.
    static FILL_FAIL: RefCell<Option<Fail>> = const { RefCell::new(None) };
}

fn fill_failed(f: Fail) {
    FILL_FAIL.with(|e| {
        let mut e = e.borrow_mut();
        if e.is_none() {
            *e = Some(f);
        }
    })
}

/// A fill that takes each block of source `id` (of `rows` rows) from
/// JavaScript, a window at a time, checks each value with `ok` once
/// (else the write fails, naming `what` the column cannot hold), and
/// converts it with `conv`.
fn hosted<'a, T: Copy + Default + 'a>(
    id: u32,
    rows: usize,
    name: &'a str,
    what: &'static str,
    ok: impl Fn(f64) -> bool + Sync + 'a,
    conv: impl Fn(f64) -> T + Sync + 'a,
) -> Box<dta_parquet::Fill<'a, T>> {
    Box::new(move |first, out: &mut [T], codes: &mut [u8]| {
        let n = out.len().min(codes.len());
        STAGE.with(|stage| {
            let mut w = stage.borrow_mut();
            if !(w.id == id && w.start <= first && first + n <= w.start + w.values.len()) {
                let len = WINDOW.max(n).min(rows.saturating_sub(first)).max(n);
                w.id = 0;
                w.values.resize(len, 0.0);
                w.codes.resize(len, 0);
                let status = unsafe { host_fill(id, first as f64, len as u32, w.values.as_mut_ptr(), w.codes.as_mut_ptr()) };
                if status != 0 {
                    fill_failed(Fail { kind: crate::wasm::IO, message: format!("column \"{name}\": its values could not be read") });
                    w.codes.fill(1);
                }
                for i in 0..len {
                    let c = w.codes[i];
                    if c == 0 {
                        if !ok(w.values[i]) {
                            fill_failed(bad(name, first + i, w.values[i], what));
                        }
                    } else if c > 27 {
                        fill_failed(Fail { kind: INVALID, message: format!("column \"{name}\": row {} has missing code {c}; codes run from 0 to 27", first + i) });
                        w.codes[i] = 1;
                    }
                }
                w.id = id;
                w.start = first;
            }
            let at = first - w.start;
            let (values, cs) = (&w.values[at..at + n], &w.codes[at..at + n]);
            codes[..n].copy_from_slice(cs);
            for i in 0..n {
                out[i] = if cs[i] == 0 { conv(values[i]) } else { T::default() };
            }
        })
    })
}

/// `hosted` for an integer column of values from `lo` to `hi`: each
/// window's values are checked and made `i32`s once, and each pass of
/// the writer over them copies them.
fn hosted_int<'a>(id: u32, rows: usize, name: &'a str, what: &'static str, lo: i32, hi: i32) -> Box<dta_parquet::Fill<'a, i32>> {
    Box::new(move |first, out: &mut [i32], codes: &mut [u8]| {
        let n = out.len().min(codes.len());
        STAGE.with(|stage| {
            let mut w = stage.borrow_mut();
            if !(w.id == id && w.start <= first && first + n <= w.start + w.ints.len()) {
                let len = WINDOW.max(n).min(rows.saturating_sub(first)).max(n);
                let Window { values, codes: cs, ints, .. } = &mut *w;
                // Kept from window to window: JavaScript and the loop
                // below write every element, so none is zeroed again.
                values.resize(len, 0.0);
                cs.resize(len, 0);
                ints.resize(len, 0);
                let status = unsafe { host_fill(id, first as f64, len as u32, values.as_mut_ptr(), cs.as_mut_ptr()) };
                if status != 0 {
                    fill_failed(Fail { kind: crate::wasm::IO, message: format!("column \"{name}\": its values could not be read") });
                    cs.fill(1);
                }
                let mut bad_row = None;
                for (i, ((&x, c), slot)) in values[..len].iter().zip(cs[..len].iter_mut()).zip(ints[..len].iter_mut()).enumerate() {
                    let v = x as i32;
                    *slot = v;
                    if *c == 0 {
                        if (v as f64 != x || v < lo || v > hi) && bad_row.is_none() {
                            bad_row = Some(i);
                        }
                    } else if *c > 27 {
                        fill_failed(Fail { kind: INVALID, message: format!("column \"{name}\": row {} has missing code {}; codes run from 0 to 27", first + i, *c) });
                        *c = 1;
                    }
                }
                if let Some(i) = bad_row {
                    fill_failed(bad(name, first + i, values[i], what));
                }
                w.id = id;
                w.start = first;
            }
            let at = first - w.start;
            // A missing row's value is ignored by the writer.
            out[..n].copy_from_slice(&w.ints[at..at + n]);
            codes[..n].copy_from_slice(&w.codes[at..at + n]);
        })
    })
}

/// The table JavaScript built, as the core takes it; `profile` gets the
/// labels, formats and the rest.
fn table_of(w: &WState, mut profile: Profile) -> Result<Table<'_>, Fail> {
    let mut out = Vec::with_capacity(w.columns.len());
    profile.columns.reserve(w.columns.len());
    for c in &w.columns {
        let name = c.name.as_str();
        // An entry per column, in order (the writer rejects two columns of
        // one name); a search per column would be quadratic.
        profile.columns.push(ColumnProfile::named(name));
        let entry = profile.columns.last_mut().expect("just pushed");
        if !c.label.is_empty() {
            entry.label = Some(c.label.clone());
        }
        if !c.format.is_empty() {
            entry.format = Some(c.format.clone());
        }
        if !c.value_labels.is_empty() {
            entry.value_labels = Some(c.value_labels.clone());
        }
        let values: Values = match &c.data {
            WData::Hosted(id) => {
                let id = *id;
                let whole_in = |lo: f64, hi: f64| move |x: f64| x.fract() == 0.0 && x >= lo && x <= hi;
                let any = |_: f64| true;
                match c.kind {
                    0 => Values::Int8(hosted_int(id, w.rows, name, "a byte column cannot hold", -128, 127)),
                    1 => Values::Int16(hosted_int(id, w.rows, name, "an int column cannot hold", -32768, 32767)),
                    2 => Values::Int32(hosted_int(id, w.rows, name, "a long column cannot hold", i32::MIN, i32::MAX)),
                    3 => Values::Float(hosted(id, w.rows, name, "a float column does not hold exactly", |x| (x as f32) as f64 == x || x.is_nan(), |x| x as f32)),
                    5 => Values::Bool(hosted(id, w.rows, name, "a bool column cannot hold (only 0 and 1)", |x| x == 0.0 || x == 1.0, |x| x as u8)),
                    6 => Values::Date(hosted_int(id, w.rows, name, "a date column cannot hold", i32::MIN, i32::MAX)),
                    9 => {
                        // Fractions of a day, or days an INT32 cannot hold
                        // (JavaScript looked): days as doubles, a date again
                        // for our readers.
                        entry.logical = Some(Logical::Date);
                        Values::Double(hosted(id, w.rows, name, "", any, |x| x))
                    }
                    7 if c.unit == 0 => {
                        // Seconds: no Parquet unit, so doubles, a
                        // timestamp again for our readers.
                        entry.logical = Some(Logical::Timestamp);
                        entry.tz = Some(c.zone.clone().unwrap_or_default());
                        Values::Double(hosted(id, w.rows, name, "", any, |x| x))
                    }
                    7 => Values::Timestamp {
                        unit: time_unit(c.unit),
                        utc: c.zone.is_some(),
                        zone: c.zone.clone().filter(|z| !z.is_empty()),
                        fill: hosted(id, w.rows, name, "is not a whole number of the column's unit within the safe integers", whole_in(-SAFE, SAFE), |x| x as i64),
                    },
                    8 => Values::Int64(hosted(id, w.rows, name, "an int64 column given as numbers cannot hold exactly (pass bigints)", whole_in(-SAFE, SAFE), |x| x as i64)),
                    _ => Values::Double(hosted(id, w.rows, name, "", any, |x| x)),
                }
            }
            WData::BigInts(v, m) => {
                let f: Box<dta_parquet::Fill<i64>> = Box::new(move |first, out: &mut [i64], c: &mut [u8]| {
                    for (i, (d, code)) in out.iter_mut().zip(c.iter_mut()).enumerate() {
                        *code = m[first + i];
                        *d = if *code == 0 { v[first + i] } else { 0 };
                    }
                });
                if c.kind == 7 && c.unit != 0 {
                    Values::Timestamp { unit: time_unit(c.unit), utc: c.zone.is_some(), zone: c.zone.clone().filter(|z| !z.is_empty()), fill: f }
                } else if c.kind == 8 {
                    Values::Int64(f)
                } else {
                    return Err(Fail { kind: INVALID, message: format!("column \"{name}\": 64-bit integers can be written only as int64 or as a timestamp in ms, us or ns") });
                }
            }
            WData::Texts { bytes, ends, missing, binary } => {
                let get: Box<dta_parquet::GetBytes> = Box::new(move |r| {
                    if missing[r] != 0 {
                        return None;
                    }
                    let start = if r == 0 { 0 } else { ends[r - 1] as usize };
                    Some(&bytes[start..ends[r] as usize])
                });
                if *binary {
                    Values::Binary(get)
                } else {
                    Values::Text(get)
                }
            }
            WData::Levels { codes, levels, ordered } => {
                if let Some(r) = codes.iter().position(|&x| x >= 0 && x as usize >= levels.len()) {
                    return Err(Fail {
                        kind: INVALID,
                        message: format!("column \"{name}\": row {r} has code {}, but there are {} levels", codes[r], levels.len()),
                    });
                }
                Values::Categorical {
                    levels: levels.clone(),
                    ordered: *ordered,
                    codes: Box::new(move |first, out: &mut [i32]| {
                        out.copy_from_slice(&codes[first..first + out.len()]);
                    }),
                }
            }
        };
        out.push(WriteColumn { name: name.to_string(), values });
    }
    // Entries left empty say nothing.
    profile.columns.retain(|c| c.label.is_some() || c.format.is_some() || c.value_labels.is_some() || c.logical.is_some() || c.tz.is_some());
    Ok(Table { rows: w.rows, columns: out, profile })
}

/// Write the table to host file `file`. `info` holds NUL-separated data
/// label then notes; `compression` names the codec; `level` is NaN for
/// the codec's default; `row_group_rows` is 0 for the default. Returns 1,
/// or 0 on failure.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn pq_write_finish(
    file: u32,
    info: *const u8,
    info_len: usize,
    compression: *const u8,
    compression_len: usize,
    level: f64,
    row_group_rows: f64,
    missing_letters: u32,
) -> u32 {
    call(0, |_| {
        let info = fields(&copy(info, info_len)?)?;
        let codec = String::from_utf8(copy(compression, compression_len)?).map_err(|_| "a codec name must be UTF-8")?;
        let state = WRITE.with(|w| std::mem::take(&mut *w.borrow_mut()));
        let compression = Compression::from_name(&codec)?;
        let options = WriteOptions {
            compression,
            compression_level: level.is_finite().then_some(level as i32),
            row_group_rows: (row_group_rows >= 1.0).then_some(row_group_rows as usize),
            missing_letters: missing_letters != 0,
            threads: 1,
            ..WriteOptions::default()
        };
        let profile = Profile {
            label: info.first().filter(|s| !s.is_empty()).cloned(),
            notes: info.iter().skip(1).cloned().collect(),
            characteristics: state.characteristics.clone(),
            sort: state.sort.clone(),
            value_labels: state.sets.clone(),
            ..Profile::default()
        };
        FILL_FAIL.with(|e| *e.borrow_mut() = None);
        STAGE.with(|s| *s.borrow_mut() = Window::default());
        let table = table_of(&state, profile)?;
        // A buffer, so the many small writes of page headers cross into
        // JavaScript a megabyte at a time.
        let mut sink = std::io::BufWriter::with_capacity(1 << 20, HostSink(file));
        let written = dta_parquet::write(&table, &mut sink, &options);
        STAGE.with(|s| *s.borrow_mut() = Window::default());
        // A value a fill found its column cannot hold is the cause of any
        // error the writer then met.
        if let Some(f) = FILL_FAIL.with(|e| e.borrow_mut().take()) {
            return Err(f);
        }
        written.map_err(|e| match e.kind {
            ErrorKind::Io => Fail { kind: crate::wasm::IO, message: e.to_string() },
            _ => Fail::from(e),
        })?;
        sink.flush().map_err(|e| Fail { kind: crate::wasm::IO, message: e.to_string() })?;
        if let Some(f) = FILL_FAIL.with(|e| e.borrow_mut().take()) {
            return Err(f);
        }
        Ok(1)
    })
}
