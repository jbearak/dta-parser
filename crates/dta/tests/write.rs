//! The writer's output reads back as written, and is laid out as haven
//! lays out the same data: reading haven's 118 fixture and writing it
//! again gives haven's file back, byte for byte. pandas' file comes back
//! identical up to the data; pandas writes an empty strL as a
//! (0, 0) reference with no entry, where haven (and we) write an entry.

use std::fs;
use std::path::Path;

use dta::{write, Bytes, Column, Dataset, Options, Reader, StorageType, Values, WriteVariable};

fn fixture(name: &str) -> Vec<u8> {
    fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures").join(name)).unwrap()
}

/// Read `bytes` and write it again with the same metadata.
fn rewrite(bytes: Vec<u8>, timestamp: &str) -> Vec<u8> {
    let mut reader = Reader::open(Bytes(bytes), Options::default()).unwrap();
    let meta = reader.metadata().clone();
    let all: Vec<usize> = (0..meta.variables.len()).collect();
    let columns = reader.read(&all, 0, meta.nobs).unwrap();
    let variables = meta
        .variables
        .iter()
        .zip(&columns)
        .map(|(v, c)| WriteVariable {
            name: v.name.clone(),
            storage: v.storage,
            format: v.format.clone(),
            label: v.label.clone(),
            value_labels: v.value_labels.clone(),
            values: match c {
                Column::Numbers { values, missing } => Values::numbers_by_row(move |i| (values[i], missing[i])),
                Column::Strings { .. } => Values::Strings(Box::new(move |i| c.bytes(i))),
            },
        })
        .collect();
    let data = Dataset {
        nobs: meta.nobs as usize,
        label: meta.label.clone(),
        timestamp: timestamp.into(),
        variables,
        value_labels: reader.value_labels().unwrap(),
        characteristics: reader.characteristics().unwrap(),
        sort_order: meta.sort_order.clone(),
    };
    let mut out = Vec::new();
    write(&data, &mut out).unwrap();
    out
}

#[test]
fn rewriting_a_118_file_gives_it_back() {
    for (name, whole) in [("haven_118.dta", true), ("pandas_118_le.dta", false)] {
        let mut original = fixture(name);
        let reader = Reader::open(Bytes(original.clone()), Options::default()).unwrap();
        let stamp = reader.metadata().timestamp.clone();
        let mut ours = rewrite(original.clone(), &stamp);
        if !whole {
            // Up to the data, whose strL cells differ for empty strings.
            let cut = |b: &[u8]| {
                let at = b.windows(6).position(|w| w == b"<data>").unwrap();
                let mut kept = b[..at].to_vec();
                // The map's last four offsets (strls onward) follow from the strL sizes.
                let map = b.windows(5).position(|w| w == b"<map>").unwrap() + 5;
                kept.drain(map + 10 * 8..map + 14 * 8);
                kept
            };
            original = cut(&original);
            ours = cut(&ours);
        }
        if ours != original {
            let at = ours.iter().zip(&original).position(|(a, b)| a != b).unwrap_or(ours.len().min(original.len()));
            panic!(
                "{name}: differs from byte {at} (ours {} bytes, theirs {}):\nours   {:?}\ntheirs {:?}",
                ours.len(),
                original.len(),
                String::from_utf8_lossy(&ours[at.saturating_sub(40)..(at + 40).min(ours.len())]),
                String::from_utf8_lossy(&original[at.saturating_sub(40)..(at + 40).min(original.len())]),
            );
        }
    }
}

