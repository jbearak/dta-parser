//! The header and variable descriptors of releases 117 to 119, which
//! wrap each section in tags such as `<header>` and record section
//! offsets in a `<map>`.

use crate::cursor::{until_nul, ByteOrder, Cursor};
use crate::encoding::Encoding;
use crate::error::{Error, Result};
use crate::source::{ensure_room, read_vec, Source};
use crate::types::StorageType;

/// One variable's descriptor.
#[derive(Debug, Clone, PartialEq)]
pub struct Variable {
    pub name: String,
    pub storage: StorageType,
    /// Display format, such as `%9.0g`.
    pub format: String,
    /// Variable label; empty when there is none.
    pub label: String,
    /// Name of the value label set attached; empty when there is none.
    pub value_labels: String,
}

/// What the header and descriptors of a file say.
#[derive(Debug, Clone, PartialEq)]
pub struct Metadata {
    pub release: u16,
    pub byte_order: ByteOrder,
    pub nobs: u64,
    /// Data label; empty when there is none.
    pub label: String,
    /// Timestamp as written, such as `28 Oct 2026 14:38`; may be empty.
    pub timestamp: String,
    pub variables: Vec<Variable>,
    /// Indices of the variables the data is sorted by, in order.
    pub sort_order: Vec<usize>,
    /// How text was decoded: UTF-8 for 118 and later.
    pub encoding: Encoding,
}

/// Field widths and other facts that differ between releases.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Layout {
    pub release: u16,
    /// Width of variable names, value label set names and
    /// characteristic names.
    pub name_len: usize,
    pub format_len: usize,
    pub var_label_len: usize,
    /// Width of each sort list entry.
    pub sort_len: usize,
    /// Whether `.a` to `.z` exist (113 and later).
    pub extended_missing: bool,
    /// In a strL cell, bytes holding the variable number; the rest hold
    /// the observation number.
    pub strl_v_len: usize,
}

impl Layout {
    pub fn tagged(release: u16) -> Layout {
        let modern = release >= 118;
        Layout {
            release,
            name_len: if modern { 129 } else { 33 },
            format_len: if modern { 57 } else { 49 },
            var_label_len: if modern { 321 } else { 81 },
            sort_len: if release == 119 { 4 } else { 2 },
            extended_missing: true,
            strl_v_len: match release {
                117 => 4,
                118 => 2,
                _ => 3,
            },
        }
    }
}

/// Where the sections after the descriptors start, as file offsets.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Sections {
    /// First byte of the first row.
    pub data: u64,
    /// The bytes of the characteristics, without their outer tags.
    pub characteristics: (u64, u64),
    /// The bytes of the strL section, without its outer tags.
    pub strls: (u64, u64),
    /// The bytes of the value label section, without its outer tags.
    pub value_labels: (u64, u64),
}

pub(crate) struct Parsed {
    pub meta: Metadata,
    pub layout: Layout,
    pub sections: Sections,
}

