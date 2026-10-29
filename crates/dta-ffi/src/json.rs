//! The little JSON the ABIs hand to JavaScript and Julia, and read back
//! from Julia, written by hand so the crate needs no dependencies.

use dta::{missing, Characteristic, Metadata, ValueLabelSet};

/// A note is the `_dta` characteristic `note1`, `note2`, ...; `note0`
/// holds their count.
#[cfg(not(target_arch = "wasm32"))]
pub fn is_note(c: &Characteristic) -> bool {
    c.variable == "_dta" && c.name.strip_prefix("note").is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

/// Everything about a file but its data, as one object: the fields of
/// [`metadata`], then `valueLabels`, `characteristics` (without notes)
/// and `notes`.
#[cfg(not(target_arch = "wasm32"))]
pub fn document(m: &Metadata, sets: &[ValueLabelSet], chars: &[Characteristic], notes: &[String]) -> String {
    let mut o = metadata(m);
    o.pop();
    o.push_str(",\"valueLabels\":");
    o.push_str(&value_labels(sets));
    o.push_str(",\"characteristics\":");
    let kept: Vec<Characteristic> = chars.iter().filter(|c| !is_note(c)).cloned().collect();
    o.push_str(&characteristics(&kept));
    o.push_str(",\"notes\":[");
    for (i, n) in notes.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        string(&mut o, n);
    }
    o.push_str("]}");
    o
}

/// A parsed JSON value.
#[cfg(not(target_arch = "wasm32"))]
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

#[cfg(not(target_arch = "wasm32"))]
impl Value {
    /// The member `key` of an object; Null when absent.
    pub fn get(&self, key: &str) -> &Value {
        match self {
            Value::Object(fields) => fields.iter().find(|(k, _)| k == key).map_or(&Value::Null, |(_, v)| v),
            _ => &Value::Null,
        }
    }

    /// A string member, or "" when absent.
    pub fn str(&self, key: &str) -> Result<&str, String> {
        match self.get(key) {
            Value::String(s) => Ok(s),
            Value::Null => Ok(""),
            _ => Err(format!("\"{key}\" must be a string")),
        }
    }

    /// An array member, or empty when absent.
    pub fn array(&self, key: &str) -> Result<&[Value], String> {
        match self.get(key) {
            Value::Array(a) => Ok(a),
            Value::Null => Ok(&[]),
            _ => Err(format!("\"{key}\" must be an array")),
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn parse(text: &str) -> Result<Value, String> {
    let mut p = Parser { s: text.as_bytes(), at: 0 };
    let v = p.value(0)?;
    p.space();
    if p.at != p.s.len() {
        return Err(p.fail("trailing characters"));
    }
    Ok(v)
}

#[cfg(not(target_arch = "wasm32"))]
struct Parser<'a> {
    s: &'a [u8],
    at: usize,
}

#[cfg(not(target_arch = "wasm32"))]
impl Parser<'_> {
    fn fail(&self, what: &str) -> String {
        format!("bad metadata JSON at byte {}: {what}", self.at)
    }

    fn space(&mut self) {
        while self.s.get(self.at).is_some_and(|b| b.is_ascii_whitespace()) {
            self.at += 1;
        }
    }

    fn eat(&mut self, b: u8) -> bool {
        self.space();
        if self.s.get(self.at) == Some(&b) {
            self.at += 1;
            true
        } else {
            false
        }
    }

    fn value(&mut self, depth: usize) -> Result<Value, String> {
        if depth > 64 {
            return Err(self.fail("nested too deeply"));
        }
        self.space();
        let rest = &self.s[self.at..];
        for (word, v) in [(&b"null"[..], Value::Null), (b"true", Value::Bool(true)), (b"false", Value::Bool(false))] {
            if rest.starts_with(word) {
                self.at += word.len();
                return Ok(v);
            }
        }
        match rest.first() {
            Some(b'"') => self.string().map(Value::String),
            Some(b'[') => {
                self.at += 1;
                let mut items = Vec::new();
                if self.eat(b']') {
                    return Ok(Value::Array(items));
                }
                loop {
                    items.push(self.value(depth + 1)?);
                    if self.eat(b']') {
                        return Ok(Value::Array(items));
                    }
                    if !self.eat(b',') {
                        return Err(self.fail("expected , or ]"));
                    }
                }
            }
            Some(b'{') => {
                self.at += 1;
                let mut fields = Vec::new();
                if self.eat(b'}') {
                    return Ok(Value::Object(fields));
                }
                loop {
                    self.space();
                    let key = self.string()?;
                    if !self.eat(b':') {
                        return Err(self.fail("expected :"));
                    }
                    fields.push((key, self.value(depth + 1)?));
                    if self.eat(b'}') {
                        return Ok(Value::Object(fields));
                    }
                    if !self.eat(b',') {
                        return Err(self.fail("expected , or }"));
                    }
                }
            }
            Some(b'-' | b'0'..=b'9') => {
                let start = self.at;
                while self.s.get(self.at).is_some_and(|b| b"+-.eE0123456789".contains(b)) {
                    self.at += 1;
                }
                let text = std::str::from_utf8(&self.s[start..self.at]).unwrap_or("");
                text.parse().map(Value::Number).map_err(|_| self.fail("bad number"))
            }
            _ => Err(self.fail("expected a value")),
        }
    }

    fn string(&mut self) -> Result<String, String> {
        if self.s.get(self.at) != Some(&b'"') {
            return Err(self.fail("expected a string"));
        }
        self.at += 1;
        let mut out = Vec::new();
        loop {
            let Some(&b) = self.s.get(self.at) else { return Err(self.fail("unterminated string")) };
            self.at += 1;
            match b {
                b'"' => break,
                b'\\' => {
                    let Some(&e) = self.s.get(self.at) else { return Err(self.fail("unterminated string")) };
                    self.at += 1;
                    let c = match e {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let mut unit = self.hex4()?;
                            if (0xd800..0xdc00).contains(&unit) && self.s[self.at..].starts_with(b"\\u") {
                                self.at += 2;
                                let low = self.hex4()?;
                                unit = 0x10000 + ((unit - 0xd800) << 10) + (low.wrapping_sub(0xdc00) & 0x3ff);
                            }
                            char::from_u32(unit).ok_or_else(|| self.fail("bad \\u escape"))?
                        }
                        _ => return Err(self.fail("bad escape")),
                    };
                    let mut tmp = [0u8; 4];
                    out.extend_from_slice(c.encode_utf8(&mut tmp).as_bytes());
                }
                b => out.push(b),
            }
        }
        String::from_utf8(out).map_err(|_| self.fail("text is not UTF-8"))
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let digits = self.s.get(self.at..self.at + 4).ok_or_else(|| self.fail("short \\u escape"))?;
        let text = std::str::from_utf8(digits).map_err(|_| self.fail("bad \\u escape"))?;
        self.at += 4;
        u32::from_str_radix(text, 16).map_err(|_| self.fail("bad \\u escape"))
    }
}

