//! Categoricals that hold `.a` to `.z` (plan 0022): written as DOUBLE
//! level numbers with `logical` categorical and a recorded value-label
//! set; damaged entries; set names in every read mode.

mod support;

use dta::{ValueLabel, ValueLabelSet};
use dta_parquet::format::{FileMetaData, KeyValue};
use dta_parquet::{
    level_index, write, write_with_letters, ColumnProfile, ColumnType, Logical, Profile, ReadOptions, Reader, Storage, WriteOptions,
};
use support::{read, table, Col, Data, Got};

fn grade(codes: Vec<i32>) -> Col {
    Col { name: "grade".into(), data: Data::Cat { levels: vec!["low".into(), "mid".into(), "high".into()], ordered: true, codes }, codes: vec![] }
}

/// low, .a, high, ., .z, mid
fn lettered() -> Col {
    grade(vec![0, -2, 2, -1, -27, 1])
}

fn bytes_of(cols: &[Col], profile: Profile, options: &WriteOptions) -> Vec<u8> {
    let mut out = Vec::new();
    write(&table(cols, profile), &mut out, options).unwrap();
    out
}

fn serial() -> ReadOptions {
    ReadOptions { threads: 1, ..Default::default() }
}

fn open(bytes: &[u8]) -> Reader<dta::Bytes<&[u8]>> {
    Reader::open(dta::Bytes(bytes), serial()).unwrap()
}

fn levels_set(name: &str) -> ValueLabelSet {
    dta_parquet::profile::levels_set(name, &["low".into(), "mid".into(), "high".into()])
}

fn set(name: &str, labels: &[(f64, u8, &str)]) -> ValueLabelSet {
    ValueLabelSet { name: name.into(), labels: labels.iter().map(|&(value, missing, text)| ValueLabel { value, missing, text: text.into() }).collect() }
}

fn with_profile(bytes: &[u8], profile: &str) -> Vec<u8> {
    let len = bytes.len();
    let footer_len = u32::from_le_bytes(bytes[len - 8..len - 4].try_into().unwrap()) as usize;
    let start = len - 8 - footer_len;
    let mut meta = FileMetaData::parse(&bytes[start..len - 8], start as u64).unwrap();
    meta.key_value.retain(|kv| kv.key != "dta");
    meta.key_value.push(KeyValue { key: "dta".into(), value: Some(profile.as_bytes().to_vec()) });
    let footer = meta.to_bytes();
    let mut out = bytes[..start].to_vec();
    out.extend_from_slice(&footer);
    out.extend_from_slice(&(footer.len() as u32).to_le_bytes());
    out.extend_from_slice(b"PAR1");
    out
}

#[test]
fn a_categorical_with_letters_is_double_level_numbers_with_its_set() {
    let bytes = bytes_of(&[lettered()], Profile::default(), &WriteOptions::default());
    let r = open(&bytes);
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    let c = &r.columns()[0];
    assert_eq!((c.kind.clone(), c.profile_logical, c.storage, c.levels), (ColumnType::Double, Some(Logical::Categorical), None, None));
    let entry = r.profile().unwrap().column("grade").unwrap();
    assert_eq!(entry.categorical.as_ref().unwrap().levels, ["low", "mid", "high"]);
    assert!(entry.categorical.as_ref().unwrap().ordered);
    assert_eq!(entry.value_labels.as_deref(), Some("grade"));
    assert_eq!(entry.storage, None);
    assert_eq!(r.profile().unwrap().value_label_set("grade"), Some(&levels_set("grade")));
    assert_eq!(r.categorical_labels(0), Some((levels_set("grade"), None)));
    let (got, letters) = read(&bytes, &["grade"], 0, 6, serial());
    assert_eq!(letters, [true]);
    assert_eq!(got[0], Got::Floats(vec![1.0, -1e300, 3.0, -1e300, -1e300, 2.0], vec![0, 2, 0, 1, 27, 0]));
}

