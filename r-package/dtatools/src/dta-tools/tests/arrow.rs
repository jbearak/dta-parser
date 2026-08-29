use std::cell::Cell;
use std::collections::HashMap;
use std::io::{Cursor, Read, Seek, SeekFrom};
use std::sync::Arc;

use arrow_array::{
    Array, ArrayRef, BooleanArray, DictionaryArray, Float32Array, Float64Array, Int16Array,
    Int32Array, Int64Array, Int8Array, RecordBatch, StringArray,
};
use arrow_ipc::reader::FileReader;
use arrow_ipc::writer::{DictionaryHandling, FileWriter, IpcWriteOptions};
use arrow_schema::{DataType, Field, Schema};

use dta_tools::arrow::{
    arrow_stored_signature, dataset_signature, read_arrow_file, read_arrow_file_from,
    save_arrow_file_to, ArrowCompression, ArrowFieldDocument, ArrowMissingEncoding,
    ArrowProfileError, ArrowRSemantics, ArrowReadOptions, ArrowWriteColumn, ArrowWriteDataset,
    DatasetDocument, StataStorage, ARROW_CHECKSUMS_KEY, ARROW_FIELD_KEY, ARROW_PROFILE_VERSION_KEY,
};
use dta_tools::{ValueLabelEntry, ValueLabelTable};

fn no_interrupt() -> impl FnMut() -> bool {
    || false
}

fn read_all_options() -> ArrowReadOptions {
    ArrowReadOptions {
        columns: None,
        row_start: 0,
        row_count: None,
        verify: true,
        profile: true,
        threads: 1,
    }
}

fn write_to_vec(dataset: &ArrowWriteDataset, compression: ArrowCompression) -> Vec<u8> {
    let mut bytes = Vec::new();
    save_arrow_file_to(
        &mut bytes,
        dataset,
        compression,
        64,
        1,
        true,
        &mut no_interrupt(),
    )
    .expect("write succeeds");
    bytes
}

fn field_document(
    storage: Option<StataStorage>,
    missing: Option<ArrowMissingEncoding>,
    class: &str,
) -> ArrowFieldDocument {
    ArrowFieldDocument {
        version: 0,
        label: format!("label for a {class} column"),
        format: String::new(),
        storage,
        value_labels: None,
        missing,
        r: Some(ArrowRSemantics {
            class: class.to_owned(),
            ordered: None,
            tz: None,
            units: None,
        }),
    }
}

fn concat_chunks(chunks: &[ArrayRef]) -> ArrayRef {
    let refs: Vec<&dyn Array> = chunks.iter().map(AsRef::as_ref).collect();
    arrow_select::concat::concat(&refs).expect("chunks concatenate")
}

