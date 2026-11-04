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
