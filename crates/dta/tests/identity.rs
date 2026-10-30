//! The writer's bytes do not change: 30 seeded random datasets, covering
//! every storage type, missing codes, strN, repeated and binary strLs,
//! value labels, characteristics and the sort order, hash to what the
//! writer produced before it was made faster (plan 0007). A change that
//! alters any file fails here, whatever reads it back.

use dta::{write_with, Characteristic, WriteOptions, Dataset, StorageType, ValueLabel, ValueLabelSet, Values, WriteVariable};

/// xorshift64*, enough to make varied data from a seed.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn below(&mut self, n: u64) -> u64 {
        self.next() % n.max(1)
    }
}

enum Data {
    Numbers(StorageType, Vec<f64>, Vec<u8>),
    Strings(Vec<Vec<u8>>),
    StrLs(Vec<(Vec<u8>, bool)>),
}

fn text(rng: &mut Rng, len: usize) -> Vec<u8> {
    const PIECES: [&str; 6] = ["a", "Z", "7", " ", "é", "€"];
    let mut s = Vec::new();
    while s.len() < len {
        s.extend_from_slice(PIECES[rng.below(PIECES.len() as u64) as usize].as_bytes());
    }
    s
}

fn column(rng: &mut Rng, nobs: usize) -> Data {
    let missing = |rng: &mut Rng| if rng.below(5) == 0 { 1 + rng.below(27) as u8 } else { 0 };
    let numbers = |rng: &mut Rng, storage, value: &dyn Fn(&mut Rng) -> f64| {
        let mut values = Vec::with_capacity(nobs);
        let mut codes = Vec::with_capacity(nobs);
        for _ in 0..nobs {
            let code = missing(rng);
            values.push(if code == 0 { value(rng) } else { f64::NAN });
            codes.push(code);
        }
        Data::Numbers(storage, values, codes)
    };
    match rng.below(8) {
        0 => numbers(rng, StorageType::Byte, &|r| r.below(228) as f64 - 127.0),
        1 => numbers(rng, StorageType::Int, &|r| r.below(65508) as f64 - 32767.0),
        2 => numbers(rng, StorageType::Long, &|r| r.below(1 << 32) as f64 - 2_147_483_647.0),
        3 => numbers(rng, StorageType::Float, &|r| (r.next() as i64 as f64 / 1e15) as f32 as f64),
        4 => numbers(rng, StorageType::Double, &|r| r.next() as i64 as f64 / 1e9),
        5 | 6 => {
            let width = [1, 5, 40, 2045][rng.below(4) as usize];
            Data::Strings((0..nobs).map(|_| {
                let n = rng.below(width as u64 + 1) as usize;
                let mut s = text(rng, n);
                // Pad by whole characters only, so the text stays UTF-8.
                while s.len() > width {
                    s.pop();
                    while std::str::from_utf8(&s).is_err() {
                        s.pop();
                    }
                }
                s
            }).collect())
        }
        _ => {
            // A few distinct texts, some long, some binary, repeated.
            let pool: Vec<(Vec<u8>, bool)> = (0..1 + rng.below(6))
                .map(|_| {
                    if rng.below(4) == 0 {
                        ((0..rng.below(50)).map(|_| rng.next() as u8).collect(), true)
                    } else {
                        let n = [0, 3, 3000][rng.below(3) as usize];
                        (text(rng, n), false)
                    }
                })
                .collect();
            Data::StrLs((0..nobs).map(|_| pool[rng.below(pool.len() as u64) as usize].clone()).collect())
        }
    }
}

