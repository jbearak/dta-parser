//! The JSON the profile needs, by hand so the crate takes no serde.
//!
//! Objects keep their members in order and keep duplicate keys, so the
//! profile's validation can find and report them. Strings without
//! escapes borrow from the text, which is checked as UTF-8 once: a
//! profile of thousands of columns and label sets is mostly short
//! strings, and allocating each was most of the time to read one.

use std::borrow::Cow;

/// A string of a parsed value: borrowed from the text unless it had
/// escapes.
pub(crate) type Text<'a> = Cow<'a, str>;

/// A parsed JSON value.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Value<'a> {
    Null,
    Bool(bool),
    Number(f64),
    String(Text<'a>),
    Array(Vec<Value<'a>>),
    Object(Vec<(Text<'a>, Value<'a>)>),
    /// A value [`parse_skipping`] passed over: its text, unparsed and
    /// only checked to be balanced.
    Skipped(&'a str),
}

impl Value<'_> {
    pub(crate) fn kind(&self) -> &'static str {
        match self {
            Value::Null => "null",
            Value::Bool(_) => "a boolean",
            Value::Number(_) => "a number",
            Value::String(_) => "text",
            Value::Array(_) => "an array",
            Value::Object(_) => "an object",
            Value::Skipped(_) => "skipped",
        }
    }
}

/// The first key that appears twice in an object's own members.
pub(crate) fn duplicate_key<'m>(members: &'m [(Text<'_>, Value<'_>)]) -> Option<&'m str> {
    let mut seen = std::collections::HashSet::with_capacity(members.len());
    members
        .iter()
        .map(|(k, _)| &**k)
        .find(|k| !seen.insert(*k))
}

/// Parse a whole JSON text.
pub(crate) fn parse(text: &[u8]) -> Result<Value<'_>, String> {
    let text = std::str::from_utf8(text)
        .map_err(|e| format!("text is not UTF-8 at byte {}", e.valid_up_to()))?;
    let mut p = Parser {
        s: text.as_bytes(),
        text,
        at: 0,
    };
    let v = p.value(0)?;
    p.space();
    if p.at != p.s.len() {
        return Err(p.fail("text after the JSON value"));
    }
    Ok(v)
}

/// Parse a whole JSON text, passing over the members of the top-level
/// object's object members for which `skip(member, key)` says so: each
/// is a [`Value::Skipped`] holding its text, to parse later if needed.
/// Scanning past a value costs a fraction of building it.
pub(crate) fn parse_skipping<'t>(
    text: &'t [u8],
    skip: &dyn Fn(&str, &str) -> bool,
) -> Result<Value<'t>, String> {
    let text = std::str::from_utf8(text)
        .map_err(|e| format!("text is not UTF-8 at byte {}", e.valid_up_to()))?;
    let mut p = Parser {
        s: text.as_bytes(),
        text,
        at: 0,
    };
    let v = if p.eat(b'{') {
        let mut members = Vec::new();
        if !p.eat(b'}') {
            loop {
                p.space();
                let key = p.string()?;
                if !p.eat(b':') {
                    return Err(p.fail("expected :"));
                }
                let value = if p.eat(b'{') {
                    let mut inner = Vec::new();
                    if !p.eat(b'}') {
                        loop {
                            p.space();
                            let k = p.string()?;
                            if !p.eat(b':') {
                                return Err(p.fail("expected :"));
                            }
                            let v = if skip(&key, &k) { p.skip()? } else { p.value(2)? };
                            inner.push((k, v));
                            if p.eat(b'}') {
                                break;
                            }
                            if !p.eat(b',') {
                                return Err(p.fail("expected , or }"));
                            }
                        }
                    }
                    Value::Object(inner)
                } else {
                    p.value(1)?
                };
                members.push((key, value));
                if p.eat(b'}') {
                    break;
                }
                if !p.eat(b',') {
                    return Err(p.fail("expected , or }"));
                }
            }
        }
        Value::Object(members)
    } else {
        p.value(0)?
    };
    p.space();
    if p.at != p.s.len() {
        return Err(p.fail("text after the JSON value"));
    }
    Ok(v)
}

struct Parser<'a> {
    s: &'a [u8],
    /// The same text, as checked UTF-8.
    text: &'a str,
    at: usize,
}

impl<'a> Parser<'a> {
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

