//! Writes release 118, little-endian, in one front-to-back pass.
//!
//! A first pass over the data checks every value fits its storage type
//! and sizes string variables and strLs. With every section's size then
//! known, the map is written up front with its final offsets, and the
//! rows are built into a buffer of about 8 MiB at a time, a slab of rows
//! at a time and column by column within it. Nothing holds a second copy
//! of the data.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::Write;

use crate::error::{Error, Result};
use crate::missing::{self, DOUBLE_MISSING, FLOAT_MISSING, LONG_MISSING};
use crate::reader::{Characteristic, ValueLabelSet};
use crate::types::StorageType;

/// One variable's values, read by row as the writer needs them.
pub enum Values<'a> {
    /// Values and missing codes a block of rows at a time: called with
    /// the block's first row and buffers of the block's length (at most
    /// [`BLOCK`] rows), it fills each row's value and missing code (0, or
    /// 1 to 27 for `.` to `.z`). See [`Values::numbers_by_row`].
    Numbers(Box<FillNumbers<'a>>),
    /// UTF-8 text.
    Strings(Box<dyn Fn(usize) -> &'a [u8] + 'a>),
    /// strLs, each UTF-8 text or, where the flag is true, binary bytes.
    StrLs(Box<dyn Fn(usize) -> (&'a [u8], bool) + 'a>),
}

/// A [`Values::Numbers`] fill: first row, values, missing codes.
pub type FillNumbers<'a> = dyn Fn(usize, &mut [f64], &mut [u8]) + Sync + 'a;

/// The most rows a [`Values::Numbers`] fill is asked for at once.
pub const BLOCK: usize = 1024;

impl<'a> Values<'a> {
    /// Numbers given a row at a time: `get(row)` is the row's value and
    /// missing code. `get` is inlined into the block loop, so this costs
    /// one dynamic call per block, not per row.
    pub fn numbers_by_row(get: impl Fn(usize) -> (f64, u8) + Sync + 'a) -> Self {
        Values::Numbers(Box::new(move |first, values, codes| {
            for (i, (v, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
                (*v, *c) = get(first + i);
            }
        }))
    }

    /// A string row's bytes and whether they are binary.
    fn string(&self, row: usize) -> (&'a [u8], bool) {
        match self {
            Values::Strings(get) => (get(row), false),
            Values::StrLs(get) => get(row),
            Values::Numbers(_) => (&[], false),
        }
    }
}

pub struct WriteVariable<'a> {
    pub name: String,
    /// The storage type of a numeric variable. String variables are
    /// sized by the writer: strN for the longest value up to 2045 bytes,
    /// strL beyond that or for [`Values::StrLs`].
    pub storage: StorageType,
    /// Display format; empty for the default of the storage type.
    pub format: String,
    pub label: String,
    /// Name of the value label set to attach; empty for none.
    pub value_labels: String,
    pub values: Values<'a>,
}

pub struct Dataset<'a> {
    pub nobs: usize,
    pub label: String,
    /// Such as `28 Oct 2026 14:38`, or empty.
    pub timestamp: String,
    pub variables: Vec<WriteVariable<'a>>,
    pub value_labels: Vec<ValueLabelSet>,
    /// Notes are the `_dta` characteristics `note0` (their count) and
    /// `note1`, `note2`, ...
    pub characteristics: Vec<Characteristic>,
    /// Indices of the variables the data is sorted by.
    pub sort_order: Vec<usize>,
}

const NAME_LEN: usize = 129;
const FORMAT_LEN: usize = 57;
const VAR_LABEL_LEN: usize = 321;
const STRN_MAX: usize = 2045;

/// How to write. The defaults suit every caller; the hidden fields are
/// for tests.
#[derive(Debug, Clone, Copy)]
pub struct WriteOptions {
    /// Rows are built this many bytes at a time (at least one row).
    #[doc(hidden)]
    pub block_bytes: usize,
    /// Within a block, rows are filled column by column this many bytes
    /// at a time (at least one row), so a slab stays in cache.
    #[doc(hidden)]
    pub slab_bytes: usize,
}

