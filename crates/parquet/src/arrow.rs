//! The `ARROW:schema` metadata entry: an Arrow IPC schema message,
//! base64-encoded. pyarrow, polars and arrow (R) read it to restore what
//! Parquet's own types do not say: that a column is a dictionary (a
//! factor or `category`, ordered or not) and a timestamp's zone.
//!
//! The message is a flatbuffer (the Arrow format's `Message.fbs` and
//! `Schema.fbs`), built and read here by hand: the few tables it needs do
//! not justify a flatbuffers dependency.
//!
//! Reading takes another writer's entry, which is untrusted: every
//! offset and length is checked against the buffer, and a damaged entry
//! is an `Err` the reader turns into a warning, never a failure.

use crate::format::TimeUnit;

/// The Arrow type written for a column.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum ArrowType {
    Int {
        bits: i32,
    },
    UInt {
        bits: i32,
    },
    Float32,
    Float64,
    Bool,
    Utf8,
    Binary,
    Date32,
    Timestamp {
        unit: TimeUnit,
        zone: Option<String>,
    },
    /// Nanoseconds since midnight (time64[ns]).
    Time64Nanos,
    /// Strings, dictionary-encoded with 32-bit indices.
    Dictionary {
        ordered: bool,
    },
}

/// A flatbuffer value: a table (fields by vtable slot), a string or a
/// vector of tables or strings.
enum Node {
    Table(Vec<(u16, Field)>),
    Str(String),
    Vector(Vec<Node>),
}

enum Field {
    Bool(bool),
    U8(u8),
    I16(i16),
    I32(i32),
    I64(i64),
    Ref(Node),
}

impl Field {
    fn size(&self) -> usize {
        match self {
            Field::Bool(_) | Field::U8(_) => 1,
            Field::I16(_) => 2,
            Field::I32(_) | Field::Ref(_) => 4,
            Field::I64(_) => 8,
        }
    }
}

/// Lays a flatbuffer out front to back. Offsets to strings, vectors and
/// tables must point forward, so each node's children are written after
/// it and the offsets patched in.
struct Builder {
    buf: Vec<u8>,
}

impl Builder {
    fn align(&mut self, n: usize) {
        while self.buf.len() % n != 0 {
            self.buf.push(0);
        }
    }

    fn patch(&mut self, slot: usize, target: usize) {
        let rel = (target - slot) as u32;
        self.buf[slot..slot + 4].copy_from_slice(&rel.to_le_bytes());
    }

    fn emit(&mut self, node: &Node) -> usize {
        match node {
            Node::Str(s) => {
                self.align(4);
                let at = self.buf.len();
                self.buf.extend_from_slice(&(s.len() as u32).to_le_bytes());
                self.buf.extend_from_slice(s.as_bytes());
                self.buf.push(0);
                at
            }
            Node::Vector(items) => {
                self.align(4);
                let at = self.buf.len();
                self.buf
                    .extend_from_slice(&(items.len() as u32).to_le_bytes());
                let slots: Vec<usize> = items
                    .iter()
                    .map(|_| {
                        let s = self.buf.len();
                        self.buf.extend_from_slice(&[0; 4]);
                        s
                    })
                    .collect();
                for (item, slot) in items.iter().zip(slots) {
                    let target = self.emit(item);
                    self.patch(slot, target);
                }
                at
            }
            Node::Table(fields) => {
                // Place fields largest first after the 4-byte vtable
                // offset; with the table aligned to 8, each is aligned.
                let mut order: Vec<&(u16, Field)> = fields.iter().collect();
                order.sort_by_key(|(_, f)| std::cmp::Reverse(f.size()));
                let mut layout = Vec::with_capacity(order.len());
                let mut size = 4usize;
                for (slot, f) in &order {
                    let n = f.size();
                    size = size.div_ceil(n) * n;
                    layout.push((*slot, size));
                    size += n;
                }
                let slots = fields.iter().map(|(s, _)| *s + 1).max().unwrap_or(0) as usize;
                // The vtable, then the table.
                self.align(2);
                let vtable = self.buf.len();
                self.buf
                    .extend_from_slice(&((4 + 2 * slots) as u16).to_le_bytes());
                self.buf.extend_from_slice(&(size as u16).to_le_bytes());
                for s in 0..slots {
                    let off = layout
                        .iter()
                        .find(|(slot, _)| *slot as usize == s)
                        .map_or(0, |(_, o)| *o);
                    self.buf.extend_from_slice(&(off as u16).to_le_bytes());
                }
                self.align(8);
                let table = self.buf.len();
                self.buf.resize(table + size, 0);
                self.buf[table..table + 4]
                    .copy_from_slice(&((table - vtable) as i32).to_le_bytes());
                let mut refs = Vec::new();
                for ((_, f), (_, off)) in order.iter().zip(&layout) {
                    let at = table + off;
                    match f {
                        Field::Bool(b) => self.buf[at] = u8::from(*b),
                        Field::U8(v) => self.buf[at] = *v,
                        Field::I16(v) => self.buf[at..at + 2].copy_from_slice(&v.to_le_bytes()),
                        Field::I32(v) => self.buf[at..at + 4].copy_from_slice(&v.to_le_bytes()),
                        Field::I64(v) => self.buf[at..at + 8].copy_from_slice(&v.to_le_bytes()),
                        Field::Ref(child) => refs.push((at, child)),
                    }
                }
                for (slot, child) in refs {
                    let target = self.emit(child);
                    self.patch(slot, target);
                }
                table
            }
        }
    }
}

