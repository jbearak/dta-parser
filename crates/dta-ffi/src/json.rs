//! The little JSON the ABI hands to JavaScript, written by hand so the
//! crate needs no dependencies.

use dta::{missing, Characteristic, Metadata, ValueLabelSet};

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
}
