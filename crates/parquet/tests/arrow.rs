//! The Arrow outputs give what the other outputs give: every compat
//! fixture and tables written here, whole, in windows and with threads,
//! compared column by column with the numbers, codes, levels and text the
//! existing outputs read.
// `drop(outs)` ends the outputs' borrows of the buffers read next.
#![allow(clippy::drop_non_drop)]


mod support;

use std::path::Path;

use dta_parquet::{
    write, ArrowData, ArrowOutput, ArrowReport, ColumnType, LevelsFrom, Numbers, Output, Profile, ReadOptions, Reader,
    Role, TextChunk, WriteOptions,
};
use support::{dated_columns, every_type, storage_columns, table, Col};

fn options(threads: usize) -> ReadOptions {
    ReadOptions { threads, parallel_bytes: 0, nested: dta_parquet::Nested::Skip, ..Default::default() }
}

/// A view's bytes.
fn view_bytes(v: u128, buffers: &[Vec<u8>]) -> Vec<u8> {
    let b = v.to_le_bytes();
    let len = u32::from_le_bytes(b[..4].try_into().unwrap()) as usize;
    if len <= 12 {
        return b[4..4 + len].to_vec();
    }
    let buf = u32::from_le_bytes(b[8..12].try_into().unwrap()) as usize;
    let off = u32::from_le_bytes(b[12..16].try_into().unwrap()) as usize;
    assert_eq!(&b[4..8], &buffers[buf][off..off + 4], "a view's prefix");
    buffers[buf][off..off + len].to_vec()
}

fn bit(bits: &[u8], r: usize) -> bool {
    (bits[r / 8] >> (r % 8)) & 1 == 1
}

/// What a column reads as, by either path: per row, a value (as text, to
/// compare across types: numbers by their bits or exact value), or a
/// missing code (1 for `.`, 2 to 27 for `.a` to `.z`).
type Cells = Vec<Result<String, u8>>;

macro_rules! numeric {
    ($r:expr, $c:expr, $skip:expr, $n:expr, $t:ty, $variant:ident, $show:expr) => {{
        let rows = $r.window($skip, $n);
        let rows = (rows.end - rows.start) as usize;
        let mut values = vec![<$t>::default(); rows];
        let mut codes = vec![0u8; rows];
        let mut outs = [Output::$variant(Numbers::new(&mut values, <$t>::default()).with_codes(&mut codes))];
        $r.read(&[$c], $skip, $n, &mut outs, |_, _| Ok(())).unwrap();
        drop(outs);
        let classic: Cells =
            values.iter().zip(&codes).map(|(v, &c)| if c == 0 { Ok($show(*v)) } else { Err(c) }).collect();
        let mut values = vec![<$t>::default(); rows];
        let mut bits = vec![0u8; rows.div_ceil(8)];
        let mut outs = [Output::Arrow(ArrowOutput { validity: Some(&mut bits), data: ArrowData::$variant(&mut values) })];
        let report = $r.read(&[$c], $skip, $n, &mut outs, |_, _| Ok(())).unwrap();
        drop(outs);
        let a: &ArrowReport = report.arrow[0].as_ref().unwrap();
        let mut arrow: Cells =
            (0..rows).map(|i| if bit(&bits, i) { Ok($show(values[i])) } else { Err(1) }).collect();
        for &(row, code) in &a.letters {
            assert_eq!(arrow[row as usize], Err(1), "a letter's row is null");
            arrow[row as usize] = Err(code);
        }
        let nulls = arrow.iter().filter(|c| c.is_err()).count() as u64;
        assert_eq!(a.nulls, nulls, "the null count");
        assert_eq!(report.letters[0], !a.letters.is_empty());
        (classic, arrow)
    }};
}

fn texts<S: dta::Source>(r: &mut Reader<S>, c: usize, skip: u64, n: u64) -> (Cells, Cells) {
    let w = r.window(skip, n);
    let rows = (w.end - w.start) as usize;
    let mut classic: Cells = vec![Err(1); rows];
    let mut outs = [Output::Text];
    r.read(&[c], skip, n, &mut outs, |_, chunk: &TextChunk| {
        for i in 0..chunk.rows {
            if let Some(b) = chunk.row(i) {
                classic[chunk.first as usize + i] = Ok(format!("{b:?}"));
            }
        }
        Ok(())
    })
    .unwrap();
    let mut views = vec![0u128; rows];
    let mut bits = vec![0u8; rows.div_ceil(8)];
    let mut outs = [Output::Arrow(ArrowOutput { validity: Some(&mut bits), data: ArrowData::Views(&mut views) })];
    let report = r.read(&[c], skip, n, &mut outs, |_, _| Ok(())).unwrap();
    drop(outs);
    let a = report.arrow[0].as_ref().unwrap();
    let arrow: Cells = (0..rows)
        .map(|i| if bit(&bits, i) { Ok(format!("{:?}", view_bytes(views[i], &a.buffers))) } else { Err(1) })
        .collect();
    (classic, arrow)
}

