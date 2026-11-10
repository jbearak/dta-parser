//! Files made to attack the reader: page headers that ask for memory the
//! page cannot fill, lengths that overflow 32-bit arithmetic, and schema
//! elements that are not columns. Each must be an error (or, for a valid
//! but extreme file, a read), never a panic or a huge allocation.

mod counting;
mod support;

use counting::{largest_during, Counting};
use dta_parquet::format::{
    Codec, ColumnChunk, ColumnMetaData, DataPageHeader, DictionaryPageHeader, Encoding, FileMetaData, PageHeader,
    PageType, PhysicalType, Repetition, RowGroup, SchemaElement,
};
use dta_parquet::{write, Compression, Numbers, Output, Profile, ReadOptions, Reader, WriteOptions};
use support::{finish, rebuild, table, Col, Data};

#[global_allocator]
static ALLOC: Counting = Counting;

const MIB: usize = 1 << 20;

fn one_thread() -> ReadOptions {
    ReadOptions { threads: 1, ..Default::default() }
}

/// A file of one column, `element`, with `rows` rows in one row group
/// whose chunk is `pages`, uncompressed.
fn one_column(element: SchemaElement, rows: i64, pages: &[(PageHeader, Vec<u8>)]) -> Vec<u8> {
    let mut out = b"PAR1".to_vec();
    let first_data = 4 + pages.iter().take_while(|(h, _)| h.kind == PageType::Dictionary).map(|(h, b)| page_len(h) + b.len()).sum::<usize>();
    let has_dictionary = pages.first().is_some_and(|(h, _)| h.kind == PageType::Dictionary);
    for (h, body) in pages {
        h.write(&mut out);
        out.extend_from_slice(body);
    }
    let chunk = (out.len() - 4) as i64;
    let meta = FileMetaData {
        version: 1,
        schema: vec![SchemaElement { name: "schema".into(), num_children: Some(1), ..Default::default() }, element.clone()],
        num_rows: rows,
        row_groups: vec![RowGroup {
            columns: vec![ColumnChunk {
                file_path: None,
                meta: Some(ColumnMetaData {
                    physical: element.physical.unwrap(),
                    encodings: vec![Encoding::Plain, Encoding::Rle],
                    path: vec![element.name.clone()],
                    codec: Codec::Uncompressed,
                    num_values: rows,
                    total_uncompressed_size: chunk,
                    total_compressed_size: chunk,
                    data_page_offset: first_data as i64,
                    dictionary_page_offset: has_dictionary.then_some(4),
                    statistics: None,
                }),
                offset_index: None,
                encrypted: false,
            }],
            total_byte_size: chunk,
            num_rows: rows,
            file_offset: None,
            total_compressed_size: None,
            ordinal: None,
        }],
        key_value: vec![],
        created_by: None,
        column_orders: None,
        encrypted: false,
    };
    finish(out, &meta)
}

fn page_len(h: &PageHeader) -> usize {
    let mut b = Vec::new();
    h.write(&mut b);
    b.len()
}

fn data_page(rows: i32, encoding: Encoding, body: Vec<u8>) -> (PageHeader, Vec<u8>) {
    let header = PageHeader {
        kind: PageType::Data,
        uncompressed_page_size: body.len() as i32,
        compressed_page_size: body.len() as i32,
        data: Some(DataPageHeader {
            num_values: rows,
            encoding,
            definition_level_encoding: Encoding::Rle,
            repetition_level_encoding: Encoding::Rle,
        }),
        dictionary: None,
        data_v2: None,
    };
    (header, body)
}

fn element(name: &str, p: PhysicalType, repetition: Repetition) -> SchemaElement {
    SchemaElement { name: name.into(), physical: Some(p), repetition: Some(repetition), ..Default::default() }
}

fn varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push(v as u8 | 0x80);
        v >>= 7;
    }
    out.push(v as u8);
}

