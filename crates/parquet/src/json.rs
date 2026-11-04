//! The JSON the profile needs, by hand so the crate takes no serde.
//!
//! Objects keep their members in order and keep duplicate keys, so the
//! profile's validation can find and report them.

/// A parsed JSON value.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Value {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    pub(crate) fn kind(&self) -> &'static str {
        match self {
            Value::Null => "null",
            Value::Bool(_) => "a boolean",
            Value::Number(_) => "a number",
            Value::String(_) => "text",
            Value::Array(_) => "an array",
            Value::Object(_) => "an object",
        }
    }
}

/// The first key that appears twice in an object's own members.
pub(crate) fn duplicate_key(members: &[(String, Value)]) -> Option<&str> {
    let mut seen = std::collections::HashSet::with_capacity(members.len());
    members
        .iter()
        .map(|(k, _)| k.as_str())
        .find(|k| !seen.insert(*k))
}

/// Parse a whole JSON text.
pub(crate) fn parse(text: &[u8]) -> Result<Value, String> {
    let mut p = Parser { s: text, at: 0 };
    let v = p.value(0)?;
    p.space();
    if p.at != p.s.len() {
        return Err(p.fail("text after the JSON value"));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    at: usize,
}

impl Parser<'_> {
    fn fail(&self, what: &str) -> String {
        format!("{what} at byte {}", self.at)
    }

    fn space(&mut self) {
        while self
            .s
            .get(self.at)
            .is_some_and(|b| matches!(b, b' ' | b'\t' | b'\n' | b'\r'))
        {
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
        if depth > 128 {
            return Err(self.fail("JSON nested too deeply"));
        }
        self.space();
        let rest = &self.s[self.at..];
        for (word, v) in [
            (&b"null"[..], Value::Null),
            (b"true", Value::Bool(true)),
            (b"false", Value::Bool(false)),
        ] {
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
                let mut members = Vec::new();
                if self.eat(b'}') {
                    return Ok(Value::Object(members));
                }
                loop {
                    self.space();
                    let key = self.string()?;
                    if !self.eat(b':') {
                        return Err(self.fail("expected :"));
                    }
                    members.push((key, self.value(depth + 1)?));
                    if self.eat(b'}') {
                        return Ok(Value::Object(members));
                    }
                    if !self.eat(b',') {
                        return Err(self.fail("expected , or }"));
                    }
                }
            }
            Some(b'-' | b'0'..=b'9') => self.number(),
            _ => Err(self.fail("expected a JSON value")),
        }
    }

    fn number(&mut self) -> Result<Value, String> {
        let start = self.at;
        let digits = |p: &mut Self| {
            let from = p.at;
            while p.s.get(p.at).is_some_and(u8::is_ascii_digit) {
                p.at += 1;
            }
            p.at > from
        };
        if self.s.get(self.at) == Some(&b'-') {
            self.at += 1;
        }
        if self.s.get(self.at) == Some(&b'0') {
            self.at += 1;
        } else if !digits(self) {
            return Err(self.fail("bad number"));
        }
        if self.s.get(self.at) == Some(&b'.') {
            self.at += 1;
            if !digits(self) {
                return Err(self.fail("bad number"));
            }
        }
        if matches!(self.s.get(self.at), Some(b'e' | b'E')) {
            self.at += 1;
            if matches!(self.s.get(self.at), Some(b'+' | b'-')) {
                self.at += 1;
            }
            if !digits(self) {
                return Err(self.fail("bad number"));
            }
        }
        let text =
            std::str::from_utf8(&self.s[start..self.at]).map_err(|_| self.fail("bad number"))?;
        text.parse()
            .map(Value::Number)
            .map_err(|_| self.fail("bad number"))
    }

    fn string(&mut self) -> Result<String, String> {
        if self.s.get(self.at) != Some(&b'"') {
            return Err(self.fail("expected a string"));
        }
        self.at += 1;
        let mut out = Vec::new();
        loop {
            // Copy the run up to the next quote or backslash at once.
            let run = self.s[self.at..]
                .iter()
                .position(|&b| b == b'"' || b == b'\\' || b < 0x20);
            let Some(n) = run else {
                return Err(self.fail("unterminated string"));
            };
            out.extend_from_slice(&self.s[self.at..self.at + n]);
            self.at += n;
            let b = self.s[self.at];
            self.at += 1;
            match b {
                b'"' => break,
                b'\\' => {
                    let Some(&e) = self.s.get(self.at) else {
                        return Err(self.fail("unterminated string"));
                    };
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
                            if (0xd800..0xdc00).contains(&unit)
                                && self.s[self.at..].starts_with(b"\\u")
                            {
                                self.at += 2;
                                let low = self.hex4()?;
                                if !(0xdc00..0xe000).contains(&low) {
                                    return Err(self.fail("bad surrogate pair"));
                                }
                                unit = 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00);
                            }
                            char::from_u32(unit).ok_or_else(|| self.fail("bad \\u escape"))?
                        }
                        _ => return Err(self.fail("bad escape")),
                    };
                    let mut tmp = [0u8; 4];
                    out.extend_from_slice(c.encode_utf8(&mut tmp).as_bytes());
                }
                _ => return Err(self.fail("control character in a string")),
            }
        }
        String::from_utf8(out).map_err(|_| self.fail("text is not UTF-8"))
    }

    fn hex4(&mut self) -> Result<u32, String> {
        let digits = self
            .s
            .get(self.at..self.at + 4)
            .ok_or_else(|| self.fail("short \\u escape"))?;
        let text = std::str::from_utf8(digits).map_err(|_| self.fail("bad \\u escape"))?;
        self.at += 4;
        u32::from_str_radix(text, 16).map_err(|_| self.fail("bad \\u escape"))
    }
}

