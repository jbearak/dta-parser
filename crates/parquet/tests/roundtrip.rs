//! Write tables with the crate's writer and read them back.

mod support;

use dta::{ValueLabel, ValueLabelSet};
use dta_parquet::format::{Codec, Encoding, FileMetaData, KeyValue, PhysicalType};
use dta_parquet::{
    tagged_code, tagged_nan, write, write_with_letters, ColumnProfile, ColumnType, Compression, Numbers, Output, Profile, ReadOptions, Reader, Role, Storage,
    WriteOptions, Logical, NA_BITS,
};
use support::{dated_columns, every_type, expected, read, same, storage_columns, table, Col, Data, Got};

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
    let (got, _) = read(bytes, &names(cols), skip as u64, n as u64, options);
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
    assert_eq!(i8p.storage, Some(Storage::Byte));
    assert_eq!(p.value_labels[0].labels[1].missing, 2);
    assert_eq!(p.column("region").unwrap().categorical.as_ref().unwrap().levels.len(), 4);
    assert!(p.column("size").unwrap().categorical.as_ref().unwrap().ordered);
    assert_eq!(p.column("when_ny").unwrap().tz.as_deref(), Some("America/New_York"));
    assert_eq!(p.column("when_utc").unwrap().tz.as_deref(), Some(""));
    assert!(p.column("local").is_none_or(|c| c.tz.is_none()));
    // Columns with .a to .z are DOUBLE, with their storage in the
    // profile; the others keep their types, and no column is added.
    let kind = |name: &str| {
        let c = &r.columns()[r.column_index(name).unwrap()];
        (c.kind.clone(), c.storage)
    };
    assert_eq!(kind("i8"), (ColumnType::Double, Some(Storage::Byte)));
    assert_eq!(kind("i16"), (ColumnType::Double, Some(Storage::Int)));
    assert_eq!(kind("f64"), (ColumnType::Double, None));
    assert_eq!(kind("i32"), (ColumnType::Int32, None));
    assert_eq!(kind("f32"), (ColumnType::Float, None));
    assert!(r.columns().iter().all(|c| c.role == Role::Data));
    assert_eq!(r.columns().len(), cols.len());
    assert_eq!(r.created_by(), Some(dta_parquet::CREATED_BY));
    assert!(r.key_value("ARROW:schema").is_some());
}

#[test]
fn the_letters_read_as_codes_and_flags() {
    let cols = every_type(100);
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let (got, letters) = read(&bytes, &["i8", "i32", "f64"], 0, 100, serial());
    assert_eq!(letters, vec![true, false, true]);
    let Got::Ints(_, codes) = &got[0] else { panic!() };
    assert_eq!(codes[3], 1);
    assert_eq!(codes[4], 2);
    assert_eq!(codes[14], 2);
    // Missing letters off: .a to .z are plain nulls, and every column
    // keeps its type.
    let off = WriteOptions { missing_letters: false, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &off);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let i8c = &r.columns()[r.column_index("i8").unwrap()];
    assert_eq!((i8c.kind.clone(), i8c.storage), (ColumnType::Int8, None));
    assert!(r.profile().is_none_or(|p| p.columns.iter().all(|c| c.storage.is_none())));
    let (got, letters) = read(&bytes, &["i8", "f64"], 0, 100, serial());
    assert_eq!(letters, vec![false, false]);
    let Got::Ints(_, codes) = &got[0] else { panic!() };
    assert_eq!((codes[3], codes[4]), (1, 1));
    let Got::Floats(values, codes) = &got[1] else { panic!() };
    assert_eq!(codes[6], 1);
    assert_eq!(values[6], -1e300, "a null, not a NaN");
}

