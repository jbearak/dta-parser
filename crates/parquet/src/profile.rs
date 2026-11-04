//! The dta profile: what Parquet cannot say about a table, as JSON under
//! the key `dta` in the file's key-value metadata (plan 0018, "The
//! profile").
//!
//! Reading is forgiving: damaged metadata is never an error, since the
//! values are intact. An entry that breaks a rule is dropped with one
//! warning naming it, and the rest is used. Writing is strict: what the
//! writer is given must be representable exactly.

use crate::json::{self, Value};
use dta::{missing, Characteristic, Error, Result, ValueLabel, ValueLabelSet};

/// The key the profile is stored under.
pub const KEY: &str = "dta";

/// The profile version this crate reads and writes.
pub const VERSION: u32 = 1;

/// The largest profile read: larger ones are ignored with a warning.
pub const MAX_BYTES: usize = 64 << 20;

/// Integer label codes must be within ±2^53, so JavaScript reads them
/// exactly.
const MAX_EXACT: f64 = 9_007_199_254_740_992.0;

/// Everything a profile says.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Profile {
    /// The profile's version; [`VERSION`] when written by this crate.
    pub version: u32,
    /// The data label.
    pub label: Option<String>,
    pub notes: Vec<String>,
    /// Characteristics of the dataset (`_dta`) and of columns.
    pub characteristics: Vec<Characteristic>,
    /// Names of the columns the data is sorted by.
    pub sort: Vec<String>,
    /// Per-column entries, in the order written.
    pub columns: Vec<ColumnProfile>,
    pub value_labels: Vec<ValueLabelSet>,
}

/// What the profile says about one column.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ColumnProfile {
    pub name: String,
    /// The variable label.
    pub label: Option<String>,
    /// The display format.
    pub format: Option<String>,
    /// The name of the column's value label set.
    pub value_labels: Option<String>,
    /// The name of the column's missing-letter column.
    pub missing_letters: Option<String>,
    pub categorical: Option<Categorical>,
    /// A timestamp's time zone. `Some("")` records a timestamp that is
    /// an instant without a zone (R's `POSIXct` without `tzone`).
    pub tz: Option<String>,
    /// A unit Parquet has no type for, such as `"s"` for pandas'
    /// `datetime64[s]` (written as milliseconds).
    pub unit: Option<String>,
}

impl ColumnProfile {
    /// A column entry with just a name.
    pub fn named(name: impl Into<String>) -> Self {
        ColumnProfile {
            name: name.into(),
            ..Default::default()
        }
    }

    fn is_empty(&self) -> bool {
        self.label.is_none()
            && self.format.is_none()
            && self.value_labels.is_none()
            && self.missing_letters.is_none()
            && self.categorical.is_none()
            && self.tz.is_none()
            && self.unit.is_none()
    }
}

/// A categorical column's levels, unused ones included, in order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Categorical {
    pub levels: Vec<String>,
    pub ordered: bool,
}

impl Profile {
    /// The entry for column `name`.
    pub fn column(&self, name: &str) -> Option<&ColumnProfile> {
        self.columns.iter().find(|c| c.name == name)
    }

    /// The entry for column `name`, added if absent.
    pub fn column_mut(&mut self, name: &str) -> &mut ColumnProfile {
        match self.columns.iter().position(|c| c.name == name) {
            Some(k) => &mut self.columns[k],
            None => {
                self.columns.push(ColumnProfile::named(name));
                self.columns.last_mut().expect("just pushed")
            }
        }
    }

    /// The value label set `name`.
    pub fn value_label_set(&self, name: &str) -> Option<&ValueLabelSet> {
        self.value_labels.iter().find(|s| s.name == name)
    }

