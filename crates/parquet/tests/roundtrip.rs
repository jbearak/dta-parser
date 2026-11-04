//! Write tables with the crate's writer and read them back.

mod support;

use dta::{ValueLabel, ValueLabelSet};
use dta_parquet::format::{Codec, Encoding, FileMetaData, KeyValue};
use dta_parquet::{write, ColumnProfile, Compression, Numbers, Output, Profile, ReadOptions, Reader, Role, WriteOptions};
use support::{every_type, expected, read, same, table, Col, Data, Got};

fn bytes_of(cols: &[Col], profile: Profile, options: &WriteOptions) -> Vec<u8> {
    let mut out = Vec::new();
    write(&table(cols, profile), &mut out, options).unwrap();
    out
}

fn serial() -> ReadOptions {
    ReadOptions { threads: 1, ..Default::default() }
}

fn threaded() -> ReadOptions {
    ReadOptions { threads: 4, parallel_bytes: 0, ..Default::default() }
}

fn names(cols: &[Col]) -> Vec<&str> {
    cols.iter().map(|c| c.name.as_str()).collect()
}

/// Read every column of `bytes` over a window and compare with `cols`.
fn check(bytes: &[u8], cols: &[Col], skip: usize, n: usize, options: ReadOptions) {
    let rows = cols[0].rows();
    let end = (skip + n).min(rows);
    let start = skip.min(rows);
    let (got, _, warnings) = read(bytes, &names(cols), skip as u64, n as u64, options);
    assert!(warnings.is_empty(), "{warnings:?}");
    for (c, g) in cols.iter().zip(&got) {
        let want = expected(c, start..end);
        assert!(same(&want, g), "column {} rows {start}..{end}:\nwant {want:?}\n got {g:?}", c.name);
    }
}

fn labelled_profile() -> Profile {
    Profile {
        label: Some("Every type".into()),
        notes: vec!["First note.".into()],
        columns: vec![ColumnProfile {
            name: "i8".into(),
            label: Some("Small numbers".into()),
            format: Some("%8.0g".into()),
            value_labels: Some("small".into()),
            ..Default::default()
        }],
        value_labels: vec![ValueLabelSet {
            name: "small".into(),
            labels: vec![
                ValueLabel { value: -100.0, missing: 0, text: "lowest".into() },
                ValueLabel { value: f64::NAN, missing: 2, text: "refused".into() },
            ],
        }],
        ..Default::default()
    }
}

#[test]
fn every_type_round_trips_with_nulls_letters_and_categoricals() {
    let cols = every_type(1000);
    let bytes = bytes_of(&cols, labelled_profile(), &WriteOptions::default());
    check(&bytes, &cols, 0, usize::MAX, serial());
    check(&bytes, &cols, 0, usize::MAX, threaded());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    let p = r.profile().unwrap();
    assert_eq!(p.label.as_deref(), Some("Every type"));
    assert_eq!(p.notes, vec!["First note.".to_string()]);
    let i8p = p.column("i8").unwrap();
    assert_eq!(i8p.label.as_deref(), Some("Small numbers"));
    assert_eq!(i8p.missing_letters.as_deref(), Some("i8__missing"));
    assert_eq!(p.value_labels[0].labels[1].missing, 2);
    assert_eq!(p.column("region").unwrap().categorical.as_ref().unwrap().levels.len(), 4);
    assert!(p.column("size").unwrap().categorical.as_ref().unwrap().ordered);
    assert_eq!(p.column("when_ny").unwrap().tz.as_deref(), Some("America/New_York"));
    assert_eq!(p.column("when_utc").unwrap().tz.as_deref(), Some(""));
    assert!(p.column("local").is_none_or(|c| c.tz.is_none()));
    // Letter columns come after the data columns and are not data.
    let roles: Vec<(&str, Role)> = r.columns().iter().map(|c| (c.name.as_str(), c.role)).collect();
    let letter_cols: Vec<&str> = roles.iter().filter(|(_, r)| *r == Role::MissingLetters).map(|(n, _)| *n).collect();
    assert_eq!(letter_cols, vec!["i8__missing", "i16__missing", "f64__missing"]);
    assert_eq!(&roles[roles.len() - 3..].iter().map(|(n, _)| *n).collect::<Vec<_>>(), &letter_cols);
    assert_eq!(r.data_columns().unwrap().len(), cols.len());
    assert_eq!(r.created_by(), Some(dta_parquet::CREATED_BY));
    assert!(r.key_value("ARROW:schema").is_some());
}