#[test]
fn a_caller_who_says_which_columns_hold_letters_gets_the_same_file() {
    let cols = every_type(100);
    let t = table(&cols, Profile::default());
    let mut plain = Vec::new();
    write(&t, &mut plain, &WriteOptions::default()).unwrap();
    // What write found, given as hints: the same bytes.
    let (_, letters) = read(&plain, &names(&cols), 0, 100, serial());
    let hints: Vec<Option<bool>> = letters.into_iter().map(Some).collect();
    assert!(hints.contains(&Some(true)) && hints.contains(&Some(false)));
    let mut hinted = Vec::new();
    write_with_letters(&t, &mut hinted, &WriteOptions::default(), &hints).unwrap();
    assert!(hinted == plain);
    // No hints at all, or too few, read the columns as write does.
    let mut short = Vec::new();
    write_with_letters(&t, &mut short, &WriteOptions::default(), &hints[..1]).unwrap();
    assert!(short == plain);
}

#[test]
fn letters_can_go_into_the_values_themselves() {
    // As R keeps .a to .z: tagged NaNs, and NA_real_ for `.`.
    let cols = every_type(50);
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let k = r.column_index("f64").unwrap();
    let mut values = vec![0.0; 50];
    let na = f64::from_bits(NA_BITS);
    let mut outputs = [Output::Float64(Numbers::new(&mut values, na).with_missing(|c| if c == 1 { na } else { tagged_nan(c) }))];
    let report = r.read(&[k], 0, 50, &mut outputs, |_, _| Ok(())).unwrap();
    assert_eq!(report.letters, vec![true]);
    assert_eq!(values[3].to_bits(), NA_BITS); // .
    assert_eq!(values[6].to_bits(), tagged_nan(3).to_bits()); // .b
    assert_eq!(tagged_code(values[6]), 3);
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
fn the_page_cache_serves_neighbouring_windows() {
    let cols = every_type(3000);
    let opts = WriteOptions { row_group_rows: Some(1000), page_bytes: 2000, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &opts);
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    r.set_page_cache(1 << 20);
    let all = names(&cols);
    // Batches of 50 rows: each page is decompressed once, then found in
    // the cache, and the values are the same as without it.
    for skip in (0..3000).step_by(50) {
        let (got, _) = support::read_with(&mut r, &all, skip, 50).unwrap();
        for (c, g) in cols.iter().zip(&got) {
            assert!(same(&expected(c, skip as usize..skip as usize + 50), g), "{} at {skip}", c.name);
        }
    }
    let (held, hits, misses) = r.page_cache_stats();
    assert!(held > 0 && held <= 1 << 20, "{held}");
    assert!(hits > 4 * misses, "{hits} hits, {misses} misses");
    // A small budget evicts and still reads right.
    r.set_page_cache(4096);
    for skip in (0..3000).rev().step_by(70) {
        let (got, _) = support::read_with(&mut r, &all, skip, 30).unwrap();
        for (c, g) in cols.iter().zip(&got) {
            let end = (skip as usize + 30).min(3000);
            assert!(same(&expected(c, skip as usize..end), g), "{} at {skip}", c.name);
        }
    }
    assert!(r.page_cache_stats().0 <= 4096);
    // Whole chunks are not cached.
    r.set_page_cache(1 << 20);
    support::read_with(&mut r, &all, 0, 3000).unwrap();
    assert_eq!(r.page_cache_stats(), (0, 0, 0));
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
    // And with row groups pipelined under the smallest budget, where
    // each chunk waits for the one before it to be written.
    let tight = bytes_of(&cols, Profile::default(), &WriteOptions { pipeline_bytes: 1, ..opts });
    assert_eq!(bytes, tight);
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
fn nearly_all_distinct_numbers_give_up_the_dictionary_early() {
    let n = 100_000;
    let f64s = |name: &str, f: &dyn Fn(usize) -> f64| Col { name: name.into(), data: Data::F64((0..n).map(f).collect()), codes: vec![0; n] };
    let cols = vec![
        // All different: given up after the first 32,768 values.
        f64s("distinct", &|r| r as f64 + 0.5),
        // 20,000 values, repeated: 61% different at 32,768, and the
        // dictionary pays over the page.
        f64s("repeats", &|r| (r % 20_000) as f64),
        // 92% different at 32,768: given up, though the dictionary would
        // have paid over the whole page.
        f64s("late", &|r| (r % 30_000) as f64),
    ];
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let dict = |k: usize| r.metadata().row_groups[0].columns[k].meta.clone().unwrap().dictionary_page_offset.is_some();
    assert_eq!((dict(0), dict(1), dict(2)), (false, true, false));
    check(&bytes, &cols, 0, n, serial());
    check(&bytes, &cols, 40_000, 1000, serial());
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
    // f64 holds .b; only its nulls are counted.
    assert_eq!(stats("f64").null_count, Some(cols[5].codes.iter().filter(|&&c| c == 1).count() as i64));
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
fn tagged_nans_round_trip_from_every_storage_type() {
    let cols = storage_columns();
    for row_group_rows in [None, Some(4)] {
        let opts = WriteOptions { row_group_rows, ..Default::default() };
        let bytes = bytes_of(&cols, Profile::default(), &opts);
        let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        assert!(r.warnings().is_empty(), "{:?}", r.warnings());
        let want = [Some(Storage::Byte), Some(Storage::Int), Some(Storage::Long), Some(Storage::Float), None];
        for (c, storage) in cols.iter().zip(want) {
            let info = &r.columns()[r.column_index(&c.name).unwrap()];
            assert_eq!(info.physical, Some(PhysicalType::Double), "{}", c.name);
            assert_eq!(info.storage, storage, "{}", c.name);
            assert_eq!(r.profile().unwrap().column(&c.name).and_then(|p| p.storage), storage);
        }
        // Read back as their storage types: the values, `.` and the letters.
        check(&bytes, &cols, 0, 12, serial());
        check(&bytes, &cols, 3, 6, threaded());
        // And into each storage type's own Rust type.
        let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        let idx: Vec<usize> = ["b", "i", "l", "f"].iter().map(|n| r.column_index(n).unwrap()).collect();
        let (mut b, mut i, mut l, mut f) = (vec![0i8; 12], vec![0i16; 12], vec![0i32; 12], vec![0f32; 12]);
        let mut codes = vec![vec![0u8; 12]; 4];
        let [cb, ci, cl, cf] = &mut codes[..] else { unreachable!() };
        let mut outputs = [
            Output::Int8(Numbers::new(&mut b, i8::MIN).with_codes(cb)),
            Output::Int16(Numbers::new(&mut i, i16::MIN).with_codes(ci)),
            Output::Int32(Numbers::new(&mut l, i32::MIN).with_codes(cl)),
            Output::Float32(Numbers::new(&mut f, -1.0).with_codes(cf)),
        ];
        let report = r.read(&idx, 0, 12, &mut outputs, |_, _| Ok(())).unwrap();
        assert_eq!(report.letters, vec![true; 4]);
        assert_eq!((b[0], b[11], b[3]), (-120, 100, i8::MIN));
        assert_eq!((i[0], l[0]), (-30_000, -1_800_000_000));
        assert_eq!(f[1], 0.25);
        assert!(f[5].is_nan());
        for c in &codes {
            assert_eq!((c[2], c[3], c[5], c[7]), (1, 2, 0, 27));
        }
    }
}

#[test]
fn a_plain_nan_stays_a_nan_and_a_null_stays_a_null() {
    let cols = storage_columns();
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions::default());
    let (got, _) = read(&bytes, &["f", "d"], 0, 12, serial());
    for g in &got {
        let Got::Floats(values, codes) = g else { panic!() };
        assert!(values[5].is_nan() && tagged_code(values[5]) == 0);
        assert_eq!(codes[5], 0, "NaN is a value");
        assert_eq!((codes[2], values[2]), (1, -1e300), "null is .");
        assert_eq!((codes[3], values[3]), (2, -1e300), ".a is .a");
    }
    // In the file: the NaN, the tagged NaNs and the null, as such.
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let k = r.column_index("d").unwrap();
    let mut v = vec![0.0; 12];
    let mut outputs = [Output::Float64(Numbers::new(&mut v, 7.0).with_missing(|c| if c == 1 { 7.0 } else { tagged_nan(c) }))];
    r.read(&[k], 0, 12, &mut outputs, |_, _| Ok(())).unwrap();
    assert_eq!(v[2], 7.0);
    assert_eq!(v[3].to_bits(), 0x7ff0_0061_0000_07a2);
    assert_eq!(v[7].to_bits(), 0x7ff0_007a_0000_07a2);
    assert!(v[5].is_nan() && tagged_code(v[5]) == 0);
}

#[test]
fn statistics_leave_out_tagged_nans_and_count_only_nulls() {
    let cols = storage_columns();
    let bytes = bytes_of(&cols, Profile::default(), &WriteOptions { row_group_rows: Some(12), ..Default::default() });
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let stats = |k: usize| r.metadata().row_groups[0].columns[k].meta.as_ref().unwrap().statistics.clone().unwrap();
    // b: -120..100 without rows 2, 3 and 7; as doubles.
    let b = stats(0);
    assert_eq!(b.min_value, Some((-120f64).to_le_bytes().to_vec()));
    assert_eq!(b.max_value, Some(100f64.to_le_bytes().to_vec()));
    assert_eq!(b.null_count, Some(1));
    // d: NaN and tagged NaNs left out; 0/3 is the minimum, written -0.0.
    let d = stats(4);
    assert_eq!(d.min_value, Some((-0.0f64).to_le_bytes().to_vec()));
    assert_eq!(d.max_value, Some((11.0f64 / 3.0).to_le_bytes().to_vec()));
    assert_eq!(d.null_count, Some(1));
}

#[test]
fn missing_letters_off_writes_nulls() {
    let cols = storage_columns();
    let off = WriteOptions { missing_letters: false, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &off);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let kinds: Vec<ColumnType> = r.columns().iter().map(|c| c.kind.clone()).collect();
    assert_eq!(kinds, vec![ColumnType::Int8, ColumnType::Int16, ColumnType::Int32, ColumnType::Float, ColumnType::Double]);
    assert!(r.columns().iter().all(|c| c.storage.is_none()));
    let stats = r.metadata().row_groups[0].columns[4].meta.as_ref().unwrap().statistics.clone().unwrap();
    assert_eq!(stats.null_count, Some(3));
    let (got, letters) = read(&bytes, &names(&cols), 0, 12, serial());
    assert_eq!(letters, vec![false; 5]);
    for g in &got {
        let codes = match g {
            Got::Ints(_, c) | Got::Floats(_, c) => c,
            _ => panic!(),
        };
        assert_eq!((codes[2], codes[3], codes[7]), (1, 1, 1));
    }
}

#[test]
fn dates_and_timestamps_with_letters_are_days_and_seconds() {
    let cols = dated_columns();
    let tz = |name: &str| -> Option<&'static str> {
        match name {
            "when" => Some("America/New_York"),
            "when_utc" => Some(""),
            _ => None,
        }
    };
    for row_group_rows in [None, Some(2)] {
        let opts = WriteOptions { row_group_rows, ..Default::default() };
        let bytes = bytes_of(&cols, Profile::default(), &opts);
        let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
        assert!(r.warnings().is_empty(), "{:?}", r.warnings());
        for c in &cols {
            let info = &r.columns()[r.column_index(&c.name).unwrap()];
            let want = if matches!(c.data, Data::Date(_)) { Logical::Date } else { Logical::Timestamp };
            // A plain DOUBLE to Parquet, with what it was in the profile.
            assert_eq!((info.physical, info.logical.clone(), info.converted), (Some(PhysicalType::Double), None, None), "{}", c.name);
            assert_eq!((info.kind.clone(), info.storage, info.profile_logical), (ColumnType::Double, None, Some(want)), "{}", c.name);
            let p = r.profile().unwrap().column(&c.name).unwrap();
            assert_eq!((p.logical, p.storage, p.tz.as_deref()), (Some(want), None, tz(&c.name)), "{}", c.name);
        }
        // Dates are days and timestamps seconds since 1970, with `.`, .a
        // and .b; read over windows and threads alike.
        let want: Vec<(Vec<f64>, Vec<u8>)> = vec![
            (vec![0.0, 19_000.0, -1.0, 365.0, -25_567.0], vec![0, 2, 1, 3, 0]),
            (vec![1_700_000_000.5, 0.0, -1.5, 0.001, 86_400.0], vec![0, 1, 0, 0, 3]),
            (vec![-0.000_001, 1.25, 0.0, 0.0, 1_600_000_000.0], vec![0, 0, 3, 2, 0]),
            (vec![1.000_000_123, -1.000_000_001, 0.0, 0.0, 1_700_000_000.123_456_7], vec![0, 0, 2, 1, 0]),
        ];
        for (skip, n, options) in [(0, 5, serial()), (1, 3, threaded())] {
            let (got, letters) = read(&bytes, &names(&cols), skip, n, options);
            let rows = skip as usize..(skip + n) as usize;
            let any: Vec<bool> = want.iter().map(|(_, k)| k[rows.clone()].iter().any(|&c| c > 1)).collect();
            assert_eq!(letters, any);
            for ((c, g), (values, codes)) in cols.iter().zip(&got).zip(&want) {
                let Got::Floats(v, k) = g else { panic!("{}: {g:?}", c.name) };
                assert_eq!(k, &codes[rows.clone()], "{}", c.name);
                for (i, r) in rows.clone().enumerate() {
                    if codes[r] == 0 {
                        // The nearest double, even to a nanosecond.
                        assert_eq!(v[i], values[r], "{} row {r}", c.name);
                    }
                }
            }
        }
    }
}

#[test]
fn dates_and_timestamps_keep_their_type_with_letters_off() {
    let cols = dated_columns();
    let off = WriteOptions { missing_letters: false, ..Default::default() };
    let bytes = bytes_of(&cols, Profile::default(), &off);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert_eq!(r.columns()[0].kind, ColumnType::Date);
    for c in &r.columns()[1..] {
        assert!(matches!(c.kind, ColumnType::Timestamp { .. }), "{}: {:?}", c.name, c.kind);
    }
    assert!(r.columns().iter().all(|c| c.profile_logical.is_none() && c.storage.is_none()));
    assert!(r.profile().unwrap().columns.iter().all(|c| c.logical.is_none()));
    let (got, letters) = read(&bytes, &names(&cols), 0, 5, serial());
    assert_eq!(letters, vec![false; 4]);
    let Got::Ints(day, codes) = &got[0] else { panic!() };
    assert_eq!((day[0], day[2], day[4]), (0, i64::MIN, -25_567));
    assert_eq!(codes, &vec![0, 1, 1, 1, 0]);
    let Got::Ints(when, codes) = &got[1] else { panic!() };
    assert_eq!((when[0], when[2], when[3]), (1_700_000_000_500, -1500, 1));
    assert_eq!(codes, &vec![0, 1, 0, 0, 1]);
}

#[test]
fn letters_only_go_where_a_double_holds_them() {
    // 64-bit integers cannot be written as DOUBLE exactly, and booleans
    // have no double form: a letter in one is an error, unless letters
    // are off.
    let code = vec![0, 2];
    let bad = [
        Col { name: "big".into(), data: Data::I64(vec![1, 2]), codes: code.clone() },
        Col { name: "yes".into(), data: Data::Bool(vec![1, 0]), codes: code.clone() },
    ];
    for c in &bad {
        let one = std::slice::from_ref(c);
        let e = write(&table(one, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
        assert!(e.message.contains(&format!("\"{}\"", c.name)) && e.message.contains("row 2 holds .a"), "{}", e.message);
        let off = WriteOptions { missing_letters: false, ..Default::default() };
        let bytes = bytes_of(one, Profile::default(), &off);
        let (got, _) = read(&bytes, &[&c.name], 0, 2, serial());
        let Got::Ints(_, codes) = &got[0] else { panic!() };
        assert_eq!(codes, &vec![0, 1]);
    }
    // A byte column written as DOUBLE still checks its values fit.
    let wide = [Col { name: "b".into(), data: Data::I8(vec![1, 200, 0]), codes: vec![2, 0, 0] }];
    let e = write(&table(&wide, Profile::default()), Vec::new(), &WriteOptions::default()).unwrap_err();
    assert!(e.message.contains("\"b\"") && e.message.contains("row 2") && e.message.contains("8 bits"), "{}", e.message);
}

#[test]
fn a_logical_type_the_columns_cannot_have_is_dropped() {
    let cols = [
        Col { name: "x".into(), data: Data::Date(vec![1, 2]), codes: vec![0, 0] },
        Col { name: "y".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 0] },
        Col { name: "z".into(), data: Data::F64(vec![2.5, 1.0]), codes: vec![0, 2] },
    ];
    let profile = r#"{"version": 1, "columns": {"x": {"logical": "date"}, "y": {"logical": "datetime", "label": "Why"}, "z": {"logical": "timestamp", "tz": "UTC"}, "gone": {"logical": "date"}}}"#;
    let bytes = with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions::default()), profile);
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let w = r.warnings().to_vec();
    assert_eq!(w.len(), 2, "{w:?}");
    assert!(w.iter().any(|w| w.contains("\"columns.y.logical\"")), "{w:?}");
    assert!(w.iter().any(|w| w.contains("\"columns.x.logical\"") && w.contains("not DOUBLE")), "{w:?}");
    let p = r.profile().unwrap();
    assert_eq!(p.column("x").and_then(|c| c.logical), None);
    assert_eq!(p.column("y").unwrap().label.as_deref(), Some("Why"));
    assert_eq!(p.column("y").unwrap().logical, None);
    assert_eq!(p.column("z").unwrap().logical, Some(Logical::Timestamp));
    let logical: Vec<Option<Logical>> = r.columns().iter().map(|c| c.profile_logical).collect();
    assert_eq!(logical, vec![None, None, Some(Logical::Timestamp)]);
    // x is still a date, and z still reads as doubles with its letter.
    assert_eq!(r.columns()[0].kind, ColumnType::Date);
    let (got, _) = read(&bytes, &["z"], 0, 2, serial());
    assert_eq!(got[0], Got::Floats(vec![2.5, -1e300], vec![0, 2]));
}