/// A flatbuffer whose root is `root`, padded to 8 bytes.
fn finish(root: &Node) -> Vec<u8> {
    let mut b = Builder { buf: vec![0; 4] };
    let at = b.emit(root);
    b.patch(0, at);
    b.align(8);
    b.buf
}

// Union tags of Schema.fbs's `Type`.
const TYPE_INT: u8 = 2;
const TYPE_FLOAT: u8 = 3;
const TYPE_BINARY: u8 = 4;
const TYPE_UTF8: u8 = 5;
const TYPE_BOOL: u8 = 6;
const TYPE_DATE: u8 = 8;
const TYPE_TIME: u8 = 9;
const TYPE_TIMESTAMP: u8 = 10;

fn int_table(bits: i32) -> Node {
    signed_table(bits, true)
}

fn signed_table(bits: i32, signed: bool) -> Node {
    Node::Table(vec![(0, Field::I32(bits)), (1, Field::Bool(signed))])
}

fn field(name: &str, ty: &ArrowType, dictionary_id: &mut i64) -> Node {
    let (tag, table, dictionary) = match ty {
        ArrowType::Int { bits } => (TYPE_INT, int_table(*bits), None),
        ArrowType::UInt { bits } => (TYPE_INT, signed_table(*bits, false), None),
        // TimeUnit NANOSECOND is 3; a 64-bit value.
        ArrowType::Time64Nanos => (TYPE_TIME, Node::Table(vec![(0, Field::I16(3)), (1, Field::I32(64))]), None),
        ArrowType::Float32 => (TYPE_FLOAT, Node::Table(vec![(0, Field::I16(1))]), None),
        ArrowType::Float64 => (TYPE_FLOAT, Node::Table(vec![(0, Field::I16(2))]), None),
        ArrowType::Bool => (TYPE_BOOL, Node::Table(vec![]), None),
        ArrowType::Utf8 => (TYPE_UTF8, Node::Table(vec![]), None),
        ArrowType::Binary => (TYPE_BINARY, Node::Table(vec![]), None),
        // DateUnit DAY is 0.
        ArrowType::Date32 => (TYPE_DATE, Node::Table(vec![(0, Field::I16(0))]), None),
        ArrowType::Timestamp { unit, zone } => {
            let u = match unit {
                TimeUnit::Millis => 1,
                TimeUnit::Micros => 2,
                TimeUnit::Nanos => 3,
            };
            let mut f = vec![(0, Field::I16(u))];
            if let Some(z) = zone {
                f.push((1, Field::Ref(Node::Str(z.clone()))));
            }
            (TYPE_TIMESTAMP, Node::Table(f), None)
        }
        ArrowType::Dictionary { ordered } => {
            let id = *dictionary_id;
            *dictionary_id += 1;
            let enc = Node::Table(vec![
                (0, Field::I64(id)),
                (1, Field::Ref(int_table(32))),
                (2, Field::Bool(*ordered)),
                (3, Field::I16(0)),
            ]);
            (TYPE_UTF8, Node::Table(vec![]), Some(enc))
        }
    };
    let mut fields = vec![
        (0, Field::Ref(Node::Str(name.to_string()))),
        (1, Field::Bool(true)),
        (2, Field::U8(tag)),
        (3, Field::Ref(table)),
        // Arrow C++ refuses a field without a children vector.
        (5, Field::Ref(Node::Vector(vec![]))),
    ];
    if let Some(d) = dictionary {
        fields.push((4, Field::Ref(d)));
    }
    Node::Table(fields)
}