fn doubles_file(compression: Compression) -> Vec<u8> {
    let n = 1000;
    let cols = vec![Col {
        name: "x".into(),
        data: Data::F64((0..n).map(|r| r as f64 * 0.25).collect()),
        codes: (0..n).map(|r| u8::from(r % 7 == 3)).collect(),
    }];
    let mut out = Vec::new();
    let options = WriteOptions { compression, ..Default::default() };
    write(&table(&cols, Profile::default()), &mut out, &options).unwrap();
    out
}

fn read_doubles(bytes: &[u8], skip: u64, n: u64) -> dta::Result<(Vec<f64>, Vec<u8>)> {
    let mut r = Reader::open(dta::Bytes(bytes), one_thread())?;
    let w = r.window(skip, n);
    let rows = (w.end - w.start) as usize;
    let (mut v, mut c) = (vec![0.0; rows], vec![0u8; rows]);
    {
        let mut outs = [Output::Float64(Numbers::new(&mut v, -1.0).with_codes(&mut c))];
        r.read(&[0], skip, n, &mut outs, |_, _| Ok(()))?;
    }
    Ok((v, c))
}

// ---- S1: memory follows the bytes present and the rows asked for ----

/// A small compressed page whose header says it holds about 2 GiB is an
/// error, and the read never asks for more than a few MiB.
#[test]
fn a_page_header_cannot_claim_gigabytes() {
    for c in [Compression::None, Compression::Snappy, Compression::Gzip, Compression::Zstd, Compression::Lz4Raw] {
        let good = doubles_file(c);
        assert!(read_doubles(&good, 0, u64::MAX).is_ok(), "{c:?}");
        let bad = rebuild(&good, |_| {}, |h, body| {
            if h.kind == PageType::Data {
                h.uncompressed_page_size = i32::MAX;
                if c == Compression::Snappy {
                    // Snappy data begins with its length: claim the same.
                    let mut at = 0;
                    while body[at] & 0x80 != 0 {
                        at += 1;
                    }
                    body.splice(..=at, [0xff, 0xff, 0xff, 0xff, 0x07]);
                }
            }
        });
        let (result, largest) = largest_during(|| read_doubles(&bad, 0, u64::MAX));
        assert!(result.is_err(), "{c:?}");
        assert!(largest <= 4 * MIB, "{c:?}: asked for {largest} bytes");
    }
}

/// An all-null page of two billion rows is one RLE run of a few bytes: a
/// one-row window at either end reads, needing memory for that row only.
#[test]
fn a_long_null_run_reads_a_row_at_a_time() {
    let rows = 2_000_000_000i64;
    let mut levels = Vec::new();
    varint(&mut levels, (rows as u64) << 1);
    levels.push(0);
    let mut body = (levels.len() as u32).to_le_bytes().to_vec();
    body.extend_from_slice(&levels);
    let file = one_column(element("x", PhysicalType::Int32, Repetition::Optional), rows, &[data_page(rows as i32, Encoding::Plain, body)]);
    for skip in [0, rows as u64 / 2, rows as u64 - 1] {
        let (result, largest) = largest_during(|| {
            let mut r = Reader::open(dta::Bytes(&file[..]), one_thread()).unwrap();
            let (mut v, mut c) = ([7i32], [9u8]);
            let mut outs = [Output::Int32(Numbers::new(&mut v, -1).with_codes(&mut c))];
            r.read(&[0], skip, 1, &mut outs, |_, _| Ok(())).map(|_| (v, c))
        });
        assert_eq!(result.unwrap(), ([-1], [1]), "row {skip}");
        assert!(largest <= MIB, "row {skip}: asked for {largest} bytes");
    }
}

// ---- S2: lengths near 2^32 do not overflow ----