#[test]
fn standard_and_profiled_columns_round_trip_with_metadata() {
    let mut dataset_document = DatasetDocument {
        version: 0,
        label: "test dataset".to_owned(),
        notes: vec!["first note".to_owned(), "second note".to_owned()],
        ..DatasetDocument::default()
    };
    dataset_document.insert_value_label_table(&ValueLabelTable {
        name: "yesno".to_owned(),
        entries: vec![
            ValueLabelEntry {
                value: 0,
                missing_tag: None,
                label: "no".to_owned(),
            },
            ValueLabelEntry {
                value: 1,
                missing_tag: None,
                label: "yes".to_owned(),
            },
        ],
    });

    let logical: ArrayRef = Arc::new(BooleanArray::from(vec![
        Some(true),
        None,
        Some(false),
        Some(true),
    ]));
    let strings: ArrayRef = Arc::new(StringArray::from(vec![
        Some("alpha"),
        Some("beta"),
        None,
        Some("delta"),
    ]));
    let keys = Int32Array::from(vec![Some(0), Some(1), None, Some(0)]);
    let values = StringArray::from(vec!["low", "high"]);
    let factor: ArrayRef =
        Arc::new(DictionaryArray::try_new(keys, Arc::new(values)).expect("valid dictionary"));
    // Profiled columns in raw Stata missing storage: sentinel integers, no
    // validity bitmap.
    let stata_byte: ArrayRef = Arc::new(Int8Array::from(vec![1, 101, 102, 127]));
    let stata_int: ArrayRef = Arc::new(Int16Array::from(vec![7, 32741, 32742, 32767]));
    let stata_float: ArrayRef = Arc::new(Float32Array::from(vec![
        1.5,
        f32::from_bits(0x7f000000),
        f32::from_bits(0x7f000800),
        f32::from_bits(0x7f00d000),
    ]));

    let dataset = ArrowWriteDataset {
        dataset: dataset_document.clone(),
        columns: vec![
            ArrowWriteColumn {
                name: "flag".to_owned(),
                field: None,
                array: logical.clone(),
            },
            ArrowWriteColumn {
                name: "name".to_owned(),
                field: None,
                array: strings.clone(),
            },
            ArrowWriteColumn {
                name: "grade".to_owned(),
                field: Some(ArrowFieldDocument {
                    r: Some(ArrowRSemantics {
                        class: "factor".to_owned(),
                        ordered: Some(true),
                        ..ArrowRSemantics::default()
                    }),
                    ..ArrowFieldDocument::default()
                }),
                array: factor.clone(),
            },
            ArrowWriteColumn {
                name: "b".to_owned(),
                field: Some(field_document(
                    Some(StataStorage::Byte),
                    Some(ArrowMissingEncoding::Sentinel),
                    "stata_numeric",
                )),
                array: stata_byte.clone(),
            },
            ArrowWriteColumn {
                name: "i".to_owned(),
                field: Some(field_document(
                    Some(StataStorage::Int),
                    Some(ArrowMissingEncoding::Sentinel),
                    "stata_numeric",
                )),
                array: stata_int.clone(),
            },
            ArrowWriteColumn {
                name: "f".to_owned(),
                field: Some(field_document(
                    Some(StataStorage::Float),
                    Some(ArrowMissingEncoding::Payload),
                    "stata_numeric",
                )),
                array: stata_float.clone(),
            },
        ],
    };

    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let mut cursor = Cursor::new(&bytes);
    let result = read_arrow_file_from(&mut cursor, &read_all_options(), &mut no_interrupt())
        .expect("read succeeds");

    assert_eq!(result.profile_version.as_deref(), Some("0"));
    assert_eq!(result.row_count, 4);
    let read_dataset = result.dataset.expect("profiled file has a dataset");
    assert_eq!(read_dataset, dataset_document);
    assert_eq!(
        read_dataset
            .value_label_table("yesno")
            .expect("table survives")
            .entries
            .len(),
        2
    );

    let expected: Vec<(&str, &ArrayRef)> = vec![
        ("flag", &logical),
        ("name", &strings),
        ("grade", &factor),
        ("b", &stata_byte),
        ("i", &stata_int),
        ("f", &stata_float),
    ];
    for (column, (name, array)) in result.columns.iter().zip(expected) {
        assert_eq!(column.name, name);
        assert_eq!(&concat_chunks(&column.chunks), array, "column `{name}`");
    }
    // Profiled columns are non-nullable; standard ones stay nullable.
    assert!(result.columns[0].nullable);
    assert!(!result.columns[3].nullable);
    assert_eq!(
        result.columns[3]
            .field
            .as_ref()
            .and_then(|document| document.storage),
        Some(StataStorage::Byte)
    );
    assert_eq!(
        result.columns[2]
            .field
            .as_ref()
            .and_then(|document| document.r.as_ref())
            .and_then(|semantics| semantics.ordered),
        Some(true)
    );

    // Float sentinel bit patterns survive bit-exactly.
    let read_float = concat_chunks(&result.columns[5].chunks);
    let read_float = read_float
        .as_any()
        .downcast_ref::<Float32Array>()
        .expect("float column");
    assert_eq!(read_float.value(1).to_bits(), 0x7f000000);
    assert_eq!(read_float.value(3).to_bits(), 0x7f00d000);
}

#[test]
fn nan_payloads_survive_bit_exactly() {
    let tagged =
        |letter: u32| f64::from_bits(0x7ff0_0000_0000_07a2_u64 | (u64::from(letter) << 32));
    let doubles: ArrayRef = Arc::new(Float64Array::from(vec![
        1.25,
        tagged(1),
        tagged(26),
        f64::from_bits(0x7ff0_0000_0000_0000),
    ]));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "x".to_owned(),
            field: Some(field_document(
                None,
                Some(ArrowMissingEncoding::Payload),
                "double",
            )),
            array: doubles.clone(),
        }],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let result = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect("read succeeds");
    let read = concat_chunks(&result.columns[0].chunks);
    let read = read
        .as_any()
        .downcast_ref::<Float64Array>()
        .expect("double column");
    let written = doubles
        .as_any()
        .downcast_ref::<Float64Array>()
        .expect("double column");
    for row in 0..written.len() {
        assert_eq!(read.value(row).to_bits(), written.value(row).to_bits());
    }
}

/// A reader that counts every byte read, to check that projection I/O is
/// proportional to the selected columns' buffers.
struct CountingReader<'a> {
    inner: Cursor<&'a [u8]>,
    bytes_read: Cell<u64>,
}

impl Read for CountingReader<'_> {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        let count = self.inner.read(buffer)?;
        self.bytes_read.set(self.bytes_read.get() + count as u64);
        Ok(count)
    }
}

impl Seek for CountingReader<'_> {
    fn seek(&mut self, position: SeekFrom) -> std::io::Result<u64> {
        self.inner.seek(position)
    }
}

