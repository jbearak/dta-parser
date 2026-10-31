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
    let texts = ["", "abc", "€uro€", "😀x", "aaaaaaaaaa", "é", "BADLEADxx", "MALFORMED"];
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
    // Make the last values malformed UTF-8 in both columns:
    // "MA\xFF\x80\xE2\x82RMED", and "\xE0\x80ADLEADxx", whose E0 80 is
    // invalid from its second byte (E0 needs A0 to BF), so a cut after it
    // keeps it.
    for at in file.windows(9).enumerate().filter(|(_, w)| *w == b"MALFORMED").map(|(i, _)| i).collect::<Vec<_>>() {
        file[at + 2..at + 6].copy_from_slice(b"\xFF\x80\xE2\x82");
    }
    for at in file.windows(9).enumerate().filter(|(_, w)| *w == b"BADLEADxx").map(|(i, _)| i).collect::<Vec<_>>() {
        file[at..at + 2].copy_from_slice(b"\xE0\x80");
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
                let raw_len = values[i].len();
                if i == n - 2 && cap == 2 {
                    assert_eq!(cut, "\u{FFFD}\u{FFFD}", "column {k}: an invalid E0 80 is kept");
                }
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

/// plan 0008 D6: rows read by index, in any order and with repeats, are
/// the rows a range read gives; a budget stops the read after a prefix of
/// the list; previews keep every row's stored length.
#[test]
fn rows_read_by_index_match_a_range_read() {
    let n = 500;
    let texts: &'static [String] = (0..n).map(|i| "é".repeat(i % 7) + &i.to_string()).collect::<Vec<_>>().leak();
    let data = Dataset {
        nobs: n,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![
            WriteVariable {
                name: "x".into(),
                storage: StorageType::Double,
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::numbers_by_row(|i| if i % 11 == 3 { (0.0, 2) } else { (i as f64 * 1.5, 0) }),
            },
            WriteVariable {
                name: "s".into(),
                storage: StorageType::Str(20),
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::Strings(Box::new(move |i| texts[i].as_bytes())),
            },
            WriteVariable {
                name: "l".into(),
                storage: StorageType::StrL,
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::StrLs(Box::new(move |i| (texts[i].as_bytes(), i % 13 == 0))),
            },
        ],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut file = Vec::new();
    write(&data, &mut file).unwrap();
    let cols = [0, 1, 2];
    let full = Reader::open(Bytes(file.clone()), Options::default()).unwrap().read(&cols, 0, n as u64).unwrap();
    let empty = || {
        vec![
            Column::Numbers { values: vec![], missing: vec![] },
            Column::Strings { bytes: vec![], ends: vec![], binary: vec![] },
            Column::Strings { bytes: vec![], ends: vec![], binary: vec![] },
        ]
    };
    let rows: Vec<u64> = [499, 0, 1, 2, 3, 250, 250, 7, 6, 5, 100, 101, 102, 498, 499, 0].into_iter().chain(200..260).collect();
    let mut reader = Reader::open(Bytes(file.clone()), Options::default()).unwrap();
    let mut got = empty();
    assert_eq!(reader.read_rows_into(&cols, &rows, None, &mut got).unwrap(), rows.len());
    let check = |got: &[Column], count: usize| {
        for (j, &r) in rows[..count].iter().enumerate() {
            let r = r as usize;
            let (Column::Numbers { values, missing }, Column::Numbers { values: v, missing: m }) = (&got[0], &full[0]) else { panic!() };
            assert_eq!((values[j].to_bits(), missing[j]), (v[r].to_bits(), m[r]), "row {r}");
            for k in 1..3 {
                assert_eq!(got[k].bytes(j), full[k].bytes(r), "column {k} row {r}");
            }
            let (Column::Strings { binary, .. }, Column::Strings { binary: b, .. }) = (&got[2], &full[2]) else { panic!() };
            assert_eq!(binary[j], b[r], "row {r}");
        }
    };
    check(&got, rows.len());
    // A budget stops after a prefix (at least one row), which reads the same.
    let mut got = empty();
    let count = reader.read_rows_into(&cols, &rows, Some(200), &mut got).unwrap();
    assert!(count >= 1 && count < rows.len(), "{count}");
    assert_eq!(got[0].len(), count);
    check(&got, count);
    // Previews: every row's stored length, across runs.
    reader.set_preview(Some(2));
    let mut got = empty();
    reader.read_rows_into(&cols, &rows, None, &mut got).unwrap();
    for k in 1..3 {
        let stored = reader.stored_lengths(k);
        assert_eq!(stored.len(), rows.len());
        for (j, &r) in rows.iter().enumerate() {
            assert_eq!(stored[j] as usize, texts[r as usize].len(), "column {k} row {r}");
        }
    }
    reader.set_preview(None);
    let err = reader.read_rows_into(&cols, &[3, n as u64], None, &mut empty()).unwrap_err();
    assert_eq!(err.kind, dta::ErrorKind::OutOfRange);
}

/// A source that counts its reads.
struct Counting(Bytes<Vec<u8>>, std::rc::Rc<std::cell::Cell<usize>>);

impl dta::Source for Counting {
    fn len(&self) -> u64 {
        self.0.len()
    }
    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        self.1.set(self.1.get() + 1);
        self.0.read_at(offset, buf)
    }
}

/// plan 0008 D8: a read resolves each distinct strL once, and reads
/// small neighbouring payloads together, giving the same values (in
/// full, as previews, and through an adopted index) in a few reads.
#[test]
fn strls_are_read_once_and_in_batches() {
    let n = 3000;
    let big = |i: usize| format!("{i}:{}", "x".repeat(100_000));
    let texts: &'static [String] = (0..n)
        // Small values first, then 100 large ones and one large repeat.
        .map(|i| match (i >= n - 300, i % 10) {
            (true, 0 | 3 | 6) => big(i),
            (true, _) => big(7),
            (_, 0..=4) => "shared".to_string(),
            (_, 5) => String::new(),
            _ => format!("é{i}"),
        })
        .collect::<Vec<_>>()
        .leak();
    let data = Dataset {
        nobs: n,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![WriteVariable {
            name: "l".into(),
            storage: StorageType::StrL,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::StrLs(Box::new(move |i| (texts[i].as_bytes(), i < n - 300 && i % 10 == 9))),
        }],
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let mut file = Vec::new();
    write(&data, &mut file).unwrap();
    let reads = std::rc::Rc::new(std::cell::Cell::new(0));
    let open = || Reader::open(Counting(Bytes(file.clone()), reads.clone()), Options::default()).unwrap();
    let mut reader = open();
    reader.read(&[0], 0, 1).unwrap(); // builds the index
    let index = reader.strl_index_bytes().unwrap();
    for adopted in [false, true] {
        for cap in [None, Some(3), Some(200_000)] {
            let mut reader = open();
            if adopted {
                reader.adopt_strl_index(&index).unwrap();
            } else {
                reader.read(&[0], 0, 1).unwrap();
            }
            reader.set_preview(cap);
            reads.set(0);
            let mut cols = vec![Column::Strings { bytes: vec![], ends: vec![], binary: vec![] }];
            reader.read_into(&[0], 0, n as u64, None, &mut cols).unwrap();
            // Read in full: a read per large value, a few for the rest
            // (3,000 without). A preview reads values it cuts one by one,
            // no more of each than it shows.
            if cap.is_none_or(|c| c >= 100_000) {
                assert!(reads.get() <= 101 + 10, "{} reads (adopted {adopted}, cap {cap:?})", reads.get());
            }
            let stored = reader.stored_lengths(0);
            for (i, text) in texts.iter().enumerate() {
                let want = match cap {
                    Some(cap) if text.len() > cap => &text.as_bytes()[..cap],
                    _ => text.as_bytes(),
                };
                let got = cols[0].bytes(i);
                if i < n - 300 && i % 10 == 9 {
                    assert_eq!(got, want, "row {i} (adopted {adopted}, cap {cap:?})");
                } else {
                    assert!(text.starts_with(std::str::from_utf8(got).unwrap()) && got.len() <= want.len(), "row {i} (adopted {adopted}, cap {cap:?})");
                    if cap.is_none_or(|c| text.len() <= c) {
                        assert_eq!(got, want, "row {i}");
                    }
                }
                if cap.is_some() {
                    assert_eq!(stored[i] as usize, text.len(), "row {i}");
                }
            }
        }
    }
}