#[test]
fn every_fixture_round_trips() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures");
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|e| e != "dta") {
            continue;
        }
        let bytes = fs::read(&path).unwrap();
        let written = rewrite(bytes.clone(), "28 Oct 2026 14:38");
        let mut a = Reader::open(Bytes(bytes), Options::default()).unwrap();
        let mut b = Reader::open(Bytes(written), Options::default()).unwrap();
        let (ma, mb) = (a.metadata().clone(), b.metadata().clone());
        assert_eq!(mb.release, 118);
        assert_eq!(ma.nobs, mb.nobs);
        assert_eq!(ma.label, mb.label);
        for (va, vb) in ma.variables.iter().zip(&mb.variables) {
            assert_eq!((&va.name, &va.format, &va.label, &va.value_labels), (&vb.name, &vb.format, &vb.label, &vb.value_labels));
            if va.storage.is_numeric() {
                assert_eq!(va.storage, vb.storage, "{}", va.name);
            }
        }
        let all: Vec<usize> = (0..ma.variables.len()).collect();
        let (ca, cb) = (a.read(&all, 0, ma.nobs).unwrap(), b.read(&all, 0, mb.nobs).unwrap());
        for (x, y) in ca.iter().zip(&cb) {
            match (x, y) {
                (Column::Numbers { values: v1, missing: m1 }, Column::Numbers { values: v2, missing: m2 }) => {
                    assert_eq!(m1, m2, "{path:?}");
                    for ((p, q), m) in v1.iter().zip(v2).zip(m1) {
                        assert!(*m != 0 || p == q, "{path:?}: {p} became {q}");
                    }
                }
                _ => assert_eq!(x, y, "{path:?}"),
            }
        }
        // Debug strings, since a missing code's value is NaN.
        assert_eq!(format!("{:?}", a.value_labels().unwrap()), format!("{:?}", b.value_labels().unwrap()));
        assert_eq!(a.characteristics().unwrap(), b.characteristics().unwrap());
    }
}

#[test]
fn text_with_a_nul_is_an_error() {
    for text in ["a\0b", &format!("{}\0", "x".repeat(3000))] {
        let data = Dataset {
            nobs: 1,
            label: String::new(),
            timestamp: String::new(),
            variables: vec![WriteVariable {
                name: "s".into(),
                storage: StorageType::Str(1),
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::Strings(Box::new(move |_| text.as_bytes())),
            }],
            value_labels: vec![],
            characteristics: vec![],
            sort_order: vec![],
        };
        let err = write(&data, Vec::new()).unwrap_err();
        assert!(err.message.contains("without NULs"), "{err}");
    }
}