#[test]
fn projection_reads_io_proportional_to_selected_columns() {
    let rows = 4096_usize;
    let wide: Vec<Option<String>> = (0..rows).map(|row| Some(format!("{row:0>512}"))).collect();
    let wide: ArrayRef = Arc::new(StringArray::from(
        wide.iter()
            .map(|value| value.as_deref())
            .collect::<Vec<_>>(),
    ));
    let narrow: ArrayRef = Arc::new(Int32Array::from((0..rows as i32).collect::<Vec<_>>()));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![
            ArrowWriteColumn {
                name: "wide".to_owned(),
                field: None,
                array: wide,
            },
            ArrowWriteColumn {
                name: "narrow".to_owned(),
                field: None,
                array: narrow.clone(),
            },
        ],
    };
    let mut bytes = Vec::new();
    save_arrow_file_to(
        &mut bytes,
        &dataset,
        ArrowCompression::Uncompressed,
        1024,
        1,
        true,
        &mut no_interrupt(),
    )
    .expect("write succeeds");

    let mut reader = CountingReader {
        inner: Cursor::new(bytes.as_slice()),
        bytes_read: Cell::new(0),
    };
    let options = ArrowReadOptions {
        columns: Some(vec![1]),
        // Skip checksum verification so the wide column's buffers need not be
        // touched at all.
        verify: false,
        ..read_all_options()
    };
    let result =
        read_arrow_file_from(&mut reader, &options, &mut no_interrupt()).expect("read succeeds");
    assert_eq!(result.columns.len(), 1);
    assert_eq!(&concat_chunks(&result.columns[0].chunks), &narrow);

    // The narrow column's values are 4 bytes per row. Everything else read is
    // footer, headers, and the narrow column's buffers; the wide column is
    // ~512 bytes per row and must remain untouched.
    let total = bytes.len() as u64;
    let narrow_bytes = (rows * 4) as u64;
    assert!(
        reader.bytes_read.get() < narrow_bytes + total / 10,
        "projected read touched {} of {} bytes",
        reader.bytes_read.get(),
        total
    );
}

#[test]
fn skip_and_limit_slice_across_batch_boundaries() {
    let rows = 200_i32;
    let values: ArrayRef = Arc::new(Int32Array::from((0..rows).collect::<Vec<_>>()));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "x".to_owned(),
            field: None,
            array: values,
        }],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let options = ArrowReadOptions {
        row_start: 70,
        row_count: Some(100),
        ..read_all_options()
    };
    let result = read_arrow_file_from(&mut Cursor::new(&bytes), &options, &mut no_interrupt())
        .expect("read succeeds");
    assert_eq!(result.row_count, 100);
    let read = concat_chunks(&result.columns[0].chunks);
    let expected: ArrayRef = Arc::new(Int32Array::from((70..170).collect::<Vec<_>>()));
    assert_eq!(&read, &expected);

    // A window that starts past the end of the data returns zero rows.
    let past_the_end = ArrowReadOptions {
        row_start: 500,
        ..read_all_options()
    };
    let empty = read_arrow_file_from(&mut Cursor::new(&bytes), &past_the_end, &mut no_interrupt())
        .expect("read succeeds");
    assert_eq!(empty.row_count, 0);
    assert!(empty.columns[0].chunks.is_empty());
    assert_eq!(empty.columns[0].data_type, DataType::Int32);
}

#[test]
fn corrupted_buffers_fail_verification_by_default() {
    let values: ArrayRef = Arc::new(Int32Array::from((1000..1064).collect::<Vec<_>>()));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "x".to_owned(),
            field: None,
            array: values,
        }],
    };
    let mut bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);

    // Flip one bit inside the stored little-endian value 1003.
    let needle = 1003_i32.to_le_bytes();
    let position = bytes
        .windows(4)
        .position(|window| window == needle)
        .expect("value bytes are stored verbatim");
    bytes[position] ^= 0x01;

    let error = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("verification fails");
    match error {
        ArrowProfileError::ChecksumMismatch { column, batch } => {
            assert_eq!(column, "x");
            assert_eq!(batch, 0);
        }
        other => panic!("expected a checksum mismatch, got {other}"),
    }

    // The escape hatch reads the corrupted value.
    let options = ArrowReadOptions {
        verify: false,
        ..read_all_options()
    };
    let result = read_arrow_file_from(&mut Cursor::new(&bytes), &options, &mut no_interrupt())
        .expect("unverified read succeeds");
    let read = concat_chunks(&result.columns[0].chunks);
    let read = read
        .as_any()
        .downcast_ref::<Int32Array>()
        .expect("integer column");
    assert_eq!(read.value(3), 1002);
}

#[test]
fn compressed_files_round_trip_and_verify() {
    let values: ArrayRef = Arc::new(Int32Array::from((0..1000).collect::<Vec<_>>()));
    let strings: Vec<Option<String>> = (0..1000).map(|row| Some(format!("row {row}"))).collect();
    let strings: ArrayRef = Arc::new(StringArray::from(
        strings
            .iter()
            .map(|value| value.as_deref())
            .collect::<Vec<_>>(),
    ));
    for compression in [ArrowCompression::Lz4, ArrowCompression::Zstd] {
        let dataset = ArrowWriteDataset {
            dataset: DatasetDocument::default(),
            columns: vec![
                ArrowWriteColumn {
                    name: "x".to_owned(),
                    field: None,
                    array: values.clone(),
                },
                ArrowWriteColumn {
                    name: "s".to_owned(),
                    field: None,
                    array: strings.clone(),
                },
            ],
        };
        let bytes = write_to_vec(&dataset, compression);
        let result = read_arrow_file_from(
            &mut Cursor::new(&bytes),
            &read_all_options(),
            &mut no_interrupt(),
        )
        .expect("compressed read succeeds");
        assert_eq!(&concat_chunks(&result.columns[0].chunks), &values);
        assert_eq!(&concat_chunks(&result.columns[1].chunks), &strings);
    }
}

