//! The header and variable descriptors of releases 104 to 115, which are
//! plain binary with fixed-width fields and no section map.
//!
//! In order: release (1 byte), byte order (1 = big-endian, 2 =
//! little-endian), file type, a spare byte, the variable count (u16),
//! the observation count (u32), the data label, the timestamp (105+),
//! then per-variable type codes, names, the sort list, formats, value
//! label set names and variable labels, then the characteristics
//! ("expansion fields", 105+), the data, and the value labels to the end
//! of the file.

use crate::cursor::{ByteOrder, Cursor};
use crate::encoding::Encoding;
use crate::error::{Error, Result};
use crate::header::{text, Layout, Metadata, Parsed, Sections, Variable};
use crate::source::{ensure_room, read_vec, Source};
use crate::types::StorageType;

pub(crate) const RELEASES: [u16; 8] = [104, 105, 108, 110, 111, 113, 114, 115];

impl Layout {
    pub fn binary(release: u16) -> Layout {
        Layout {
            release,
            name_len: if release <= 108 { 9 } else { 33 },
            format_len: match release {
                104 => 7,
                105..=113 => 12,
                _ => 49,
            },
            var_label_len: if release <= 105 { 32 } else { 81 },
            sort_len: 2,
            extended_missing: release >= 113,
            strl_v_len: 0,
        }
    }
}

/// The type code releases 111 to 115 store.
fn type_111(code: u8) -> Option<StorageType> {
    Some(match code {
        1..=244 => StorageType::Str(code as u16),
        251 => StorageType::Byte,
        252 => StorageType::Int,
        253 => StorageType::Long,
        254 => StorageType::Float,
        255 => StorageType::Double,
        _ => return None,
    })
}

/// The type code releases before 111 store: a letter for numbers, or
/// 127 plus the width for strings.
fn type_old(code: u8) -> Option<StorageType> {
    Some(match code {
        b'b' => StorageType::Byte,
        b'i' => StorageType::Int,
        b'l' => StorageType::Long,
        b'f' => StorageType::Float,
        b'd' => StorageType::Double,
        128..=255 => StorageType::Str(code as u16 - 127),
        _ => return None,
    })
}

pub(crate) fn parse_binary<S: Source + ?Sized>(src: &mut S, encoding: Encoding) -> Result<Parsed> {
    let len = src.len();
    let head = read_vec(src, 0, len.min(4))?;
    let release = head[0] as u16;
    if !RELEASES.contains(&release) {
        return Err(Error::at(0, format!("unsupported .dta release {release}")));
    }
    let order = match head.get(1) {
        Some(1) => ByteOrder::Big,
        Some(2) => ByteOrder::Little,
        _ => return Err(Error::at(1, "byte order must be 1 or 2")),
    };
    let layout = Layout::binary(release);
    let data_label_len = if release <= 105 { 32 } else { 81 };
    let stamp_len = if release >= 105 { 18 } else { 0 };

    let fixed = 4 + 2 + 4 + data_label_len + stamp_len;
    let prefix = read_vec(src, 0, (fixed as u64).min(len))?;
    let mut c = Cursor::new(&prefix, 0, order);
    c.skip(4)?;
    let nvar = c.u16()? as usize;
    let nobs = c.u32()? as u64;
    let label = text(c.bytes(data_label_len)?, encoding);
    let timestamp = text(c.bytes(stamp_len)?, encoding);

    let k = nvar as u64;
    let size = k
        + k * layout.name_len as u64
        + (k + 1) * 2
        + k * layout.format_len as u64
        + k * layout.name_len as u64
        + k * layout.var_label_len as u64;
    let block = read_vec(src, fixed as u64, size)?;
    ensure_room((size as usize).saturating_mul(3).saturating_add(nvar.saturating_mul(256)))?;
    let mut c = Cursor::new(&block, fixed as u64, order);
    let mut types = Vec::with_capacity(nvar);
    for _ in 0..nvar {
        let at = c.offset();
        let code = c.u8()?;
        let t = if release >= 111 { type_111(code) } else { type_old(code) };
        types.push(t.ok_or_else(|| Error::at(at, format!("unknown storage type code {code}")))?);
    }
    let field = |c: &mut Cursor, width: usize| -> Result<String> { Ok(text(c.bytes(width)?, encoding)) };
    let names = (0..nvar).map(|_| field(&mut c, layout.name_len)).collect::<Result<Vec<_>>>()?;
    let mut sort_order = Vec::new();
    let mut ended = false;
    for _ in 0..=nvar {
        let at = c.offset();
        let v = c.u16()? as usize;
        if v == 0 {
            ended = true;
        } else if !ended {
            if v > nvar {
                return Err(Error::at(at, "sort list names a variable that does not exist"));
            }
            sort_order.push(v - 1);
        }
    }
    let formats = (0..nvar).map(|_| field(&mut c, layout.format_len)).collect::<Result<Vec<_>>>()?;
    let label_sets = (0..nvar).map(|_| field(&mut c, layout.name_len)).collect::<Result<Vec<_>>>()?;
    let var_labels = (0..nvar).map(|_| field(&mut c, layout.var_label_len)).collect::<Result<Vec<_>>>()?;

    // Characteristics: records of (type, length, body) ending with a
    // record of type 0. Their length field is an i16 before 110.
    let chars_start = fixed as u64 + size;
    let mut pos = chars_start;
    if release >= 105 {
        let len_width = if release >= 110 { 4 } else { 2 };
        loop {
            let head = read_vec(src, pos, 1 + len_width)?;
            let mut c = Cursor::new(&head, pos, order);
            let kind = c.u8()?;
            let body = if len_width == 4 { c.i32()? as i64 } else { c.i16()? as i64 };
            if body < 0 {
                return Err(Error::at(pos, "negative characteristic length"));
            }
            pos += 1 + len_width as u64;
            if kind == 0 {
                break;
            }
            pos += body as u64;
            if pos > len {
                return Err(Error::at(pos, "characteristics run past the end of the file"));
            }
        }
    }
    let chars_end = if release >= 105 { pos - 1 - if release >= 110 { 4 } else { 2 } } else { pos };

    let data = pos;
    let row_len: u64 = types.iter().map(|t| t.width() as u64).sum();
    let data_end = nobs
        .checked_mul(row_len)
        .and_then(|n| n.checked_add(data))
        .filter(|&end| end <= len)
        .ok_or_else(|| Error::at(data, "the data runs past the end of the file"))?;

    let variables = (0..nvar)
        .map(|i| Variable {
            name: names[i].clone(),
            storage: types[i],
            format: formats[i].clone(),
            label: var_labels[i].clone(),
            value_labels: label_sets[i].clone(),
        })
        .collect();
    Ok(Parsed {
        meta: Metadata {
            release,
            byte_order: order,
            nobs,
            label,
            timestamp,
            variables,
            sort_order,
            encoding,
        },
        layout,
        sections: Sections {
            data,
            characteristics: (chars_start, chars_end),
            strls: (data_end, data_end),
            value_labels: (data_end, len),
        },
    })
}
