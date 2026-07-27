use std::fmt;

use serde::{de, Deserialize, Deserializer, Serialize, Serializer};

/// Stata file format release.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u16)]
pub enum FormatVersion {
    V113 = 113,
    V114 = 114,
    V115 = 115,
    V117 = 117,
    V118 = 118,
    V119 = 119,
}

impl FormatVersion {
    pub const fn as_u16(self) -> u16 {
        self as u16
    }

    pub const fn is_modern(self) -> bool {
        matches!(self, Self::V117 | Self::V118 | Self::V119)
    }
}

impl fmt::Display for FormatVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.as_u16().fmt(formatter)
    }
}

impl TryFrom<u16> for FormatVersion {
    type Error = u16;

    fn try_from(value: u16) -> Result<Self, Self::Error> {
        match value {
            113 => Ok(Self::V113),
            114 => Ok(Self::V114),
            115 => Ok(Self::V115),
            117 => Ok(Self::V117),
            118 => Ok(Self::V118),
            119 => Ok(Self::V119),
            other => Err(other),
        }
    }
}

impl Serialize for FormatVersion {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u16(self.as_u16())
    }
}

impl<'de> Deserialize<'de> for FormatVersion {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = u16::deserialize(deserializer)?;
        Self::try_from(value)
            .map_err(|invalid| de::Error::custom(format!("unsupported format version {invalid}")))
    }
}

/// Byte order stored in a `.dta` header.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ByteOrder {
    #[serde(rename = "MSF")]
    Msf,
    #[serde(rename = "LSF")]
    Lsf,
}

/// Logical Stata storage type.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum DtaType {
    Byte,
    Int,
    Long,
    Float,
    Double,
    FixedString(u16),
    StrL,
}

impl fmt::Display for DtaType {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Byte => formatter.write_str("byte"),
            Self::Int => formatter.write_str("int"),
            Self::Long => formatter.write_str("long"),
            Self::Float => formatter.write_str("float"),
            Self::Double => formatter.write_str("double"),
            Self::FixedString(width) => write!(formatter, "str{width}"),
            Self::StrL => formatter.write_str("strL"),
        }
    }
}

impl Serialize for DtaType {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for DtaType {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        match value.as_str() {
            "byte" => Ok(Self::Byte),
            "int" => Ok(Self::Int),
            "long" => Ok(Self::Long),
            "float" => Ok(Self::Float),
            "double" => Ok(Self::Double),
            "strL" => Ok(Self::StrL),
            fixed if fixed.starts_with("str") => {
                let width = fixed[3..]
                    .parse::<u16>()
                    .map_err(|_| de::Error::custom(format!("invalid DtaType {value:?}")))?;
                if (1..=2045).contains(&width) {
                    Ok(Self::FixedString(width))
                } else {
                    Err(de::Error::custom(format!("invalid DtaType {value:?}")))
                }
            }
            _ => Err(de::Error::custom(format!("invalid DtaType {value:?}"))),
        }
    }
}

mod decimal_u64 {
    use serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &u64, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.collect_str(value)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<u64, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        value
            .parse()
            .map_err(|_| de::Error::custom(format!("invalid decimal u64 {value:?}")))
    }
}

mod optional_decimal_u64 {
    use serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &Option<u64>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match value {
            Some(value) => serializer.serialize_some(&value.to_string()),
            None => serializer.serialize_none(),
        }
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<u64>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Option::<String>::deserialize(deserializer)?;
        value
            .map(|value| {
                value.parse().map_err(|_| {
                    de::Error::custom(format!("invalid optional decimal u64 {value:?}"))
                })
            })
            .transpose()
    }
}

/// Options controlling which observations and variables are decoded.
///
/// Row ranges are zero-based and are clamped to the available observations.
/// An explicit column projection preserves the first occurrence of every
/// requested index and discards later duplicates.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadOptions {
    #[serde(with = "decimal_u64")]
    pub row_start: u64,
    #[serde(with = "optional_decimal_u64")]
    pub row_count: Option<u64>,
    pub column_indices: Option<Vec<u32>>,
}