#[test]
fn the_arrow_ipc_reader_is_an_oracle_for_written_files() {
    let values: ArrayRef = Arc::new(Int32Array::from(vec![Some(1), None, Some(3)]));
    let keys = Int32Array::from(vec![0, 1, 0]);
    let dictionary_values = StringArray::from(vec!["a", "b"]);
    let factor: ArrayRef = Arc::new(
        DictionaryArray::try_new(keys, Arc::new(dictionary_values)).expect("valid dictionary"),
    );
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![
            ArrowWriteColumn {
                name: "x".to_owned(),
                field: None,
                array: values.clone(),
            },
            ArrowWriteColumn {
                name: "g".to_owned(),
                field: None,
                array: factor.clone(),
            },
        ],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let reader = FileReader::try_new(Cursor::new(&bytes), None).expect("official reader accepts");
    let batches: Vec<RecordBatch> = reader.collect::<Result<_, _>>().expect("batches decode");
    assert_eq!(batches.len(), 1);
    assert_eq!(batches[0].column(0), &values);
    assert_eq!(batches[0].column(1), &factor);
    assert_eq!(
        batches[0]
            .schema()
            .metadata()
            .get(ARROW_PROFILE_VERSION_KEY)
            .map(String::as_str),
        Some("0")
    );
}

fn plain_arrow_file(metadata: HashMap<String, String>) -> Vec<u8> {
    let values: ArrayRef = Arc::new(Int32Array::from(vec![Some(10), None, Some(30)]));
    let strings: ArrayRef = Arc::new(StringArray::from(vec![Some("x"), Some("y"), None]));
    let schema = Arc::new(
        Schema::new(vec![
            Field::new("v", DataType::Int32, true),
            Field::new("s", DataType::Utf8, true),
        ])
        .with_metadata(metadata),
    );
    let batch = RecordBatch::try_new(schema.clone(), vec![values, strings]).expect("valid batch");
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new(&mut bytes, &schema).expect("writer opens");
    writer.write(&batch).expect("batch writes");
    writer.finish().expect("writer finishes");
    drop(writer);
    bytes
}

#[test]
fn plain_arrow_files_read_without_stata_semantics() {
    let bytes = plain_arrow_file(HashMap::new());
    let result = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect("plain file reads");
    assert_eq!(result.profile_version, None);
    assert!(result.dataset.is_none());
    assert_eq!(result.row_count, 3);
    assert!(result.columns.iter().all(|column| column.field.is_none()));
    let expected: ArrayRef = Arc::new(Int32Array::from(vec![Some(10), None, Some(30)]));
    assert_eq!(&concat_chunks(&result.columns[0].chunks), &expected);
}