#[test]
fn the_letters_read_as_codes_and_flags() {
    let cols = every_type(100);
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let (got, letters, _) = read(&bytes, &["i8", "i32", "f64"], 0, 100, serial());
    assert_eq!(letters, vec![true, false, true]);
    let Got::Ints(_, codes) = &got[0] else { panic!() };
    assert_eq!(codes[3], 1);
    assert_eq!(codes[4], 2);
    assert_eq!(codes[14], 2);
    // Missing letters off: .a to .z are plain nulls, with no letter columns.
    let off = WriteOptions { missing_letters: false, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &off);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert!(r.columns().iter().all(|c| c.role == Role::Data));
    let (got, letters, _) = read(&bytes, &["i8"], 0, 100, serial());
    assert_eq!(letters, vec![false]);
    let Got::Ints(_, codes) = &got[0] else { panic!() };
    assert_eq!(codes[4], 1);
}

#[test]
fn letters_can_go_into_the_values_themselves() {
    // As R keeps .a to .z in a double's NaN payload.
    let cols = every_type(50);
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let k = r.column_index("f64").unwrap();
    let mut values = vec![0.0; 50];
    let mut outputs = [Output::Float64(Numbers::new(&mut values, f64::NAN).with_missing(|code| -f64::from(code)))];
    let report = r.read(&[k], 0, 50, &mut outputs, |_, _| Ok(())).unwrap();
    assert_eq!(report.letters, vec![true]);
    assert_eq!(values[3], -1.0); // .
    assert_eq!(values[6], -3.0); // .b
    assert_eq!(values[2], 2.0 / 3.0);
}

#[test]
fn empty_and_one_row_tables() {
    for n in [0, 1] {
        let cols = every_type(n);
        let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
        let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        assert_eq!(r.rows(), n as u64);
        assert_eq!(r.row_groups().len(), n);
        check(&bytes, &cols, 0, 10, serial());
        check(&bytes, &cols, 5, 10, serial());
    }
    // No columns at all.
    let mut out = Vec::new();
    write(&dta_parquet::Table { rows: 0, columns: vec![], profile: Profile::default() }, &mut out, &WriteOptions::default()).unwrap();
    let r = Reader::open(dta::Bytes(&out[..]), serial()).unwrap();
    assert!(r.columns().is_empty());
}

#[test]
fn row_windows_across_pages_and_row_groups() {
    let cols = every_type(3000);
    // Small pages and row groups, so windows cross both.
    for offset_index in [true, false] {
        let opts = WriteOptions { row_group_rows: Some(700), page_bytes: 300, offset_index, ..Default::default() };
        let bytes = bytes_of(&cols, Profile::default(), &opts);
        let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        assert_eq!(r.row_groups().len(), 5);
        let meta: &FileMetaData = r.metadata();
        assert_eq!(meta.row_groups[0].columns[0].offset_index.is_some(), offset_index);
        for (skip, n) in [(0, 3000), (0, 1), (699, 2), (700, 700), (1, 2998), (1234, 567), (2999, 5), (3000, 5), (5000, 1), (650, 1500)] {
            check(&bytes, &cols, skip, n, serial());
            check(&bytes, &cols, skip, n, threaded());
        }
    }
}

