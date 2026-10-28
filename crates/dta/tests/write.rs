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
                Column::Numbers { values, missing } => Values::Numbers(Box::new(move |i| (values[i], missing[i]))),
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
            values: Values::Numbers(Box::new(move |_| (value, 0))),
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
}