#[test]
fn a_double_column_keeps_the_logical_type_it_is_given() {
    // R writes a Date with fractions of a day, or a POSIXct whose seconds
    // are not whole microseconds, as DOUBLE with `logical` in the
    // profile, letters or not; other columns cannot be given one.
    let cols = [
        Col { name: "day".into(), data: Data::F64(vec![1.5, 2.0]), codes: vec![0, 1] },
        Col { name: "when".into(), data: Data::F64(vec![0.1, 2.0]), codes: vec![2, 0] },
        Col { name: "n".into(), data: Data::I32(vec![1, 2]), codes: vec![0, 0] },
    ];
    let mut profile = Profile::default();
    profile.column_mut("day").logical = Some(Logical::Date);
    profile.column_mut("when").logical = Some(Logical::Timestamp);
    profile.column_mut("when").tz = Some("America/Chicago".into());
    profile.column_mut("n").logical = Some(Logical::Date);
    let bytes = bytes_of(&cols, profile, &WriteOptions::default());
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert!(r.warnings().is_empty(), "{:?}", r.warnings());
    let logical: Vec<Option<Logical>> = r.columns().iter().map(|c| c.profile_logical).collect();
    assert_eq!(logical, vec![Some(Logical::Date), Some(Logical::Timestamp), None]);
    assert_eq!(r.profile().unwrap().column("when").unwrap().tz.as_deref(), Some("America/Chicago"));
    let (got, _) = read(&bytes, &["day", "when"], 0, 2, serial());
    assert_eq!(got[0], Got::Floats(vec![1.5, -1e300], vec![0, 1]));
    assert_eq!(got[1], Got::Floats(vec![-1e300, 2.0], vec![2, 0]));
}