    fn value(&mut self, depth: usize) -> Result<Value<'a>, String> {
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

    /// Pass over one value, to the comma or bracket after it: strings
    /// to their closing quote, arrays and objects to their matching
    /// bracket. Parsing its text later finds any other damage.
    fn skip(&mut self) -> Result<Value<'a>, String> {
        self.space();
        let start = self.at;
        let mut open = Vec::new();
        loop {
            let Some(&b) = self.s.get(self.at) else {
                return Err(self.fail("unterminated JSON value"));
            };
            match b {
                b'"' => {
                    self.at += 1;
                    loop {
                        let run = self.s[self.at..]
                            .iter()
                            .position(|&b| b == b'"' || b == b'\\');
                        let Some(n) = run else {
                            return Err(self.fail("unterminated string"));
                        };
                        self.at += n + 1;
                        if self.s[self.at - 1] == b'"' {
                            break;
                        }
                        // After a backslash, pass over the character it
                        // escapes.
                        self.at += 1;
                    }
                }
                b'[' | b'{' => {
                    if open.len() >= 128 {
                        return Err(self.fail("JSON nested too deeply"));
                    }
                    open.push(if b == b'[' { b']' } else { b'}' });
                    self.at += 1;
                }
                b']' | b'}' if open.is_empty() => break,
                b']' | b'}' => {
                    if open.pop() != Some(b) {
                        return Err(self.fail("unbalanced brackets"));
                    }
                    self.at += 1;
                }
                b',' if open.is_empty() => break,
                _ => self.at += 1,
            }
        }
        let raw = self.text[start..self.at].trim_end();
        if raw.is_empty() {
            return Err(self.fail("expected a JSON value"));
        }
        Ok(Value::Skipped(raw))
    }

    fn number(&mut self) -> Result<Value<'a>, String> {
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
        self.text[start..self.at]
            .parse()
            .map(Value::Number)
            .map_err(|_| self.fail("bad number"))
    }

    fn string(&mut self) -> Result<Text<'a>, String> {
        if self.s.get(self.at) != Some(&b'"') {
            return Err(self.fail("expected a string"));
        }
        self.at += 1;
        let start = self.at;
        let mut out = Vec::new();
        loop {
            // Copy the run up to the next quote or backslash at once.
            let run = self.s[self.at..]
                .iter()
                .position(|&b| b == b'"' || b == b'\\' || b < 0x20);
            let Some(n) = run else {
                return Err(self.fail("unterminated string"));
            };
            if out.is_empty() && self.s[self.at + n] == b'"' && self.at == start {
                // No escapes: the string is a slice of the text, which
                // ends at an ASCII quote, a character boundary.
                self.at += n + 1;
                return Ok(Cow::Borrowed(&self.text[start..start + n]));
            }
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
        String::from_utf8(out)
            .map(Cow::Owned)
            .map_err(|_| self.fail("text is not UTF-8"))
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
    fn skipped_members_keep_their_text() {
        let text = br#"{"v": 1, "c": {"a": {"x": [1, "]}\"", {}]}, "b" : "t\"" , "d": -2.5e1 }, "s": {"a": 2}}"#;
        let v = parse_skipping(text, &|m, k| m == "c" && k != "a").unwrap();
        let Value::Object(m) = &v else { panic!() };
        let Value::Object(c) = &m[1].1 else { panic!() };
        assert!(matches!(c[0].1, Value::Object(_)));
        assert_eq!(c[1].1, Value::Skipped(r#""t\"""#));
        assert_eq!(c[2].1, Value::Skipped("-2.5e1"));
        assert_eq!(m[2].1, parse(br#"{"a": 2}"#).unwrap());
        // Parsing the skipped text gives what a whole parse gives.
        let whole = parse(text).unwrap();
        let Value::Object(w) = &whole else { panic!() };
        let Value::Object(wc) = &w[1].1 else { panic!() };
        assert_eq!(parse(r#""t\"""#.as_bytes()).unwrap(), wc[1].1);
        for bad in [&br#"{"c": {"b": [1}}"#[..], br#"{"c": {"b": "x}}"#, br#"{"c": {"b": }}"#, br#"{"c": {"b": [}"#] {
            assert!(parse_skipping(bad, &|_, _| true).is_err(), "{:?}", String::from_utf8_lossy(bad));
        }
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