/// Parse a file of release 117, 118 or 119.
pub(crate) fn parse_tagged<S: Source + ?Sized>(src: &mut S, encoding: Encoding) -> Result<Parsed> {
    let len = src.len();
    // The header and map take well under 1 KiB.
    let prefix = read_vec(src, 0, len.min(2048))?;
    let mut c = Cursor::new(&prefix, 0, ByteOrder::Little);
    c.tag("<stata_dta><header><release>")?;
    let at = c.offset();
    let release = match c.bytes(3)? {
        b"117" => 117,
        b"118" => 118,
        b"119" => 119,
        _ => return Err(Error::at(at, "unsupported .dta release")),
    };
    let layout = Layout::tagged(release);
    let enc = if release >= 118 { Encoding::Utf8 } else { encoding };
    c.tag("</release><byteorder>")?;
    let at = c.offset();
    c.order = match c.bytes(3)? {
        b"LSF" => ByteOrder::Little,
        b"MSF" => ByteOrder::Big,
        _ => return Err(Error::at(at, "byte order must be LSF or MSF")),
    };
    c.tag("</byteorder><K>")?;
    let nvar = if release == 119 { c.u32()? as usize } else { c.u16()? as usize };
    c.tag("</K><N>")?;
    let nobs = if release == 117 { c.u32()? as u64 } else { c.u64()? };
    c.tag("</N><label>")?;
    let label_len = if release == 117 { c.u8()? as usize } else { c.u16()? as usize };
    let label = text(c.bytes(label_len)?, enc);
    c.tag("</label><timestamp>")?;
    let stamp_len = c.u8()? as usize;
    let timestamp = text(c.bytes(stamp_len)?, enc);
    c.tag("</timestamp></header><map>")?;
    let mut map = [0u64; 14];
    for m in map.iter_mut() {
        *m = c.u64()?;
    }
    c.tag("</map>")?;
    let order = c.order;

    // The descriptors follow the map directly, in a fixed order and of
    // sizes the header determines. Reading them by those sizes rather
    // than by the map's offsets sidesteps 117 files whose map is wrong
    // about where the variable labels start (pandas works around the
    // same thing).
    let start = c.offset();
    let size = descriptor_size(&layout, nvar);
    let block = read_vec(src, start, size)?;
    // The descriptors decode to at most three times their bytes, plus a
    // `Variable` each.
    ensure_room((size as usize).saturating_mul(3).saturating_add(nvar.saturating_mul(256)))?;
    let mut c = Cursor::new(&block, start, order);
    c.tag("<variable_types>")?;
    let mut types = Vec::with_capacity(nvar);
    for _ in 0..nvar {
        let at = c.offset();
        let code = c.u16()?;
        types.push(
            StorageType::from_code_117(code)
                .ok_or_else(|| Error::at(at, format!("unknown storage type code {code}")))?,
        );
    }
    c.tag("</variable_types><varnames>")?;
    let names = fields(&mut c, nvar, layout.name_len, enc)?;
    c.tag("</varnames><sortlist>")?;
    let mut sort_order = Vec::new();
    let mut ended = false;
    for _ in 0..=nvar {
        let at = c.offset();
        let v = c.uint(layout.sort_len)? as usize;
        if v == 0 {
            ended = true;
        } else if !ended {
            if v > nvar {
                return Err(Error::at(at, "sort list names a variable that does not exist"));
            }
            sort_order.push(v - 1);
        }
    }
    c.tag("</sortlist><formats>")?;
    let formats = fields(&mut c, nvar, layout.format_len, enc)?;
    c.tag("</formats><value_label_names>")?;
    let label_sets = fields(&mut c, nvar, layout.name_len, enc)?;
    c.tag("</value_label_names><variable_labels>")?;
    let var_labels = fields(&mut c, nvar, layout.var_label_len, enc)?;
    c.tag("</variable_labels>")?;

    let mut variables = Vec::with_capacity(nvar);
    for i in 0..nvar {
        variables.push(Variable {
            name: names[i].clone(),
            storage: types[i],
            format: formats[i].clone(),
            label: var_labels[i].clone(),
            value_labels: label_sets[i].clone(),
        });
    }

    let row_len: u64 = types.iter().map(|t| t.width() as u64).sum();
    let sections = Sections {
        characteristics: inner(src, map[8], map[9], "<characteristics>", "</characteristics>")?,
        data: map[9] + 6,
        strls: inner(src, map[10], map[11], "<strls>", "</strls>")?,
        value_labels: inner(src, map[11], map[12], "<value_labels>", "</value_labels>")?,
    };
    let (data_start, data_end) = inner(src, map[9], map[10], "<data>", "</data>")?;
    let data_len = nobs.checked_mul(row_len);
    if data_len != Some(data_end - data_start) {
        return Err(Error::at(data_start, "data section size does not match the header"));
    }

    Ok(Parsed {
        meta: Metadata {
            release,
            byte_order: order,
            nobs,
            label,
            timestamp,
            variables,
            sort_order,
            encoding: enc,
        },
        layout,
        sections,
    })
}

fn descriptor_size(layout: &Layout, nvar: usize) -> u64 {
    let k = nvar as u64;
    let tags = "<variable_types></variable_types><varnames></varnames><sortlist></sortlist>\
                <formats></formats><value_label_names></value_label_names>\
                <variable_labels></variable_labels>"
        .len() as u64;
    tags + k * 2
        + k * layout.name_len as u64
        + (k + 1) * layout.sort_len as u64
        + k * layout.format_len as u64
        + k * layout.name_len as u64
        + k * layout.var_label_len as u64
}

/// The byte range between `open` at `start` and `close` ending at `end`,
/// after checking both tags are where the map says.
fn inner<S: Source + ?Sized>(
    src: &mut S,
    start: u64,
    end: u64,
    open: &str,
    close: &str,
) -> Result<(u64, u64)> {
    let first = start.checked_add(open.len() as u64);
    let last = end.checked_sub(close.len() as u64);
    match (first, last) {
        (Some(first), Some(last)) if first <= last && end <= src.len() => {
            if read_vec(src, start, open.len() as u64)? != open.as_bytes() {
                return Err(Error::at(start, format!("expected {open}")));
            }
            if read_vec(src, last, close.len() as u64)? != close.as_bytes() {
                return Err(Error::at(last, format!("expected {close}")));
            }
            Ok((first, last))
        }
        _ => Err(Error::at(start, format!("the map's offsets for {open} are out of range"))),
    }
}

/// `n` fixed-width text fields of `width` bytes.
fn fields(c: &mut Cursor, n: usize, width: usize, enc: Encoding) -> Result<Vec<String>> {
    (0..n).map(|_| Ok(text(c.bytes(width)?, enc))).collect()
}

/// Text of a field that ends at its first NUL, if any.
pub(crate) fn text(b: &[u8], enc: Encoding) -> String {
    enc.decode(until_nul(b))
}