impl Default for WriteOptions {
    fn default() -> Self {
        WriteOptions { block_bytes: 8 << 20, slab_bytes: 256 << 10 }
    }
}

/// Write `data` as release 118.
pub fn write(data: &Dataset, out: impl Write) -> Result<()> {
    write_with(data, out, &WriteOptions::default())
}

/// [`write`] with options.
pub fn write_with(data: &Dataset, out: impl Write, options: &WriteOptions) -> Result<()> {
    let mut out = std::io::BufWriter::with_capacity(1 << 16, out);
    let plan = Plan::new(data)?;
    plan.write(data, &mut out, options)?;
    out.flush()?;
    Ok(())
}

/// A strL's bytes and whether they are binary.
type StrlText<'a> = (&'a [u8], bool);

/// What the first pass learns.
struct Plan<'a> {
    types: Vec<StorageType>,
    row_len: usize,
    strl_bytes: u64,
    /// For each strL variable (empty for others), the first row holding
    /// each distinct text: identical texts share one strL entry. Keys
    /// borrow the caller's data, so this costs a table entry per
    /// distinct text and nothing per row.
    strl_first: Vec<HashMap<StrlText<'a>, usize, BuildHasherDefault<FastHash>>>,
    /// For each strL variable, the rows whose text is written to the
    /// strL section (the first of each distinct text), in order.
    strl_rows: Vec<Vec<usize>>,
    value_labels: Vec<u8>,
    characteristics: Vec<u8>,
}