/// The IPC schema message for `columns`, as the `ARROW:schema` value:
/// the continuation marker, the length, the flatbuffer, in base64.
pub(crate) fn schema_entry(columns: &[(String, ArrowType)]) -> String {
    let mut dictionary_id = 0;
    let fields = columns
        .iter()
        .map(|(name, ty)| field(name, ty, &mut dictionary_id))
        .collect();
    let schema = Node::Table(vec![
        (0, Field::I16(0)),
        (1, Field::Ref(Node::Vector(fields))),
    ]);
    // MetadataVersion V5 is 4; MessageHeader Schema is 1.
    let message = Node::Table(vec![
        (0, Field::I16(4)),
        (1, Field::U8(1)),
        (2, Field::Ref(schema)),
        (3, Field::I64(0)),
    ]);
    let fb = finish(&message);
    let mut ipc = Vec::with_capacity(fb.len() + 8);
    ipc.extend_from_slice(&0xffff_ffffu32.to_le_bytes());
    ipc.extend_from_slice(&(fb.len() as u32).to_le_bytes());
    ipc.extend_from_slice(&fb);
    base64(&ipc)
}

fn base64(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = u32::from(b[0]) << 16 | u32::from(b[1]) << 8 | u32::from(b[2]);
        for k in 0..4 {
            if k <= chunk.len() {
                out.push(ALPHABET[(n >> (18 - 6 * k) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

// ---- reading ----

/// What the reader takes from one top-level field of an `ARROW:schema`
/// entry.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ArrowField {
    pub(crate) name: String,
    /// The field is dictionary-encoded.
    pub(crate) dictionary: bool,
    /// Its (value) type is text: Utf8, LargeUtf8 or Utf8View.
    pub(crate) text: bool,
    /// A timestamp's zone.
    pub(crate) zone: Option<String>,
}

const TYPE_LARGE_UTF8: u8 = 20;
const TYPE_UTF8_VIEW: u8 = 24;

/// A flatbuffer being read: every access is checked, giving `None` past
/// the end.
struct Flat<'a>(&'a [u8]);

/// A table: its position and its vtable's.
#[derive(Clone, Copy)]
struct TableAt {
    at: usize,
    vtable: usize,
    vtable_len: usize,
}

impl<'a> Flat<'a> {
    fn bytes<const N: usize>(&self, at: usize) -> Option<[u8; N]> {
        self.0.get(at..at.checked_add(N)?)?.try_into().ok()
    }
    fn u8(&self, at: usize) -> Option<u8> {
        self.0.get(at).copied()
    }
    fn u16(&self, at: usize) -> Option<usize> {
        Some(u16::from_le_bytes(self.bytes(at)?) as usize)
    }
    fn u32(&self, at: usize) -> Option<usize> {
        usize::try_from(u32::from_le_bytes(self.bytes(at)?)).ok()
    }
    /// Follow the offset stored at `at`.
    fn deref(&self, at: usize) -> Option<usize> {
        let to = at.checked_add(self.u32(at)?)?;
        (to < self.0.len()).then_some(to)
    }
    fn table(&self, at: usize) -> Option<TableAt> {
        let back = i32::from_le_bytes(self.bytes(at)?);
        let vtable = usize::try_from(at as i64 - i64::from(back)).ok()?;
        let vtable_len = self.u16(vtable)?;
        if vtable_len < 4 || vtable.checked_add(vtable_len)? > self.0.len() {
            return None;
        }
        Some(TableAt {
            at,
            vtable,
            vtable_len,
        })
    }
    /// Where field `slot` of `t` is, if present.
    fn field(&self, t: TableAt, slot: usize) -> Option<usize> {
        let entry = 4 + 2 * slot;
        if entry + 2 > t.vtable_len {
            return None;
        }
        match self.u16(t.vtable + entry)? {
            0 => None,
            off => {
                let at = t.at.checked_add(off)?;
                (at < self.0.len()).then_some(at)
            }
        }
    }
    /// The table field `slot` of `t` points to.
    fn child(&self, t: TableAt, slot: usize) -> Option<TableAt> {
        self.table(self.deref(self.field(t, slot)?)?)
    }
    fn string(&self, t: TableAt, slot: usize) -> Option<Option<String>> {
        let Some(at) = self.field(t, slot) else {
            return Some(None);
        };
        let s = self.deref(at)?;
        let len = self.u32(s)?;
        let bytes = self
            .0
            .get(s.checked_add(4)?..s.checked_add(4)?.checked_add(len)?)?;
        Some(Some(std::str::from_utf8(bytes).ok()?.to_string()))
    }
    fn u8_field(&self, t: TableAt, slot: usize) -> Option<u8> {
        match self.field(t, slot) {
            Some(at) => self.u8(at),
            None => Some(0),
        }
    }
}

/// The top-level fields of an `ARROW:schema` value: base64 of an Arrow
/// IPC message (with or without the continuation marker) whose header is
/// a schema. `Err` says what is wrong with it.
pub(crate) fn read_schema(value: &[u8]) -> Result<Vec<ArrowField>, String> {
    let ipc = unbase64(value).ok_or("it is not base64")?;
    let (start, len) = match ipc.get(..4) {
        Some([0xff, 0xff, 0xff, 0xff]) => (8, ipc.get(4..8)),
        Some(_) => (4, ipc.get(..4)),
        None => return Err("it is too short".into()),
    };
    let len = len
        .map(|b| u32::from_le_bytes(b.try_into().expect("4 bytes")) as usize)
        .ok_or("it is too short")?;
    let fb = ipc
        .get(start..)
        .and_then(|b| b.get(..len))
        .ok_or("its message is longer than the entry")?;
    fields(&Flat(fb)).ok_or_else(|| "its message is damaged".to_string())
}

fn fields(fb: &Flat) -> Option<Vec<ArrowField>> {
    let message = fb.table(fb.deref(0)?)?;
    // MessageHeader 1 is Schema.
    if fb.u8_field(message, 1)? != 1 {
        return None;
    }
    let schema = fb.child(message, 2)?;
    let Some(at) = fb.field(schema, 1) else {
        return Some(Vec::new());
    };
    let vector = fb.deref(at)?;
    let n = fb.u32(vector)?;
    // Each element is a 4-byte offset, all within the buffer.
    if n > (fb.0.len() - vector) / 4 {
        return None;
    }
    let mut out = Vec::with_capacity(n);
    for k in 0..n {
        let field = fb.table(fb.deref(vector + 4 + 4 * k)?)?;
        let tag = fb.u8_field(field, 2)?;
        let zone = if tag == TYPE_TIMESTAMP {
            match fb.field(field, 3) {
                Some(_) => fb.string(fb.child(field, 3)?, 1)?,
                None => None,
            }
        } else {
            None
        };
        out.push(ArrowField {
            name: fb.string(field, 0)?.unwrap_or_default(),
            dictionary: fb.field(field, 4).is_some(),
            text: matches!(tag, TYPE_UTF8 | TYPE_LARGE_UTF8 | TYPE_UTF8_VIEW),
            zone,
        });
    }
    Some(out)
}

/// Each byte's base64 value, or 255 for a byte that is not a digit
/// (padding and whitespace among them).
const BASE64: [u8; 256] = {
    let mut t = [255u8; 256];
    let digits = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut i = 0;
    while i < 64 {
        t[digits[i] as usize] = i as u8;
        i += 1;
    }
    t
};

/// Standard base64, with or without padding; ASCII whitespace is
/// skipped. Four digits at a time while they are all digits (a wide
/// file's entry is hundreds of kilobytes of them), then a byte at a
/// time from the first group that holds anything else.
fn unbase64(text: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() / 4 * 3 + 3);
    let mut at = 0;
    for group in text.chunks_exact(4) {
        let v = [BASE64[group[0] as usize], BASE64[group[1] as usize], BASE64[group[2] as usize], BASE64[group[3] as usize]];
        if (v[0] | v[1] | v[2] | v[3]) > 63 {
            break;
        }
        let word = u32::from(v[0]) << 18 | u32::from(v[1]) << 12 | u32::from(v[2]) << 6 | u32::from(v[3]);
        out.extend_from_slice(&word.to_be_bytes()[1..]);
        at += 4;
    }
    unbase64_rest(&text[at..], out)
}

/// [`unbase64`] a byte at a time, appending to `out` (which holds whole
/// groups of four digits' bytes, so no bits are carried in).
fn unbase64_rest(text: &[u8], mut out: Vec<u8>) -> Option<Vec<u8>> {
    let (mut acc, mut bits) = (0u32, 0u32);
    let mut padding = 0;
    for &c in text {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => {
                padding += 1;
                continue;
            }
            c if c.is_ascii_whitespace() => continue,
            _ => return None,
        };
        if padding > 0 {
            return None;
        }
        acc = acc << 6 | u32::from(v);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    (padding <= 2).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_by_fours_reads_as_a_byte_at_a_time_does() {
        let mut seed = 0x1234_5678_9abc_def1u64;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        let digits = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for case in 0..5000 {
            let len = (next() % 70) as usize;
            let mut text: Vec<u8> = (0..len).map(|_| digits[(next() % 64) as usize]).collect();
            // Sometimes whitespace, padding or a byte that is no digit,
            // anywhere.
            for _ in 0..next() % 4 {
                if !text.is_empty() {
                    let at = (next() as usize) % text.len();
                    text[at] = [b' ', b'\n', b'=', b'=', b'-', 0xff, b'\t'][(next() % 7) as usize];
                }
            }
            for _ in 0..next() % 3 {
                text.push(b'=');
            }
            assert_eq!(unbase64(&text), unbase64_rest(&text, Vec::new()), "case {case}: {:?}", String::from_utf8_lossy(&text));
        }
        assert_eq!(unbase64(b"aGVsbG8gd29ybGQ=").as_deref(), Some(&b"hello world"[..]));
    }

    #[test]
    fn our_own_entry_reads_back() {
        let columns = vec![
            ("a".to_string(), ArrowType::Int { bits: 8 }),
            (
                "region".to_string(),
                ArrowType::Dictionary { ordered: true },
            ),
            ("s".to_string(), ArrowType::Utf8),
            (
                "when".to_string(),
                ArrowType::Timestamp {
                    unit: TimeUnit::Micros,
                    zone: Some("America/New_York".into()),
                },
            ),
            (
                "local".to_string(),
                ArrowType::Timestamp {
                    unit: TimeUnit::Nanos,
                    zone: None,
                },
            ),
        ];
        let got = read_schema(schema_entry(&columns).as_bytes()).unwrap();
        let summary: Vec<(&str, bool, bool, Option<&str>)> = got
            .iter()
            .map(|f| (f.name.as_str(), f.dictionary, f.text, f.zone.as_deref()))
            .collect();
        assert_eq!(
            summary,
            vec![
                ("a", false, false, None),
                ("region", true, true, None),
                ("s", false, true, None),
                ("when", false, false, Some("America/New_York")),
                ("local", false, false, None),
            ]
        );
    }

    #[test]
    fn damaged_entries_are_errors_not_panics() {
        let columns = vec![
            (
                "region".to_string(),
                ArrowType::Dictionary { ordered: false },
            ),
            (
                "when".to_string(),
                ArrowType::Timestamp {
                    unit: TimeUnit::Millis,
                    zone: Some("UTC".into()),
                },
            ),
        ];
        let good = schema_entry(&columns);
        let ipc = unbase64(good.as_bytes()).unwrap();
        assert!(read_schema(b"not base64!").is_err());
        assert!(read_schema(b"").is_err());
        assert!(read_schema(b"AAAA====").is_err());
        // Every byte set to each of a few values, and every cut: an
        // answer or an error, never a panic.
        for at in 0..ipc.len() {
            for v in [0x00, 0x01, 0x7f, 0x80, 0xff] {
                let mut bad = ipc.clone();
                bad[at] = v;
                let _ = read_schema(base64(&bad).as_bytes());
            }
            let _ = read_schema(base64(&ipc[..at]).as_bytes());
        }
        // Without the continuation marker (the older framing).
        let legacy = &ipc[4..];
        assert_eq!(read_schema(base64(legacy).as_bytes()).unwrap().len(), 2);
    }

    #[test]
    fn base64_reads_back() {
        for data in [&b""[..], b"f", b"fo", b"foo", b"foobar", &[0xff, 0, 0x80]] {
            assert_eq!(unbase64(base64(data).as_bytes()).unwrap(), data);
        }
        assert_eq!(unbase64(b"Zm9v\nYmFy").unwrap(), b"foobar");
        assert_eq!(unbase64(b"Zm9v YmFy").unwrap(), b"foobar");
        assert!(unbase64(b"Zg==Zg").is_none());
    }

    #[test]
    fn base64_matches_known_values() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    /// A reader for the flatbuffers written here, enough to check them.
    struct Fb<'a>(&'a [u8]);

    impl Fb<'_> {
        fn u32(&self, at: usize) -> usize {
            u32::from_le_bytes(self.0[at..at + 4].try_into().unwrap()) as usize
        }
        fn u16(&self, at: usize) -> usize {
            u16::from_le_bytes(self.0[at..at + 2].try_into().unwrap()) as usize
        }
        /// The absolute position of field `slot` of the table at `table`.
        fn field(&self, table: usize, slot: usize) -> Option<usize> {
            let vt =
                table - i32::from_le_bytes(self.0[table..table + 4].try_into().unwrap()) as usize;
            if 4 + 2 * slot >= self.u16(vt) {
                return None;
            }
            match self.u16(vt + 4 + 2 * slot) {
                0 => None,
                off => Some(table + off),
            }
        }
        fn deref(&self, at: usize) -> usize {
            at + self.u32(at)
        }
        fn string(&self, at: usize) -> &str {
            let s = self.deref(at);
            std::str::from_utf8(&self.0[s + 4..s + 4 + self.u32(s)]).unwrap()
        }
    }

    #[test]
    fn the_message_has_the_fields_arrow_reads() {
        let columns = vec![
            ("a".to_string(), ArrowType::Int { bits: 8 }),
            (
                "region".to_string(),
                ArrowType::Dictionary { ordered: true },
            ),
            (
                "when".to_string(),
                ArrowType::Timestamp {
                    unit: TimeUnit::Micros,
                    zone: Some("America/New_York".into()),
                },
            ),
        ];
        let text = schema_entry(&columns);
        // Decode the base64 again.
        let alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut bits = Vec::new();
        for c in text.bytes().filter(|&c| c != b'=') {
            bits.push(alphabet.iter().position(|&a| a == c).unwrap() as u32);
        }
        let mut bytes = Vec::new();
        for chunk in bits.chunks(4) {
            let n = chunk
                .iter()
                .enumerate()
                .fold(0u32, |n, (k, v)| n | v << (18 - 6 * k));
            for k in 0..chunk.len() - 1 {
                bytes.push((n >> (16 - 8 * k)) as u8);
            }
        }
        assert_eq!(&bytes[..4], &[0xff; 4]);
        let len = u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
        assert_eq!(len % 8, 0);
        let fb = Fb(&bytes[8..8 + len]);
        let message = fb.deref(0);
        assert_eq!(message % 8, 0);
        assert_eq!(fb.u16(fb.field(message, 0).unwrap()), 4);
        assert_eq!(fb.0[fb.field(message, 1).unwrap()], 1);
        let schema = fb.deref(fb.field(message, 2).unwrap());
        let fields = fb.deref(fb.field(schema, 1).unwrap());
        assert_eq!(fb.u32(fields), 3);
        let field = |k: usize| fb.deref(fields + 4 + 4 * k);
        assert_eq!(fb.string(fb.field(field(0), 0).unwrap()), "a");
        assert_eq!(fb.0[fb.field(field(0), 2).unwrap()], TYPE_INT);
        let int = fb.deref(fb.field(field(0), 3).unwrap());
        assert_eq!(fb.u32(fb.field(int, 0).unwrap()), 8);
        // The dictionary field: utf8 values, ordered, int32 indices.
        assert_eq!(fb.0[fb.field(field(1), 2).unwrap()], TYPE_UTF8);
        let dict = fb.deref(fb.field(field(1), 4).unwrap());
        assert_eq!(fb.0[fb.field(dict, 2).unwrap()], 1);
        let index = fb.deref(fb.field(dict, 1).unwrap());
        assert_eq!(fb.u32(fb.field(index, 0).unwrap()), 32);
        // Every field has a children vector.
        for k in 0..3 {
            assert_eq!(fb.u32(fb.deref(fb.field(field(k), 5).unwrap())), 0);
        }
        let ts = fb.deref(fb.field(field(2), 3).unwrap());
        assert_eq!(fb.u16(fb.field(ts, 0).unwrap()), 2);
        assert_eq!(fb.string(fb.field(ts, 1).unwrap()), "America/New_York");
    }
}
