//! Regenerate portable TypeScript interoperability fixtures with the canonical Rust reader/writer.
//! cargo run -p dta-tools --example typescript_arrow_fixtures -- <output directory>
use arrow_array::*;
use arrow_ipc::{
    writer::{DictionaryHandling, FileWriter, IpcWriteOptions},
    CompressionType,
};
use arrow_schema::{Field, Schema};
use dta_tools::arrow::*;
use dta_tools::{StataCharacteristic, StataNote};
use std::{
    fs,
    io::{Cursor, Write},
    path::Path,
    sync::Arc,
};

fn plain(path: &Path, columns: &[(String, ArrayRef)], codec: Option<CompressionType>) {
    let schema = Arc::new(Schema::new(
        columns
            .iter()
            .map(|(n, a)| Field::new(n, a.data_type().clone(), true))
            .collect::<Vec<_>>(),
    ));
    let batch = RecordBatch::try_new(
        schema.clone(),
        columns.iter().map(|(_, a)| a.clone()).collect(),
    )
    .unwrap();
    let options = IpcWriteOptions::default()
        .try_with_compression(codec)
        .unwrap();
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new_with_options(&mut bytes, &schema, options).unwrap();
    writer.write(&batch.slice(0, 2)).unwrap();
    writer.write(&batch.slice(2, 2)).unwrap();
    writer.finish().unwrap();
    drop(writer);
    verify(&bytes);
    fs::write(path, bytes).unwrap();
}
fn verify(bytes: &[u8]) {
    read_arrow_file_from(
        &mut Cursor::new(bytes),
        &ArrowReadOptions {
            columns: None,
            row_start: 0,
            row_count: None,
            max_output_rows: None,
            verify: true,
            profile: true,
            record_signature: false,
            threads: 1,
        },
        &mut || false,
    )
    .unwrap();
}
fn cell(array: &dyn Array, row: usize) -> serde_json::Value {
    use arrow_schema::DataType;
    use serde_json::json;
    if array.is_null(row) {
        return serde_json::Value::Null;
    }
    macro_rules! number {
        ($t:ty) => {
            json!(array.as_any().downcast_ref::<$t>().unwrap().value(row))
        };
    }
    macro_rules! big { ($t:ty) => { json!({"bigint":array.as_any().downcast_ref::<$t>().unwrap().value(row).to_string()}) }; }
    match array.data_type() {
        DataType::Boolean => number!(BooleanArray),
        DataType::Int8 => number!(Int8Array),
        DataType::Int16 => number!(Int16Array),
        DataType::Int32 => number!(Int32Array),
        DataType::Int64 => big!(Int64Array),
        DataType::UInt8 => number!(UInt8Array),
        DataType::UInt16 => number!(UInt16Array),
        DataType::UInt32 => number!(UInt32Array),
        DataType::UInt64 => big!(UInt64Array),
        DataType::Float32 | DataType::Float64 => {
            let value = if array.data_type() == &DataType::Float32 {
                array
                    .as_any()
                    .downcast_ref::<Float32Array>()
                    .unwrap()
                    .value(row) as f64
            } else {
                array
                    .as_any()
                    .downcast_ref::<Float64Array>()
                    .unwrap()
                    .value(row)
            };
            if value.is_nan() {
                json!({"number":"NaN"})
            } else if value == f64::INFINITY {
                json!({"number":"Infinity"})
            } else if value == f64::NEG_INFINITY {
                json!({"number":"-Infinity"})
            } else if value == 0.0 && value.is_sign_negative() {
                json!({"number":"-0"})
            } else {
                json!(value)
            }
        }
        DataType::Utf8 => number!(StringArray),
        DataType::LargeUtf8 => number!(LargeStringArray),
        DataType::Date32 => number!(Date32Array),
        DataType::Timestamp(_, _) | DataType::Duration(_) => {
            let data = array.to_data();
            let offset = (data.offset() + row) * 8;
            json!({"bigint":i64::from_le_bytes(data.buffers()[0][offset..offset+8].try_into().unwrap()).to_string()})
        }
        DataType::Dictionary(key, _) => {
            macro_rules! key {
                ($t:ty) => {
                    json!(array
                        .as_any()
                        .downcast_ref::<DictionaryArray<$t>>()
                        .unwrap()
                        .key(row)
                        .unwrap())
                };
            }
            match key.as_ref() {
                DataType::Int8 => key!(types::Int8Type),
                DataType::Int16 => key!(types::Int16Type),
                DataType::Int32 => key!(types::Int32Type),
                DataType::Int64 => {
                    json!({"bigint":array.as_any().downcast_ref::<DictionaryArray<types::Int64Type>>().unwrap().keys().value(row).to_string()})
                }
                _ => unreachable!(),
            }
        }
        _ => unreachable!(),
    }
}
fn main() {
    let output = std::env::args().nth(1).expect("output directory");
    let out = Path::new(&output);
    fs::create_dir_all(out).unwrap();
    let mut cols: Vec<(String, ArrayRef)> = vec![];
    macro_rules! col {
        ($name:expr,$array:expr) => {
            cols.push(($name.into(), Arc::new($array)))
        };
    }
    col!(
        "bool",
        BooleanArray::from(vec![Some(true), None, Some(false), Some(true)])
    );
    col!(
        "i8",
        Int8Array::from(vec![Some(-128), None, Some(127), Some(0)])
    );
    col!(
        "i16",
        Int16Array::from(vec![Some(-32768), None, Some(32767), Some(0)])
    );
    col!(
        "i32",
        Int32Array::from(vec![Some(i32::MIN), None, Some(i32::MAX), Some(0)])
    );
    col!(
        "i64",
        Int64Array::from(vec![
            Some(i64::MIN),
            None,
            Some(i64::MAX),
            Some(9007199254740993)
        ])
    );
    col!(
        "u8",
        UInt8Array::from(vec![Some(0), None, Some(255), Some(1)])
    );
    col!(
        "u16",
        UInt16Array::from(vec![Some(0), None, Some(65535), Some(1)])
    );
    col!(
        "u32",
        UInt32Array::from(vec![Some(0), None, Some(u32::MAX), Some(1)])
    );
    col!(
        "u64",
        UInt64Array::from(vec![Some(0), None, Some(u64::MAX), Some(9007199254740993)])
    );
    col!(
        "f32",
        Float32Array::from(vec![Some(1.5), None, Some(f32::NAN), Some(f32::INFINITY)])
    );
    col!(
        "f64",
        Float64Array::from(vec![
            Some(-0.0),
            None,
            Some(f64::NAN),
            Some(f64::NEG_INFINITY)
        ])
    );
    col!(
        "utf8",
        StringArray::from(vec![Some("café"), None, Some(""), Some("😀")])
    );
    col!(
        "large_utf8",
        LargeStringArray::from(vec![Some("東京"), None, Some(""), Some("fin")])
    );
    col!(
        "date32",
        Date32Array::from(vec![Some(-1), None, Some(0), Some(20000)])
    );
    col!(
        "timestamp_s",
        TimestampSecondArray::from(vec![Some(-1), None, Some(0), Some(1700000000)])
    );
    col!(
        "timestamp_ms",
        TimestampMillisecondArray::from(vec![Some(-1), None, Some(0), Some(1700000000000)])
            .with_timezone("America/New_York")
    );
    col!(
        "timestamp_us",
        TimestampMicrosecondArray::from(vec![Some(-1), None, Some(0), Some(1700000000000000)])
    );
    col!(
        "timestamp_ns",
        TimestampNanosecondArray::from(vec![Some(-1), None, Some(0), Some(1700000000000000001)])
    );
    col!(
        "duration_s",
        DurationSecondArray::from(vec![Some(-1), None, Some(0), Some(60)])
    );
    col!(
        "duration_ms",
        DurationMillisecondArray::from(vec![Some(-1), None, Some(0), Some(60000)])
    );
    col!(
        "duration_us",
        DurationMicrosecondArray::from(vec![Some(-1), None, Some(0), Some(60000000)])
    );
    col!(
        "duration_ns",
        DurationNanosecondArray::from(vec![Some(-1), None, Some(0), Some(60000000001)])
    );
    macro_rules! dict {
        ($name:expr,$key:ty) => {
            col!(
                $name,
                DictionaryArray::try_new(
                    <$key>::from(vec![Some(1), None, Some(0), Some(1)]),
                    Arc::new(StringArray::from(vec!["low", "high", "unused"]))
                )
                .unwrap()
            );
        };
    }
    dict!("dict_i8", Int8Array);
    dict!("dict_i16", Int16Array);
    dict!("dict_i32", Int32Array);
    dict!("dict_i64", Int64Array);
    for (name, codec) in [
        ("none", None),
        ("lz4", Some(CompressionType::LZ4_FRAME)),
        ("zstd", Some(CompressionType::ZSTD)),
    ] {
        plain(&out.join(format!("plain-{name}.arrow")), &cols, codec);
    }
    fs::write(out.join("plain.expected.json"),serde_json::to_string_pretty(&cols.iter().map(|(name,array)|serde_json::json!({"name":name,"values":(0..array.len()).map(|row|cell(array.as_ref(),row)).collect::<Vec<_>>()})).collect::<Vec<_>>()).unwrap()).unwrap();
    let mut profiled = ArrowWriteDataset {
        dataset: DatasetDocument {
            version: 0,
            label: "TypeScript parity café".into(),
            output_container: Some("data.frame".into()),
            notes: vec![StataNote {
                number: 2,
                text: "numbered note".into(),
            }],
            characteristics: vec![StataCharacteristic {
                name: "source".into(),
                value: "Rust".into(),
            }],
            ..Default::default()
        },
        columns: vec![],
    };
    let missing = |storage, encoding| {
        Some(ArrowFieldDocument {
            storage: Some(storage),
            missing: Some(encoding),
            label: "all Stata missing codes".into(),
            notes: vec![StataNote {
                number: 4,
                text: String::new(),
            }],
            characteristics: vec![StataCharacteristic {
                name: "role".into(),
                value: "test".into(),
            }],
            r: Some(ArrowRSemantics {
                class: "stata_numeric".into(),
                ..Default::default()
            }),
            ..Default::default()
        })
    };
    macro_rules! pcol {
        ($name:expr,$arr:expr,$field:expr) => {
            profiled.columns.push(ArrowWriteColumn {
                name: $name.into(),
                array: Arc::new($arr),
                field: $field,
            })
        };
    }
    pcol!(
        "byte",
        Int8Array::from(std::iter::once(1).chain(101..=127).collect::<Vec<_>>()),
        missing(StataStorage::Byte, ArrowMissingEncoding::Sentinel)
    );
    pcol!(
        "int",
        Int16Array::from(std::iter::once(1).chain(32741..=32767).collect::<Vec<_>>()),
        missing(StataStorage::Int, ArrowMissingEncoding::Sentinel)
    );
    pcol!(
        "long",
        Int32Array::from(
            std::iter::once(1)
                .chain(2147483621..=2147483647)
                .collect::<Vec<_>>()
        ),
        missing(StataStorage::Long, ArrowMissingEncoding::Sentinel)
    );
    pcol!(
        "float",
        Float32Array::from(
            std::iter::once(1.5)
                .chain((0..27).map(|i| f32::from_bits(0x7f000000 + i * 0x800)))
                .collect::<Vec<_>>()
        ),
        missing(StataStorage::Float, ArrowMissingEncoding::Payload)
    );
    pcol!(
        "double",
        Float64Array::from(
            std::iter::once(1.5)
                .chain((0..27).map(|i| f64::from_bits(0x7fe0000000000000 + i * 0x10000000000)))
                .collect::<Vec<_>>()
        ),
        missing(StataStorage::Double, ArrowMissingEncoding::Payload)
    );
    pcol!(
        "date_fallback",
        Float64Array::from(vec![1.25; 28]),
        Some(ArrowFieldDocument {
            r: Some(ArrowRSemantics {
                class: "Date".into(),
                ..Default::default()
            }),
            ..Default::default()
        })
    );
    pcol!(
        "timestamp_fallback",
        Float64Array::from(vec![1.0000000001; 28]),
        Some(ArrowFieldDocument {
            r: Some(ArrowRSemantics {
                class: "POSIXct".into(),
                tz: Some("UTC".into()),
                ..Default::default()
            }),
            ..Default::default()
        })
    );
    pcol!(
        "duration_fallback",
        Float64Array::from(vec![2.5; 28]),
        Some(ArrowFieldDocument {
            r: Some(ArrowRSemantics {
                class: "difftime".into(),
                units: Some("hours".into()),
                ..Default::default()
            }),
            ..Default::default()
        })
    );
    profiled
        .dataset
        .insert_value_label_table(dta_tools::ValueLabelTable {
            name: "answers".into(),
            entries: vec![dta_tools::ValueLabelEntry {
                value: 1,
                missing_tag: None,
                label: "yes".into(),
            }],
        })
        .unwrap();
    profiled.columns[0].field.as_mut().unwrap().value_labels = Some("answers".into());
    profiled.columns[0].field.as_mut().unwrap().format = "%8.0g".into();
    pcol!(
        "string",
        StringArray::from(vec!["café"; 28]),
        Some(ArrowFieldDocument {
            string_storage: Some("strL".into()),
            r: Some(ArrowRSemantics {
                class: "character".into(),
                ..Default::default()
            }),
            ..Default::default()
        })
    );
    pcol!(
        "factor",
        DictionaryArray::try_new(
            Int32Array::from((0..28).map(|i| i % 2).collect::<Vec<_>>()),
            Arc::new(StringArray::from(vec!["low", "high", "unused"]))
        )
        .unwrap(),
        Some(ArrowFieldDocument {
            r: Some(ArrowRSemantics {
                class: "factor".into(),
                ordered: Some(true),
                ..Default::default()
            }),
            ..Default::default()
        })
    );
    fs::write(out.join("profile.expected.json"),serde_json::to_string_pretty(&serde_json::json!({"dataset":profiled.dataset,"columns":profiled.columns.iter().enumerate().map(|(i,column)|serde_json::json!({"name":column.name,"field":column.field,"values":(0..28).map(|row|if i<5 && row>0 {serde_json::json!({"missing":if row==1 {".".into()}else{format!(".{}",(b'a'+row as u8-2) as char)}})}else{cell(column.array.as_ref(),row)}).collect::<Vec<_>>()})).collect::<Vec<_>>()})).unwrap()).unwrap();
    for (name, codec) in [
        ("none", ArrowCompression::Uncompressed),
        ("lz4", ArrowCompression::Lz4),
        ("zstd", ArrowCompression::Zstd),
    ] {
        let mut bytes = Vec::new();
        save_arrow_file_to(&mut bytes, &profiled, codec, 1, true, &mut || false).unwrap();
        verify(&bytes);
        fs::write(out.join(format!("profile-{name}.arrow")), bytes).unwrap();
    }
    let dictionary_type = arrow_schema::DataType::Dictionary(
        Box::new(arrow_schema::DataType::Int32),
        Box::new(arrow_schema::DataType::Utf8),
    );
    let schema = Arc::new(Schema::new(vec![Field::new(
        "factor",
        dictionary_type,
        false,
    )]));
    let mut bytes = Vec::new();
    let mut writer = FileWriter::try_new_with_options(
        &mut bytes,
        &schema,
        IpcWriteOptions::default().with_dictionary_handling(DictionaryHandling::Delta),
    )
    .unwrap();
    for (keys, values) in [(vec![0], vec!["a"]), (vec![1, 0], vec!["a", "b"])] {
        let arr =
            DictionaryArray::try_new(Int32Array::from(keys), Arc::new(StringArray::from(values)))
                .unwrap();
        writer
            .write(&RecordBatch::try_new(schema.clone(), vec![Arc::new(arr)]).unwrap())
            .unwrap();
    }
    writer.finish().unwrap();
    drop(writer);
    verify(&bytes);
    fs::write(out.join("dictionary-delta.arrow"), bytes).unwrap();
    let empty = ArrowWriteDataset {
        dataset: DatasetDocument::default(),
        columns: vec![ArrowWriteColumn {
            name: "empty".into(),
            field: None,
            array: Arc::new(Int32Array::from(Vec::<i32>::new())),
        }],
    };
    let mut bytes = Vec::new();
    save_arrow_file_to(
        &mut bytes,
        &empty,
        ArrowCompression::Zstd,
        1,
        true,
        &mut || false,
    )
    .unwrap();
    verify(&bytes);
    fs::write(out.join("empty.arrow"), bytes).unwrap();
    // A long-distance match follows 96 MiB of zeros. The compressed fixture stays small.
    // Its first and final 128 KiB share a deterministic xorshift byte sequence.
    // Invert 32 initial tail bytes to force a sequence whose 26 offset bits
    // start at bit 7, exercising the fifth input byte omitted by upstream fzstd.
    let mut wide = vec![0_u8; 96 * 1024 * 1024 + 256 * 1024];
    let mut seed = 0x12345678_u32;
    for byte in &mut wide[..128 * 1024] {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        *byte = seed as u8;
    }
    let tail = wide.len() - 128 * 1024;
    wide.copy_within(0..128 * 1024, tail);
    for byte in &mut wide[tail..tail + 32] {
        *byte ^= 0xff;
    }
    let mut encoder = zstd::stream::Encoder::new(Vec::new(), 3).unwrap();
    encoder.window_log(27).unwrap();
    encoder.long_distance_matching(true).unwrap();
    encoder.include_checksum(true).unwrap();
    encoder.write_all(&wide).unwrap();
    let encoded = encoder.finish().unwrap();
    assert_eq!(zstd::decode_all(Cursor::new(&encoded)).unwrap(), wide);
    fs::write(out.join("codec-wide-offset.zstd"), encoded).unwrap();
    let payload = b"Arrow IPC portable codec regression. ".repeat(1000);
    fs::write(out.join("codec.raw"), &payload).unwrap();
    fs::write(
        out.join("codec.zstd"),
        zstd::encode_all(Cursor::new(&payload), 3).unwrap(),
    )
    .unwrap();
    let mut enc = lz4_flex::frame::FrameEncoder::new(Vec::new());
    enc.write_all(&payload).unwrap();
    fs::write(out.join("codec.lz4"), enc.finish().unwrap()).unwrap();
}