#[test]
fn without_letters_a_categorical_is_text_with_no_set() {
    let bytes = bytes_of(&[grade(vec![0, -1, 2, 1])], Profile::default(), &WriteOptions::default());
    let r = open(&bytes);
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    assert_eq!(r.columns()[0].kind, ColumnType::Text);
    assert_eq!(r.columns()[0].profile_logical, None);
    let entry = r.profile().unwrap().column("grade").unwrap();
    assert_eq!((entry.value_labels.clone(), entry.logical), (None, None));
    assert!(r.profile().unwrap().value_labels.is_empty());
    assert_eq!(r.categorical_labels(0), None);
    let (got, _) = read(&bytes, &["grade"], 0, 4, serial());
    assert_eq!(got[0], Got::Levels(vec![0, -1, 2, 1]));
}

#[test]
fn letters_off_or_a_false_hint_write_text_with_nulls() {
    let off = WriteOptions { missing_letters: false, ..Default::default() };
    let a = bytes_of(&[lettered()], Profile::default(), &off);
    let mut b = Vec::new();
    write_with_letters(&table(&[lettered()], Profile::default()), &mut b, &WriteOptions::default(), &[Some(false)]).unwrap();
    for bytes in [a, b] {
        let r = open(&bytes);
        assert_eq!(r.columns()[0].kind, ColumnType::Text);
        assert!(r.profile().unwrap().value_labels.is_empty());
        let (got, _) = read(&bytes, &["grade"], 0, 6, serial());
        assert_eq!(got[0], Got::Levels(vec![0, -1, 2, -1, -1, 1]));
    }
    // A true hint gives the file the scan gives.
    let mut c = Vec::new();
    write_with_letters(&table(&[lettered()], Profile::default()), &mut c, &WriteOptions::default(), &[Some(true)]).unwrap();
    assert_eq!(c, bytes_of(&[lettered()], Profile::default(), &WriteOptions::default()));
}