/// Four-byte lengths of 0xffffffff, in a text value, a dictionary entry,
/// a page's levels and an RLE boolean page. On a 32-bit target such as
/// wasm32, adding to them overflowed; each must be an error.
#[test]
fn lengths_of_four_gigabytes_are_errors() {
    let huge = 0xffff_ffffu32.to_le_bytes();
    let with = |tail: &[u8]| [&huge[..], tail].concat();
    let text = one_column(element("s", PhysicalType::ByteArray, Repetition::Required), 1, &[data_page(1, Encoding::Plain, with(b"abc"))]);
    let dictionary = one_column(
        element("s", PhysicalType::ByteArray, Repetition::Required),
        1,
        &[
            (
                PageHeader {
                    kind: PageType::Dictionary,
                    uncompressed_page_size: 7,
                    compressed_page_size: 7,
                    data: None,
                    dictionary: Some(DictionaryPageHeader { num_values: 1, encoding: Encoding::Plain }),
                    data_v2: None,
                },
                with(b"abc"),
            ),
            data_page(1, Encoding::RleDictionary, vec![1, 2, 0]),
        ],
    );
    let levels = one_column(element("x", PhysicalType::Int32, Repetition::Optional), 1, &[data_page(1, Encoding::Plain, with(&[2, 1, 7, 0, 0, 0]))]);
    let booleans = one_column(element("b", PhysicalType::Boolean, Repetition::Required), 1, &[data_page(1, Encoding::Rle, with(&[2, 1]))]);
    for (what, file, text) in [("text", text, true), ("dictionary", dictionary, true), ("levels", levels, false), ("booleans", booleans, false)] {
        let mut r = Reader::open(dta::Bytes(&file[..]), one_thread()).unwrap();
        let (mut v, mut c) = ([0i32], [0u8]);
        let mut outs = [if text { Output::Text } else { Output::Int32(Numbers::new(&mut v, -1).with_codes(&mut c)) }];
        let e = r.read(&[0], 0, 1, &mut outs, |_, _| Ok(())).unwrap_err();
        assert!(e.message.contains("past the") || e.message.contains("ends early"), "{what}: {}", e.message);
    }
}

// ---- S3: a schema element that is not a column ----

/// A group with no children and no type has no column chunk; opening
/// such a file is an error naming it, rather than a reader that panics
/// when asked for the chunk.
#[test]
fn an_empty_group_is_not_a_column() {
    let meta = FileMetaData {
        version: 1,
        schema: vec![
            SchemaElement { name: "schema".into(), num_children: Some(1), ..Default::default() },
            SchemaElement { name: "g".into(), repetition: Some(Repetition::Optional), ..Default::default() },
        ],
        num_rows: 1,
        row_groups: vec![RowGroup {
            columns: vec![],
            total_byte_size: 0,
            num_rows: 1,
            file_offset: None,
            total_compressed_size: None,
            ordinal: None,
        }],
        key_value: vec![],
        created_by: None,
        column_orders: None,
        encrypted: false,
    };
    let file = finish(b"PAR1".to_vec(), &meta);
    let Err(e) = Reader::open(dta::Bytes(&file[..]), one_thread()).map(|mut r| r.plan(&[0], 0, 1)) else {
        panic!("an error, not a reader");
    };
    assert!(e.message.contains("\"g\"") && e.message.contains("neither a type nor children"), "{}", e.message);
}

// ---- S4: the damage plan 0018 names ----

/// Read `columns` of rows `skip..skip + n` into the Arrow outputs, which
/// decode through their own kernels (`columnar.rs`): text and bytes as
/// views, DECIMAL as text, numbers into a type that holds every value.
fn read_arrow<S: dta::Source>(r: &mut Reader<S>, columns: &[usize], skip: u64, n: u64) -> dta::Result<()> {
    use dta_parquet::ColumnType::*;
    use dta_parquet::{ArrowData, ArrowOutput};
    let w = r.window(skip, n);
    let rows = (w.end - w.start) as usize;
    // A column's doubles, integers, unsigned integers, views and bits.
    type Store = (Vec<f64>, Vec<i64>, Vec<u64>, Vec<u128>, Vec<u8>);
    let mut store: Vec<Store> =
        vec![(vec![0.0; rows], vec![0; rows], vec![0; rows], vec![0; rows], vec![0; rows.div_ceil(8)]); columns.len()];
    let mut outs: Vec<Output> = columns
        .iter()
        .zip(store.iter_mut())
        .map(|(&c, v)| {
            let data = match r.columns()[c].kind {
                Decimal { .. } => return Output::Text,
                Text | Binary => ArrowData::Views(&mut v.3),
                Float | Double => ArrowData::Float64(&mut v.0),
                UInt8 | UInt16 | UInt32 | UInt64 => ArrowData::UInt64(&mut v.2),
                _ => ArrowData::Int64(&mut v.1),
            };
            Output::Arrow(ArrowOutput { validity: Some(&mut v.4), data })
        })
        .collect();
    r.read(columns, skip, n, &mut outs, |_, _| Ok(())).map(drop)
}

