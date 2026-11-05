//! Damage files at random, deterministically, and read each whole and in
//! windows: every case must be an answer or an error, never a panic, and
//! no allocation may be far larger than the file and the rows asked for.
//!
//! The files are the fixtures other tools wrote (compat/parquet/fixtures)
//! and a few this crate's writer makes. `DTA_FUZZ_CASES` sets the cases
//! per file (default 200); `DTA_FUZZ_SEED` the first seed.

mod counting;
mod support;

use std::panic::{catch_unwind, AssertUnwindSafe};

use counting::{largest_during, Counting};
use dta_parquet::{write, ColumnType, Compression, LevelsFrom, Numbers, Output, Profile, ReadOptions, Reader, Role, WriteOptions};
use support::{every_type, rebuild, table};

#[global_allocator]
static ALLOC: Counting = Counting;

/// xorshift64*.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
}

fn files() -> Vec<(String, Vec<u8>)> {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../../compat/parquet/fixtures");
    let mut out: Vec<(String, Vec<u8>)> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|x| x == "parquet"))
        .map(|p| (p.file_name().unwrap().to_string_lossy().into_owned(), std::fs::read(&p).unwrap()))
        .collect();
    out.sort();
    let cols = every_type(400);
    for (name, options) in [
        ("zstd, small pages", WriteOptions { compression: Compression::Zstd, row_group_rows: Some(150), page_bytes: 200, ..Default::default() }),
        ("snappy, no index", WriteOptions { compression: Compression::Snappy, offset_index: false, ..Default::default() }),
        ("gzip", WriteOptions { compression: Compression::Gzip, row_group_rows: Some(300), ..Default::default() }),
        ("lz4, no letters", WriteOptions { compression: Compression::Lz4Raw, missing_letters: false, page_bytes: 500, ..Default::default() }),
        ("uncompressed", WriteOptions { compression: Compression::None, page_bytes: 300, ..Default::default() }),
    ] {
        let mut bytes = Vec::new();
        write(&table(&cols, Profile::default()), &mut bytes, &options).unwrap();
        out.push((format!("writer: {name}"), bytes));
    }
    out
}

/// A value a damaged header field might hold.
fn extreme(rng: &mut Rng, was: i64) -> i64 {
    [i32::MAX as i64, 1 << 30, 2_000_000_000, 0, -1, was * 2 + 1, was - 1, was + 1][rng.below(8)]
}

/// Rewrite a copy of `file` with one page header field, or a row group's
/// row count, set to an extreme value: what byte damage seldom reaches.
fn mutate_fields(file: &[u8], rng: &mut Rng) -> Vec<u8> {
    let pages = {
        let mut n = 0;
        rebuild(file, |_| {}, |_, _| n += 1);
        n
    };
    let target = rng.below(pages);
    let field = rng.below(5);
    let value = rng.next();
    let mut r2 = Rng(value | 1);
    let mut k = 0;
    let more_rows = rng.below(3) == 0;
    let rows = extreme(rng, 0).max(1);
    rebuild(
        file,
        |meta| {
            if more_rows {
                for g in &mut meta.row_groups {
                    g.num_rows = g.num_rows.max(rows);
                }
            }
        },
        |h, _| {
            if k == target {
                let set = |x: &mut i32, rng: &mut Rng| *x = extreme(rng, i64::from(*x)) as i32;
                match field {
                    0 => set(&mut h.uncompressed_page_size, &mut r2),
                    1 => {
                        if let Some(d) = &mut h.data {
                            set(&mut d.num_values, &mut r2);
                        }
                        if let Some(d) = &mut h.data_v2 {
                            set(&mut d.num_rows, &mut r2);
                        }
                        if let Some(d) = &mut h.dictionary {
                            set(&mut d.num_values, &mut r2);
                        }
                    }
                    2 => {
                        if let Some(d) = &mut h.data_v2 {
                            set(&mut d.definition_levels_byte_length, &mut r2);
                        }
                    }
                    3 => {
                        if let Some(d) = &mut h.data_v2 {
                            d.is_compressed = !d.is_compressed;
                        }
                    }
                    _ => {
                        set(&mut h.uncompressed_page_size, &mut r2);
                        if let Some(d) = &mut h.data {
                            set(&mut d.num_values, &mut r2);
                        }
                    }
                }
            }
            k += 1;
        },
    )
}

/// Damage a copy of `file`: flip bits, overwrite bytes with extreme
/// values, or cut it short, in the footer or anywhere.
fn mutate(file: &[u8], rng: &mut Rng) -> Vec<u8> {
    let mut b = file.to_vec();
    let n = b.len();
    let footer_len = u32::from_le_bytes(b[n - 8..n - 4].try_into().unwrap()) as usize;
    let footer = n.saturating_sub(8 + footer_len)..n - 8;
    let edits = 1 + rng.below(4);
    for _ in 0..edits {
        // Half the edits land in the footer, where one byte changes much.
        let at = if rng.below(2) == 0 { footer.start + rng.below(footer.len()) } else { rng.below(n) };
        match rng.below(6) {
            0 | 1 => b[at] ^= 1 << rng.below(8),
            2 => b[at] = rng.next() as u8,
            3 => b[at] = [0x00, 0x7f, 0x80, 0xff][rng.below(4)],
            4 => {
                let v = [u32::MAX, i32::MAX as u32, 0x8000_0000, 0, rng.next() as u32][rng.below(5)].to_le_bytes();
                for (k, x) in v.iter().enumerate() {
                    if let Some(y) = b.get_mut(at + k) {
                        *y = *x;
                    }
                }
            }
            _ => {
                // A varint made longer or larger.
                b[at] |= 0x80;
            }
        }
    }
    match rng.below(10) {
        0 => b.truncate(rng.below(n)),
        // Cut out a run of bytes but keep the end, so the footer is found.
        1 => {
            let from = rng.below(n - 8);
            let len = 1 + rng.below(64);
            b.drain(from..(from + len).min(n - 8));
        }
        _ => {}
    }
    b
}