#[test]
fn other_negative_codes_are_dots_and_a_code_past_the_levels_is_an_error() {
    let bytes = bytes_of(&[grade(vec![-28, -2, -100, 0])], Profile::default(), &WriteOptions::default());
    let (got, _) = read(&bytes, &["grade"], 0, 4, serial());
    assert_eq!(got[0], Got::Floats(vec![-1e300, -1e300, -1e300, 1.0], vec![1, 2, 1, 0]));
    let e = write(&table(&[grade(vec![0, -2, 3])], Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
    assert!(e.message.contains("\"grade\"") && e.message.contains("row 3") && e.message.contains("3 levels"), "{}", e.message);
}

#[test]
fn level_index_takes_only_whole_numbers_from_one_to_the_levels() {
    assert_eq!(level_index(1.0, 3), Some(0));
    assert_eq!(level_index(3.0, 3), Some(2));
    for bad in [1.5, 0.0, 4.0, -1.0, f64::NAN, f64::INFINITY] {
        assert_eq!(level_index(bad, 3), None, "{bad}");
    }
    assert_eq!(level_index(1.0, 0), None);
}

#[test]
fn a_supplied_logical_or_categorical_follows_the_values() {
    let cols = [
        Col { name: "x".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 2] },
        Col { name: "n".into(), data: Data::I32(vec![1, 2]), codes: vec![0, 0] },
        Col { name: "d".into(), data: Data::F64(vec![1.5, 2.0]), codes: vec![0, 0] },
    ];
    let mut profile = Profile::default();
    profile.column_mut("x").logical = Some(Logical::Categorical);
    profile.column_mut("x").categorical = Some(dta_parquet::Categorical { levels: vec!["a".into(), "b".into()], ordered: false });
    profile.column_mut("n").categorical = Some(dta_parquet::Categorical { levels: vec!["a".into()], ordered: false });
    profile.column_mut("d").logical = Some(Logical::Date);
    let bytes = bytes_of(&cols, profile, &WriteOptions::default());
    let r = open(&bytes);
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    let p = r.profile().unwrap();
    assert!(p.column("x").is_none_or(|c| c.logical.is_none() && c.categorical.is_none()));
    assert!(p.column("n").is_none_or(|c| c.categorical.is_none()));
    assert_eq!(p.column("d").unwrap().logical, Some(Logical::Date));
}

#[test]
fn the_set_recorded_is_the_callers_if_it_fits_else_the_first_free_or_fitting_name() {
    let write_with = |sets: Vec<ValueLabelSet>, named: Option<&str>, other_uses: Option<&str>| {
        let mut profile = Profile { value_labels: sets, ..Default::default() };
        if let Some(n) = named {
            profile.column_mut("grade").value_labels = Some(n.into());
        }
        let mut cols = vec![lettered()];
        if let Some(o) = other_uses {
            cols.push(Col { name: "other".into(), data: Data::F64(vec![1.0; 6]), codes: vec![0; 6] });
            profile.column_mut("other").value_labels = Some(o.into());
        }
        let bytes = bytes_of(&cols, profile, &WriteOptions::default());
        let r = open(&bytes);
        assert!(r.warnings().is_empty(), "{:?}", r.warnings());
        let p = r.profile().unwrap().clone();
        let got = r.categorical_labels(0).unwrap();
        assert_eq!(got.1, None);
        (p, got.0)
    };
    // The caller's set fits, with a label on .r: recorded as it is.
    let mine = set("g", &[(1.0, 0, "low"), (2.0, 0, "mid"), (3.0, 0, "high"), (f64::NAN, 19, "Refused")]);
    let (p, s) = write_with(vec![mine.clone()], Some("g"), None);
    assert_eq!(p.column("grade").unwrap().value_labels.as_deref(), Some("g"));
    assert_eq!((s.name.as_str(), s.labels.len(), s.labels[3].missing), ("g", 4, 19));
    assert_eq!(p.value_labels.len(), 1);
    // The caller's set does not fit (codes 1, 2, 5): kept, and the column
    // gets its own name.
    let codes = set("g", &[(1.0, 0, "low"), (2.0, 0, "mid"), (5.0, 0, "high")]);
    let (p, s) = write_with(vec![codes.clone()], Some("g"), None);
    assert_eq!(s, levels_set("grade"));
    assert_eq!(p.value_label_set("g"), Some(&codes));
    // A set named after the column that another column uses and that
    // does not fit is left as it is; the column records grade_2.
    let theirs = set("grade", &[(1.0, 0, "yes")]);
    let (p, s) = write_with(vec![theirs.clone()], None, Some("grade"));
    assert_eq!(s, levels_set("grade_2"));
    assert_eq!(p.value_label_set("grade"), Some(&theirs));
    assert_eq!(p.column("other").unwrap().value_labels.as_deref(), Some("grade"));
    // grade_2 taken too: grade_3.
    let (_, s) = write_with(vec![theirs.clone(), set("grade_2", &[(1.0, 0, "no")])], None, Some("grade"));
    assert_eq!(s.name, "grade_3");
    // One that fits is reused, not doubled.
    let (p, s) = write_with(vec![theirs.clone(), levels_set("grade_2")], None, Some("grade"));
    assert_eq!(s, levels_set("grade_2"));
    assert_eq!(p.value_labels.len(), 2);
}

#[test]
fn writing_back_what_was_read_names_the_same_set() {
    let theirs = set("grade", &[(1.0, 0, "yes")]);
    let mut profile = Profile { value_labels: vec![theirs], ..Default::default() };
    profile.column_mut("other").value_labels = Some("grade".into());
    let cols = vec![lettered(), Col { name: "other".into(), data: Data::F64(vec![1.0; 6]), codes: vec![0; 6] }];
    let mut bytes = bytes_of(&cols, profile, &WriteOptions::default());
    for _ in 0..2 {
        let r = open(&bytes);
        let p = r.profile().unwrap().clone();
        assert_eq!(p.column("grade").unwrap().value_labels.as_deref(), Some("grade_2"));
        let again = bytes_of(&cols, p.clone(), &WriteOptions::default());
        assert_eq!(open(&again).profile().unwrap(), &p);
        bytes = again;
    }
}

/// The lettered file with `profile` for its dta profile, and a column
/// `other` (DOUBLE) beside it.
fn hand_made(profile: &str) -> Vec<u8> {
    let cols = [lettered(), Col { name: "other".into(), data: Data::F64(vec![1.0; 6]), codes: vec![0; 6] }];
    with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions::default()), profile)
}

const LEVELS: &str = r#""categorical": {"levels": ["low", "mid", "high"], "ordered": true}"#;