/// Read every column of `file`, whole and as a window (which, without an
/// offset index, walks the page headers), on one thread and on four.
fn read_all(file: &[u8]) -> Vec<dta::Result<()>> {
    let mut out = Vec::new();
    for threads in [1, 4] {
        for (skip, n) in [(0, u64::MAX), (430, 20)] {
            let options = ReadOptions { threads, parallel_bytes: 0, ..Default::default() };
            let result = Reader::open(dta::Bytes(file), options).and_then(|mut r| {
                let columns = r.data_columns()?;
                let w = r.window(skip, n);
                let rows = (w.end - w.start) as usize;
                // Each kind into a type that holds every value.
                let mut store: Vec<(Vec<f64>, Vec<i64>, Vec<u64>)> = vec![(vec![0.0; rows], vec![0; rows], vec![0; rows]); columns.len()];
                let mut outs: Vec<Output> = columns
                    .iter()
                    .zip(store.iter_mut())
                    .map(|(&c, v)| {
                        use dta_parquet::ColumnType::*;
                        match r.columns()[c].kind {
                            Text | Binary | Decimal { .. } => Output::Text,
                            Float | Double => Output::Float64(Numbers::new(&mut v.0, -1.0)),
                            UInt8 | UInt16 | UInt32 | UInt64 => Output::UInt64(Numbers::new(&mut v.2, 0)),
                            _ => Output::Int64(Numbers::new(&mut v.1, -1)),
                        }
                    })
                    .collect();
                r.read(&columns, skip, n, &mut outs, |_, _| Ok(())).map(drop)
            });
            out.push(result);
            // The same through the Arrow outputs, which have their own kernels.
            let arrow = Reader::open(dta::Bytes(file), options).and_then(|mut r| {
                let columns = r.data_columns()?;
                read_arrow(&mut r, &columns, skip, n)
            });
            out.push(arrow);
        }
    }
    out
}

/// Each read is an error naming a column and a row group, at a byte
/// offset inside the file.
fn named_errors(what: &str, file: &[u8], column: Option<&str>) {
    for result in read_all(file) {
        let e = result.expect_err(what);
        let named = match column {
            Some(c) => e.message.contains(&format!("column \"{c}\"")),
            None => e.message.contains("column \""),
        };
        assert!(named && e.message.contains(", row group "), "{what}: {}", e.message);
        let offset = e.offset.unwrap_or_else(|| panic!("{what}: no offset in {}", e.message));
        assert!(offset < file.len() as u64, "{what}: offset {offset}");
    }
}

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../compat/parquet/fixtures/").to_string() + name).unwrap()
}

#[test]
fn a_bad_magic_number_or_footer_length_is_an_error() {
    let good = doubles_file(Compression::Zstd);
    for (what, at) in [("start", 0), ("end", good.len() - 1)] {
        let mut bad = good.clone();
        bad[at] ^= 0x20;
        let e = Reader::open(dta::Bytes(&bad[..]), one_thread()).err().unwrap();
        assert!(e.message.contains("PAR1"), "{what}: {}", e.message);
    }
    // A footer longer than the file, and one longer than all but the
    // magic numbers.
    for claimed in [u32::MAX, good.len() as u32 - 11] {
        let mut bad = good.clone();
        let n = bad.len();
        bad[n - 8..n - 4].copy_from_slice(&claimed.to_le_bytes());
        let e = Reader::open(dta::Bytes(&bad[..]), one_thread()).err().unwrap();
        assert!(e.message.contains("footer") && e.offset == Some(n as u64 - 8), "{}", e);
    }
}