#[test]
fn window_reads_fetch_only_the_pages_they_need() {
    let n = 1_000_000;
    let cols = vec![Col { name: "x".into(), data: Data::F64((0..n).map(|r| r as f64 * 1.000001).collect()), codes: vec![0; n] }];
    let opts = WriteOptions { compression: Compression::None, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &opts);
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let k = r.column_index("x").unwrap();
    let whole: u64 = r.plan(&[k], 0, n as u64).unwrap().iter().map(|r| r.end - r.start).sum();
    let window: u64 = r.plan(&[k], 500_000, 1000).unwrap().iter().map(|r| r.end - r.start).sum();
    assert!(whole > 8_000_000, "{whole}");
    // One or two pages of about 1 MiB.
    assert!(window <= 2 * 1_100_000, "{window} of {whole}");
    check(&bytes, &cols, 500_000, 1000, serial());
    // Without an offset index the reader walks the page headers and
    // still decodes the window.
    let opts = WriteOptions { offset_index: false, ..opts };
    let bytes = bytes_of(&cols, Profile::default(), &opts);
    check(&bytes, &cols, 500_000, 1000, serial());
}

#[test]
fn every_codec_round_trips() {
    let cols = every_type(500);
    for c in [Compression::None, Compression::Snappy, Compression::Gzip, Compression::Zstd, Compression::Lz4Raw] {
        let opts = WriteOptions { compression: c, ..Default::default() };
        let bytes = bytes_of(&cols, Profile::default(), &opts);
        let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        let expected = match c {
            Compression::None => Codec::Uncompressed,
            Compression::Snappy => Codec::Snappy,
            Compression::Gzip => Codec::Gzip,
            Compression::Zstd => Codec::Zstd,
            Compression::Lz4Raw => Codec::Lz4Raw,
        };
        assert_eq!(r.codecs(), vec![expected]);
        check(&bytes, &cols, 0, 500, serial());
    }
    let opts = WriteOptions { compression: Compression::Zstd, compression_level: Some(19), ..Default::default() };
    check(&bytes_of(&cols, Profile::default(), &opts), &cols, 0, 500, serial());
}

#[test]
fn many_row_groups_with_threads() {
    let cols = every_type(20_000);
    let opts = WriteOptions { row_group_rows: Some(1000), threads: 4, parallel_bytes: 0, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &opts);
    // The same bytes with one thread.
    let one = bytes_of(&cols, Profile::default(), &WriteOptions { threads: 1, ..opts });
    assert_eq!(bytes, one);
    check(&bytes, &cols, 0, 20_000, threaded());
    check(&bytes, &cols, 4321, 9000, threaded());
}

#[test]
fn a_wide_table_with_large_label_sets() {
    let n = 20;
    let cols: Vec<Col> = (0..5000)
        .map(|k| Col { name: format!("v{k}"), data: Data::I32((0..n).map(|r| (r * k) as i32).collect()), codes: vec![0; n] })
        .collect();
    let sets: Vec<ValueLabelSet> = (0..50)
        .map(|s| ValueLabelSet {
            name: format!("set{s}"),
            labels: (0..1000).map(|v| ValueLabel { value: f64::from(v), missing: 0, text: format!("label {v} of set {s}") }).collect(),
        })
        .collect();
    let profile = Profile {
        columns: (0..5000)
            .map(|k| ColumnProfile { name: format!("v{k}"), label: Some(format!("Variable {k}")), value_labels: Some(format!("set{}", k % 50)), ..Default::default() })
            .collect(),
        value_labels: sets,
        ..Default::default()
    };
    let bytes = bytes_of(&cols, profile, &WriteOptions::default());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert_eq!(r.columns().len(), 5000);
    assert_eq!(r.profile().unwrap().value_labels.len(), 50);
    assert_eq!(r.profile().unwrap().column("v4999").unwrap().value_labels.as_deref(), Some("set49"));
    let pick = [&cols[0], &cols[2500], &cols[4999]].map(Clone::clone);
    check(&bytes, &pick, 0, n, serial());
}