#[test]
fn every_damaged_entry_gives_one_warning_and_its_type() {
    let cases: [(&str, &str, Option<Logical>, Option<Storage>); 4] = [
        // logical categorical with no valid categorical
        (r#"{"version": 1, "columns": {"grade": {"logical": "categorical"}}}"#, "columns.grade.logical", None, None),
        (r#"{"version": 1, "columns": {"grade": {"logical": "categorical", "categorical": {"levels": ["a", "a"]}}}}"#, "columns.grade.categorical", None, None),
        // categorical without logical: the doubles, levels ignored
        (&format!(r#"{{"version": 1, "columns": {{"grade": {{{LEVELS}}}}}}}"#), "not text", None, None),
        // logical and storage both
        (&format!(r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", "storage": "long", {LEVELS}}}}}}}"#), "storage type", None, Some(Storage::Long)),
    ]
    .map(|(p, w, l, s)| (Box::leak(p.to_string().into_boxed_str()) as &str, w, l, s));
    for (profile, warning, logical, storage) in cases {
        let bytes = hand_made(profile);
        let r = open(&bytes);
        let w = r.warnings();
        assert_eq!(w.len(), 1, "{profile}: {w:?}");
        assert!(w.iter().any(|w| w.contains(warning)), "{profile}: {w:?}");
        let c = &r.columns()[0];
        assert_eq!((c.kind.clone(), c.profile_logical, c.storage), (ColumnType::Double, logical, storage), "{profile}");
        assert_eq!(r.categorical_labels(0), None);
    }
    // logical categorical on a column that is not DOUBLE.
    let cols = [Col { name: "n".into(), data: Data::I32(vec![1, 2]), codes: vec![0, 0] }];
    let bytes = with_profile(
        &bytes_of(&cols, Profile::default(), &WriteOptions::default()),
        &format!(r#"{{"version": 1, "columns": {{"n": {{"logical": "categorical", {LEVELS}}}}}}}"#),
    );
    let r = open(&bytes);
    assert_eq!(r.warnings().len(), 1, "{:?}", r.warnings());
    assert!(r.warnings()[0].contains("columns.n.logical") && r.warnings()[0].contains("not DOUBLE"), "{:?}", r.warnings());
    assert_eq!((r.columns()[0].kind.clone(), r.columns()[0].profile_logical), (ColumnType::Int32, None));
}

#[test]
fn a_missing_or_unfitting_set_is_made_from_the_levels() {
    // No value_labels: no warning, a set named after the column.
    let r_bytes = hand_made(&format!(r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", {LEVELS}}}}}}}"#));
    let r = open(&r_bytes);
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    assert_eq!(r.categorical_labels(0), Some((levels_set("grade"), None)));
    // A set the profile lacks: the parser drops the name (one warning).
    let bytes = hand_made(&format!(r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", "value_labels": "nosuch", {LEVELS}}}}}}}"#));
    let r = open(&bytes);
    assert_eq!(r.warnings().len(), 1, "{:?}", r.warnings());
    assert_eq!(r.categorical_labels(0), Some((levels_set("grade"), None)));
    // One that does not fit: one warning, from categorical_labels.
    let bytes = hand_made(&format!(
        r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", "value_labels": "g", {LEVELS}}}}}, "value_labels": {{"g": [[1, "low"], [2, "high"]]}}}}"#
    ));
    let r = open(&bytes);
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    let (s, w) = r.categorical_labels(0).unwrap();
    assert_eq!(s, levels_set("grade"));
    assert!(w.unwrap().contains("\"g\""));
}

#[test]
fn every_set_name_is_known_when_only_some_columns_are_read() {
    // grade records no set; other, not selected, owns a set named grade
    // that does not fit, and grade_2 fits.
    let bytes = hand_made(&format!(
        r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", {LEVELS}}}, "other": {{"value_labels": "grade"}}}},
            "value_labels": {{"grade": [[1, "yes"]], "grade_2": [[1, "low"], [2, "mid"], [3, "high"], [".r", "Refused"]]}}}}"#
    ));
    for lazy in [false, true] {
        let options = ReadOptions { lazy_value_labels: lazy, ..serial() };
        for selected in [None, Some(&["grade"][..])] {
            let r = Reader::open_for(dta::Bytes(&bytes[..]), options, selected).unwrap();
            assert!(r.warnings().is_empty(), "{:?}", r.warnings());
            assert_eq!(r.all_value_label_set_names(), ["grade", "grade_2"]);
            let (s, w) = r.categorical_labels(0).unwrap();
            assert_eq!(w, None);
            assert_eq!((s.name.as_str(), s.labels.len()), ("grade_2", 4), "lazy {lazy}, selected {selected:?}");
        }
    }
    // Without grade_2, the made set is grade_2 in every mode.
    let bytes = hand_made(&format!(
        r#"{{"version": 1, "columns": {{"grade": {{"logical": "categorical", {LEVELS}}}, "other": {{"value_labels": "grade"}}}}, "value_labels": {{"grade": [[1, "yes"]]}}}}"#
    ));
    for lazy in [false, true] {
        let options = ReadOptions { lazy_value_labels: lazy, ..serial() };
        let r = Reader::open_for(dta::Bytes(&bytes[..]), options, Some(&["grade"])).unwrap();
        assert_eq!(r.categorical_labels(0), Some((levels_set("grade_2"), None)));
    }
}

#[test]
fn the_profile_entry_lists_the_three_logical_types() {
    let bytes = hand_made(r#"{"version": 1, "columns": {"grade": {"logical": "factor"}}}"#);
    let r = open(&bytes);
    assert!(r.warnings()[0].contains(r#""date", "timestamp" and "categorical""#), "{:?}", r.warnings());
    let _ = ColumnProfile::named("x");
}

#[test]
fn made_names_do_not_collide() {
    // Categoricals x and x_2 (other levels) record no set; a set x that
    // does not fit is taken. x skips x_2, a column's name, and makes x_3;
    // x_2 makes x_2: read whole or a column at a time.
    let cat = |name: &str, levels: &[&str]| Col {
        name: name.into(),
        data: Data::Cat { levels: levels.iter().map(|l| l.to_string()).collect(), ordered: false, codes: vec![0, -2] },
        codes: vec![],
    };
    let cols = [cat("x", &["a", "b"]), cat("x_2", &["c"])];
    let bytes = with_profile(
        &bytes_of(&cols, Profile::default(), &WriteOptions::default()),
        r#"{"version": 1, "columns": {"x": {"logical": "categorical", "categorical": {"levels": ["a", "b"]}}, "x_2": {"logical": "categorical", "categorical": {"levels": ["c"]}}}, "value_labels": {"x": [[1, "other"]]}}"#,
    );
    for lazy in [false, true] {
        let options = ReadOptions { lazy_value_labels: lazy, ..serial() };
        for selected in [None, Some(&["x"][..]), Some(&["x_2"][..])] {
            let r = Reader::open_for(dta::Bytes(&bytes[..]), options, selected).unwrap();
            assert!(r.warnings().is_empty(), "{:?}", r.warnings());
            let names: Vec<String> = (0..2).filter_map(|k| r.categorical_labels(k)).map(|(s, _)| s.name).collect();
            let want: &[&str] = match selected {
                None => &["x_3", "x_2"],
                Some(["x"]) => &["x_3"],
                _ => &["x_2"],
            };
            assert_eq!(names, want, "lazy {lazy}, selected {selected:?}");
        }
    }
    // The writer makes the same names.
    let profile = Profile { value_labels: vec![set("x", &[(1.0, 0, "other")])], ..Default::default() };
    let r_bytes = bytes_of(&cols, profile, &WriteOptions::default());
    let r = open(&r_bytes);
    let p = r.profile().unwrap();
    assert_eq!(p.column("x").unwrap().value_labels.as_deref(), Some("x_3"));
    assert_eq!(p.column("x_2").unwrap().value_labels.as_deref(), Some("x_2"));
}

#[test]
fn an_absent_or_malformed_categorical_beside_logical_warns_once() {
    for entry in [r#"{"logical": "categorical"}"#, r#"{"logical": "categorical", "categorical": 3}"#, r#"{"categorical": {"levels": ["a", "a"]}, "logical": "categorical"}"#] {
        let bytes = hand_made(&format!(r#"{{"version": 1, "columns": {{"grade": {entry}}}}}"#));
        let r = open(&bytes);
        assert_eq!(r.warnings().len(), 1, "{entry}: {:?}", r.warnings());
        assert_eq!(r.columns()[0].profile_logical, None);
    }
}
