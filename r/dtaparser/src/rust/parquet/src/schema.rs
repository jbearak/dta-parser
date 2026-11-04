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
    Float,
    Double,
    Boolean,
    /// BYTE_ARRAY annotated STRING, ENUM or JSON: UTF-8 text.
    Text,
    /// BYTE_ARRAY without a text annotation (or BSON): bytes.
    Binary,
    /// INT32 DATE: days since 1970-01-01.
    Date,
    /// INT64 TIMESTAMP: units since 1970-01-01 00:00, as an instant
    /// (`utc`) or a clock time without zone.
    Timestamp {
        unit: TimeUnit,
        utc: bool,
    },
    /// A type this version does not read; the text names it.
    Unsupported(String),
}

impl ColumnType {
    /// Numbers, including dates, timestamps and booleans.
    pub fn is_numeric(&self) -> bool {
        !matches!(
            self,
            ColumnType::Text | ColumnType::Binary | ColumnType::Unsupported(_)
        )
    }
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
    let unsupported =
        |what: &str| Unsupported(format!("{what}, which this version does not read yet"));
    let physical = match e.physical {
        Some(p) => p,
        None => return Unsupported("a column without a physical type".into()),
    };
    let conv = e.converted;
    match (physical, &e.logical) {
        (PhysicalType::Boolean, _) => Boolean,
        (PhysicalType::Int32, Some(LogicalType::Integer { bits, signed: true })) => match bits {
            8 => Int8,
            16 => Int16,
            32 => Int32,
            b => Unsupported(format!(
                "INT32 annotated INT({b}), which is not a valid annotation"
            )),
        },
        (
            PhysicalType::Int32 | PhysicalType::Int64,
            Some(LogicalType::Integer { signed: false, .. }),
        ) => unsupported("an unsigned integer"),
        (PhysicalType::Int32, Some(LogicalType::Date)) => Date,
        (_, Some(LogicalType::Decimal { .. })) => unsupported("DECIMAL"),
        (_, Some(LogicalType::Time { .. })) => unsupported("TIME"),
        (
            PhysicalType::Int64,
            Some(LogicalType::Integer {
                bits: 64,
                signed: true,
            }),
        ) => Int64,
        (PhysicalType::Int64, Some(LogicalType::Timestamp { utc, unit })) => match unit {
            Some(unit) => Timestamp {
                unit: *unit,
                utc: *utc,
            },
            None => Unsupported("a TIMESTAMP whose unit this version does not know".into()),
        },
        (PhysicalType::FixedLenByteArray, Some(LogicalType::Float16)) => {
            Unsupported("FLOAT16, which is not read".into())
        }
        (
            PhysicalType::ByteArray,
            Some(LogicalType::String | LogicalType::Enum | LogicalType::Json),
        ) => Text,
        (PhysicalType::ByteArray, Some(LogicalType::Bson)) => Binary,
        (PhysicalType::Int32, None | Some(LogicalType::Null)) => match conv {
            Some(converted::INT_8) => Int8,
            Some(converted::INT_16) => Int16,
            Some(converted::DATE) => Date,
            Some(converted::UINT_8 | converted::UINT_16 | converted::UINT_32) => {
                unsupported("an unsigned integer")
            }
            Some(converted::DECIMAL) => unsupported("DECIMAL"),
            Some(converted::TIME_MILLIS) => unsupported("TIME"),
            _ => Int32,
        },
        (PhysicalType::Int64, None | Some(LogicalType::Null)) => match conv {
            Some(converted::TIMESTAMP_MILLIS) => Timestamp {
                unit: TimeUnit::Millis,
                utc: true,
            },
            Some(converted::TIMESTAMP_MICROS) => Timestamp {
                unit: TimeUnit::Micros,
                utc: true,
            },
            Some(converted::UINT_64) => unsupported("an unsigned integer"),
            Some(converted::DECIMAL) => unsupported("DECIMAL"),
            Some(converted::TIME_MICROS) => unsupported("TIME"),
            _ => Int64,
        },
        (PhysicalType::Float, _) => Float,
        (PhysicalType::Double, _) => Double,
        (PhysicalType::ByteArray, None | Some(LogicalType::Null)) => match conv {
            Some(converted::UTF8 | converted::ENUM | converted::JSON) => Text,
            Some(converted::DECIMAL) => unsupported("DECIMAL"),
            _ => Binary,
        },
        (PhysicalType::Int96, _) => unsupported("an INT96 timestamp"),
        (PhysicalType::FixedLenByteArray, _) => unsupported("FIXED_LEN_BYTE_ARRAY"),
        (p, Some(l)) => Unsupported(format!(
            "{} annotated {l:?}, which this version does not read",
            p.name()
        )),
        (PhysicalType::Other(v), None) => Unsupported(format!(
            "physical type {v}, which this version does not know"
        )),
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
        for (e, word) in [
            (leaf("a", Int96, None, None), "INT96"),
            (
                leaf(
                    "a",
                    Int32,
                    Some(LogicalType::Integer {
                        bits: 16,
                        signed: false,
                    }),
                    None,
                ),
                "unsigned",
            ),
            (leaf("a", Int64, None, Some(converted::UINT_64)), "unsigned"),
            (
                leaf("a", FixedLenByteArray, Some(LogicalType::Float16), None),
                "FLOAT16",
            ),
            (
                leaf(
                    "a",
                    FixedLenByteArray,
                    Some(LogicalType::Decimal {
                        scale: 2,
                        precision: 20,
                    }),
                    None,
                ),
                "DECIMAL",
            ),
            (
                leaf(
                    "a",
                    Int64,
                    Some(LogicalType::Time {
                        utc: true,
                        unit: Some(TimeUnit::Micros),
                    }),
                    None,
                ),
                "TIME",
            ),
        ] {
            match column_type(&e) {
                ColumnType::Unsupported(why) => assert!(why.contains(word), "{why}"),
                other => panic!("{other:?}"),
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