#[test]
fn dictionary_and_plain_fallback() {
    let n = 100_000;
    let cols = vec![
        // Few distinct values: dictionary.
        Col { name: "few".into(), data: Data::F64((0..n).map(|r| (r % 7) as f64).collect()), codes: vec![0; n] },
        // All distinct: the first page fails the 60% rule, so PLAIN.
        Col { name: "distinct".into(), data: Data::F64((0..n).map(|r| r as f64 + 0.5).collect()), codes: vec![0; n] },
        // Few at first, then distinct: the dictionary passes on the first
        // page, fills up later, and the rest of the chunk is PLAIN.
        Col {
            name: "text".into(),
            data: Data::Text((0..n).map(|r| Some(if r < 20_000 { format!("{}", r % 10) } else { format!("value number {r}") })).collect()),
            codes: vec![],
        },
        // Distinct from the start: the dictionary passes the size limit
        // within the first page, so PLAIN from the start.
        Col { name: "long".into(), data: Data::Text((0..n).map(|r| Some(format!("a longer distinct value {r}"))).collect()), codes: vec![] },
    ];
    let opts = WriteOptions { row_group_rows: Some(n), page_bytes: 4096, dictionary_bytes: 64 << 10, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &opts);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let meta = |k: usize| r.metadata().row_groups[0].columns[k].meta.clone().unwrap();
    assert!(meta(0).dictionary_page_offset.is_some());
    assert!(!meta(1).encodings.contains(&Encoding::RleDictionary));
    assert!(meta(1).dictionary_page_offset.is_none());
    let text = meta(2);
    assert!(text.encodings.contains(&Encoding::RleDictionary) && text.dictionary_page_offset.is_some(), "{:?}", text.encodings);
    assert!(meta(3).dictionary_page_offset.is_none());
    check(&bytes, &cols, 0, n, serial());
    check(&bytes, &cols, 50_000, 1000, serial());
    check(&bytes, &cols, 0, n, threaded());
}

#[test]
fn statistics_are_written() {
    let cols = every_type(100);
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let stats = |name: &str| {
        let k = r.column_index(name).unwrap();
        r.metadata().row_groups[0].columns[r.columns()[k].leaf()].meta.as_ref().unwrap().statistics.clone().unwrap()
    };
    let i32s = stats("i32");
    let values: Vec<i32> = match &cols[2].data {
        Data::I32(v) => v.iter().zip(&cols[2].codes).filter(|(_, &c)| c == 0).map(|(&v, _)| v).collect(),
        _ => unreachable!(),
    };
    assert_eq!(i32s.min_value, Some(values.iter().min().unwrap().to_le_bytes().to_vec()));
    assert_eq!(i32s.max_value, Some(values.iter().max().unwrap().to_le_bytes().to_vec()));
    assert_eq!(i32s.null_count, Some(cols[2].codes.iter().filter(|&&c| c != 0).count() as i64));
    // f64 has -0.0 at row 1 and 0 nowhere else; the minimum is -0.0.
    assert_eq!(stats("f64").min_value, Some((-0.0f64).to_le_bytes().to_vec()));
    // f32 has NaN at row 7, left out.
    let f = stats("f32");
    assert_eq!(f.min_value, Some((-100.0f32).to_le_bytes().to_vec()));
    let name = stats("name");
    assert_eq!(name.min_value.as_deref(), Some("name 0 é".as_bytes()));
    assert_eq!(name.max_value.as_deref(), Some("name 9 é".as_bytes()));
    let region = stats("region");
    assert_eq!(region.min_value.as_deref(), Some(&b"North"[..]));
    assert_eq!(region.max_value.as_deref(), Some(&b"West"[..]));
    assert_eq!(stats("flag").max_value, Some(vec![1]));
    // Long text gets no minimum or maximum.
    let long = vec![Col { name: "t".into(), data: Data::Text(vec![Some("x".repeat(65)), Some("a".into())]), codes: vec![] }];
    let bytes = bytes_of(&long, Profile::default(), &WriteOptions::default());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let s = r.metadata().row_groups[0].columns[0].meta.as_ref().unwrap().statistics.clone().unwrap();
    assert_eq!((s.min_value, s.max_value, s.null_count), (None, None, Some(0)));
    assert!(r.metadata().column_orders.is_some());
}

