//! What a read gives beside its table, and what a write takes beside its
//! stream, as plain Rust (plan 0025, stage 2a). The binding turns a
//! [`ReadMeta`] into the dict datakit's `Meta` is made from, and makes a
//! [`WriteMeta`] of the dict datakit's `prepare` gives.
//!
//! A read's [`ReadMeta`] borrows its text from the reader where it can
//! (`Cow`), so a read hands it to a callback while the reader is open
//! rather than copying every name, label and format out.
//!
//! Lists that the binding makes dicts of keep dict assignment's rule: an
//! entry whose key is already there replaces that entry's value and keeps
//! its place. A reader of these structs in another language follows it.

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};

use super::ffi::{Imported, Table};

/// A value label's code as datakit keys it: an integer where whole (and
/// within ±9e15), else a float; `.` and `.a` to `.z` by their missing
/// codes (1 and 2 to 27), which datakit keys by name ([`LabelKey::name`]).
#[derive(Clone, Debug, PartialEq)]
pub enum LabelKey {
    Int(i64),
    Float(f64),
    Missing(u8),
}

/// `.` and `.a` to `.z`, by missing code less one.
const MISSING_NAMES: [&str; 27] = [
    ".", ".a", ".b", ".c", ".d", ".e", ".f", ".g", ".h", ".i", ".j", ".k", ".l", ".m", ".n", ".o", ".p", ".q", ".r", ".s",
    ".t", ".u", ".v", ".w", ".x", ".y", ".z",
];

impl LabelKey {
    /// The key of a label on `value`, or on the missing code `missing`
    /// when it is not 0 (a code past `.z` is `.`).
    pub fn of(value: f64, missing: u8) -> Self {
        if missing != 0 {
            LabelKey::Missing(if usize::from(missing) <= MISSING_NAMES.len() { missing } else { dta::missing::SYSTEM })
        } else if value.fract() == 0.0 && value.abs() < 9.0e15 {
            LabelKey::Int(value as i64)
        } else {
            LabelKey::Float(value)
        }
    }

    /// A form that is equal for two keys exactly when Python's `==` says
    /// they are (an int and a float of one whole value are).
    pub fn canonical(&self) -> CanonicalKey {
        match self {
            LabelKey::Int(i) => CanonicalKey::Whole(i128::from(*i)),
            LabelKey::Float(f) if f.fract() == 0.0 && f.abs() < 1.0e38 => CanonicalKey::Whole(*f as i128),
            LabelKey::Float(f) => CanonicalKey::Bits(f.to_bits()),
            LabelKey::Missing(c) => CanonicalKey::Missing(*c),
        }
    }

    /// A missing code's name: `.` or `.a` to `.z`.
    pub fn name(code: u8) -> &'static str {
        MISSING_NAMES.get(usize::from(code).wrapping_sub(1)).copied().unwrap_or(".")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CanonicalKey {
    Whole(i128),
    Bits(u64),
    Missing(u8),
}

/// Text a read gives: borrowed from the reader, or made.
pub type Text<'a> = Cow<'a, str>;

/// One value-label set: its labels in order, `(code, text)`.
pub type LabelSet<'a> = Vec<(LabelKey, Text<'a>)>;

/// One column of a read.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ColumnMeta<'a> {
    pub name: Text<'a>,
    pub label: Option<Text<'a>>,
    pub format: Option<Text<'a>>,
    /// The name of its value-label set.
    pub value_labels: Option<Text<'a>>,
    /// For a categorical: whether its levels are ordered.
    pub ordered: Option<bool>,
    /// The storage type it was written from (byte, int, ...).
    pub storage: Option<Text<'a>>,
    /// For datakit: "categorical" (make it Categorical), "decimal(p,s)"
    /// (cast the text to Decimal), or None.
    pub flag: Option<String>,
    /// Whether `.a` to `.z` can be written to it.
    pub eligible: bool,
}