    /// Read a profile. Returns `None`, with one warning, when the text is
    /// not JSON, is too large or is not an object; otherwise the profile
    /// and a warning for each entry dropped.
    pub fn parse(text: &[u8]) -> (Option<Profile>, Vec<String>) {
        let mut warnings = Vec::new();
        if text.len() > MAX_BYTES {
            warnings.push(format!(
                "the dta profile is {} bytes, more than the {} read; the file is read as plain Parquet",
                text.len(),
                MAX_BYTES
            ));
            return (None, warnings);
        }
        let members = match json::parse(text) {
            Ok(Value::Object(m)) => m,
            Ok(other) => {
                warnings.push(format!(
                    "the dta profile is {}, not an object; the file is read as plain Parquet",
                    other.kind()
                ));
                return (None, warnings);
            }
            Err(e) => {
                warnings.push(format!(
                    "the dta profile is not JSON ({e}); the file is read as plain Parquet"
                ));
                return (None, warnings);
            }
        };
        let mut p = Profile {
            version: VERSION,
            ..Default::default()
        };
        let mut warn = |w: String| warnings.push(w);
        let mut seen_version = false;
        for (key, value) in unique(&members, "", &mut warn) {
            match key {
                "version" => {
                    seen_version = true;
                    match value {
                        Value::Number(v) if v.fract() == 0.0 && *v >= 1.0 && *v <= f64::from(u32::MAX) => {
                            p.version = *v as u32;
                            if p.version > VERSION {
                                warn(format!(
                                    "the dta profile is version {}, newer than this reader's {VERSION}; what this reader knows is used",
                                    p.version
                                ));
                            }
                        }
                        _ => warn(format!("dropped the dta profile's \"version\": it is {}, not a positive integer", value.kind())),
                    }
                }
                "label" => match value {
                    Value::String(s) => p.label = Some(s.clone()),
                    _ => warn(dropped("label", "is not text")),
                },
                "notes" => match strings(value) {
                    Some(v) => p.notes = v,
                    None => warn(dropped("notes", "is not an array of text")),
                },
                "sort" => match strings(value) {
                    Some(v) => p.sort = v,
                    None => warn(dropped("sort", "is not an array of text")),
                },
                "characteristics" => match value {
                    Value::Object(vars) => {
                        for (var, entry) in unique(vars, "characteristics.", &mut warn) {
                            match text_object(entry) {
                                Ok(pairs) => p.characteristics.extend(pairs.into_iter().map(
                                    |(name, value)| Characteristic {
                                        variable: var.to_string(),
                                        name,
                                        value,
                                    },
                                )),
                                Err(why) => warn(dropped(&format!("characteristics.{var}"), &why)),
                            }
                        }
                    }
                    _ => warn(dropped("characteristics", "is not an object")),
                },
                "columns" => match value {
                    Value::Object(cols) => {
                        for (name, entry) in unique(cols, "columns.", &mut warn) {
                            if let Some(c) = column(name, entry, &mut warn) {
                                p.columns.push(c);
                            }
                        }
                    }
                    _ => warn(dropped("columns", "is not an object")),
                },
                "value_labels" => match value {
                    Value::Object(sets) => {
                        for (name, entry) in unique(sets, "value_labels.", &mut warn) {
                            match label_set(name, entry) {
                                Ok(set) => p.value_labels.push(set),
                                Err(why) => warn(dropped(&format!("value_labels.{name}"), &why)),
                            }
                        }
                    }
                    _ => warn(dropped("value_labels", "is not an object")),
                },
                _ => {}
            }
        }
        if !seen_version {
            warn("the dta profile has no \"version\"; it is read as version 1".into());
        }
        // A column may only name a set the profile has.
        for c in &mut p.columns {
            if let Some(set) = &c.value_labels {
                if !p.value_labels.iter().any(|s| &s.name == set) {
                    warnings.push(dropped(
                        &format!("columns.{}.value_labels", c.name),
                        &format!("names the set \"{set}\", which the profile does not have"),
                    ));
                    c.value_labels = None;
                }
            }
        }
        p.columns.retain(|c| !c.is_empty());
        (Some(p), warnings)
    }