#[test]
fn plain_dictionary_columns_accept_all_signed_key_widths() {
    let values: ArrayRef = Arc::new(StringArray::from(vec!["low", "high"]));
    let arrays: Vec<ArrayRef> = vec![
        Arc::new(
            DictionaryArray::try_new(
                Int8Array::from(vec![Some(0), Some(1), None]),
                values.clone(),
            )
            .expect("int8 dictionary"),
        ),
        Arc::new(
            DictionaryArray::try_new(
                Int16Array::from(vec![Some(0), Some(1), None]),
                values.clone(),
            )
            .expect("int16 dictionary"),
        ),
        Arc::new(
            DictionaryArray::try_new(
                Int32Array::from(vec![Some(0), Some(1), None]),
                values.clone(),
            )
            .expect("int32 dictionary"),
        ),
        Arc::new(
            DictionaryArray::try_new(Int64Array::from(vec![Some(0), Some(1), None]), values)
                .expect("int64 dictionary"),
        ),
    ];
    let schema = Arc::new(Schema::new(
        arrays
            .iter()
            .enumerate()
            .map(|(index, array)| Field::new(format!("f{index}"), array.data_type().clone(), true))
            .collect::<Vec<_>>(),
    ));
    let batch = RecordBatch::try_new(schema.clone(), arrays).expect("valid batch");
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new(&mut bytes, &schema).expect("writer opens");
    writer.write(&batch).expect("batch writes");
    writer.finish().expect("writer finishes");
    drop(writer);

    let result = read_arrow_file_from(
        &mut Cursor::new(bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect("signed dictionary key widths read");
    assert_eq!(result.columns.len(), 4);
    for column in result.columns {
        assert_eq!(column.chunks[0].len(), 3);
        assert_eq!(column.chunks[0].null_count(), 1);
    }
}

#[test]
fn newer_profile_versions_are_a_hard_error_with_an_escape_hatch() {
    let bytes = plain_arrow_file(HashMap::from([(
        ARROW_PROFILE_VERSION_KEY.to_owned(),
        "1".to_owned(),
    )]));
    let error = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("newer profile is rejected");
    match &error {
        ArrowProfileError::NewerProfile(version) => assert_eq!(version, "1"),
        other => panic!("expected a newer-profile error, got {other}"),
    }
    assert!(error.to_string().contains("\"1\""));

    let options = ArrowReadOptions {
        profile: false,
        verify: false,
        ..read_all_options()
    };
    let result = read_arrow_file_from(&mut Cursor::new(&bytes), &options, &mut no_interrupt())
        .expect("profile = FALSE reads the raw storage");
    assert_eq!(result.profile_version, None);
    assert_eq!(result.row_count, 3);
}

#[test]
fn incompatible_field_semantics_are_malformed_with_an_escape_hatch() {
    let mut field = Field::new("day", DataType::Int32, true);
    field.set_metadata(HashMap::from([(
        ARROW_FIELD_KEY.to_owned(),
        r#"{"version":0,"r":{"class":"Date"}}"#.to_owned(),
    )]));
    let schema = Arc::new(Schema::new(vec![field]).with_metadata(HashMap::from([(
        ARROW_PROFILE_VERSION_KEY.to_owned(),
        "0".to_owned(),
    )])));
    let values: ArrayRef = Arc::new(Int32Array::from(vec![1, 2, 3]));
    let batch = RecordBatch::try_new(schema.clone(), vec![values]).expect("valid batch");
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new(&mut bytes, &schema).expect("writer opens");
    writer.write(&batch).expect("batch writes");
    writer.finish().expect("writer finishes");
    drop(writer);

    let options = ArrowReadOptions {
        verify: false,
        ..read_all_options()
    };
    let error = read_arrow_file_from(&mut Cursor::new(&bytes), &options, &mut no_interrupt())
        .expect_err("incompatible field semantics are rejected");
    assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
    assert!(error
        .to_string()
        .contains("incompatible with Arrow type Int32"));

    let raw_options = ArrowReadOptions {
        profile: false,
        verify: false,
        ..read_all_options()
    };
    let result = read_arrow_file_from(&mut Cursor::new(bytes), &raw_options, &mut no_interrupt())
        .expect("profile = FALSE reads the raw field");
    assert_eq!(result.profile_version, None);
    assert_eq!(result.columns[0].data_type, DataType::Int32);
}

#[test]
fn nonnullable_profile_fields_reject_nulls() {
    let mut field = Field::new("x", DataType::Int8, false);
    field.set_metadata(HashMap::from([(
        ARROW_FIELD_KEY.to_owned(),
        r#"{"version":0,"storage":"byte","missing":"sentinel","r":{"class":"stata_numeric"}}"#
            .to_owned(),
    )]));
    let schema = Arc::new(Schema::new(vec![field]).with_metadata(HashMap::from([(
        ARROW_PROFILE_VERSION_KEY.to_owned(),
        "0".to_owned(),
    )])));
    let values: ArrayRef = Arc::new(Int8Array::from(vec![Some(1), None]));
    // Nullability does not affect the physical array layout, so this satisfies
    // RecordBatch::new_unchecked's type, length, and column-count contracts.
    let batch = unsafe { RecordBatch::new_unchecked(schema.clone(), vec![values], 2) };
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new(&mut bytes, &schema).expect("writer opens");
    writer.write(&batch).expect("malformed batch writes");
    writer.finish().expect("writer finishes");
    drop(writer);

    let options = ArrowReadOptions {
        verify: false,
        ..read_all_options()
    };
    let error = read_arrow_file_from(&mut Cursor::new(bytes), &options, &mut no_interrupt())
        .expect_err("nulls in a nonnullable profile field are rejected");
    assert!(error
        .to_string()
        .contains("non-nullable field contains nulls"));
}

#[test]
fn profiled_files_without_checksums_are_malformed_when_verifying() {
    let bytes = plain_arrow_file(HashMap::from([(
        ARROW_PROFILE_VERSION_KEY.to_owned(),
        "0".to_owned(),
    )]));
    let error = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("missing checksums are malformed");
    assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));

    // Without verification the profile still applies.
    let options = ArrowReadOptions {
        verify: false,
        ..read_all_options()
    };
    let result = read_arrow_file_from(&mut Cursor::new(&bytes), &options, &mut no_interrupt())
        .expect("unverified read succeeds");
    assert_eq!(result.profile_version.as_deref(), Some("0"));
}

#[test]
fn dangling_value_label_references_are_malformed() {
    let values: ArrayRef = Arc::new(Float64Array::from(vec![1.0, 2.0]));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "status".to_owned(),
            field: Some(ArrowFieldDocument {
                value_labels: Some("missing_table".to_owned()),
                ..ArrowFieldDocument::default()
            }),
            array: values,
        }],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);

    let error = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("dangling value-label reference is rejected");
    match error {
        ArrowProfileError::MalformedProfile { detail, .. } => assert_eq!(
            detail,
            "field `status` refers to missing value-label table `missing_table`"
        ),
        other => panic!("expected a malformed-profile error, got {other}"),
    }
}

#[test]
fn unsupported_columns_error_naming_the_column() {
    let list =
        arrow_array::ListArray::from_iter_primitive::<arrow_array::types::Int32Type, _, _>(vec![
            Some(vec![Some(1), Some(2)]),
            Some(vec![Some(3)]),
        ]);
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "nested".to_owned(),
            field: None,
            array: Arc::new(list),
        }],
    };
    let mut bytes = Vec::new();
    let error = save_arrow_file_to(
        &mut bytes,
        &dataset,
        ArrowCompression::Uncompressed,
        64,
        1,
        true,
        &mut no_interrupt(),
    )
    .expect_err("nested columns are unsupported");
    match error {
        ArrowProfileError::UnsupportedColumn { column, .. } => assert_eq!(column, "nested"),
        other => panic!("expected an unsupported-column error, got {other}"),
    }
}