/// What a read gives beside its tables: what datakit's `Meta` is made
/// from, and the read's warnings.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ReadMeta<'a> {
    pub rows: usize,
    /// In the frame's order (the names are the frame's).
    pub columns: Vec<ColumnMeta<'a>>,
    /// `(set, labels)`, each set once; codes by dict assignment's rule.
    pub value_labels: Vec<(Text<'a>, LabelSet<'a>)>,
    pub label: Option<String>,
    pub notes: Vec<String>,
    /// `(variable, name, text)`, by dict assignment's rule on each
    /// variable's names.
    pub characteristics: Vec<(String, String, String)>,
    pub sort: Vec<String>,
    pub timestamp: Option<String>,
    pub warnings: Vec<String>,
    /// The columns holding `.a` to `.z` in the rows read: those the
    /// letters table has, in its order.
    pub letter_columns: Vec<String>,
    /// A Parquet read's time per step, in seconds.
    pub steps: Option<Vec<(&'static str, f64)>>,
    /// A `.dta` read's release.
    pub release: Option<u16>,
}

/// Whether `labels` holds two codes Python's `==` calls equal.
pub fn repeats_a_code(labels: &LabelSet<'_>) -> bool {
    // Most sets are short: comparing pairs costs less than a hash set.
    if labels.len() <= 16 {
        return labels.iter().enumerate().any(|(i, (a, _))| {
            let a = a.canonical();
            labels[..i].iter().any(|(b, _)| b.canonical() == a)
        });
    }
    let mut seen = HashSet::with_capacity(labels.len());
    labels.iter().any(|(k, _)| !seen.insert(k.canonical()))
}

/// A read: the frame, the letters (one `LETTERS` column per column
/// holding `.a` to `.z` in the rows read; None when none does) and the
/// rest.
pub struct ReadOutput<'a> {
    pub frame: Table,
    pub letters: Option<Table>,
    pub meta: ReadMeta<'a>,
}

/// One column of a Parquet file's footer, for `read_parquet_info`.
#[derive(Clone, Debug, PartialEq)]
pub struct InfoColumn<'a> {
    pub name: Text<'a>,
    /// "data" or "nested".
    pub role: &'static str,
    /// The Arrow format a read gives; None for a column it does not read.
    pub format: Option<String>,
    pub flag: Option<String>,
    /// An Enum's levels.
    pub levels: Option<Vec<String>>,
    pub physical_type: Option<String>,
    pub logical_type: Option<String>,
    pub label: Option<Text<'a>>,
    pub value_labels: Option<Text<'a>>,
    pub storage: Option<&'static str>,
}

/// A Parquet file's footer.
pub struct ParquetInfo<'a> {
    pub rows: u64,
    /// `(rows, compressed bytes, uncompressed bytes)` per row group.
    pub row_groups: Vec<(u64, u64, u64)>,
    pub created_by: Option<String>,
    pub compression: Vec<String>,
    pub key_value: Vec<(String, String)>,
    pub columns: Vec<InfoColumn<'a>>,
    /// As a whole-file read gives it, for every data column it reads.
    pub meta: ReadMeta<'a>,
}

/// A value label's code as `meta` gives it: `.` or `.a` to `.z` (checked
/// by the writer), or a number.
#[derive(Clone, Debug, PartialEq)]
pub enum Code {
    Text(String),
    Number(f64),
}

/// A value-label set as `meta` gives it: its name and `(code, text)`
/// pairs, in order.
pub type GivenSet = (String, Vec<(Code, String)>);

/// A column's entry in `meta.columns`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ColumnEntry {
    pub label: Option<String>,
    pub format: Option<String>,
    pub value_labels: Option<String>,
    pub ordered: Option<bool>,
}

/// What a write takes beside its stream: datakit's `meta` dict, of which
/// the binding keeps what the writer reads (`columns` and `missing` only
/// for the frame's columns).
#[derive(Default)]
pub struct WriteMeta {
    pub label: Option<String>,
    pub timestamp: Option<String>,
    pub notes: Vec<String>,
    pub sort: Vec<String>,
    /// `(variable, [(name, text)])`, in `meta`'s order.
    pub characteristics: Vec<(String, Vec<(String, String)>)>,
    /// The entry of each of the frame's columns that has one.
    pub columns: HashMap<String, ColumnEntry>,
    /// The sets, in `meta`'s order.
    pub value_labels: Vec<GivenSet>,
    /// `(column, its letters)`: a `LETTERS` or String column, or a frame
    /// of one, `.a` to `.z` or null per row, for each of the frame's
    /// columns that `meta.missing` names.
    pub missing: Vec<(String, Imported)>,
}
