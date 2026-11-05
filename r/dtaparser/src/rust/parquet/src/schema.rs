//! From Parquet's schema tree to the flat columns this crate reads.

use crate::format::{
    converted, FileMetaData, LogicalType, PhysicalType, Repetition, SchemaElement, TimeUnit,
};
use crate::profile::{Logical, Storage};
use dta::{Error, Result};

/// What a column holds, as this crate reads it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ColumnType {
    /// INT32 annotated INT(8, signed).
    Int8,
    /// INT32 annotated INT(16, signed).
    Int16,
    /// INT32, unannotated or INT(32, signed).
    Int32,
    /// INT64, unannotated or INT(64, signed).
    Int64,
    /// INT32 annotated INT(8, unsigned) (or UINT_8).
    UInt8,
    /// INT32 annotated INT(16, unsigned).
    UInt16,
    /// INT32 annotated INT(32, unsigned): the bits read as a `u32`.
    UInt32,
    /// INT64 annotated INT(64, unsigned): the bits read as a `u64`.
    UInt64,
    Float,
    Double,
    Boolean,
    /// BYTE_ARRAY annotated STRING, ENUM or JSON: UTF-8 text.
    Text,
    /// BYTE_ARRAY without a text annotation (or BSON), or
    /// FIXED_LEN_BYTE_ARRAY without one (or UUID): bytes.
    Binary,
    /// INT32 DATE: days since 1970-01-01.
    Date,
    /// INT64 TIMESTAMP: units since 1970-01-01 00:00, as an instant
    /// (`utc`) or a clock time without zone. An INT96 timestamp reads as
    /// nanoseconds, not adjusted to UTC (as pyarrow reads it), and
    /// [`ColumnInfo::physical`] says it was INT96.
    Timestamp {
        unit: TimeUnit,
        utc: bool,
    },
    /// TIME: units since midnight; INT32 in milliseconds, INT64 in
    /// microseconds or nanoseconds.
    Time {
        unit: TimeUnit,
        utc: bool,
    },
    /// DECIMAL: an integer (INT32, INT64, or big-endian two's complement
    /// in a BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY of at most 32 bytes)
    /// times 10^-`scale`, with at most `precision` digits. Reads as
    /// text, every digit kept ([`crate::Output::Text`]), or as the
    /// nearest double, where a value with more than 15 significant
    /// digits is an error ([`crate::decimal`]).
    Decimal {
        precision: u32,
        scale: u32,
    },
    /// A type this version does not read; the text names it.
    Unsupported(String),
}

impl ColumnType {
    /// Numbers, including dates, times, timestamps, booleans and
    /// decimals.
    pub fn is_numeric(&self) -> bool {
        !matches!(
            self,
            ColumnType::Text | ColumnType::Binary | ColumnType::Unsupported(_)
        )
    }
}

/// Where a categorical column's levels come from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LevelsFrom {
    /// The dta profile's `categorical` entry: every level, in order,
    /// ordered or not as it says.
    Profile,
    /// The rows read: the column is a dictionary of strings in the
    /// file's `ARROW:schema` (pandas `category`, polars `Categorical`,
    /// an arrow factor) and the profile gives it no levels. The levels
    /// are the distinct values of the rows read, in order of first
    /// appearance ([`crate::ReadReport::levels`]), and unordered.
    Rows,
}

/// What a column is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// A column of data.
    Data,
    /// A list, map or group, which this crate does not read.
    Nested,
}

/// One top-level column of the file.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnInfo {
    pub name: String,
    pub role: Role,
    /// `None` for a nested column.
    pub physical: Option<PhysicalType>,
    pub logical: Option<LogicalType>,
    pub converted: Option<i32>,
    pub kind: ColumnType,
    /// The column is REQUIRED: it has no nulls.
    pub required: bool,
    /// The length of a FIXED_LEN_BYTE_ARRAY column's values.
    pub type_length: Option<i32>,
    /// Whether the column reads as a categorical, and where its levels
    /// come from (read it with [`crate::Output::Levels`]).
    pub levels: Option<LevelsFrom>,
    /// A timestamp's zone, from the file's `ARROW:schema` (the dta
    /// profile's `tz` is in [`crate::Profile`]).
    pub zone: Option<String>,
    /// For a DOUBLE column written wider because it holds `.a` to `.z`,
    /// the storage type the profile records for it.
    pub storage: Option<Storage>,
    /// For a DOUBLE column written as such because it holds `.a` to
    /// `.z`, the date or timestamp the profile records it was: days or
    /// seconds since 1970, its zone in the profile's `tz`. Unlike
    /// [`logical`](Self::logical), this comes from the dta profile.
    pub profile_logical: Option<Logical>,
    /// The first leaf (column chunk) of this column, and how many it has
    /// (more than one only for nested columns).
    pub(crate) leaf: usize,
    pub(crate) leaves: usize,
}