impl<'a> Plan<'a> {
    fn new(data: &Dataset<'a>) -> Result<Plan<'a>> {
        let k = data.variables.len();
        if k > 32767 {
            return Err(Error::new(format!("release 118 holds at most 32,767 variables, not {k}")));
        }
        check_text("the data label", &data.label, 80, 320)?;
        if data.sort_order.iter().any(|&s| s >= k) {
            return Err(Error::new("the sort order names a variable that does not exist"));
        }
        let mut types = Vec::with_capacity(k);
        let mut strl_bytes = 0u64;
        let mut strl_first = Vec::with_capacity(k);
        let mut strl_rows = Vec::with_capacity(k);
        for (i, v) in data.variables.iter().enumerate() {
            strl_first.push(HashMap::default());
            strl_rows.push(Vec::new());
            check_name(&v.name)?;
            check_text(&format!("the label of {}", v.name), &v.label, 80, VAR_LABEL_LEN - 1)?;
            if v.format.len() >= FORMAT_LEN {
                return Err(Error::new(format!("the format of {} is too long", v.name)));
            }
            if !v.value_labels.is_empty() {
                check_name(&v.value_labels)?;
            }
            types.push(match &v.values {
                Values::Numbers(fill) => {
                    if !v.storage.is_numeric() {
                        return Err(Error::new(format!("{} has numbers but storage {}", v.name, v.storage.name())));
                    }
                    check_numbers(v, fill, data.nobs)?;
                    v.storage
                }
                values => {
                    // Text must be UTF-8 without NULs: readers stop a string at a NUL.
                    let check = |(s, binary): (&[u8], bool), row: usize| {
                        if !binary && (s.contains(&0) || std::str::from_utf8(s).is_err()) {
                            Err(Error::new(format!("{} row {} is not UTF-8 text without NULs", v.name, row + 1)))
                        } else {
                            Ok(())
                        }
                    };
                    let longest = (0..data.nobs).map(|row| values.string(row).0.len()).max().unwrap_or(0);
                    let strl = matches!(values, Values::StrLs(_)) || v.storage == StorageType::StrL;
                    if longest > STRN_MAX || strl {
                        if data.nobs as u64 >= 1 << 48 || i + 1 >= 1 << 16 {
                            return Err(Error::new("too many rows or variables for strLs in release 118"));
                        }
                        // Each distinct text is checked and counted once.
                        let mut first = HashMap::default();
                        let mut recent = RecentTexts::new();
                        for row in 0..data.nobs {
                            let s = values.string(row);
                            if recent.get(s).is_some() {
                                continue;
                            }
                            let f = *first.entry(s).or_insert_with(|| {
                                strl_rows[i].push(row);
                                row
                            });
                            if f == row {
                                check(s, row)?;
                                strl_bytes += gso_len(s) as u64;
                            }
                            recent.put(s, f);
                        }
                        strl_first[i] = first;
                        StorageType::StrL
                    } else {
                        for row in 0..data.nobs {
                            check(values.string(row), row)?;
                        }
                        StorageType::Str(longest.max(1) as u16)
                    }
                }
            });
        }
        let row_len = types.iter().map(|t| t.width()).sum();
        Ok(Plan {
            types,
            row_len,
            strl_bytes,
            strl_first,
            strl_rows,
            value_labels: value_labels(&data.value_labels)?,
            characteristics: characteristics(&data.characteristics)?,
        })
    }

    fn write(&self, data: &Dataset, out: &mut impl Write, options: &WriteOptions) -> Result<()> {
        let k = data.variables.len();
        let nobs = data.nobs as u64;

        let mut head = Vec::new();
        head.extend_from_slice(b"<stata_dta><header><release>118</release><byteorder>LSF</byteorder><K>");
        head.extend_from_slice(&(k as u16).to_le_bytes());
        head.extend_from_slice(b"</K><N>");
        head.extend_from_slice(&nobs.to_le_bytes());
        head.extend_from_slice(b"</N><label>");
        head.extend_from_slice(&(data.label.len() as u16).to_le_bytes());
        head.extend_from_slice(data.label.as_bytes());
        head.extend_from_slice(b"</label><timestamp>");
        let stamp = data.timestamp.as_bytes();
        if stamp.len() > 255 {
            return Err(Error::new("the timestamp is too long"));
        }
        head.push(stamp.len() as u8);
        head.extend_from_slice(stamp);
        head.extend_from_slice(b"</timestamp></header>");

        // Section offsets, in the order the map lists them.
        let k64 = k as u64;
        let map_at = head.len() as u64;
        let types_at = map_at + 5 + 14 * 8 + 6;
        let names_at = types_at + 16 + 2 * k64 + 17;
        let sort_at = names_at + 10 + NAME_LEN as u64 * k64 + 11;
        let formats_at = sort_at + 10 + 2 * (k64 + 1) + 11;
        let vl_names_at = formats_at + 9 + FORMAT_LEN as u64 * k64 + 10;
        let labels_at = vl_names_at + 19 + NAME_LEN as u64 * k64 + 20;
        let chars_at = labels_at + 17 + VAR_LABEL_LEN as u64 * k64 + 18;
        let data_at = chars_at + 17 + self.characteristics.len() as u64 + 18;
        let strls_at = data_at + 6 + nobs * self.row_len as u64 + 7;
        let vl_at = strls_at + 7 + self.strl_bytes + 8;
        let end_tag_at = vl_at + 14 + self.value_labels.len() as u64 + 15;
        let end = end_tag_at + 12;

        head.extend_from_slice(b"<map>");
        for offset in [
            0, map_at, types_at, names_at, sort_at, formats_at, vl_names_at, labels_at, chars_at, data_at,
            strls_at, vl_at, end_tag_at, end,
        ] {
            head.extend_from_slice(&offset.to_le_bytes());
        }
        head.extend_from_slice(b"</map><variable_types>");
        for t in &self.types {
            head.extend_from_slice(&t.code_117().to_le_bytes());
        }
        head.extend_from_slice(b"</variable_types><varnames>");
        for v in &data.variables {
            field(&mut head, &v.name, NAME_LEN);
        }
        head.extend_from_slice(b"</varnames><sortlist>");
        for i in 0..=k {
            let entry = data.sort_order.get(i).map_or(0, |&s| s as u16 + 1);
            head.extend_from_slice(&entry.to_le_bytes());
        }
        head.extend_from_slice(b"</sortlist><formats>");
        for (v, t) in data.variables.iter().zip(&self.types) {
            let format = if v.format.is_empty() { default_format(*t) } else { v.format.clone() };
            field(&mut head, &format, FORMAT_LEN);
        }
        head.extend_from_slice(b"</formats><value_label_names>");
        for v in &data.variables {
            field(&mut head, &v.value_labels, NAME_LEN);
        }
        head.extend_from_slice(b"</value_label_names><variable_labels>");
        for v in &data.variables {
            field(&mut head, &v.label, VAR_LABEL_LEN);
        }
        head.extend_from_slice(b"</variable_labels><characteristics>");
        head.extend_from_slice(&self.characteristics);
        head.extend_from_slice(b"</characteristics><data>");
        debug_assert_eq!(head.len() as u64, data_at + 6);
        out.write_all(&head)?;

        self.write_rows(data, out, options)?;

        out.write_all(b"</data><strls>")?;
        self.write_strls(data, out)?;
        out.write_all(b"</strls><value_labels>")?;
        out.write_all(&self.value_labels)?;
        out.write_all(b"</value_labels></stata_dta>")?;
        Ok(())
    }

    fn write_rows(&self, data: &Dataset, out: &mut impl Write, options: &WriteOptions) -> Result<()> {
        if self.row_len == 0 || data.nobs == 0 {
            return Ok(());
        }
        let block_rows = (options.block_bytes / self.row_len).max(1);
        let slab_rows = (options.slab_bytes / self.row_len).max(1);
        // Every byte of a row is written each time (values, string
        // padding, strL references), so the buffer is zeroed only once.
        let mut buf = vec![0u8; block_rows.min(data.nobs) * self.row_len];
        // Address caches for strL variables only.
        let mut recent: Vec<Option<RecentTexts>> =
            self.types.iter().map(|&t| (t == StorageType::StrL).then(RecentTexts::new)).collect();
        let mut scratch = Scratch::default();
        let mut row = 0;
        while row < data.nobs {
            let n = block_rows.min(data.nobs - row);
            let block = &mut buf[..n * self.row_len];
            for (k, slab) in block.chunks_mut(slab_rows * self.row_len).enumerate() {
                let first = row + k * slab_rows;
                self.fill_strings(data, slab, first, &mut recent);
                self.fill_numbers(data, slab, first, &mut scratch);
            }
            out.write_all(block)?;
            row += n;
        }
        Ok(())
    }

    /// The string and strL cells of the rows in `slab`, the first of
    /// which is row `first`.
    fn fill_strings(&self, data: &Dataset, slab: &mut [u8], first: usize, recent: &mut [Option<RecentTexts>]) {
        let row_len = self.row_len;
        let mut offset = 0;
        for (j, (v, t)) in data.variables.iter().zip(&self.types).enumerate() {
            match (&v.values, *t) {
                (Values::Numbers(_), _) => {}
                (values, StorageType::StrL) => {
                    // A reference to (variable, observation), 2 + 6 bytes.
                    let cache = recent[j].as_mut().expect("strL variables have a cache");
                    for (r, row) in slab.chunks_exact_mut(row_len).enumerate() {
                        let s = values.string(first + r);
                        let first_row = cache.get(s).unwrap_or_else(|| {
                            let f = self.strl_first[j][&s];
                            cache.put(s, f);
                            f
                        });
                        let cell = &mut row[offset..offset + 8];
                        cell[..2].copy_from_slice(&(j as u16 + 1).to_le_bytes());
                        cell[2..].copy_from_slice(&(first_row as u64 + 1).to_le_bytes()[..6]);
                    }
                }
                (values, StorageType::Str(w)) => {
                    for (r, row) in slab.chunks_exact_mut(row_len).enumerate() {
                        let s = values.string(first + r).0;
                        let cell = &mut row[offset..offset + w as usize];
                        cell[..s.len()].copy_from_slice(s);
                        cell[s.len()..].fill(0);
                    }
                }
                _ => unreachable!("the plan gives strings a string type"),
            }
            offset += t.width();
        }
    }

    /// The numeric cells of the rows in `slab`, the first of which is
    /// row `first`.
    fn fill_numbers(&self, data: &Dataset, slab: &mut [u8], first: usize, scratch: &mut Scratch) {
        let row_len = self.row_len;
        let rows = slab.len() / row_len;
        let mut offset = 0;
        for (v, t) in data.variables.iter().zip(&self.types) {
            if let Values::Numbers(fill) = &v.values {
                let mut done = 0;
                while done < rows {
                    let n = BLOCK.min(rows - done);
                    let (values, codes) = (&mut scratch.values[..n], &mut scratch.codes[..n]);
                    fill(first + done, values, codes);
                    let cells = &mut slab[done * row_len..(done + n) * row_len];
                    encode(cells, row_len, offset, *t, values, codes);
                    done += n;
                }
            }
            offset += t.width();
        }
    }

    fn write_strls(&self, data: &Dataset, out: &mut impl Write) -> Result<()> {
        for (j, (v, t)) in data.variables.iter().zip(&self.types).enumerate() {
            if *t != StorageType::StrL {
                continue;
            }
            for &r in &self.strl_rows[j] {
                let (s, binary) = v.values.string(r);
                let mut head = Vec::with_capacity(20);
                head.extend_from_slice(b"GSO");
                head.extend_from_slice(&(j as u32 + 1).to_le_bytes());
                head.extend_from_slice(&(r as u64 + 1).to_le_bytes());
                // Binary is stored as is; text ends with a NUL.
                head.push(if binary { 129 } else { 130 });
                head.extend_from_slice(&(s.len() as u32 + !binary as u32).to_le_bytes());
                out.write_all(&head)?;
                out.write_all(s)?;
                if !binary {
                    out.write_all(&[0])?;
                }
            }
        }
        Ok(())
    }
}

/// Bytes a strL takes in the strL section.
fn gso_len((s, binary): (&[u8], bool)) -> usize {
    3 + 4 + 8 + 1 + 4 + s.len() + !binary as usize
}

/// Buffers for one block of a numeric column.
struct Scratch {
    values: Vec<f64>,
    codes: Vec<u8>,
}

impl Default for Scratch {
    fn default() -> Self {
        Scratch { values: vec![0.0; BLOCK], codes: vec![0; BLOCK] }
    }
}

/// Store `values` and their missing `codes` as storage type `t` at
/// `offset` in each row of `rows` (rows of `row_len` bytes).
fn encode(rows: &mut [u8], row_len: usize, offset: usize, t: StorageType, values: &[f64], codes: &[u8]) {
    fn store<const W: usize>(
        rows: &mut [u8],
        row_len: usize,
        offset: usize,
        values: &[f64],
        codes: &[u8],
        cell: impl Fn(f64, u32) -> [u8; W],
    ) {
        for ((row, &value), &code) in rows.chunks_exact_mut(row_len).zip(values).zip(codes) {
            row[offset..offset + W].copy_from_slice(&cell(value, code as u32));
        }
    }
    // A missing code's step from `.`; codes are 1 to 27 here.
    let step = |code: u32| code.saturating_sub(1);
    match t {
        StorageType::Byte => store(rows, row_len, offset, values, codes, |value, code| {
            let v = if code == 0 { value as i8 } else { missing::BYTE_MISSING + step(code) as i8 };
            [v as u8]
        }),
        StorageType::Int => store(rows, row_len, offset, values, codes, |value, code| {
            let v = if code == 0 { value as i16 } else { missing::INT_MISSING + step(code) as i16 };
            v.to_le_bytes()
        }),
        StorageType::Long => store(rows, row_len, offset, values, codes, |value, code| {
            let v = if code == 0 { value as i32 } else { LONG_MISSING + step(code) as i32 };
            v.to_le_bytes()
        }),
        StorageType::Float => store(rows, row_len, offset, values, codes, |value, code| {
            let bits = if code == 0 { (value as f32).to_bits() } else { FLOAT_MISSING + (step(code) << 11) };
            bits.to_le_bytes()
        }),
        StorageType::Double => store(rows, row_len, offset, values, codes, |value, code| {
            let bits = if code == 0 { value.to_bits() } else { DOUBLE_MISSING + ((step(code) as u64) << 40) };
            bits.to_le_bytes()
        }),
        StorageType::Str(_) | StorageType::StrL => {}
    }
}

/// An error unless every value of the numeric variable `v` (of `nobs`
/// rows, filled by `fill`) fits its storage type; the first bad row is
/// the one reported.
fn check_numbers(v: &WriteVariable, fill: &FillNumbers, nobs: usize) -> Result<()> {
    let mut scratch = Scratch::default();
    let bounds = Bounds::of(v.storage);
    let mut row = 0;
    while row < nobs {
        let n = BLOCK.min(nobs - row);
        let (values, codes) = (&mut scratch.values[..n], &mut scratch.codes[..n]);
        fill(row, values, codes);
        if let Some(i) = (0..n).find(|&i| !bounds.allows(values[i], codes[i])) {
            return check_value(v, (values[i], codes[i]), row + i);
        }
        row += n;
    }
    Ok(())
}

/// The numbers a storage type holds.
struct Bounds {
    lo: f64,
    hi: f64,
    integer: bool,
}

impl Bounds {
    fn of(storage: StorageType) -> Bounds {
        let (lo, hi, integer) = match storage {
            StorageType::Byte => (-127.0, 100.0, true),
            StorageType::Int => (-32767.0, 32740.0, true),
            StorageType::Long => (-2_147_483_647.0, 2_147_483_620.0, true),
            // The largest float and double below the bits of `.`.
            StorageType::Float => {
                let max = f32::from_bits(missing::FLOAT_MISSING - 1) as f64;
                (-max, max, false)
            }
            _ => {
                let max = f64::from_bits(missing::DOUBLE_MISSING - 1);
                (-max, max, false)
            }
        };
        Bounds { lo, hi, integer }
    }

