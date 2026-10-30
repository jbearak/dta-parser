//! Damaged files give errors, never panics: every fixture truncated at
//! many points, and with bytes flipped at many positions, is either read
//! in full or rejected.

use std::fs;
use std::path::Path;

use dta::{Bytes, Options, Reader};

/// Open and read everything; Err if any step fails.
fn read_all(bytes: Vec<u8>) -> dta::Result<()> {
    let mut reader = Reader::open(Bytes(bytes), Options::default())?;
    let meta = reader.metadata().clone();
    let all: Vec<usize> = (0..meta.variables.len()).collect();
    reader.read(&all, 0, meta.nobs)?;
    reader.value_labels()?;
    reader.characteristics()?;
    Ok(())
}

fn fixtures() -> Vec<Vec<u8>> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures");
    let mut paths: Vec<_> = fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    paths.retain(|p| p.extension().is_some_and(|e| e == "dta"));
    paths.sort();
    paths.into_iter().map(|p| fs::read(p).unwrap()).collect()
}

#[test]
fn truncated_files_are_errors() {
    for bytes in fixtures() {
        read_all(bytes.clone()).expect("the intact fixture reads");
        let step = (bytes.len() / 200).max(1);
        for len in (0..bytes.len()).step_by(step) {
            // Any outcome but a panic is fine; most are errors.
            let _ = read_all(bytes[..len].to_vec());
        }
    }
}

#[test]
fn flipped_bytes_do_not_panic() {
    for bytes in fixtures() {
        let step = (bytes.len() / 300).max(1);
        for pos in (0..bytes.len()).step_by(step) {
            for flip in [0x01u8, 0x80, 0xff] {
                let mut damaged = bytes.clone();
                damaged[pos] ^= flip;
                let _ = read_all(damaged);
            }
        }
    }
}

#[test]
fn errors_say_what_kind_they_are() {
    use dta::ErrorKind;
    let bytes = fixtures().remove(0);
    let mut damaged = bytes.clone();
    damaged[..40].fill(b'A');
    assert_eq!(Reader::open(Bytes(damaged), Options::default()).err().unwrap().kind, ErrorKind::Corrupt);

    let mut reader = Reader::open(Bytes(bytes), Options::default()).unwrap();
    let (nvar, nobs) = (reader.metadata().variables.len(), reader.metadata().nobs);
    assert_eq!(reader.read(&[nvar], 0, 1).unwrap_err().kind, ErrorKind::OutOfRange);
    assert_eq!(reader.read(&[0], nobs, 1).unwrap_err().kind, ErrorKind::OutOfRange);

    let data = dta::Dataset {
        nobs: 1,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![dta::WriteVariable {
            name: "1bad".into(),
            storage: dta::StorageType::Double,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: dta::Values::numbers_by_row(|_| (1.0, 0)),
        }],
        value_labels: Vec::new(),
        characteristics: Vec::new(),
        sort_order: Vec::new(),
    };
    assert_eq!(dta::write(&data, Vec::new()).unwrap_err().kind, ErrorKind::Invalid);

    struct Full;
    impl std::io::Write for Full {
        fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
            Err(std::io::Error::other("disk full"))
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let ok = dta::Dataset { variables: vec![dta::WriteVariable { name: "x".into(), ..data.variables.into_iter().next().unwrap() }], ..data };
    assert_eq!(dta::write(&ok, Full).unwrap_err().kind, ErrorKind::Io);
}
