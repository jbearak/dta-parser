use std::io::Cursor;

use dta_parser::{
    read_dta, read_dta_with_options, write_dta_to, ByteOrder, ColumnValues, DtaType,
    DtaWriteColumn, DtaWriteColumnValues, DtaWriteData, DtaWriteLabelValue, DtaWriteNumericValue,
    DtaWriteOptions, DtaWriteValueLabel, FormatVersion, MissingTag, ReadOptions, StataVersion,
};
use sha2::{Digest, Sha256};

#[test]
fn writes_a_release_118_dataset_that_the_public_parser_can_read() {
    let values = [
        DtaWriteNumericValue::Value(-5.0),
        DtaWriteNumericValue::Missing(MissingTag::A),
    ];
    let data = DtaWriteData {
        dataset_label: "writer tracer bullet".into(),
        notes: vec!["written by dta-parser".into(), String::new()],
        row_count: 2,
        columns: vec![DtaWriteColumn {
            name: "answer".into(),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: "the answer".into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let options = DtaWriteOptions {
        stata_version: StataVersion::V19,
        timestamp: Some("27 Aug 2026 12:34".into()),
    };

    let mut output = Cursor::new(Vec::new());
    let summary = write_dta_to(&mut output, &data, &options).unwrap();
    let bytes = output.into_inner();

    assert_eq!(summary.format_version, FormatVersion::V118);
    assert!(bytes.starts_with(b"<stata_dta><header><release>118</release><byteorder>LSF"));
    assert_eq!(
        format!("{:x}", Sha256::digest(&bytes)),
        "07aa56af3b191c8fba1f9cbde98305b79208876549fcef7a51a37e30c043fb22"
    );

    let parsed = read_dta(&bytes).unwrap();
    assert_eq!(parsed.metadata.format_version, FormatVersion::V118);
    assert_eq!(parsed.metadata.byte_order, ByteOrder::Lsf);
    assert_eq!(parsed.metadata.dataset_label, "writer tracer bullet");
    assert_eq!(parsed.metadata.notes, ["written by dta-parser", ""]);
    assert_eq!(parsed.metadata.variables[0].name, "answer");
    assert_eq!(parsed.metadata.variables[0].label, "the answer");
    assert_eq!(parsed.metadata.variables[0].dta_type, DtaType::Byte);
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::Byte {
            values: vec![-5, 102],
            missing_tags: vec![None, Some(MissingTag::A)],
        }
    );
}

#[test]
fn writes_every_storage_width_fixed_utf8_and_sorted_value_labels() {
    let byte = [
        DtaWriteNumericValue::Value(-127.0),
        DtaWriteNumericValue::Missing(MissingTag::Z),
    ];
    let int = [
        DtaWriteNumericValue::Value(-32_767.0),
        DtaWriteNumericValue::Value(32_740.0),
    ];
    let long = [
        DtaWriteNumericValue::Value(-1.0),
        DtaWriteNumericValue::Value(1.0),
    ];
    let float = [
        DtaWriteNumericValue::Value(1.25),
        DtaWriteNumericValue::Missing(MissingTag::System),
    ];
    let double = [
        DtaWriteNumericValue::Value(-2.5),
        DtaWriteNumericValue::Missing(MissingTag::C),
    ];
    let strings = ["é".to_owned(), "abcd".to_owned()];
    let data = DtaWriteData {
        dataset_label: String::new(),
        notes: Vec::new(),
        row_count: 2,
        columns: vec![
            DtaWriteColumn {
                name: "b".into(),
                dta_type: DtaType::Byte,
                format: "%8.0g".into(),
                label: String::new(),
                has_value_labels: false,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&byte),
            },
            DtaWriteColumn {
                name: "i".into(),
                dta_type: DtaType::Int,
                format: "%8.0g".into(),
                label: String::new(),
                has_value_labels: false,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&int),
            },
            DtaWriteColumn {
                name: "l".into(),
                dta_type: DtaType::Long,
                format: "%12.0g".into(),
                label: String::new(),
                has_value_labels: true,
                value_labels: vec![
                    DtaWriteValueLabel {
                        value: DtaWriteLabelValue::Integer(1),
                        label: "positive".into(),
                    },
                    DtaWriteValueLabel {
                        value: DtaWriteLabelValue::Integer(-1),
                        label: "negative".into(),
                    },
                ],
                values: DtaWriteColumnValues::Numeric(&long),
            },
            DtaWriteColumn {
                name: "f".into(),
                dta_type: DtaType::Float,
                format: "%9.0g".into(),
                label: String::new(),
                has_value_labels: false,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&float),
            },
            DtaWriteColumn {
                name: "d".into(),
                dta_type: DtaType::Double,
                format: "%10.0g".into(),
                label: String::new(),
                has_value_labels: false,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&double),
            },
            DtaWriteColumn {
                name: "s".into(),
                dta_type: DtaType::FixedString(4),
                format: "%9s".into(),
                label: String::new(),
                has_value_labels: false,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Strings(&strings),
            },
        ],
    };

    let mut output = Cursor::new(Vec::new());
    write_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let parsed = read_dta(&output.into_inner()).unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::Byte {
            values: vec![-127, 127],
            missing_tags: vec![None, Some(MissingTag::Z)]
        }
    );
    assert_eq!(
        parsed.columns[1].values,
        ColumnValues::Int {
            values: vec![-32_767, 32_740],
            missing_tags: vec![None, None]
        }
    );
    assert_eq!(
        parsed.columns[2].values,
        ColumnValues::Long {
            values: vec![-1, 1],
            missing_tags: vec![None, None]
        }
    );
    assert_eq!(
        parsed.columns[3].values,
        ColumnValues::Float {
            values: vec![1.25, f32::from_bits(dta_parser::FLOAT_MISSING_DOT_BITS)],
            missing_tags: vec![None, Some(MissingTag::System)]
        }
    );
    assert_eq!(
        parsed.columns[4].values,
        ColumnValues::Double {
            values: vec![
                -2.5,
                f64::from_bits(
                    dta_parser::DOUBLE_MISSING_DOT_BITS + 3 * dta_parser::DOUBLE_MISSING_STEP_BITS
                )
            ],
            missing_tags: vec![None, Some(MissingTag::C)]
        }
    );
    assert_eq!(
        parsed.columns[5].values,
        ColumnValues::FixedString {
            values: strings.to_vec()
        }
    );
    let labels = parsed.value_label_table_for_variable(2).unwrap();
    assert_eq!(
        labels
            .entries
            .iter()
            .map(|entry| (entry.value, entry.label.as_str()))
            .collect::<Vec<_>>(),
        vec![(-1, "negative"), (1, "positive")]
    );
}