/// Replace the profile in a file's footer.
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
fn letter_columns_are_checked() {
    let n = 10;
    let x = Col { name: "x".into(), data: Data::F64((0..n).map(|r| r as f64).collect()), codes: (0..n).map(|r| u8::from(r % 2 == 1)).collect() };
    let letters = |v: Vec<Option<&str>>| Col { name: "lx".into(), data: Data::Text(v.into_iter().map(|s| s.map(String::from)).collect()), codes: vec![] };
    let profile = r#"{"version": 1, "columns": {"x": {"missing_letters": "lx"}}}"#;
    let read_x = |cols: &[Col]| {
        let bytes = with_profile(&bytes_of(cols, Profile::default(), &WriteOptions::default()), profile);
        let (got, letters, warnings) = read(&bytes, &["x"], 0, n as u64, serial());
        let Got::Floats(_, codes) = &got[0] else { panic!() };
        (codes.clone(), letters[0], warnings)
    };
    // Good letters: on null rows only.
    let mut good = vec![None; n];
    good[1] = Some(".a");
    good[9] = Some(".z");
    let (codes, found, warnings) = read_x(&[x.clone(), letters(good)]);
    assert!(warnings.is_empty(), "{warnings:?}");
    assert!(found);
    assert_eq!((codes[1], codes[3], codes[9]), (2, 1, 27));
    // A letter where x has a value.
    let mut on_value = vec![None; n];
    on_value[1] = Some(".a");
    on_value[4] = Some(".b");
    let (codes, found, warnings) = read_x(&[x.clone(), letters(on_value)]);
    assert!(!found);
    assert_eq!(codes[1], 1);
    assert_eq!(warnings.len(), 1);
    assert!(warnings[0].contains("\"lx\"") && warnings[0].contains("\"x\"") && warnings[0].contains("row 5"), "{}", warnings[0]);
    // A value that is not a letter.
    let mut not_letter = vec![None; n];
    not_letter[3] = Some("..");
    let (_, found, warnings) = read_x(&[x.clone(), letters(not_letter)]);
    assert!(!found);
    assert!(warnings[0].contains("row 4"), "{}", warnings[0]);
    // A letter column that is not text stays a data column.
    let ints = Col { name: "lx".into(), data: Data::I32(vec![1; n]), codes: vec![0; n] };
    let bytes = with_profile(&bytes_of(&[x.clone(), ints], Profile::default(), &WriteOptions::default()), profile);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert_eq!(r.warnings().len(), 1);
    assert!(r.warnings()[0].contains("not a text column"));
    assert_eq!(r.data_columns().unwrap().len(), 2);
    // A letter column the file does not have.
    let bytes = with_profile(&bytes_of(std::slice::from_ref(&x), Profile::default(), &WriteOptions::default()), profile);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert_eq!(r.warnings().len(), 1);
    assert!(r.warnings()[0].contains("not in the file"));
    // Letter checks fail in one row group of several: no letters at all.
    let mut late = vec![None; n];
    late[1] = Some(".a");
    late[8] = Some(".c");
    let cols = [x, letters(late)];
    let bytes = with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions { row_group_rows: Some(3), ..Default::default() }), profile);
    for opts in [serial(), threaded()] {
        let (got, found, warnings) = read(&bytes, &["x"], 0, n as u64, opts);
        let Got::Floats(_, codes) = &got[0] else { panic!() };
        assert_eq!(found, vec![false]);
        assert_eq!(codes[1], 1, "letters from good row groups are undone too");
        assert!(warnings[0].contains("row 9"), "{}", warnings[0]);
    }
}

#[test]
fn a_damaged_profile_is_a_warning() {
    let cols = every_type(10);
    let bytes = with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions::default()), "{not json");
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert!(r.profile().is_none());
    assert_eq!(r.warnings().len(), 1);
    // The letter columns are then ordinary text columns, as for any tool.
    assert!(r.columns().iter().any(|c| c.name == "i8__missing" && c.role == Role::Data));
    let (got, _, _) = read(&bytes, &["i8__missing"], 0, 10, serial());
    assert_eq!(got[0], Got::Bytes((0..10).map(|r| (r == 4).then(|| b".a".to_vec())).collect()));
}