#[test]
fn a_storage_the_columns_cannot_have_is_dropped() {
    let cols = [
        Col { name: "x".into(), data: Data::I32(vec![1, 2]), codes: vec![0, 0] },
        Col { name: "y".into(), data: Data::F64(vec![1.0, 2.0]), codes: vec![0, 0] },
        Col { name: "z".into(), data: Data::F64(vec![2.5, 1.0]), codes: vec![0, 2] },
    ];
    let profile = r#"{"version": 1, "columns": {"x": {"storage": "byte"}, "y": {"storage": "short", "label": "Why"}, "z": {"storage": "int"}, "gone": {"storage": "long"}}}"#;
    let bytes = with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions::default()), profile);
    let mut r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    let w = r.warnings().to_vec();
    assert_eq!(w.len(), 2, "{w:?}");
    assert!(w.iter().any(|w| w.contains("\"columns.y.storage\"")), "{w:?}");
    assert!(w.iter().any(|w| w.contains("\"columns.x.storage\"") && w.contains("not DOUBLE")), "{w:?}");
    let p = r.profile().unwrap();
    assert_eq!(p.column("x").and_then(|c| c.storage), None);
    assert_eq!(p.column("y").unwrap().label.as_deref(), Some("Why"));
    assert_eq!(p.column("y").unwrap().storage, None);
    let storage: Vec<Option<Storage>> = r.columns().iter().map(|c| c.storage).collect();
    assert_eq!(storage, vec![None, None, Some(Storage::Int)]);
    // A DOUBLE column without an integer storage does not read as integers.
    let y = r.column_index("y").unwrap();
    let mut v = vec![0i16; 2];
    let e = r.read(&[y], 0, 2, &mut [Output::Int16(Numbers::new(&mut v, 0))], |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("cannot be read as"), "{}", e.message);
    // With one, a value that is not a whole number is an error naming it.
    let z = r.column_index("z").unwrap();
    let mut v = vec![0i16; 2];
    let e = r.read(&[z], 0, 2, &mut [Output::Int16(Numbers::new(&mut v, 0))], |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("\"z\"") && e.message.contains("2.5") && e.message.contains("row 1"), "{}", e.message);
}