#[test]
fn writes_an_attached_empty_value_label_table() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let data = DtaWriteData {
        dataset_label: String::new(),
        notes: Vec::new(),
        row_count: 1,
        columns: vec![DtaWriteColumn {
            name: "coded".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new(),
            has_value_labels: true,
            value_labels: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    write_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let parsed = read_dta(&output.into_inner()).unwrap();
    let table = parsed.value_label_table_for_variable(0).unwrap();
    assert!(table.entries.is_empty());
}

#[test]
fn release_119_uses_three_variable_bytes_in_strl_pointers() {
    let numeric = [DtaWriteNumericValue::Value(0.0)];
    let text = ["wide strL".to_owned()];
    let mut columns = Vec::with_capacity(32_768);
    for index in 0..32_767 {
        columns.push(DtaWriteColumn {
            name: format!("x{index}"),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: String::new(),
            has_value_labels: false,
            value_labels: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&numeric),
        });
    }
    columns.push(DtaWriteColumn {
        name: "wide_text".into(),
        dta_type: DtaType::StrL,
        format: "%9s".into(),
        label: String::new(),
        has_value_labels: false,
        value_labels: Vec::new(),
        values: DtaWriteColumnValues::Strings(&text),
    });
    let data = DtaWriteData {
        dataset_label: String::new(),
        notes: Vec::new(),
        row_count: 1,
        columns,
    };

    let mut output = Cursor::new(Vec::new());
    let summary = write_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    assert_eq!(summary.format_version, FormatVersion::V119);

    let bytes = output.into_inner();
    assert_eq!(
        format!("{:x}", Sha256::digest(&bytes)),
        "65a4eefafbc550066f61cfe9f9d7898137af21c80cde587b6cbeb8c83cbcc4ed"
    );
    let parsed = read_dta_with_options(
        &bytes,
        &ReadOptions {
            row_start: 0,
            row_count: None,
            column_indices: Some(vec![32_767]),
        },
    )
    .unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::StrL {
            values: text.to_vec()
        }
    );
}

#[test]
fn writes_deduplicated_strl_values_and_null_pointers_for_empty_strings() {
    let values = vec![
        "a repeated long value".to_owned(),
        "a repeated long value".to_owned(),
        "a different long value".to_owned(),
        String::new(),
    ];
    let data = DtaWriteData {
        dataset_label: String::new(),
        notes: Vec::new(),
        row_count: 4,
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new(),
            has_value_labels: false,
            value_labels: Vec::new(),
            values: DtaWriteColumnValues::Strings(&values),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    write_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let bytes = output.into_inner();

    let parsed = read_dta(&bytes).unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::StrL {
            values: values.clone()
        }
    );
    assert_eq!(
        bytes.windows(3).filter(|window| *window == b"GSO").count(),
        2,
        "the repeated value should reference its first GSO record"
    );
}