impl ColumnInfo {
    /// The index of the column's chunk in each row group (its first, for
    /// a nested column).
    pub fn leaf(&self) -> usize {
        self.leaf
    }
}

/// The type a flat column reads as.
pub(crate) fn column_type(e: &SchemaElement) -> ColumnType {
    use ColumnType::*;
    let physical = match e.physical {
        Some(p) => p,
        None => return Unsupported("a column without a physical type".into()),
    };
    let invalid = |what: String| Unsupported(format!("{what}, which is not a valid annotation"));
    let conv = e.converted;
    let logical = match &e.logical {
        Some(LogicalType::Null) | None => None,
        Some(l) => Some(l),
    };
    // A converted type stands for its logical type where there is none.
    let from_converted;
    let logical = match (logical, conv) {
        (Some(l), _) => Some(l),
        (None, Some(c)) => {
            from_converted = match c {
                converted::UTF8 => Some(LogicalType::String),
                converted::ENUM => Some(LogicalType::Enum),
                converted::JSON => Some(LogicalType::Json),
                converted::BSON => Some(LogicalType::Bson),
                converted::DATE => Some(LogicalType::Date),
                converted::DECIMAL => Some(LogicalType::Decimal {
                    scale: e.scale.unwrap_or(0),
                    precision: e.precision.unwrap_or(0),
                }),
                converted::TIME_MILLIS | converted::TIME_MICROS => Some(LogicalType::Time {
                    utc: true,
                    unit: Some(if c == converted::TIME_MILLIS {
                        TimeUnit::Millis
                    } else {
                        TimeUnit::Micros
                    }),
                }),
                converted::TIMESTAMP_MILLIS | converted::TIMESTAMP_MICROS => {
                    Some(LogicalType::Timestamp {
                        utc: true,
                        unit: Some(if c == converted::TIMESTAMP_MILLIS {
                            TimeUnit::Millis
                        } else {
                            TimeUnit::Micros
                        }),
                    })
                }
                converted::INT_8 | converted::INT_16 | converted::INT_32 | converted::INT_64 => {
                    Some(LogicalType::Integer {
                        bits: [8, 16, 32, 64][(c - converted::INT_8) as usize],
                        signed: true,
                    })
                }
                converted::UINT_8
                | converted::UINT_16
                | converted::UINT_32
                | converted::UINT_64 => Some(LogicalType::Integer {
                    bits: [8, 16, 32, 64][(c - converted::UINT_8) as usize],
                    signed: false,
                }),
                converted::INTERVAL => {
                    return Unsupported("an INTERVAL, which this version does not read".into())
                }
                _ => None,
            };
            from_converted.as_ref()
        }
        (None, None) => None,
    };
    use PhysicalType as P;
    match (physical, logical) {
        (P::Boolean, _) => Boolean,
        (P::Int32, Some(LogicalType::Integer { bits, signed })) => match (bits, signed) {
            (8, true) => Int8,
            (16, true) => Int16,
            (32, true) => Int32,
            (8, false) => UInt8,
            (16, false) => UInt16,
            (32, false) => UInt32,
            (b, _) => invalid(format!("INT32 annotated INT({b})")),
        },
        (P::Int64, Some(LogicalType::Integer { bits, signed })) => match (bits, signed) {
            (64, true) => Int64,
            (64, false) => UInt64,
            (b, _) => invalid(format!("INT64 annotated INT({b})")),
        },
        (P::Int32, Some(LogicalType::Date)) => Date,
        (
            P::Int32 | P::Int64 | P::FixedLenByteArray | P::ByteArray,
            Some(LogicalType::Decimal { scale, precision }),
        ) => decimal(physical, *precision, *scale, e.type_length),
        (P::Int32 | P::Int64, Some(LogicalType::Time { utc, unit })) => match (physical, unit) {
            (P::Int32, Some(TimeUnit::Millis))
            | (P::Int64, Some(TimeUnit::Micros | TimeUnit::Nanos)) => Time {
                unit: unit.expect("matched"),
                utc: *utc,
            },
            (_, Some(u)) => invalid(format!("{} annotated TIME({u:?})", physical.name())),
            (_, None) => Unsupported("a TIME whose unit this version does not know".into()),
        },
        (P::Int64, Some(LogicalType::Timestamp { utc, unit })) => match unit {
            Some(unit) => Timestamp {
                unit: *unit,
                utc: *utc,
            },
            None => Unsupported("a TIMESTAMP whose unit this version does not know".into()),
        },
        (P::FixedLenByteArray, Some(LogicalType::Float16)) => {
            Unsupported("FLOAT16, which is not read".into())
        }
        (P::ByteArray, Some(LogicalType::String | LogicalType::Enum | LogicalType::Json)) => Text,
        (P::ByteArray, Some(LogicalType::Bson)) => Binary,
        (P::FixedLenByteArray, None | Some(LogicalType::Uuid)) => match e.type_length {
            Some(n) if n > 0 => Binary,
            _ => Unsupported("a FIXED_LEN_BYTE_ARRAY without a length".into()),
        },
        (P::Int32, None) => Int32,
        (P::Int64, None) => Int64,
        (P::Float, _) => Float,
        (P::Double, _) => Double,
        (P::ByteArray, None) => Binary,
        // INT96 has no annotations; every writer of it meant a timestamp.
        (P::Int96, _) => Timestamp {
            unit: TimeUnit::Nanos,
            utc: false,
        },
        (p, Some(l)) => Unsupported(format!(
            "{} annotated {l:?}, which this version does not read",
            p.name()
        )),
        (P::Other(v), None) => Unsupported(format!(
            "physical type {v}, which this version does not know"
        )),
    }
}