/// Metadata describing one variable in source order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VariableInfo {
    pub name: String,
    #[serde(rename = "type")]
    pub dta_type: DtaType,
    pub type_code: u16,
    pub format: String,
    pub label: String,
    pub value_label_name: String,
    pub byte_width: u32,
    #[serde(with = "decimal_u64")]
    pub byte_offset: u64,
}

/// Absolute file offsets. Legacy files synthesize the modern section names
/// from their sequential layout.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SectionOffsets {
    #[serde(with = "decimal_u64")]
    pub stata_data: u64,
    #[serde(with = "decimal_u64")]
    pub map: u64,
    #[serde(with = "decimal_u64")]
    pub variable_types: u64,
    #[serde(with = "decimal_u64")]
    pub varnames: u64,
    #[serde(with = "decimal_u64")]
    pub sortlist: u64,
    #[serde(with = "decimal_u64")]
    pub formats: u64,
    #[serde(with = "decimal_u64")]
    pub value_label_names: u64,
    #[serde(with = "decimal_u64")]
    pub variable_labels: u64,
    #[serde(with = "decimal_u64")]
    pub characteristics: u64,
    #[serde(with = "decimal_u64")]
    pub data: u64,
    #[serde(with = "decimal_u64")]
    pub strls: u64,
    #[serde(with = "decimal_u64")]
    pub value_labels: u64,
    #[serde(with = "decimal_u64")]
    pub stata_data_close: u64,
    #[serde(with = "decimal_u64")]
    pub end_of_file: u64,
}

impl SectionOffsets {
    pub(crate) const NAMES: [&'static str; 14] = [
        "stata_data",
        "map",
        "variable_types",
        "varnames",
        "sortlist",
        "formats",
        "value_label_names",
        "variable_labels",
        "characteristics",
        "data",
        "strls",
        "value_labels",
        "stata_data_close",
        "end_of_file",
    ];

    pub(crate) fn from_array(values: [u64; 14]) -> Self {
        Self {
            stata_data: values[0],
            map: values[1],
            variable_types: values[2],
            varnames: values[3],
            sortlist: values[4],
            formats: values[5],
            value_label_names: values[6],
            variable_labels: values[7],
            characteristics: values[8],
            data: values[9],
            strls: values[10],
            value_labels: values[11],
            stata_data_close: values[12],
            end_of_file: values[13],
        }
    }

    pub(crate) fn as_array(&self) -> [u64; 14] {
        [
            self.stata_data,
            self.map,
            self.variable_types,
            self.varnames,
            self.sortlist,
            self.formats,
            self.value_label_names,
            self.variable_labels,
            self.characteristics,
            self.data,
            self.strls,
            self.value_labels,
            self.stata_data_close,
            self.end_of_file,
        ]
    }
}

/// Canonical metadata model shared with the TypeScript implementation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DtaMetadata {
    pub format_version: FormatVersion,
    pub byte_order: ByteOrder,
    pub nvar: u32,
    #[serde(with = "decimal_u64")]
    pub nobs: u64,
    pub dataset_label: String,
    #[serde(default)]
    pub notes: Vec<String>,
    pub variables: Vec<VariableInfo>,
    pub section_offsets: SectionOffsets,
    #[serde(with = "decimal_u64")]
    pub obs_length: u64,
}