    /// The profile as JSON. Fails, naming the problem, on what JSON or
    /// the profile cannot hold: a label code that is not finite or is an
    /// integer beyond ±2^53, a code given twice in a set, a level given
    /// twice, a name used for two entries.
    pub fn to_json(&self) -> Result<String> {
        let mut o = String::from("{\"version\":");
        o.push_str(&VERSION.to_string());
        if let Some(l) = &self.label {
            o.push_str(",\"label\":");
            json::string(&mut o, l);
        }
        if !self.notes.is_empty() {
            o.push_str(",\"notes\":");
            string_array(&mut o, &self.notes);
        }
        if !self.characteristics.is_empty() {
            o.push_str(",\"characteristics\":{");
            let mut vars: Vec<&str> = Vec::new();
            for c in &self.characteristics {
                if !vars.contains(&c.variable.as_str()) {
                    vars.push(&c.variable);
                }
            }
            for (i, var) in vars.iter().enumerate() {
                if i > 0 {
                    o.push(',');
                }
                json::string(&mut o, var);
                o.push_str(":{");
                let mut names: Vec<&str> = Vec::new();
                for c in self.characteristics.iter().filter(|c| c.variable == *var) {
                    if names.contains(&c.name.as_str()) {
                        return Err(Error::invalid(format!(
                            "the characteristic {var}[{}] is given twice",
                            c.name
                        )));
                    }
                    if !names.is_empty() {
                        o.push(',');
                    }
                    names.push(&c.name);
                    json::string(&mut o, &c.name);
                    o.push(':');
                    json::string(&mut o, &c.value);
                }
                o.push('}');
            }
            o.push('}');
        }
        if !self.sort.is_empty() {
            o.push_str(",\"sort\":");
            string_array(&mut o, &self.sort);
        }
        let columns: Vec<&ColumnProfile> = self.columns.iter().filter(|c| !c.is_empty()).collect();
        if !columns.is_empty() {
            o.push_str(",\"columns\":{");
            for (i, c) in columns.iter().enumerate() {
                if columns[..i].iter().any(|d| d.name == c.name) {
                    return Err(Error::invalid(format!(
                        "the profile has two entries for column \"{}\"",
                        c.name
                    )));
                }
                if i > 0 {
                    o.push(',');
                }
                json::string(&mut o, &c.name);
                o.push_str(":{");
                let mut first = true;
                let mut field = |o: &mut String, key: &str| {
                    if !first {
                        o.push(',');
                    }
                    first = false;
                    json::string(o, key);
                    o.push(':');
                };
                for (key, value) in [
                    ("label", &c.label),
                    ("format", &c.format),
                    ("value_labels", &c.value_labels),
                    ("missing_letters", &c.missing_letters),
                    ("tz", &c.tz),
                    ("unit", &c.unit),
                ] {
                    if let Some(v) = value {
                        field(&mut o, key);
                        json::string(&mut o, v);
                    }
                }
                if let Some(cat) = &c.categorical {
                    if let Some(level) = first_duplicate(&cat.levels) {
                        return Err(Error::invalid(format!(
                            "column \"{}\" has the level \"{level}\" twice",
                            c.name
                        )));
                    }
                    field(&mut o, "categorical");
                    o.push_str("{\"levels\":");
                    string_array(&mut o, &cat.levels);
                    o.push_str(if cat.ordered {
                        ",\"ordered\":true}"
                    } else {
                        ",\"ordered\":false}"
                    });
                }
                o.push('}');
            }
            o.push('}');
        }
        if !self.value_labels.is_empty() {
            o.push_str(",\"value_labels\":{");
            for (i, set) in self.value_labels.iter().enumerate() {
                if self.value_labels[..i].iter().any(|s| s.name == set.name) {
                    return Err(Error::invalid(format!(
                        "there are two value label sets named \"{}\"",
                        set.name
                    )));
                }
                if i > 0 {
                    o.push(',');
                }
                json::string(&mut o, &set.name);
                o.push_str(":[");
                let mut seen = std::collections::HashSet::new();
                for (j, l) in set.labels.iter().enumerate() {
                    let code = code_key(l).map_err(|why| {
                        Error::invalid(format!("value label set \"{}\": {why}", set.name))
                    })?;
                    if !seen.insert(code) {
                        return Err(Error::invalid(format!(
                            "value label set \"{}\" labels {} twice",
                            set.name,
                            code_text(l)
                        )));
                    }
                    if j > 0 {
                        o.push(',');
                    }
                    o.push('[');
                    if l.missing == 0 {
                        json::number(&mut o, l.value);
                    } else {
                        json::string(
                            &mut o,
                            &missing::name(l.missing).expect("checked by code_key"),
                        );
                    }
                    o.push(',');
                    json::string(&mut o, &l.text);
                    o.push(']');
                }
                o.push(']');
            }
            o.push('}');
        }
        o.push('}');
        if o.len() > MAX_BYTES {
            return Err(Error::invalid(format!(
                "the dta profile would be {} bytes, more than the {MAX_BYTES} readers accept",
                o.len()
            )));
        }
        Ok(o)
    }
}