    /// Whether a value and missing code can be written.
    #[inline]
    fn allows(&self, value: f64, code: u8) -> bool {
        match code {
            0 => (self.lo..=self.hi).contains(&value) && !(self.integer && value.fract() != 0.0),
            _ => code <= missing::LAST,
        }
    }
}

/// An error unless `value` fits `v`'s storage type.
fn check_value(v: &WriteVariable, (value, code): (f64, u8), row: usize) -> Result<()> {
    if code > missing::LAST {
        return Err(Error::new(format!("{} row {}: {} is not a missing code", v.name, row + 1, code)));
    }
    if !Bounds::of(v.storage).allows(value, code) {
        return Err(Error::new(format!(
            "{} row {}: {} does not fit storage type {}",
            v.name,
            row + 1,
            value,
            v.storage.name()
        )));
    }
    Ok(())
}

fn check_name(name: &str) -> Result<()> {
    let ok = !name.is_empty()
        && name.chars().count() <= 32
        && !name.starts_with(|c: char| c.is_ascii_digit())
        && name.chars().all(|c| c == '_' || c.is_alphanumeric());
    if ok {
        Ok(())
    } else {
        Err(Error::new(format!("\"{name}\" is not a valid Stata name")))
    }
}

fn check_text(what: &str, text: &str, max_chars: usize, max_bytes: usize) -> Result<()> {
    if text.chars().count() > max_chars || text.len() > max_bytes || text.contains('\0') {
        return Err(Error::new(format!("{what} is longer than {max_chars} characters or has a NUL")));
    }
    Ok(())
}

/// `s`, NUL-padded to `width` bytes. Callers have checked it fits.
fn field(buf: &mut Vec<u8>, s: &str, width: usize) {
    let b = &s.as_bytes()[..s.len().min(width - 1)];
    buf.extend_from_slice(b);
    buf.resize(buf.len() + width - b.len(), 0);
}

fn default_format(t: StorageType) -> String {
    match t {
        StorageType::Byte | StorageType::Int => "%8.0g".into(),
        StorageType::Long => "%12.0g".into(),
        StorageType::Float => "%9.0g".into(),
        StorageType::Double => "%10.0g".into(),
        StorageType::Str(w) => format!("%-{}s", w.min(2045)),
        StorageType::StrL => "%9s".into(),
    }
}

/// The value label section's contents.
fn value_labels(sets: &[ValueLabelSet]) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    for set in sets {
        check_name(&set.name)?;
        let mut entries: Vec<(i32, &str)> = Vec::with_capacity(set.labels.len());
        for l in &set.labels {
            let value = match l.missing {
                0 if l.value.fract() == 0.0 && (-2_147_483_647.0..=2_147_483_620.0).contains(&l.value) => {
                    l.value as i32
                }
                0 => return Err(Error::new(format!("value label {} in {} is not an integer Stata can label", l.value, set.name))),
                missing::SYSTEM => return Err(Error::new(format!("{} labels `.`, which Stata does not allow", set.name))),
                code => LONG_MISSING + (code - 1) as i32,
            };
            check_text(&format!("a label in {}", set.name), &l.text, 32000, 32000)?;
            entries.push((value, &l.text));
        }
        entries.sort_by_key(|&(v, _)| v);
        if entries.windows(2).any(|w| w[0].0 == w[1].0) {
            return Err(Error::new(format!("{} labels a value twice", set.name)));
        }
        let mut text = Vec::new();
        let mut offsets = Vec::with_capacity(entries.len());
        for (_, t) in &entries {
            offsets.push(text.len() as i32);
            text.extend_from_slice(t.as_bytes());
            text.push(0);
        }
        let n = entries.len();
        let table_len = 8 + 8 * n + text.len();
        out.extend_from_slice(b"<lbl>");
        out.extend_from_slice(&(table_len as i32).to_le_bytes());
        field(&mut out, &set.name, NAME_LEN);
        out.extend_from_slice(&[0; 3]);
        out.extend_from_slice(&(n as i32).to_le_bytes());
        out.extend_from_slice(&(text.len() as i32).to_le_bytes());
        for o in &offsets {
            out.extend_from_slice(&o.to_le_bytes());
        }
        for (v, _) in &entries {
            out.extend_from_slice(&v.to_le_bytes());
        }
        out.extend_from_slice(&text);
        out.extend_from_slice(b"</lbl>");
    }
    Ok(out)
}