/// Append `s` as a JSON string.
pub(crate) fn string(out: &mut String, s: &str) {
    out.push('"');
    let mut from = 0;
    for (i, c) in s.char_indices() {
        let escape = match c {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            c if (c as u32) < 0x20 => "",
            _ => continue,
        };
        out.push_str(&s[from..i]);
        if escape.is_empty() {
            out.push_str(&format!("\\u{:04x}", c as u32));
        } else {
            out.push_str(escape);
        }
        from = i + c.len_utf8();
    }
    out.push_str(&s[from..]);
    out.push('"');
}

/// Append a finite number so that it parses back to the same double:
/// integers without a fraction, others in Rust's shortest round-trip form.
pub(crate) fn number(out: &mut String, v: f64) {
    // `as i64` writes -0.0 as 0: label codes are compared as numbers, and
    // the two are the same code.
    if v.fract() == 0.0 && v.abs() < 1e17 {
        out.push_str(&format!("{}", v as i64));
    } else {
        out.push_str(&format!("{v:?}"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_values() {
        let v = parse(
            br#" {"a": [1, -2.5e3, true, false, null], "b": "x\"\u00e9\ud83d\ude00", "a": {}} "#,
        )
        .unwrap();
        let Value::Object(m) = &v else { panic!() };
        assert_eq!(m.len(), 3);
        assert_eq!(
            m[0].1,
            Value::Array(vec![
                Value::Number(1.0),
                Value::Number(-2500.0),
                Value::Bool(true),
                Value::Bool(false),
                Value::Null
            ])
        );
        assert_eq!(m[1].1, Value::String("x\"é😀".into()));
        assert_eq!(duplicate_key(m), Some("a"));
    }

    #[test]
    fn rejects_bad_json() {
        for bad in [
            &b""[..],
            b"{",
            b"[1,]",
            b"{\"a\" 1}",
            b"01",
            b"1.",
            b"-",
            b"\"\\x\"",
            b"\"a\nb\"",
            b"{} x",
            b"\"\xff\"",
        ] {
            assert!(parse(bad).is_err(), "{:?}", String::from_utf8_lossy(bad));
        }
        let deep = "[".repeat(1000);
        assert!(parse(deep.as_bytes()).unwrap_err().contains("deeply"));
    }

    #[test]
    fn strings_and_numbers_round_trip() {
        for s in [
            "",
            "plain",
            "quote \" back \\ slash",
            "line\nbreak\ttab\u{1}",
            "é 😀",
        ] {
            let mut out = String::new();
            string(&mut out, s);
            assert_eq!(parse(out.as_bytes()).unwrap(), Value::String(s.into()));
        }
        for v in [
            0.0,
            -0.0,
            1.0,
            -97.0,
            1.5,
            1e300,
            -1e-300,
            9007199254740992.0,
            0.1,
            123456789012345680000.0,
        ] {
            let mut out = String::new();
            number(&mut out, v);
            assert_eq!(
                parse(out.as_bytes()).unwrap(),
                Value::Number(if v == 0.0 { 0.0 } else { v }),
                "{out}"
            );
        }
        let mut out = String::new();
        number(&mut out, 97.0);
        assert_eq!(out, "97");
    }
}