fn dropped(what: &str, why: &str) -> String {
    format!("dropped \"{what}\" from the dta profile: it {why}")
}

/// The members of an object whose keys appear once; a key that appears
/// more than once is dropped, every time, with one warning.
fn unique<'v>(
    members: &'v [(String, Value)],
    path: &str,
    warn: &mut impl FnMut(String),
) -> Vec<(&'v str, &'v Value)> {
    let mut counts = std::collections::HashMap::<&str, usize>::new();
    for (k, _) in members {
        *counts.entry(k.as_str()).or_default() += 1;
    }
    let mut warned = std::collections::HashSet::new();
    let mut out = Vec::with_capacity(members.len());
    for (k, v) in members {
        if counts[k.as_str()] > 1 {
            if warned.insert(k.as_str()) {
                warn(dropped(&format!("{path}{k}"), "appears more than once"));
            }
        } else {
            out.push((k.as_str(), v));
        }
    }
    out
}

fn strings(v: &Value) -> Option<Vec<String>> {
    match v {
        Value::Array(items) => items
            .iter()
            .map(|i| match i {
                Value::String(s) => Some(s.clone()),
                _ => None,
            })
            .collect(),
        _ => None,
    }
}

/// An object whose values are all text.
fn text_object(v: &Value) -> std::result::Result<Vec<(String, String)>, String> {
    let Value::Object(members) = v else {
        return Err("is not an object".into());
    };
    if let Some(k) = json::duplicate_key(members) {
        return Err(format!("has the key \"{k}\" more than once"));
    }
    members
        .iter()
        .map(|(k, v)| match v {
            Value::String(s) => Ok((k.clone(), s.clone())),
            _ => Err(format!("has \"{k}\", which is not text")),
        })
        .collect()
}

fn column(name: &str, v: &Value, warn: &mut impl FnMut(String)) -> Option<ColumnProfile> {
    let Value::Object(members) = v else {
        warn(dropped(&format!("columns.{name}"), "is not an object"));
        return None;
    };
    let mut c = ColumnProfile::named(name);
    let path = format!("columns.{name}.");
    for (key, value) in unique(members, &path, warn) {
        let text = |value: &Value| match value {
            Value::String(s) => Some(s.clone()),
            _ => None,
        };
        let slot = match key {
            "label" => &mut c.label,
            "format" => &mut c.format,
            "value_labels" => &mut c.value_labels,
            "missing_letters" => &mut c.missing_letters,
            "tz" => &mut c.tz,
            "unit" => &mut c.unit,
            "categorical" => {
                match categorical(value) {
                    Ok(cat) => c.categorical = Some(cat),
                    Err(why) => warn(dropped(&format!("{path}categorical"), &why)),
                }
                continue;
            }
            _ => continue,
        };
        match text(value) {
            Some(s) => *slot = Some(s),
            None => warn(dropped(&format!("{path}{key}"), "is not text")),
        }
    }
    Some(c)
}

fn categorical(v: &Value) -> std::result::Result<Categorical, String> {
    let Value::Object(members) = v else {
        return Err("is not an object".into());
    };
    if let Some(k) = json::duplicate_key(members) {
        return Err(format!("has the key \"{k}\" more than once"));
    }
    let mut cat = Categorical::default();
    let mut has_levels = false;
    for (k, v) in members {
        match k.as_str() {
            "levels" => {
                cat.levels = strings(v).ok_or("has levels that are not an array of text")?;
                if let Some(level) = first_duplicate(&cat.levels) {
                    return Err(format!("has the level \"{level}\" more than once"));
                }
                has_levels = true;
            }
            "ordered" => match v {
                Value::Bool(b) => cat.ordered = *b,
                _ => return Err("has an \"ordered\" that is not true or false".into()),
            },
            _ => {}
        }
    }
    if !has_levels {
        return Err("has no levels".into());
    }
    Ok(cat)
}

fn first_duplicate(items: &[String]) -> Option<&str> {
    let mut seen = std::collections::HashSet::with_capacity(items.len());
    items.iter().map(String::as_str).find(|s| !seen.insert(*s))
}

