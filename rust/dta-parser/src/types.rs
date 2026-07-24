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

/// Byte order marker stored in a modern `.dta` header.
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

/// Absolute file offsets from the 14-entry modern section map.
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
    pub variables: Vec<VariableInfo>,
    pub section_offsets: SectionOffsets,
    #[serde(with = "decimal_u64")]
    pub obs_length: u64,
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
        assert_eq!(value["variables"][0]["type"], "str12");
        assert_eq!(value["variables"][0]["byte_offset"], "0");
        assert_eq!(value["section_offsets"]["data"], "0");
        assert_eq!(value["obs_length"], "12");

        let round_trip: DtaMetadata = serde_json::from_value(value).unwrap();
        assert_eq!(round_trip, metadata);
    }
}