/// The most bytes a DECIMAL value may take: 32 holds 76 digits, as
/// Arrow's widest decimal does.
pub(crate) const DECIMAL_BYTES: usize = 32;

fn decimal(physical: PhysicalType, precision: i32, scale: i32, length: Option<i32>) -> ColumnType {
    let bad = |why: &str| {
        ColumnType::Unsupported(format!(
            "DECIMAL({precision}, {scale}), which is not valid: {why}"
        ))
    };
    if !(1..=76).contains(&precision) {
        return bad("the precision must be 1 to 76");
    }
    if scale < 0 || scale > precision {
        return bad("the scale must be 0 to the precision");
    }
    if physical == PhysicalType::FixedLenByteArray
        && !length.is_some_and(|n| n > 0 && n as usize <= DECIMAL_BYTES)
    {
        return bad("its values must take 1 to 32 bytes");
    }
    ColumnType::Decimal {
        precision: precision as u32,
        scale: scale as u32,
    }
}

/// The top-level columns of a file, each with its leaves. Fails if the
/// tree is malformed or row groups have a different number of chunks.
pub(crate) fn columns(meta: &FileMetaData) -> Result<Vec<ColumnInfo>> {
    let schema = &meta.schema;
    let root = schema
        .first()
        .ok_or_else(|| Error::new("the file has no schema"))?;
    let top = usize::try_from(root.num_children.unwrap_or(0))
        .map_err(|_| Error::new("the schema's root has a negative number of children"))?;
    let mut out = Vec::with_capacity(top.min(schema.len()));
    let mut at = 1;
    let mut leaf = 0;
    for _ in 0..top {
        let e = schema
            .get(at)
            .ok_or_else(|| Error::new("the schema ends before its last column"))?;
        let start = at;
        let leaves = subtree_leaves(schema, &mut at, 0)?;
        let nested = at - start > 1
            || e.repetition == Some(Repetition::Repeated)
            || e.num_children.is_some_and(|n| n > 0);
        out.push(ColumnInfo {
            name: e.name.clone(),
            role: if nested { Role::Nested } else { Role::Data },
            physical: if nested { None } else { e.physical },
            logical: e.logical.clone(),
            converted: e.converted,
            kind: if nested {
                ColumnType::Unsupported(
                    "a nested column (list, map or group), which is not read".into(),
                )
            } else {
                column_type(e)
            },
            required: e.repetition == Some(Repetition::Required),
            type_length: e.type_length,
            levels: None,
            zone: None,
            storage: None,
            profile_logical: None,
            leaf,
            leaves,
        });
        leaf += leaves;
    }
    if at != schema.len() {
        return Err(Error::new("the schema has elements after its last column"));
    }
    for (k, g) in meta.row_groups.iter().enumerate() {
        if g.columns.len() != leaf {
            return Err(Error::new(format!(
                "row group {} has {} column chunks, but the schema has {leaf} columns",
                k + 1,
                g.columns.len()
            )));
        }
    }
    Ok(out)
}