fn one_column(storage: StorageType, value: f64) -> dta::Result<Vec<u8>> {
    let data = Dataset {
        nobs: 1,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![WriteVariable {
            name: "x".into(),
            storage,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::numbers_by_row(move |_| (value, 0)),
        }],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut out = Vec::new();
    write(&data, &mut out).map(|_| out)
}

#[test]
fn values_outside_the_storage_type_are_errors() {
    assert!(one_column(StorageType::Byte, 100.0).is_ok());
    assert!(one_column(StorageType::Byte, 101.0).is_err());
    assert!(one_column(StorageType::Byte, 1.5).is_err());
    assert!(one_column(StorageType::Int, -32768.0).is_err());
    assert!(one_column(StorageType::Long, 2_147_483_621.0).is_err());
    assert!(one_column(StorageType::Float, 1e39).is_err());
    assert!(one_column(StorageType::Double, f64::NAN).is_err());
    assert!(one_column(StorageType::Double, f64::INFINITY).is_err());
    // The largest values below the missing range are fine; the next are not.
    assert!(one_column(StorageType::Float, f32::from_bits(0x7eff_ffff) as f64).is_ok());
    assert!(one_column(StorageType::Float, -(f32::from_bits(0x7eff_ffff) as f64)).is_ok());
    assert!(one_column(StorageType::Float, f32::from_bits(0x7f00_0000) as f64).is_err());
    assert!(one_column(StorageType::Double, f64::from_bits(0x7fdf_ffff_ffff_ffff)).is_ok());
    assert!(one_column(StorageType::Double, f64::from_bits(0x7fe0_0000_0000_0000)).is_err());
}

#[test]
fn binary_strls_read_back_as_binary() {
    let rows: [(&[u8], bool); 5] =
        [(b"text", false), (b"\0\xff\x01", true), (b"text", true), (b"", false), (b"\0\xff\x01", true)];
    let data = Dataset {
        nobs: rows.len(),
        label: String::new(),
        timestamp: String::new(),
        variables: vec![WriteVariable {
            name: "s".into(),
            storage: StorageType::StrL,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::StrLs(Box::new(move |i| rows[i])),
        }],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut out = Vec::new();
    write(&data, &mut out).unwrap();
    let mut reader = Reader::open(Bytes(out), Options::default()).unwrap();
    assert_eq!(reader.metadata().variables[0].storage, StorageType::StrL);
    let column = &reader.read(&[0], 0, rows.len() as u64).unwrap()[0];
    let Column::Strings { binary, .. } = column else { panic!("not strings") };
    for (i, &(bytes, is_binary)) in rows.iter().enumerate() {
        assert_eq!((column.bytes(i), binary[i]), (bytes, is_binary), "row {i}");
    }
}

#[test]
fn two_strls_with_one_id_are_an_error() {
    let rows: [(&[u8], bool); 3] = [(b"first", false), (b"second", false), (b"third", false)];
    let data = Dataset {
        nobs: rows.len(),
        label: String::new(),
        timestamp: String::new(),
        variables: vec![WriteVariable {
            name: "s".into(),
            storage: StorageType::StrL,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::StrLs(Box::new(move |i| rows[i])),
        }],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut out = Vec::new();
    write(&data, &mut out).unwrap();
    Reader::open(Bytes(out.clone()), Options::default()).unwrap().read(&[0], 0, 3).unwrap();
    // Give the third strL the first one's (v, o): 4 + 8 bytes after "GSO".
    let gso: Vec<usize> = out.windows(3).enumerate().filter(|(_, w)| *w == b"GSO").map(|(i, _)| i).collect();
    assert_eq!(gso.len(), 3);
    let id = out[gso[0] + 3..gso[0] + 15].to_vec();
    out[gso[2] + 3..gso[2] + 15].copy_from_slice(&id);
    let err = Reader::open(Bytes(out), Options::default()).unwrap().read(&[0], 0, 3).unwrap_err();
    assert_eq!(err.kind, dta::ErrorKind::Corrupt);
    assert!(err.message.contains("two strLs"), "{err}");
}

fn strls(values: Vec<String>) -> Vec<u8> {
    let n = values.len();
    let values: &'static [String] = values.leak();
    let data = Dataset {
        nobs: n,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![WriteVariable {
            name: "s".into(),
            storage: StorageType::StrL,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::StrLs(Box::new(move |i| (values[i].as_bytes(), false))),
        }],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut out = Vec::new();
    write(&data, &mut out).unwrap();
    out
}

/// plan 0008 M3: with `max_text_units` (the wasm module's JavaScript
/// limit), a longer text strL is TooLarge; its UTF-16 length is counted
/// in 1 MiB pieces, across which three-byte characters split.
#[test]
fn a_text_strl_longer_than_one_string_is_too_large() {
    let value = "€".repeat(700_000) + "😀";
    let units = value.encode_utf16().count();
    let file = strls(vec![value.clone()]);
    for (max, ok) in [(units - 1, false), (units, true)] {
        let options = Options { max_text_units: Some(max), ..Options::default() };
        let got = Reader::open(Bytes(file.clone()), options).unwrap().read(&[0], 0, 1);
        match got {
            Ok(columns) => assert!(ok && columns[0].bytes(0) == value.as_bytes(), "max {max}"),
            Err(e) => assert!(!ok && e.kind == dta::ErrorKind::TooLarge, "max {max}: {e}"),
        }
    }
}

/// A call ends before the row that would take a column's text past
/// `max_text_units`, so JavaScript can decode it as one string; a call's
/// first row is always taken.
#[test]
fn a_budgeted_read_ends_before_its_text_passes_the_limit() {
    let file = strls((0..10).map(|i| format!("{i}").repeat(100)).collect());
    let options = Options { max_text_units: Some(250), ..Options::default() };
    let mut reader = Reader::open(Bytes(file), options).unwrap();
    let mut rows = Vec::new();
    let mut start = 0;
    while start < 10 {
        let n = reader.read_chunks(&[0], start, 10 - start, Some(1 << 20), |_, _| Ok(())).unwrap();
        rows.push(n);
        start += n;
    }
    assert_eq!(rows, [2, 2, 2, 2, 2]);
}

/// plan 0008 M5: previews keep at most `cap` stored bytes, cut on whole
/// characters, decode to a prefix of the full value, and record each
/// value's full stored length; a value was cut exactly when that length
/// passes the cap.
#[test]
fn previews_cut_on_characters_and_record_stored_lengths() {
    let texts = ["", "abc", "€uro€", "😀x", "aaaaaaaaaa", "é", "MALFORMED"];
    let values: &'static [String] = texts.iter().map(|t| t.to_string()).collect::<Vec<_>>().leak();
    let n = values.len();
    let column = |name: &str, storage| WriteVariable {
        name: name.into(),
        storage,
        format: String::new(),
        label: String::new(),
        value_labels: String::new(),
        values: if storage == StorageType::StrL {
            Values::StrLs(Box::new(move |i| (values[i].as_bytes(), false)))
        } else {
            Values::Strings(Box::new(move |i| values[i].as_bytes()))
        },
    };
    let data = Dataset {
        nobs: n,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![column("s", StorageType::Str(12)), column("l", StorageType::StrL)],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut file = Vec::new();
    write(&data, &mut file).unwrap();
    // Make the last value malformed UTF-8 in both columns: "MA\xFF\x80\xE2\x82RMED".
    for at in file.windows(9).enumerate().filter(|(_, w)| *w == b"MALFORMED").map(|(i, _)| i).collect::<Vec<_>>() {
        file[at + 2..at + 6].copy_from_slice(b"\xFF\x80\xE2\x82");
    }
    let full = Reader::open(Bytes(file.clone()), Options::default()).unwrap().read(&[0, 1], 0, n as u64).unwrap();
    for cap in 0..=12usize {
        let mut reader = Reader::open(Bytes(file.clone()), Options::default()).unwrap();
        reader.set_preview(Some(cap));
        let mut cols = vec![
            Column::Strings { bytes: vec![], ends: vec![], binary: vec![] },
            Column::Strings { bytes: vec![], ends: vec![], binary: vec![] },
        ];
        reader.read_into(&[0, 1], 0, n as u64, None, &mut cols).unwrap();
        for k in 0..2 {
            let stored = reader.stored_lengths(k);
            for i in 0..n {
                let whole = std::str::from_utf8(full[k].bytes(i)).unwrap();
                let cut = std::str::from_utf8(cols[k].bytes(i)).unwrap();
                let raw_len = if i == n - 1 { 9 } else { values[i].len() };
                assert_eq!(stored[i] as usize, raw_len, "column {k} row {i} cap {cap}");
                assert!(whole.starts_with(cut), "column {k} row {i} cap {cap}: {cut:?} is not a prefix of {whole:?}");
                assert_eq!(cut != whole, raw_len > cap, "column {k} row {i} cap {cap}: {cut:?} / {whole:?}");
            }
        }
    }
}

/// plan 0008 M6: an index exported from one reader reads the same values
/// in another; an index from a file of the same size and layout whose
/// entries point elsewhere is caught as the strLs are read.
#[test]
fn an_adopted_strl_index_reads_the_same_and_mismatches_are_errors() {
    let a = strls(vec!["aa".into(), "bbbb".into(), "€".into()]);
    let b = strls(vec!["bbbb".into(), "aa".into(), "€".into()]);
    assert_eq!(a.len(), b.len());
    let mut first = Reader::open(Bytes(a.clone()), Options::default()).unwrap();
    let index = first.strl_index_bytes().unwrap();
    let expected = first.read(&[0], 0, 3).unwrap();

    let mut second = Reader::open(Bytes(a.clone()), Options::default()).unwrap();
    second.adopt_strl_index(&index).unwrap();
    assert_eq!(second.read(&[0], 0, 3).unwrap(), expected);

    let mut other = Reader::open(Bytes(b), Options::default()).unwrap();
    other.adopt_strl_index(&index).unwrap();
    let err = other.read(&[0], 0, 3).unwrap_err();
    assert_eq!(err.kind, dta::ErrorKind::Corrupt, "{err}");

    let longer = strls(vec!["aa".into(), "bbbbb".into(), "€".into()]);
    let mut wrong_shape = Reader::open(Bytes(longer), Options::default()).unwrap();
    assert_eq!(wrong_shape.adopt_strl_index(&index).unwrap_err().kind, dta::ErrorKind::Corrupt);
}
