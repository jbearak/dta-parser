//! The `ARROW:schema` metadata entry: an Arrow IPC schema message,
//! base64-encoded. pyarrow, polars and arrow (R) read it to restore what
//! Parquet's own types do not say: that a column is a dictionary (a
//! factor or `category`, ordered or not) and a timestamp's zone.
//!
//! The message is a flatbuffer (the Arrow format's `Message.fbs` and
//! `Schema.fbs`), built here by hand: the few tables it needs do not
//! justify a flatbuffers dependency.

use crate::format::TimeUnit;

/// The Arrow type written for a column.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum ArrowType {
    Int {
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
const TYPE_TIMESTAMP: u8 = 10;

fn int_table(bits: i32) -> Node {
    Node::Table(vec![(0, Field::I32(bits)), (1, Field::Bool(true))])
}

fn field(name: &str, ty: &ArrowType, dictionary_id: &mut i64) -> Node {
    let (tag, table, dictionary) = match ty {
        ArrowType::Int { bits } => (TYPE_INT, int_table(*bits), None),
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

#[cfg(test)]
mod tests {
    use super::*;

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