#[test]
fn empty_datasets_round_trip() {
    let values: ArrayRef = Arc::new(Int32Array::from(Vec::<i32>::new()));
    let keys = Int32Array::from(Vec::<i32>::new());
    let levels = StringArray::from(vec!["unused one", "unused two"]);
    let factor: ArrayRef =
        Arc::new(DictionaryArray::try_new(keys, Arc::new(levels)).expect("valid dictionary"));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument {
            version: 0,
            label: "empty".to_owned(),
            ..DatasetDocument::default()
        },
        columns: vec![
            ArrowWriteColumn {
                name: "x".to_owned(),
                field: None,
                array: values,
            },
            ArrowWriteColumn {
                name: "f".to_owned(),
                field: Some(field_document(None, None, "factor")),
                array: factor,
            },
        ],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let result = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect("empty file reads");
    assert_eq!(result.row_count, 0);
    assert_eq!(result.columns[0].data_type, DataType::Int32);
    let factor = result.columns[1].chunks[0]
        .as_any()
        .downcast_ref::<DictionaryArray<arrow_array::types::Int32Type>>()
        .expect("factor stays dictionary encoded");
    assert_eq!(factor.values().len(), 2);
    assert_eq!(
        result.dataset.expect("dataset document survives").label,
        "empty"
    );
}

#[test]
fn delta_dictionaries_are_accumulated() {
    let data_type = DataType::Dictionary(Box::new(DataType::Int32), Box::new(DataType::Utf8));
    let schema = Arc::new(Schema::new(vec![Field::new("f", data_type, false)]));
    let first: ArrayRef = Arc::new(
        DictionaryArray::try_new(
            Int32Array::from(vec![0]),
            Arc::new(StringArray::from(vec!["a"])),
        )
        .expect("first dictionary"),
    );
    let second: ArrayRef = Arc::new(
        DictionaryArray::try_new(
            Int32Array::from(vec![1, 0]),
            Arc::new(StringArray::from(vec!["a", "b"])),
        )
        .expect("grown dictionary"),
    );
    let first = RecordBatch::try_new(schema.clone(), vec![first]).expect("first batch");
    let second = RecordBatch::try_new(schema.clone(), vec![second]).expect("second batch");
    let options = IpcWriteOptions::default().with_dictionary_handling(DictionaryHandling::Delta);
    let mut bytes = Vec::new();
    let mut writer =
        FileWriter::try_new_with_options(&mut bytes, &schema, options).expect("delta writer opens");
    writer.write(&first).expect("first batch writes");
    writer.write(&second).expect("second batch writes");
    writer.finish().expect("writer finishes");
    drop(writer);

    let result = read_arrow_file_from(
        &mut Cursor::new(bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect("delta dictionary file reads");
    assert_eq!(result.columns[0].chunks.len(), 2);
    for chunk in &result.columns[0].chunks {
        let dictionary = chunk
            .as_any()
            .downcast_ref::<DictionaryArray<arrow_array::types::Int32Type>>()
            .expect("dictionary chunk");
        assert_eq!(dictionary.values().len(), 2);
    }
}

#[test]
fn parallel_decoding_matches_serial() {
    // 1,000 rows over 64-row batches give every worker several blocks.
    let rows = 1_000_usize;
    let doubles: ArrayRef = Arc::new(Float64Array::from(
        (0..rows).map(|row| row as f64 / 3.0).collect::<Vec<_>>(),
    ));
    let strings: ArrayRef = Arc::new(StringArray::from(
        (0..rows)
            .map(|row| format!("value {}", row % 17))
            .collect::<Vec<_>>(),
    ));
    let integers: ArrayRef = Arc::new(Int32Array::from(
        (0..rows).map(|row| row as i32).collect::<Vec<_>>(),
    ));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![
            ArrowWriteColumn {
                name: "x".to_owned(),
                field: None,
                array: doubles,
            },
            ArrowWriteColumn {
                name: "s".to_owned(),
                field: None,
                array: strings,
            },
            ArrowWriteColumn {
                name: "n".to_owned(),
                field: None,
                array: integers,
            },
        ],
    };
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    let path = std::env::temp_dir().join(format!(
        "dtatools-parallel-decode-{}.arrow",
        std::process::id()
    ));
    std::fs::write(&path, &bytes).expect("temp file writes");

    let serial = read_arrow_file(&path, &read_all_options(), &mut no_interrupt())
        .expect("serial read succeeds");
    let parallel = read_arrow_file(
        &path,
        &ArrowReadOptions {
            threads: 4,
            ..read_all_options()
        },
        &mut no_interrupt(),
    )
    .expect("parallel read succeeds");
    let windowed = read_arrow_file(
        &path,
        &ArrowReadOptions {
            threads: 4,
            row_start: 100,
            row_count: Some(500),
            ..read_all_options()
        },
        &mut no_interrupt(),
    )
    .expect("windowed parallel read succeeds");
    std::fs::remove_file(&path).ok();

    assert_eq!(parallel.row_count, serial.row_count);
    for (left, right) in parallel.columns.iter().zip(&serial.columns) {
        assert_eq!(left.name, right.name);
        let left_values = concat_chunks(&left.chunks);
        let right_values = concat_chunks(&right.chunks);
        assert_eq!(&left_values, &right_values, "column `{}`", left.name);
    }
    assert_eq!(windowed.row_count, 500);
    for (column, full) in windowed.columns.iter().zip(&serial.columns) {
        let expected = concat_chunks(&full.chunks).slice(100, 500);
        let values = concat_chunks(&column.chunks);
        assert_eq!(&values, &expected, "windowed column `{}`", column.name);
    }
}

#[test]
fn non_arrow_input_is_rejected() {
    let error = read_arrow_file_from(
        &mut Cursor::new(b"not an arrow file at all".as_slice()),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("garbage is rejected");
    assert!(matches!(error, ArrowProfileError::NotAnArrowFile(_)));
}

#[test]
fn parallel_checksum_hashing_matches_serial() {
    // 1,000 rows over 64-row batches give every worker several hash tasks,
    // and the dictionary column exercises the dictionary-values task.
    let rows = 1_000_usize;
    let doubles: ArrayRef = Arc::new(Float64Array::from(
        (0..rows).map(|row| row as f64 / 7.0).collect::<Vec<_>>(),
    ));
    let keys = Int32Array::from((0..rows).map(|row| (row % 3) as i32).collect::<Vec<_>>());
    let values = StringArray::from(vec!["one", "two", "three"]);
    let dictionary: ArrayRef =
        Arc::new(DictionaryArray::try_new(keys, Arc::new(values)).expect("valid dictionary"));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![
            ArrowWriteColumn {
                name: "x".to_owned(),
                field: None,
                array: doubles,
            },
            ArrowWriteColumn {
                name: "k".to_owned(),
                field: None,
                array: dictionary,
            },
        ],
    };

    let mut serial = Vec::new();
    save_arrow_file_to(
        &mut serial,
        &dataset,
        ArrowCompression::Uncompressed,
        64,
        1,
        true,
        &mut no_interrupt(),
    )
    .expect("serial write succeeds");
    let mut parallel = Vec::new();
    save_arrow_file_to(
        &mut parallel,
        &dataset,
        ArrowCompression::Uncompressed,
        64,
        4,
        true,
        &mut no_interrupt(),
    )
    .expect("parallel write succeeds");
    assert_eq!(serial, parallel, "thread count must not change the bytes");
}

#[test]
fn checksum_free_writes_round_trip_without_verification() {
    let rows = 200_usize;
    let doubles: ArrayRef = Arc::new(Float64Array::from(
        (0..rows).map(|row| row as f64 / 3.0).collect::<Vec<_>>(),
    ));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "x".to_owned(),
            field: None,
            array: doubles.clone(),
        }],
    };
    let mut bytes = Vec::new();
    save_arrow_file_to(
        &mut bytes,
        &dataset,
        ArrowCompression::Uncompressed,
        64,
        1,
        false,
        &mut no_interrupt(),
    )
    .expect("checksum-free write succeeds");

    let error = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &read_all_options(),
        &mut no_interrupt(),
    )
    .expect_err("verification requires checksums");
    assert!(
        error.to_string().contains("verification off"),
        "error should point at the fix: {error}"
    );

    let unverified = read_arrow_file_from(
        &mut Cursor::new(&bytes),
        &ArrowReadOptions {
            verify: false,
            ..read_all_options()
        },
        &mut no_interrupt(),
    )
    .expect("reads without verification");
    assert_eq!(unverified.row_count, rows as u64);
    let column = arrow_select::concat::concat(
        &unverified.columns[0]
            .chunks
            .iter()
            .map(|chunk| chunk.as_ref())
            .collect::<Vec<_>>(),
    )
    .expect("chunks concatenate");
    assert_eq!(column.as_ref(), doubles.as_ref());
}