fn dataset(seed: u64, options: &WriteOptions) -> Vec<u8> {
    let mut rng = Rng(seed.wrapping_mul(0x9e37_79b9_7f4a_7c15) | 1);
    let nobs = [0, 1, 7, 300, 5000][rng.below(5) as usize];
    let k = 1 + rng.below(12) as usize;
    let columns: Vec<Data> = (0..k).map(|_| column(&mut rng, nobs)).collect();
    let variables = columns
        .iter()
        .enumerate()
        .map(|(i, c)| {
            let (storage, values) = match c {
                Data::Numbers(storage, v, m) => (*storage, Values::numbers_by_row(move |r| (v[r], m[r]))),
                Data::Strings(s) => (StorageType::Str(1), Values::Strings(Box::new(move |r| s[r].as_slice()))),
                Data::StrLs(s) => (StorageType::StrL, Values::StrLs(Box::new(move |r| (s[r].0.as_slice(), s[r].1)))),
            };
            WriteVariable {
                name: format!("v{i}"),
                storage,
                format: if i % 3 == 0 { String::new() } else { "%9.2f".into() },
                label: if i % 2 == 0 { format!("Variable {i} é") } else { String::new() },
                value_labels: if i % 4 == 1 { "yesno".into() } else { String::new() },
                values,
            }
        })
        .collect();
    let data = Dataset {
        nobs,
        label: format!("seed {seed}"),
        timestamp: "30 Oct 2026 12:00".into(),
        variables,
        value_labels: vec![ValueLabelSet {
            name: "yesno".into(),
            labels: vec![
                ValueLabel { value: 0.0, missing: 0, text: "No".into() },
                ValueLabel { value: 1.0, missing: 0, text: "Yes".into() },
                ValueLabel { value: f64::NAN, missing: 5, text: "Don't know".into() },
            ],
        }],
        characteristics: vec![
            Characteristic { variable: "_dta".into(), name: "note0".into(), value: "1".into() },
            Characteristic { variable: "_dta".into(), name: "note1".into(), value: "a note".into() },
            Characteristic { variable: "v0".into(), name: "unit".into(), value: "kg".into() },
        ],
        sort_order: if k > 1 { vec![1, 0] } else { vec![] },
    };
    let mut out = Vec::new();
    write_with(&data, &mut out, options).unwrap();
    out
}

/// 64-bit FNV-1a.
fn fnv(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |h, &b| (h ^ b as u64).wrapping_mul(0x0100_0000_01b3))
}

/// The hashes of `dataset(0..30)` as the writer wrote them before plan 0007.
const EXPECTED: [u64; 30] = [
    0x5d5a5b650801cc2b,
    0xb3a3d53111645b08,
    0x8a90c5a537019fe4,
    0xca2089eb16c816cb,
    0x503a590e6c670312,
    0xa1d2072adce97aa5,
    0x25f3bd7d048fb075,
    0xc723a0451cfbd205,
    0x06ead0c3f4155b13,
    0x19a1eafedfa80a2c,
    0x155ea03470d2d56a,
    0xbc8dee448d64df16,
    0xcbe25e1b1b43a35a,
    0x0b491a95f733e933,
    0x0b3d35ecd0550c04,
    0x4d956537de65011d,
    0x989e6a5f4c4adc6c,
    0x39b7f99506d668c7,
    0x5299904b81579ea3,
    0xd79f8c26518125aa,
    0x1c27167330e53ca0,
    0x5674d4ba6b599214,
    0x66e50e8557d21e19,
    0xc5b363b0e97f7137,
    0xe7125200e4220884,
    0xb050846473a01174,
    0xa5689c0d0eea553b,
    0xeb3479662eaccaf2,
    0x738cfbc9cf3b5654,
    0x9c9f3cbb57ce9d4c,
];

fn check(options: &WriteOptions) {
    let got: Vec<u64> = (0..30).map(|seed| fnv(&dataset(seed, options))).collect();
    if got != EXPECTED {
        panic!("hashes differ with {options:?}; got:\n{got:#018x?}");
    }
}

#[test]
fn the_writer_s_bytes_have_not_changed() {
    check(&WriteOptions::default());
}

#[test]
fn small_blocks_and_slabs_give_the_same_bytes() {
    // Blocks of a few rows, slabs of one or two: every boundary is crossed.
    check(&WriteOptions { block_bytes: 300, slab_bytes: 64 });
}