#[test]
fn values_the_output_cannot_hold_are_errors() {
    let mut cols = every_type(20);
    cols.push(Col { name: "big".into(), data: Data::I64((0..20).map(|r| (1 << 53) + r).collect()), codes: vec![0; 20] });
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let k = r.column_index("big").unwrap();
    let mut v = vec![0.0; 20];
    let mut outputs = [Output::Float64(Numbers::new(&mut v, f64::NAN))];
    let e = r.read(&[k], 0, 20, &mut outputs, |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("\"big\"") && e.message.contains("row 2") && e.message.contains("double"), "{}", e.message);
    // An output type that cannot hold the column at all.
    let k = r.column_index("f64").unwrap();
    let mut v = vec![0i32; 20];
    let mut outputs = [Output::Int32(Numbers::new(&mut v, 0))];
    let e = r.read(&[k], 0, 20, &mut outputs, |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("cannot be read as"), "{}", e.message);
    // A slice of the wrong length.
    let mut v = vec![0.0; 19];
    let mut outputs = [Output::Float64(Numbers::new(&mut v, 0.0))];
    assert!(r.read(&[k], 0, 20, &mut outputs, |_, _| Ok(())).is_err());
    // i8 values read into i8 fit.
    let k = r.column_index("i8").unwrap();
    let mut v = vec![0i8; 20];
    let mut outputs = [Output::Int8(Numbers::new(&mut v, i8::MIN))];
    r.read(&[k], 0, 20, &mut outputs, |_, _| Ok(())).unwrap();
    assert_eq!(v[0], -100);
}

#[test]
fn writer_errors_name_the_column_and_row() {
    let bad_int8 = vec![Col { name: "b".into(), data: Data::I8(vec![1, 200]), codes: vec![0, 0] }];
    let e = write(&table(&bad_int8, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
    assert!(e.message.contains("\"b\"") && e.message.contains("row 2"), "{}", e.message);
    let bad_code = vec![Col { name: "b".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 28] }];
    let e = write(&table(&bad_code, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
    assert!(e.message.contains("missing code 28"), "{}", e.message);
    let bad_level = vec![Col { name: "c".into(), data: Data::Cat { levels: vec!["a".into()], ordered: false, codes: vec![0, 1] }, codes: vec![] }];
    let e = write(&table(&bad_level, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
    assert!(e.message.contains("level code 1"), "{}", e.message);
    let twice = vec![
        Col { name: "a".into(), data: Data::I32(vec![1]), codes: vec![0] },
        Col { name: "a".into(), data: Data::I32(vec![1]), codes: vec![0] },
    ];
    assert!(write(&table(&twice, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err().message.contains("two columns"));
    let bad_utf8 = [Col { name: "t".into(), data: Data::Binary(vec![Some(vec![0xff])]), codes: vec![] }];
    // Binary may hold any bytes.
    write(&table(&bad_utf8, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap();
    let e = WriteOptions { compression: Compression::Snappy, compression_level: Some(3), ..Default::default() };
    assert!(write(&table(&twice[..1], Profile::default()), Vec::new(), &e).is_err());
}

#[test]
fn letter_column_names_avoid_taken_names() {
    let cols = vec![
        Col { name: "x".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 2] },
        Col { name: "x__missing".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 0] },
    ];
    let mut out = Vec::new();
    let report = write(&table(&cols, Profile::default()), &mut out, &WriteOptions::default()).unwrap();
    assert_eq!(report.missing_letters, vec![("x".to_string(), "x__missing_1".to_string())]);
    let (got, letters, _) = read(&out, &["x", "x__missing"], 0, 2, serial());
    assert_eq!(letters, vec![true, false]);
    let Got::Floats(_, codes) = &got[0] else { panic!() };
    assert_eq!(codes, &vec![0, 2]);
}