fn signature_dataset(values: Vec<f64>, name: &str) -> ArrowWriteDataset {
    ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: name.to_owned(),
            field: None,
            array: Arc::new(Float64Array::from(values)),
        }],
    }
}

#[test]
fn dataset_signature_is_stable_across_thread_counts() {
    let values: Vec<f64> = (0..1_000).map(|row| row as f64 / 7.0).collect();
    let serial = dataset_signature(
        &signature_dataset(values.clone(), "x"),
        64,
        1,
        &mut no_interrupt(),
    )
    .expect("serial signature");
    let parallel = dataset_signature(&signature_dataset(values, "x"), 64, 4, &mut no_interrupt())
        .expect("parallel signature");
    assert_eq!(serial, parallel);
    assert!(serial.starts_with("1000:1:"), "unexpected form: {serial}");
}

#[test]
fn dataset_signature_detects_value_order_and_names() {
    // The failure mode Stata's datasignature misses: two values swapped
    // within one column.
    let base = dataset_signature(
        &signature_dataset(vec![1.0, 2.0, 3.0], "x"),
        64,
        1,
        &mut no_interrupt(),
    )
    .expect("base signature");
    let swapped = dataset_signature(
        &signature_dataset(vec![2.0, 1.0, 3.0], "x"),
        64,
        1,
        &mut no_interrupt(),
    )
    .expect("swapped signature");
    assert_ne!(base, swapped);
    let renamed = dataset_signature(
        &signature_dataset(vec![1.0, 2.0, 3.0], "y"),
        64,
        1,
        &mut no_interrupt(),
    )
    .expect("renamed signature");
    assert_ne!(base, renamed);
    let identical = dataset_signature(
        &signature_dataset(vec![1.0, 2.0, 3.0], "x"),
        64,
        1,
        &mut no_interrupt(),
    )
    .expect("identical signature");
    assert_eq!(base, identical);
}