/// What identifies a label's code within its set: a number's bits (with
/// -0.0 as 0.0), or a missing code.
#[derive(Hash, PartialEq, Eq)]
enum CodeKey {
    Number(u64),
    Missing(u8),
}

fn code_key(l: &ValueLabel) -> std::result::Result<CodeKey, String> {
    if l.missing != 0 {
        return match missing::name(l.missing) {
            Some(_) => Ok(CodeKey::Missing(l.missing)),
            None => Err(format!(
                "missing code {} is not one of . and .a to .z",
                l.missing
            )),
        };
    }
    let v = l.value;
    if !v.is_finite() {
        return Err(format!("the code {v} is not a finite number"));
    }
    if v.fract() == 0.0 && v.abs() > MAX_EXACT {
        return Err(format!(
            "the code {v} is an integer beyond ±2^53, which JavaScript cannot hold exactly"
        ));
    }
    Ok(CodeKey::Number(if v == 0.0 { 0 } else { v.to_bits() }))
}

fn code_text(l: &ValueLabel) -> String {
    if l.missing != 0 {
        missing::name(l.missing).unwrap_or_default()
    } else {
        let mut s = String::new();
        json::number(&mut s, l.value);
        s
    }
}

fn label_set(name: &str, v: &Value) -> std::result::Result<ValueLabelSet, String> {
    let Value::Array(pairs) = v else {
        return Err("is not an array of [code, text] pairs".into());
    };
    let mut labels = Vec::with_capacity(pairs.len());
    let mut seen = std::collections::HashSet::with_capacity(pairs.len());
    for pair in pairs {
        let (code, text) = match pair {
            Value::Array(p) if p.len() == 2 => (&p[0], &p[1]),
            _ => return Err("has an entry that is not a [code, text] pair".into()),
        };
        let Value::String(text) = text else {
            return Err("has a label that is not text".into());
        };
        let label = match code {
            Value::Number(v) => ValueLabel {
                value: *v,
                missing: 0,
                text: text.clone(),
            },
            Value::String(s) => match missing::from_name(s) {
                Some(m) => ValueLabel {
                    value: f64::NAN,
                    missing: m,
                    text: text.clone(),
                },
                None => return Err(format!("has the code \"{s}\", which is not . or .a to .z")),
            },
            other => return Err(format!("has a code that is {}", other.kind())),
        };
        let key = code_key(&label).map_err(|why| format!("has {why}"))?;
        if !seen.insert(key) {
            return Err(format!("labels {} more than once", code_text(&label)));
        }
        labels.push(label);
    }
    Ok(ValueLabelSet {
        name: name.to_string(),
        labels,
    })
}

fn string_array(o: &mut String, items: &[String]) {
    o.push('[');
    for (i, s) in items.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        json::string(o, s);
    }
    o.push(']');
}

#[cfg(test)]
mod tests {
    use super::*;

    fn full() -> Profile {
        Profile {
            version: 1,
            label: Some("Smoking survey, 2024".into()),
            notes: vec!["Wave 2 only.".into()],
            characteristics: vec![
                Characteristic {
                    variable: "_dta".into(),
                    name: "note0".into(),
                    value: "1".into(),
                },
                Characteristic {
                    variable: "age".into(),
                    name: "source".into(),
                    value: "q12".into(),
                },
            ],
            sort: vec!["id".into()],
            columns: vec![
                ColumnProfile {
                    name: "age".into(),
                    label: Some("Age in years".into()),
                    format: Some("%9.0g".into()),
                    value_labels: Some("agelbl".into()),
                    missing_letters: Some("age__missing".into()),
                    ..Default::default()
                },
                ColumnProfile {
                    name: "region".into(),
                    categorical: Some(Categorical {
                        levels: vec!["North".into(), "South".into(), "West".into()],
                        ordered: false,
                    }),
                    ..Default::default()
                },
                ColumnProfile {
                    name: "seen".into(),
                    format: Some("%tdCCYY-NN-DD".into()),
                    ..Default::default()
                },
                ColumnProfile {
                    name: "when".into(),
                    tz: Some("America/New_York".into()),
                    ..Default::default()
                },
                ColumnProfile {
                    name: "stamp".into(),
                    unit: Some("s".into()),
                    ..Default::default()
                },
            ],
            value_labels: vec![ValueLabelSet {
                name: "agelbl".into(),
                labels: vec![
                    ValueLabel {
                        value: 97.0,
                        missing: 0,
                        text: "Refused".into(),
                    },
                    ValueLabel {
                        value: f64::NAN,
                        missing: 5,
                        text: "Don't know".into(),
                    },
                    ValueLabel {
                        value: -1.5,
                        missing: 0,
                        text: "half".into(),
                    },
                ],
            }],
        }
    }