#[test]
fn a_page_whose_size_does_not_match_its_header_is_an_error() {
    for c in [Compression::None, Compression::Snappy, Compression::Gzip, Compression::Zstd, Compression::Lz4Raw] {
        let good = doubles_file(c);
        assert!(read_all(&good).iter().all(Result::is_ok), "{c:?}");
        // The uncompressed size one more or one less than the page holds.
        for delta in [1, -1] {
            let bad = rebuild(&good, |_| {}, |h, _| {
                if h.kind == PageType::Data {
                    h.uncompressed_page_size += delta;
                }
            });
            named_errors(&format!("{c:?}, size {delta:+}"), &bad, Some("x"));
        }
        // A chunk that ends inside its last page.
        let bad = rebuild(&good, |m| m.row_groups[0].columns[0].meta.as_mut().unwrap().total_compressed_size -= 1, |_, _| {});
        named_errors(&format!("{c:?}, chunk cut short"), &bad, Some("x"));
    }
}

#[test]
fn a_page_that_fails_to_decompress_is_an_error() {
    let mut files: Vec<(String, Vec<u8>, Option<&str>)> = [Compression::Snappy, Compression::Gzip, Compression::Zstd, Compression::Lz4Raw]
        .into_iter()
        .map(|c| (format!("{c:?}"), doubles_file(c), Some("x")))
        .collect();
    files.push(("brotli (pyarrow)".into(), fixture("pyarrow_brotli.parquet"), None));
    files.push(("brotli (fastparquet)".into(), fixture("fastparquet_int96_brotli.parquet"), None));
    files.push(("snappy, DELTA (pyarrow)".into(), fixture("pyarrow_delta_v2.parquet"), None));
    for (what, good, column) in files {
        assert!(read_all(&good).iter().all(Result::is_ok), "{what}");
        // Cut each data page's compressed bytes in half, or scramble them.
        for cut in [true, false] {
            let bad = rebuild(&good, |_| {}, |h, body| {
                if matches!(h.kind, PageType::Data | PageType::DataV2) && body.len() > 4 {
                    if cut {
                        body.truncate(body.len() / 2);
                    } else {
                        let n = body.len();
                        for b in &mut body[n / 4..] {
                            *b = b.wrapping_mul(31).wrapping_add(7);
                        }
                    }
                }
            });
            named_errors(&format!("{what}, {}", if cut { "cut" } else { "scrambled" }), &bad, column);
        }
    }
}

// ---- S5: pages no fixture has ----

fn zigzag(out: &mut Vec<u8>, v: i64) {
    varint(out, ((v << 1) ^ (v >> 63)) as u64);
}

/// A DELTA_BINARY_PACKED page of two billion values in one block of
/// width 0 is a few bytes: a one-row window at its end reads at once,
/// needing memory for that row only.
#[test]
fn a_delta_page_of_two_billion_values_reads_a_row_at_a_time() {
    let rows = 2_000_000_000i64;
    let mut body = Vec::new();
    varint(&mut body, 1 << 31); // values per block
    varint(&mut body, 1); // miniblocks per block
    varint(&mut body, rows as u64);
    zigzag(&mut body, 5); // the first value
    zigzag(&mut body, 3); // the block's minimum delta
    body.push(0); // its one miniblock's bit width
    let file = one_column(element("x", PhysicalType::Int64, Repetition::Required), rows, &[data_page(rows as i32, Encoding::DeltaBinaryPacked, body)]);
    for skip in [0, rows as u64 - 1] {
        let (result, largest) = largest_during(|| {
            let mut r = Reader::open(dta::Bytes(&file[..]), one_thread()).unwrap();
            let mut v = [0i64];
            let mut outs = [Output::Int64(Numbers::new(&mut v, -1))];
            r.read(&[0], skip, 1, &mut outs, |_, _| Ok(())).map(|_| v[0])
        });
        assert_eq!(result.unwrap(), 5 + 3 * skip as i64);
        assert!(largest <= MIB, "row {skip}: asked for {largest} bytes");
    }
}