fn string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn field(out: &mut String, name: &str, value: &str) {
    string(out, name);
    out.push(':');
    string(out, value);
}

pub fn metadata(m: &Metadata) -> String {
    let mut o = String::from("{");
    o.push_str(&format!("\"release\":{},\"nobs\":{},", m.release, m.nobs));
    field(&mut o, "byteOrder", if m.byte_order == dta::ByteOrder::Little { "little" } else { "big" });
    o.push(',');
    field(&mut o, "label", &m.label);
    o.push(',');
    field(&mut o, "timestamp", &m.timestamp);
    o.push(',');
    field(&mut o, "encoding", m.encoding.name());
    o.push_str(",\"sortedBy\":[");
    for (i, v) in m.sort_order.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push_str(&v.to_string());
    }
    o.push_str("],\"variables\":[");
    for (i, v) in m.variables.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push('{');
        field(&mut o, "name", &v.name);
        o.push(',');
        field(&mut o, "type", &v.storage.name());
        o.push(',');
        field(&mut o, "format", &v.format);
        o.push(',');
        field(&mut o, "label", &v.label);
        o.push(',');
        field(&mut o, "valueLabels", &v.value_labels);
        o.push('}');
    }
    o.push_str("]}");
    o
}

/// `[{"name": ..., "labels": [[value or ".a", text], ...]}, ...]`
pub fn value_labels(sets: &[ValueLabelSet]) -> String {
    let mut o = String::from("[");
    for (i, s) in sets.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push('{');
        field(&mut o, "name", &s.name);
        o.push_str(",\"labels\":[");
        for (j, l) in s.labels.iter().enumerate() {
            if j > 0 {
                o.push(',');
            }
            o.push('[');
            match missing::name(l.missing) {
                Some(name) => string(&mut o, &name),
                None => o.push_str(&l.value.to_string()),
            }
            o.push(',');
            string(&mut o, &l.text);
            o.push(']');
        }
        o.push_str("]}");
    }
    o.push(']');
    o
}

pub fn characteristics(chars: &[Characteristic]) -> String {
    let mut o = String::from("[");
    for (i, c) in chars.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push('{');
        field(&mut o, "variable", &c.variable);
        o.push(',');
        field(&mut o, "name", &c.name);
        o.push(',');
        field(&mut o, "value", &c.value);
        o.push('}');
    }
    o.push(']');
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_strings() {
        let mut o = String::new();
        string(&mut o, "a\"b\\c\n\u{1}é");
        assert_eq!(o, "\"a\\\"b\\\\c\\n\\u0001é\"");
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[test]
    fn parses_what_it_writes() {
        let text = "a\"b\\c\n\u{1}é😀";
        let mut o = String::new();
        string(&mut o, text);
        assert_eq!(parse(&o).unwrap(), Value::String(text.into()));
        assert_eq!(parse(r#""😀""#).unwrap(), Value::String("😀".into()));
        let v = parse(r#" {"a": [1, -2.5e3, true, null], "b": {}, "c": "x"} "#).unwrap();
        assert_eq!(v.array("a").unwrap(), &[Value::Number(1.0), Value::Number(-2500.0), Value::Bool(true), Value::Null]);
        assert_eq!(v.str("c").unwrap(), "x");
        assert_eq!(v.str("absent").unwrap(), "");
        for bad in ["[1,", r#"{"a" 1}"#, r#""abc"#, "[1] x", "tru", "[01x]"] {
            assert!(parse(bad).is_err(), "{bad}");
        }
    }
}