/// Storage-preserving values for one decoded variable.
///
/// Numeric variants retain the Stata storage width. Missing values remain in
/// `values` exactly as decoded and are additionally classified in the parallel
/// `missing_tags` vector.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "storage_type", rename_all = "snake_case")]
pub enum ColumnValues {
    Byte {
        values: Vec<i8>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Int {
        values: Vec<i16>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Long {
        values: Vec<i32>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Float {
        values: Vec<f32>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Double {
        values: Vec<f64>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    FixedString {
        values: Vec<String>,
    },
    /// Resolved `strL` values. Null `(0, 0)` pointers are represented by an
    /// empty string, matching Stata and the TypeScript implementation.
    StrL {
        values: Vec<String>,
    },
}

impl ColumnValues {
    /// Number of decoded observations in the column.
    pub fn len(&self) -> usize {
        match self {
            Self::Byte { values, .. } => values.len(),
            Self::Int { values, .. } => values.len(),
            Self::Long { values, .. } => values.len(),
            Self::Float { values, .. } => values.len(),
            Self::Double { values, .. } => values.len(),
            Self::FixedString { values } => values.len(),
            Self::StrL { values } => values.len(),
        }
    }

    /// Whether the column contains no decoded observations.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

/// One decoded variable, identified by its source metadata index.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Column {
    pub variable_index: u32,
    pub values: ColumnValues,
}

/// One integer-to-text entry in a Stata value-label table.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValueLabelEntry {
    pub value: i32,
    pub missing_tag: Option<crate::MissingTag>,
    pub label: String,
}

/// A named Stata value-label table in source order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValueLabelTable {
    pub name: String,
    pub entries: Vec<ValueLabelEntry>,
}

impl ValueLabelTable {
    /// Find the first entry with the requested raw integer value.
    pub fn entry(&self, value: i32) -> Option<&ValueLabelEntry> {
        self.entries.iter().find(|entry| entry.value == value)
    }
}

/// Column-oriented decoded observations plus their metadata and label tables.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DtaData {
    pub metadata: DtaMetadata,
    #[serde(with = "decimal_u64")]
    pub row_start: u64,
    #[serde(with = "decimal_u64")]
    pub row_count: u64,
    pub columns: Vec<Column>,
    pub value_label_tables: Vec<ValueLabelTable>,
}

impl DtaData {
    /// Find a decoded column by its source variable index.
    pub fn column(&self, variable_index: u32) -> Option<&Column> {
        self.columns
            .iter()
            .find(|column| column.variable_index == variable_index)
    }

    /// Find a decoded column by its source variable name.
    pub fn column_by_name(&self, name: &str) -> Option<&Column> {
        let index = self
            .metadata
            .variables
            .iter()
            .position(|variable| variable.name == name)?;
        self.column(u32::try_from(index).ok()?)
    }

    /// Find a value-label table by its Stata name.
    pub fn value_label_table(&self, name: &str) -> Option<&ValueLabelTable> {
        self.value_label_tables
            .iter()
            .find(|table| table.name == name)
    }

    /// Resolve the label table associated with a source variable index.
    pub fn value_label_table_for_variable(&self, variable_index: u32) -> Option<&ValueLabelTable> {
        let variable = self
            .metadata
            .variables
            .get(usize::try_from(variable_index).ok()?)?;
        if variable.value_label_name.is_empty() {
            return None;
        }
        self.value_label_table(&variable.value_label_name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_serde_uses_typescript_spellings_and_decimal_u64s() {
        let metadata = DtaMetadata {
            format_version: FormatVersion::V119,
            byte_order: ByteOrder::Msf,
            nvar: 1,
            nobs: 9_007_199_254_740_993,
            dataset_label: "fixture".into(),
            notes: vec!["first note".into()],
            variables: vec![VariableInfo {
                name: "x".into(),
                dta_type: DtaType::FixedString(12),
                type_code: 12,
                format: "%12s".into(),
                label: String::new(),
                value_label_name: String::new(),
                byte_width: 12,
                byte_offset: 0,
            }],
            section_offsets: SectionOffsets::from_array([0; 14]),
            obs_length: 12,
        };

        let value = serde_json::to_value(&metadata).unwrap();
        assert_eq!(value["format_version"], 119);
        assert_eq!(value["byte_order"], "MSF");
        assert_eq!(value["nobs"], "9007199254740993");
        assert_eq!(value["notes"][0], "first note");
        assert_eq!(value["variables"][0]["type"], "str12");
        assert_eq!(value["variables"][0]["byte_offset"], "0");
        assert_eq!(value["section_offsets"]["data"], "0");
        assert_eq!(value["obs_length"], "12");

        let round_trip: DtaMetadata = serde_json::from_value(value).unwrap();
        assert_eq!(round_trip, metadata);
    }

    #[test]
    fn read_options_default_to_a_full_read() {
        assert_eq!(
            ReadOptions::default(),
            ReadOptions {
                row_start: 0,
                row_count: None,
                column_indices: None,
            }
        );
    }
}