#[test]
fn stored_signature_matches_recomputed_signature() {
    let rows = 300_usize;
    let doubles: ArrayRef = Arc::new(Float64Array::from(
        (0..rows).map(|row| row as f64 / 3.0).collect::<Vec<_>>(),
    ));
    let keys = Int32Array::from((0..rows).map(|row| (row % 2) as i32).collect::<Vec<_>>());
    let values = StringArray::from(vec!["yes", "no"]);
    let dictionary: ArrayRef =
        Arc::new(DictionaryArray::try_new(keys, Arc::new(values)).expect("valid dictionary"));
    let dataset = ArrowWriteDataset {
        dataset: DatasetDocument {
            version: 0,
            label: "stored signature".to_owned(),
            ..DatasetDocument::default()
        },
        columns: vec![
            ArrowWriteColumn {
                name: "x".to_owned(),
                field: Some(field_document(None, None, "double")),
                array: doubles,
            },
            ArrowWriteColumn {
                name: "k".to_owned(),
                field: None,
                array: dictionary,
            },
        ],
    };
    let recomputed = dataset_signature(&dataset, 64, 1, &mut no_interrupt()).expect("signature");

    let directory =
        std::env::temp_dir().join(format!("dtatools-stored-signature-{}", std::process::id()));
    std::fs::create_dir_all(&directory).expect("temp dir");
    let path = directory.join("signed.arrow");
    let bytes = write_to_vec(&dataset, ArrowCompression::Uncompressed);
    std::fs::write(&path, bytes).expect("file written");
    let stored = arrow_stored_signature(&path).expect("stored signature");
    assert_eq!(stored, recomputed);

    // A compressed copy signs identically: the checksums cover uncompressed
    // buffers.
    let compressed_path = directory.join("signed-zstd.arrow");
    let bytes = write_to_vec(&dataset, ArrowCompression::Zstd);
    std::fs::write(&compressed_path, bytes).expect("file written");
    assert_eq!(
        arrow_stored_signature(&compressed_path).expect("compressed signature"),
        recomputed
    );

    // A checksums-free file has nothing to derive the signature from.
    let bare_path = directory.join("bare.arrow");
    let mut bare = Vec::new();
    save_arrow_file_to(
        &mut bare,
        &dataset,
        ArrowCompression::Uncompressed,
        64,
        1,
        false,
        &mut no_interrupt(),
    )
    .expect("checksums-free write succeeds");
    std::fs::write(&bare_path, bare).expect("file written");
    let error = arrow_stored_signature(&bare_path).expect_err("no checksums to derive from");
    assert!(error.to_string().contains("without checksums"));
    std::fs::remove_dir_all(&directory).expect("temp dir removed");
}

fn profile_file_with_checksums(
    schema: Arc<Schema>,
    columns: Vec<ArrayRef>,
    checksums: &str,
) -> Vec<u8> {
    let batch = RecordBatch::try_new(schema.clone(), columns).expect("valid batch");
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new(&mut bytes, &schema).expect("writer opens");
    writer.write(&batch).expect("batch writes");
    writer.write_metadata(ARROW_CHECKSUMS_KEY, checksums);
    writer.finish().expect("writer finishes");
    drop(writer);
    bytes
}

#[test]
fn stored_signatures_require_complete_checksum_coverage() {
    let profile = HashMap::from([(ARROW_PROFILE_VERSION_KEY.to_owned(), "0".to_owned())]);
    let schema = Arc::new(
        Schema::new(vec![
            Field::new("x", DataType::Int32, false),
            Field::new("y", DataType::Int32, false),
        ])
        .with_metadata(profile.clone()),
    );
    let bytes = profile_file_with_checksums(
        schema,
        vec![
            Arc::new(Int32Array::from(vec![1])),
            Arc::new(Int32Array::from(vec![2])),
        ],
        r#"{"version":0,"algorithm":"xxh64","batches":[{"columns":[["0000000000000000"]]}]}"#,
    );
    let directory = std::env::temp_dir().join(format!(
        "dtatools-incomplete-signature-{}",
        std::process::id()
    ));
    std::fs::create_dir_all(&directory).expect("temp dir");
    let columns_path = directory.join("columns.arrow");
    std::fs::write(&columns_path, bytes).expect("file written");
    let error = arrow_stored_signature(&columns_path).expect_err("one column is omitted");
    assert!(error.to_string().contains("does not cover every column"));

    let data_type = DataType::Dictionary(Box::new(DataType::Int32), Box::new(DataType::Utf8));
    let schema =
        Arc::new(Schema::new(vec![Field::new("f", data_type, false)]).with_metadata(profile));
    let dictionary: ArrayRef = Arc::new(
        DictionaryArray::try_new(
            Int32Array::from(vec![0]),
            Arc::new(StringArray::from(vec!["a", "unused"])),
        )
        .expect("valid dictionary"),
    );
    let bytes = profile_file_with_checksums(
        schema,
        vec![dictionary],
        r#"{"version":0,"algorithm":"xxh64","batches":[{"columns":[["0000000000000000"]]}]}"#,
    );
    let dictionary_path = directory.join("dictionary.arrow");
    std::fs::write(&dictionary_path, bytes).expect("file written");
    let error = arrow_stored_signature(&dictionary_path).expect_err("dictionary is omitted");
    assert!(error
        .to_string()
        .contains("does not cover every dictionary column"));

    std::fs::remove_dir_all(&directory).expect("temp dir removed");
}