fn keys<S: dta::Source>(r: &mut Reader<S>, c: usize, skip: u64, n: u64) -> (Cells, Cells) {
    let w = r.window(skip, n);
    let rows = (w.end - w.start) as usize;
    let mut codes = vec![0i32; rows];
    let mut outs = [Output::Levels { codes: &mut codes, base: 0, null: -1 }];
    r.read(&[c], skip, n, &mut outs, |_, _| Ok(())).unwrap();
    drop(outs);
    let classic: Cells = codes.iter().map(|&k| if k < 0 { Err(1) } else { Ok(k.to_string()) }).collect();
    let mut keys = vec![0u32; rows];
    let mut bits = vec![0u8; rows.div_ceil(8)];
    let mut outs = [Output::Arrow(ArrowOutput { validity: Some(&mut bits), data: ArrowData::Keys(&mut keys) })];
    r.read(&[c], skip, n, &mut outs, |_, _| Ok(())).unwrap();
    drop(outs);
    let arrow: Cells = (0..rows).map(|i| if bit(&bits, i) { Ok(keys[i].to_string()) } else { Err(1) }).collect();
    (classic, arrow)
}

/// Compare the two paths on every data column of `bytes`.
fn compare(label: &str, bytes: &[u8], windows: &[(u64, u64)]) -> usize {
    let mut checked = 0;
    for threads in [1, 4] {
        let mut r = Reader::open(dta::Bytes(bytes), options(threads)).unwrap();
        let cols: Vec<usize> = (0..r.columns().len()).filter(|&k| r.columns()[k].role == Role::Data).collect();
        for &c in &cols {
            let info = r.columns()[c].clone();
            let kind = info.storage.map_or_else(|| info.kind.clone(), |s| s.column_type());
            for &(skip, n) in windows {
                let (classic, arrow) = match &kind {
                    ColumnType::Int8 => numeric!(r, c, skip, n, i8, Int8, |v: i8| v.to_string()),
                    ColumnType::Int16 => numeric!(r, c, skip, n, i16, Int16, |v: i16| v.to_string()),
                    ColumnType::Int32 | ColumnType::Date => numeric!(r, c, skip, n, i32, Int32, |v: i32| v.to_string()),
                    ColumnType::Int64 | ColumnType::Timestamp { .. } | ColumnType::Time { .. } => {
                        numeric!(r, c, skip, n, i64, Int64, |v: i64| v.to_string())
                    }
                    ColumnType::UInt8 | ColumnType::Boolean => numeric!(r, c, skip, n, u8, UInt8, |v: u8| v.to_string()),
                    ColumnType::UInt16 => numeric!(r, c, skip, n, u16, UInt16, |v: u16| v.to_string()),
                    ColumnType::UInt32 => numeric!(r, c, skip, n, u32, UInt32, |v: u32| v.to_string()),
                    ColumnType::UInt64 => numeric!(r, c, skip, n, u64, UInt64, |v: u64| v.to_string()),
                    ColumnType::Float => numeric!(r, c, skip, n, f32, Float32, |v: f32| v.to_bits().to_string()),
                    ColumnType::Double => numeric!(r, c, skip, n, f64, Float64, |v: f64| v.to_bits().to_string()),
                    ColumnType::Text if info.levels == Some(LevelsFrom::Profile) => {
                        let k = keys(&mut r, c, skip, n);
                        assert_eq!(k.0, k.1, "{label}: keys of column {} rows {skip}+{n}, {threads} threads", info.name);
                        texts(&mut r, c, skip, n)
                    }
                    ColumnType::Text | ColumnType::Binary => texts(&mut r, c, skip, n),
                    _ => continue,
                };
                assert_eq!(
                    classic, arrow,
                    "{label}: column {} ({kind:?}) rows {skip}+{n}, {threads} threads",
                    info.name
                );
                checked += 1;
            }
        }
        // Every column at once, as a binding reads them.
        let mut whole = Vec::new();
        let rows = r.rows() as usize;
        let mut views: Vec<Vec<u128>> = Vec::new();
        let mut bits: Vec<Vec<u8>> = Vec::new();
        let mut doubles: Vec<Vec<f64>> = Vec::new();
        let mut which = Vec::new();
        for &c in &cols {
            let info = &r.columns()[c];
            match (&info.kind, info.storage) {
                (ColumnType::Text | ColumnType::Binary, _) => {
                    views.push(vec![0; rows]);
                    which.push((c, true));
                }
                (ColumnType::Double, None) => {
                    doubles.push(vec![0.0; rows]);
                    which.push((c, false));
                }
                _ => continue,
            }
            bits.push(vec![0; rows.div_ceil(8)]);
        }
        let (mut vi, mut di) = (views.iter_mut(), doubles.iter_mut());
        for ((_, text), b) in which.iter().zip(bits.iter_mut()) {
            let data = if *text {
                ArrowData::Views(vi.next().unwrap())
            } else {
                ArrowData::Float64(di.next().unwrap())
            };
            whole.push(Output::Arrow(ArrowOutput { validity: Some(b), data }));
        }
        let selected: Vec<usize> = which.iter().map(|w| w.0).collect();
        r.read(&selected, 0, u64::MAX, &mut whole, |_, _| Ok(())).unwrap();
    }
    checked
}