/// DECIMAL in a BYTE_ARRAY: big-endian two's complement of any length up
/// to 32 bytes, as text with every digit, or as doubles while a value has
/// at most 15 significant digits.
#[test]
fn byte_array_decimals() {
    let values: [&[u8]; 4] = [&[0x01], &[0xff, 0x85], &[0x00, 0x00, 0x30, 0x39], &12_345_678_901_234_567_890_123i128.to_be_bytes()[6..]];
    let mut body = Vec::new();
    for v in values {
        body.extend_from_slice(&(v.len() as u32).to_le_bytes());
        body.extend_from_slice(v);
    }
    let decimal = SchemaElement {
        logical: Some(dta_parquet::format::LogicalType::Decimal { scale: 3, precision: 40 }),
        ..element("d", PhysicalType::ByteArray, Repetition::Required)
    };
    let file = one_column(decimal, 4, &[data_page(4, Encoding::Plain, body)]);
    let mut r = Reader::open(dta::Bytes(&file[..]), one_thread()).unwrap();
    assert_eq!(r.columns()[0].kind, dta_parquet::ColumnType::Decimal { precision: 40, scale: 3 });
    let mut text = Vec::new();
    r.read(&[0], 0, 4, &mut [Output::Text], |_, chunk| {
        for row in 0..chunk.rows {
            text.push(String::from_utf8(chunk.row(row).unwrap().to_vec()).unwrap());
        }
        Ok(())
    })
    .unwrap();
    assert_eq!(text, ["0.001", "-0.123", "12.345", "12345678901234567890.123"]);
    let mut v = [0.0; 3];
    r.read(&[0], 0, 3, &mut [Output::Float64(Numbers::new(&mut v, -1.0))], |_, _| Ok(())).unwrap();
    assert_eq!(v, [0.001, -0.123, 12.345]);
    let mut v = [0.0; 4];
    let e = r.read(&[0], 0, 4, &mut [Output::Float64(Numbers::new(&mut v, -1.0))], |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("column \"d\"") && e.message.contains("row 4") && e.message.contains("text"), "{}", e.message);
    // Only doubles and text read a DECIMAL.
    let mut f = [0f32; 1];
    assert!(r.read(&[0], 0, 1, &mut [Output::Float32(Numbers::new(&mut f, 0.0))], |_, _| Ok(())).is_err());
}

/// An all-null BYTE_STREAM_SPLIT page of a FIXED_LEN_BYTE_ARRAY column
/// whose declared width is 2 GiB has no value bytes to bound that width:
/// reading it must not allocate the width.
#[test]
fn an_all_null_split_page_does_not_allocate_its_width() {
    let rows = 4i64;
    let mut levels = Vec::new();
    varint(&mut levels, (rows as u64) << 1);
    levels.push(0);
    let mut body = (levels.len() as u32).to_le_bytes().to_vec();
    body.extend_from_slice(&levels);
    let mut col = element("x", PhysicalType::FixedLenByteArray, Repetition::Optional);
    col.type_length = Some(i32::MAX);
    let file = one_column(col, rows, &[data_page(rows as i32, Encoding::ByteStreamSplit, body)]);
    let (result, largest) = largest_during(|| {
        let mut r = Reader::open(dta::Bytes(&file[..]), one_thread())?;
        r.read(&[0], 0, rows as u64, &mut [Output::Text], |_, _| Ok(()))
    });
    assert!(largest <= MIB, "asked for {largest} bytes");
    result.unwrap();
}