    /// Compare profiles, treating NaN values of missing-code labels as equal.
    fn same(a: &Profile, b: &Profile) {
        let strip = |p: &Profile| {
            let mut p = p.clone();
            for s in &mut p.value_labels {
                for l in &mut s.labels {
                    if l.missing != 0 {
                        l.value = 0.0;
                    }
                }
            }
            p
        };
        assert_eq!(strip(a), strip(b));
    }

    #[test]
    fn the_plans_example_round_trips() {
        let p = full();
        let text = p.to_json().unwrap();
        let (back, warnings) = Profile::parse(text.as_bytes());
        assert!(warnings.is_empty(), "{warnings:?}");
        same(&back.unwrap(), &p);
        assert!(
            text.contains(r#""agelbl":[[97,"Refused"],[".d","Don't know"],[-1.5,"half"]]"#),
            "{text}"
        );
    }

    #[test]
    fn not_json_too_large_or_not_an_object_is_one_warning() {
        for bad in [&b"{"[..], b"[1, 2]", b"\"text\"", b"\xff"] {
            let (p, w) = Profile::parse(bad);
            assert!(p.is_none());
            assert_eq!(w.len(), 1, "{w:?}");
            assert!(w[0].contains("plain Parquet"));
        }
        let big = vec![b' '; MAX_BYTES + 1];
        let (p, w) = Profile::parse(&big);
        assert!(p.is_none() && w.len() == 1 && w[0].contains("more than"));
    }

    #[test]
    fn a_higher_version_warns_once_and_reads() {
        let (p, w) = Profile::parse(br#"{"version": 7, "label": "x", "future": {"a": 1}}"#);
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("version 7"));
        let p = p.unwrap();
        assert_eq!(p.version, 7);
        assert_eq!(p.label.as_deref(), Some("x"));
        let (_, w) = Profile::parse(br#"{"label": "x"}"#);
        assert!(w[0].contains("no \"version\""));
        let (_, w) = Profile::parse(br#"{"version": "1"}"#);
        assert!(w[0].contains("\"version\""));
    }

    #[test]
    fn duplicate_keys_drop_the_entry_at_every_level() {
        let (p, w) =
            Profile::parse(br#"{"version": 1, "label": "a", "label": "b", "notes": ["n"]}"#);
        let p = p.unwrap();
        assert_eq!(p.label, None);
        assert_eq!(p.notes, vec!["n".to_string()]);
        assert_eq!(w, vec![dropped("label", "appears more than once")]);

        let (p, w) = Profile::parse(br#"{"version": 1, "columns": {"x": {"label": "a"}, "x": {"label": "b"}, "y": {"label": "c", "label": "d", "format": "%9.0g"}}}"#);
        let p = p.unwrap();
        assert_eq!(p.columns.len(), 1);
        assert_eq!(p.columns[0].name, "y");
        assert_eq!(p.columns[0].label, None);
        assert_eq!(p.columns[0].format.as_deref(), Some("%9.0g"));
        assert_eq!(w.len(), 2, "{w:?}");

        let (p, w) = Profile::parse(br#"{"version": 1, "characteristics": {"_dta": {"a": "1", "a": "2"}, "x": {"b": "3"}}}"#);
        assert_eq!(p.unwrap().characteristics.len(), 1);
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("characteristics._dta"));

        let (p, w) = Profile::parse(br#"{"version": 1, "columns": {"r": {"categorical": {"levels": ["a"], "levels": ["b"]}}}}"#);
        assert!(p.unwrap().columns.is_empty());
        assert!(w[0].contains("columns.r.categorical"));
    }

    #[test]
    fn malformed_entries_are_dropped_with_one_warning_each() {
        let text = br#"{
            "version": 1,
            "label": 3,
            "notes": ["a", 1],
            "sort": "id",
            "characteristics": {"_dta": {"note0": 1}},
            "columns": {
                "a": {"label": "ok", "format": 9, "value_labels": "nosuch"},
                "b": [],
                "c": {"categorical": {"levels": ["x", "x"]}},
                "d": {"categorical": {"levels": ["x"], "ordered": "yes"}},
                "e": {"categorical": {"ordered": true}},
                "f": {"value_labels": "good", "tz": "UTC"}
            },
            "value_labels": {
                "notpairs": {"1": "a"},
                "dupcode": [[1, "a"], [1.0, "b"]],
                "dupmissing": [[".a", "a"], [".a", "b"]],
                "badcode": [[".A", "a"]],
                "big": [[9007199254740994, "a"]],
                "triple": [[1, "a", "b"]],
                "nottext": [[1, 2]],
                "nullcode": [[null, "a"]],
                "good": [[0, "no"], [-0.0, "zero again"]]
            }
        }"#;
        let (p, w) = Profile::parse(text);
        let p = p.unwrap();
        let expected = [
            "\"label\"",
            "\"notes\"",
            "\"sort\"",
            "\"characteristics._dta\"",
            "\"columns.a.format\"",
            "\"columns.b\"",
            "\"columns.c.categorical\"",
            "\"columns.d.categorical\"",
            "\"columns.e.categorical\"",
            "\"value_labels.notpairs\"",
            "\"value_labels.dupcode\"",
            "\"value_labels.dupmissing\"",
            "\"value_labels.badcode\"",
            "\"value_labels.big\"",
            "\"value_labels.triple\"",
            "\"value_labels.nottext\"",
            "\"value_labels.nullcode\"",
            "\"value_labels.good\"",
            "\"columns.a.value_labels\"",
            "\"columns.f.value_labels\"",
        ];
        assert_eq!(w.len(), expected.len(), "{w:#?}");
        for (got, want) in w.iter().zip(expected) {
            assert!(got.contains(want), "{got} should name {want}");
        }
        // -0.0 and 0 are the same code, so "good" is dropped too, and
        // column f's reference to it with it.
        assert!(p.value_labels.is_empty());
        let a = p.column("a").unwrap();
        assert_eq!(a.label.as_deref(), Some("ok"));
        assert_eq!(a.value_labels, None);
        let f = p.column("f").unwrap();
        assert_eq!(f.tz.as_deref(), Some("UTC"));
        assert_eq!(f.value_labels, None);
        assert!(p.column("c").is_none());
    }

    #[test]
    fn writing_refuses_what_json_cannot_hold() {
        let mut p = full();
        p.value_labels[0].labels.push(ValueLabel {
            value: f64::INFINITY,
            missing: 0,
            text: "inf".into(),
        });
        assert!(p
            .to_json()
            .unwrap_err()
            .message
            .contains("not a finite number"));
        let mut p = full();
        p.value_labels[0].labels.push(ValueLabel {
            value: 2f64.powi(53) + 2.0,
            missing: 0,
            text: "big".into(),
        });
        assert!(p.to_json().unwrap_err().message.contains("2^53"));
        let mut p = full();
        p.value_labels[0].labels.push(ValueLabel {
            value: 2f64.powi(53),
            missing: 0,
            text: "edge".into(),
        });
        p.to_json().unwrap();
        let mut p = full();
        p.value_labels[0].labels.push(ValueLabel {
            value: 97.0,
            missing: 0,
            text: "again".into(),
        });
        assert!(p.to_json().unwrap_err().message.contains("labels 97 twice"));
        let mut p = full();
        p.columns[1]
            .categorical
            .as_mut()
            .unwrap()
            .levels
            .push("North".into());
        assert!(p
            .to_json()
            .unwrap_err()
            .message
            .contains("level \"North\" twice"));
        let mut p = full();
        p.characteristics.push(p.characteristics[0].clone());
        assert!(p.to_json().unwrap_err().message.contains("given twice"));
    }

    #[test]
    fn text_is_escaped() {
        let p = Profile {
            label: Some("quote \" and \\ and\nnewline é".into()),
            ..Default::default()
        };
        let (back, w) = Profile::parse(p.to_json().unwrap().as_bytes());
        assert!(w.is_empty());
        assert_eq!(back.unwrap().label, p.label);
    }
}