/// The characteristics section's contents.
fn characteristics(chars: &[Characteristic]) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    for c in chars {
        if c.variable != "_dta" {
            check_name(&c.variable)?;
        }
        check_name(&c.name)?;
        if c.value.contains('\0') {
            return Err(Error::new(format!("characteristic {}[{}] has a NUL", c.variable, c.name)));
        }
        out.extend_from_slice(b"<ch>");
        out.extend_from_slice(&((2 * NAME_LEN + c.value.len() + 1) as u32).to_le_bytes());
        field(&mut out, &c.variable, NAME_LEN);
        field(&mut out, &c.name, NAME_LEN);
        out.extend_from_slice(c.value.as_bytes());
        out.push(0);
        out.extend_from_slice(b"</ch>");
    }
    Ok(out)
}

/// A fast hash for strL texts, which can be kilobytes each: eight bytes
/// at a time, multiply and rotate (as rustc's FxHash). Not resistant to
/// crafted collisions, which do not matter for data a caller writes.
#[derive(Default)]
struct FastHash(u64);

impl Hasher for FastHash {
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for c in &mut chunks {
            self.add(u64::from_le_bytes(c.try_into().unwrap_or_default()));
        }
        for &b in chunks.remainder() {
            self.add(b as u64);
        }
    }

    fn write_usize(&mut self, n: usize) {
        self.add(n as u64);
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

impl FastHash {
    fn add(&mut self, word: u64) {
        self.0 = (self.0.rotate_left(5) ^ word).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
}

/// Texts seen lately, by address and length. Callers such as R hand over
/// one text many times at the same address, so a row whose text is here
/// skips hashing it. Texts stay put while the writer runs, so the same
/// address and length means the same text.
struct RecentTexts(Vec<(usize, usize, bool, usize)>);

impl RecentTexts {
    const SLOTS: usize = 1024;

    fn new() -> Self {
        RecentTexts(vec![(0, 0, false, usize::MAX); Self::SLOTS])
    }

    fn slot(s: &[u8]) -> usize {
        ((s.as_ptr() as usize >> 3) ^ s.len()) % Self::SLOTS
    }

    /// The first row holding `s`, if `s` was seen here.
    fn get(&self, (s, binary): (&[u8], bool)) -> Option<usize> {
        let (addr, len, b, first) = self.0[Self::slot(s)];
        (addr == s.as_ptr() as usize && len == s.len() && b == binary && first != usize::MAX).then_some(first)
    }

    fn put(&mut self, (s, binary): (&[u8], bool), first: usize) {
        self.0[Self::slot(s)] = (s.as_ptr() as usize, s.len(), binary, first);
    }
}