/// Read `columns` of rows `skip..skip + n`, each as its kind suggests:
/// text, bytes and decimals as text, a dictionary of text from
/// `ARROW:schema` as levels, numbers as doubles.
fn read(r: &mut Reader<dta::Bytes<&[u8]>>, columns: &[usize], skip: u64, n: u64) -> dta::Result<()> {
    let w = r.window(skip, n);
    let rows = (w.end - w.start) as usize;
    let mut floats: Vec<(Vec<f64>, Vec<u8>, Vec<i32>)> = vec![(vec![0.0; rows], vec![0; rows], vec![0; rows]); columns.len()];
    let mut outputs: Vec<Output> = Vec::new();
    for (&c, f) in columns.iter().zip(floats.iter_mut()) {
        let col = &r.columns()[c];
        outputs.push(match col.kind {
            ColumnType::Text if col.levels == Some(LevelsFrom::Rows) => Output::Levels { codes: &mut f.2, base: 1, null: 0 },
            ColumnType::Text | ColumnType::Binary | ColumnType::Decimal { .. } => Output::Text,
            _ => Output::Float64(Numbers::new(&mut f.0, f64::NAN).with_codes(&mut f.1)),
        });
    }
    let mut seen = 0usize;
    r.read(columns, skip, n, &mut outputs, |_, chunk| {
        for row in 0..chunk.rows {
            seen += chunk.row(row).map_or(0, <[u8]>::len);
        }
        Ok(())
    })
    .map(drop)
}

/// What one damaged file did: an error opening it, or how many reads it
/// took and how many failed.
fn run_case(bytes: &[u8], rng: &mut Rng) -> Result<(usize, usize, usize), String> {
    let options = ReadOptions { threads: 1, ..Default::default() };
    let len = bytes.len();
    let (opened, largest) = largest_during(|| Reader::open(dta::Bytes(bytes), options));
    if largest > bound(len, 0) {
        return Err(format!("opening asked for {largest} bytes"));
    }
    let Ok(mut r) = opened else { return Ok((0, 0, 0)) };
    let columns: Vec<usize> = (0..r.columns().len())
        .filter(|&k| {
            let c = &r.columns()[k];
            c.role == Role::Data && !matches!(c.kind, ColumnType::Unsupported(_))
        })
        .collect();
    let rows = r.rows();
    let mut windows = vec![];
    // Whole only when the outputs are of a size a test can allocate.
    if rows <= 100_000 {
        windows.push((0, u64::MAX));
    }
    for _ in 0..3 {
        let skip = rng.next() % rows.max(1);
        windows.push((skip, 1 + rng.next() % 64));
    }
    let (mut reads, mut failed) = (0, 0);
    for (skip, n) in windows {
        let w = r.window(skip, n);
        let (result, largest) = largest_during(|| read(&mut r, &columns, skip, n));
        reads += 1;
        if let Err(e) = result {
            failed += 1;
            if e.message.contains("panicked") {
                return Err(format!("rows {skip}+{n}: {}", e.message));
            }
        }
        let limit = bound(len, (w.end - w.start) as usize * columns.len().max(1));
        if largest > limit {
            return Err(format!("rows {skip}+{n} asked for {largest} bytes, more than {limit}"));
        }
    }
    Ok((1, reads, failed))
}

/// The most a read may ask for at once: a constant for codec buffers, a
/// multiple of the file (a page may expand 255 times under LZ4) and a
/// multiple of the values asked for.
fn bound(file: usize, values: usize) -> usize {
    (4 << 20) + 256 * file + 64 * values
}

#[test]
fn damaged_files_are_answers_or_errors() {
    let per_file: usize = std::env::var("DTA_FUZZ_CASES").ok().and_then(|v| v.parse().ok()).unwrap_or(200);
    let seed: u64 = std::env::var("DTA_FUZZ_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(0x5eed);
    let files = files();
    // Panics are caught and reported below; their messages need not
    // also go to the terminal.
    let quiet = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let mut failures = Vec::new();
    let (mut cases, mut opened, mut reads, mut failed) = (0, 0, 0, 0);
    for (f, (name, bytes)) in files.iter().enumerate() {
        for case in 0..per_file {
            let case_seed = seed ^ ((f as u64) << 32 | case as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15) | 1;
            let mut rng = Rng(case_seed);
            // A quarter of the cases damage fields, the rest bytes.
            let damaged = if rng.below(4) == 0 { mutate_fields(bytes, &mut rng) } else { mutate(bytes, &mut rng) };
            cases += 1;
            match catch_unwind(AssertUnwindSafe(|| run_case(&damaged, &mut rng))) {
                Ok(Ok((o, r, e))) => {
                    opened += o;
                    reads += r;
                    failed += e;
                }
                Ok(Err(why)) => failures.push(format!("{name}, seed {case_seed}: {why}")),
                Err(p) => {
                    let text = p.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| p.downcast_ref::<String>().cloned()).unwrap_or_default();
                    failures.push(format!("{name}, seed {case_seed}: panicked: {text}"));
                }
            }
        }
    }
    std::panic::set_hook(quiet);
    eprintln!("{cases} damaged files: {opened} opened; {reads} reads, {failed} of them errors; {} failures", failures.len());
    assert!(failures.is_empty(), "{} of {cases} cases failed:\n{}", failures.len(), failures.iter().take(20).cloned().collect::<Vec<_>>().join("\n"));
}