fn windows(rows: u64) -> Vec<(u64, u64)> {
    vec![(0, u64::MAX), (3, 17), (rows / 2, 1000), (rows.saturating_sub(5), 9), (rows, 4)]
}

#[test]
fn every_fixture_reads_the_same_into_arrow() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/parquet/fixtures");
    let mut n = 0;
    for entry in std::fs::read_dir(&dir).unwrap() {
        let p = entry.unwrap().path();
        if p.extension().is_some_and(|e| e == "parquet") {
            let bytes = std::fs::read(&p).unwrap();
            let rows = Reader::open(dta::Bytes(&bytes[..]), options(1)).unwrap().rows();
            n += compare(&p.display().to_string(), &bytes, &windows(rows));
        }
    }
    assert!(n > 500, "only {n} columns compared");
}

fn written(cols: &[Col], opts: &WriteOptions) -> Vec<u8> {
    let mut out = Vec::new();
    write(&table(cols, Profile::default()), &mut out, opts).unwrap();
    out
}

#[test]
fn written_tables_read_the_same_into_arrow() {
    for rows in [0usize, 1, 9, 5000] {
        let cols = every_type(rows);
        for opts in [
            WriteOptions::default(),
            WriteOptions { row_group_rows: Some(1001), page_bytes: 700, ..WriteOptions::default() },
            WriteOptions { row_group_rows: Some(7), dictionary_bytes: 64, ..WriteOptions::default() },
        ] {
            let bytes = written(&cols, &opts);
            compare(&format!("every_type({rows})"), &bytes, &windows(rows as u64));
        }
    }
    for cols in [storage_columns(), dated_columns()] {
        let bytes = written(&cols, &WriteOptions::default());
        compare("storage and dates", &bytes, &windows(cols[0].rows() as u64));
        let bytes = written(&cols, &WriteOptions { row_group_rows: Some(3), ..WriteOptions::default() });
        compare("storage and dates, 3-row groups", &bytes, &windows(cols[0].rows() as u64));
    }
}

#[test]
fn long_text_goes_into_buffers_and_nulls_need_a_bitmap() {
    use support::Data;
    let long = |r: usize| format!("{}-{}", "a long value over twelve bytes", r % 97);
    let cols = vec![Col {
        name: "t".into(),
        data: Data::Text((0..3000).map(|r| if r % 5 == 0 { None } else { Some(long(r)) }).collect()),
        codes: vec![],
    }];
    for opts in [WriteOptions::default(), WriteOptions { dictionary_bytes: 100, row_group_rows: Some(999), ..Default::default() }] {
        let bytes = written(&cols, &opts);
        compare("long text", &bytes, &windows(3000));
        // A column with nulls read without a bitmap is an error, not a
        // silent loss.
        let mut r = Reader::open(dta::Bytes(&bytes[..]), options(1)).unwrap();
        let mut views = vec![0u128; 3000];
        let mut outs = [Output::Arrow(ArrowOutput { validity: None, data: ArrowData::Views(&mut views) })];
        assert!(r.read(&[0], 0, u64::MAX, &mut outs, |_, _| Ok(())).is_err());
    }
}