#[test]
fn a_damaged_profile_is_a_warning() {
    let cols = every_type(10);
    let bytes = with_profile(&bytes_of(&cols, Profile::default(), &WriteOptions::default()), "{not json");
    let r = Reader::open(dta::Bytes(&bytes[..]), serial()).unwrap();
    assert!(r.profile().is_none());
    assert_eq!(r.warnings().len(), 1);
    // A byte column with letters is then a plain DOUBLE column, whose
    // tagged NaNs are still .a to .z.
    assert!(r.columns().iter().all(|c| c.storage.is_none()));
    let (got, letters) = read(&bytes, &["i8"], 0, 10, serial());
    assert_eq!(letters, vec![true]);
    let Got::Floats(values, codes) = &got[0] else { panic!() };
    assert_eq!((values[0], codes[3], codes[4]), (-100.0, 1, 2));
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

/// An output that fails once it has taken `room` bytes.
struct Full {
    room: usize,
}

impl std::io::Write for Full {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if buf.len() > self.room {
            return Err(std::io::Error::other("the disk is full"));
        }
        self.room -= buf.len();
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn a_write_on_threads_stops_at_the_first_error() {
    // Many columns, so workers run ahead of the column being written.
    let cols: Vec<Col> = (0..64)
        .map(|k| Col { name: format!("v{k}"), data: Data::F64((0..500).map(|i| (i * k) as f64).collect()), codes: vec![0; 500] })
        .collect();
    let threads = WriteOptions { threads: 4, parallel_bytes: 0, ..Default::default() };
    let whole = bytes_of(&cols, Profile::default(), &threads);
    assert_eq!(whole, bytes_of(&cols, Profile::default(), &WriteOptions { threads: 1, ..threads }));
    for room in [10, whole.len() / 3, whole.len() - 10] {
        let e = write(&table(&cols, Profile::default()), Full { room }, &threads).unwrap_err();
        assert!(e.message.contains("the disk is full"), "{}", e.message);
    }
    // A column that cannot be encoded, among others that can.
    let mut bad = cols.clone();
    let mut values = vec![1; 500];
    values[7] = 200;
    bad[40] = Col { name: "b".into(), data: Data::I8(values), codes: vec![0; 500] };
    let e = write(&table(&bad, Profile::default()), Vec::new(), &threads).unwrap_err();
    assert!(e.message.contains("\"b\"") && e.message.contains("row 8"), "{}", e.message);
}