/// Walk the subtree at `*at`, leaving `*at` after it; returns its leaves.
fn subtree_leaves(schema: &[SchemaElement], at: &mut usize, depth: usize) -> Result<usize> {
    if depth > 100 {
        return Err(Error::new("the schema is nested too deeply"));
    }
    let e = schema
        .get(*at)
        .ok_or_else(|| Error::new("the schema ends inside a group"))?;
    *at += 1;
    let children = e.num_children.unwrap_or(0);
    if children < 0 {
        return Err(Error::new(format!(
            "schema element \"{}\" has a negative number of children",
            e.name
        )));
    }
    if children == 0 {
        // A primitive is one leaf. An element with neither a type nor
        // children is not a column at all.
        if e.physical.is_none() {
            return Err(Error::new(format!(
                "schema element \"{}\" has neither a type nor children",
                e.name
            )));
        }
        return Ok(1);
    }
    let mut leaves = 0;
    for _ in 0..children {
        leaves += subtree_leaves(schema, at, depth + 1)?;
    }
    Ok(leaves)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaf(
        name: &str,
        p: PhysicalType,
        logical: Option<LogicalType>,
        conv: Option<i32>,
    ) -> SchemaElement {
        SchemaElement {
            name: name.into(),
            physical: Some(p),
            repetition: Some(Repetition::Optional),
            logical,
            converted: conv,
            ..Default::default()
        }
    }

    #[test]
    fn types_from_logical_and_converted_annotations() {
        use PhysicalType::*;
        let cases = [
            (
                leaf(
                    "a",
                    Int32,
                    Some(LogicalType::Integer {
                        bits: 8,
                        signed: true,
                    }),
                    None,
                ),
                ColumnType::Int8,
            ),
            (
                leaf("a", Int32, None, Some(converted::INT_16)),
                ColumnType::Int16,
            ),
            (leaf("a", Int32, None, None), ColumnType::Int32),
            (
                leaf("a", Int32, None, Some(converted::DATE)),
                ColumnType::Date,
            ),
            (
                leaf("a", Int64, None, Some(converted::TIMESTAMP_MILLIS)),
                ColumnType::Timestamp {
                    unit: TimeUnit::Millis,
                    utc: true,
                },
            ),
            (
                leaf(
                    "a",
                    Int64,
                    Some(LogicalType::Timestamp {
                        utc: false,
                        unit: Some(TimeUnit::Nanos),
                    }),
                    None,
                ),
                ColumnType::Timestamp {
                    unit: TimeUnit::Nanos,
                    utc: false,
                },
            ),
            (
                leaf("a", ByteArray, None, Some(converted::UTF8)),
                ColumnType::Text,
            ),
            (
                leaf("a", ByteArray, Some(LogicalType::Enum), None),
                ColumnType::Text,
            ),
            (leaf("a", ByteArray, None, None), ColumnType::Binary),
            (leaf("a", Boolean, None, None), ColumnType::Boolean),
        ];
        for (e, want) in cases {
            assert_eq!(column_type(&e), want, "{e:?}");
        }
        // The types the second slice reads.
        let with = |mut e: SchemaElement, f: &dyn Fn(&mut SchemaElement)| {
            f(&mut e);
            e
        };
        let unsigned = |bits| {
            Some(LogicalType::Integer {
                bits,
                signed: false,
            })
        };
        let dec = |precision, scale| Some(LogicalType::Decimal { scale, precision });
        let time = |unit| {
            Some(LogicalType::Time {
                utc: false,
                unit: Some(unit),
            })
        };
        let flba = |n: i32, logical| {
            with(leaf("a", FixedLenByteArray, logical, None), &|e| {
                e.type_length = Some(n)
            })
        };
        let cases = [
            (
                leaf("a", Int96, None, None),
                ColumnType::Timestamp {
                    unit: TimeUnit::Nanos,
                    utc: false,
                },
            ),
            (leaf("a", Int32, unsigned(8), None), ColumnType::UInt8),
            (leaf("a", Int32, unsigned(16), None), ColumnType::UInt16),
            (
                leaf("a", Int32, None, Some(converted::UINT_32)),
                ColumnType::UInt32,
            ),
            (
                leaf("a", Int64, None, Some(converted::UINT_64)),
                ColumnType::UInt64,
            ),
            (
                leaf("a", Int32, time(TimeUnit::Millis), None),
                ColumnType::Time {
                    unit: TimeUnit::Millis,
                    utc: false,
                },
            ),
            (
                leaf("a", Int64, time(TimeUnit::Nanos), None),
                ColumnType::Time {
                    unit: TimeUnit::Nanos,
                    utc: false,
                },
            ),
            (
                leaf("a", Int64, None, Some(converted::TIME_MICROS)),
                ColumnType::Time {
                    unit: TimeUnit::Micros,
                    utc: true,
                },
            ),
            (
                leaf("a", Int32, dec(9, 2), None),
                ColumnType::Decimal {
                    precision: 9,
                    scale: 2,
                },
            ),
            (
                leaf("a", ByteArray, dec(40, 0), None),
                ColumnType::Decimal {
                    precision: 40,
                    scale: 0,
                },
            ),
            (
                flba(16, dec(38, 10)),
                ColumnType::Decimal {
                    precision: 38,
                    scale: 10,
                },
            ),
            (
                with(leaf("a", Int64, None, Some(converted::DECIMAL)), &|e| {
                    e.precision = Some(18);
                    e.scale = Some(4)
                }),
                ColumnType::Decimal {
                    precision: 18,
                    scale: 4,
                },
            ),
            (flba(3, None), ColumnType::Binary),
            (flba(16, Some(LogicalType::Uuid)), ColumnType::Binary),
            (
                leaf("a", ByteArray, Some(LogicalType::Json), None),
                ColumnType::Text,
            ),
            (
                leaf("a", ByteArray, None, Some(converted::ENUM)),
                ColumnType::Text,
            ),
        ];
        for (e, want) in cases {
            assert_eq!(column_type(&e), want, "{e:?}");
        }
        for (e, word) in [
            (flba(2, Some(LogicalType::Float16)), "FLOAT16"),
            (leaf("a", Int32, unsigned(64), None), "INT(64)"),
            (leaf("a", Int32, time(TimeUnit::Micros), None), "TIME"),
            (leaf("a", Int64, time(TimeUnit::Millis), None), "TIME"),
            (
                leaf("a", FixedLenByteArray, dec(20, 2), None),
                "1 to 32 bytes",
            ),
            (flba(33, dec(20, 2)), "1 to 32 bytes"),
            (leaf("a", Int64, dec(18, 19), None), "scale"),
            (leaf("a", Int64, dec(0, 0), None), "precision"),
            (leaf("a", ByteArray, dec(77, 0), None), "precision"),
            (
                leaf("a", Int64, None, Some(converted::DECIMAL)),
                "precision",
            ),
            (leaf("a", FixedLenByteArray, None, None), "without a length"),
            (flba(0, None), "without a length"),
            (
                with(flba(12, None), &|e| e.converted = Some(converted::INTERVAL)),
                "INTERVAL",
            ),
        ] {
            match column_type(&e) {
                ColumnType::Unsupported(why) => assert!(why.contains(word), "{word}: {why}"),
                other => panic!("{word}: {other:?}"),
            }
        }
    }

    #[test]
    fn nested_columns_are_found_with_their_leaves() {
        let group = |name: &str, n: i32, rep: Repetition| SchemaElement {
            name: name.into(),
            num_children: Some(n),
            repetition: Some(rep),
            ..Default::default()
        };
        let meta = FileMetaData {
            version: 1,
            schema: vec![
                SchemaElement {
                    name: "schema".into(),
                    num_children: Some(4),
                    ..Default::default()
                },
                leaf("a", PhysicalType::Int32, None, None),
                group("l", 1, Repetition::Optional),
                group("list", 1, Repetition::Repeated),
                leaf("element", PhysicalType::Int32, None, None),
                SchemaElement {
                    repetition: Some(Repetition::Repeated),
                    ..leaf("r", PhysicalType::Int64, None, None)
                },
                leaf("b", PhysicalType::Double, None, None),
            ],
            num_rows: 0,
            row_groups: vec![],
            key_value: vec![],
            created_by: None,
            column_orders: None,
            encrypted: false,
        };
        let cols = columns(&meta).unwrap();
        let summary: Vec<(&str, Role, usize, usize)> = cols
            .iter()
            .map(|c| (c.name.as_str(), c.role, c.leaf, c.leaves))
            .collect();
        assert_eq!(
            summary,
            vec![
                ("a", Role::Data, 0, 1),
                ("l", Role::Nested, 1, 1),
                ("r", Role::Nested, 2, 1),
                ("b", Role::Data, 3, 1)
            ]
        );
        let mut bad = meta.clone();
        bad.schema[0].num_children = Some(9);
        assert!(columns(&bad).is_err());
        let mut bad = meta.clone();
        bad.schema[2].num_children = Some(-1);
        assert!(columns(&bad).is_err());
        let mut bad = meta.clone();
        bad.schema[0].num_children = Some(1);
        assert!(columns(&bad).is_err());
        // An element with neither a type nor children, at the top or in a
        // group.
        for at in [1, 4] {
            let mut bad = meta.clone();
            bad.schema[at].physical = None;
            let e = columns(&bad).unwrap_err();
            assert!(
                e.message.contains("neither a type nor children"),
                "{}",
                e.message
            );
        }
    }
}
