/// How a variable's values are stored.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageType {
    Byte,
    Int,
    Long,
    Float,
    Double,
    /// A fixed-width string of this many bytes (1 to 2045).
    Str(u16),
    /// A long string stored in the strL section.
    StrL,
}

impl StorageType {
    /// Bytes the type takes in a row.
    pub fn width(self) -> usize {
        match self {
            StorageType::Byte => 1,
            StorageType::Int => 2,
            StorageType::Long | StorageType::Float => 4,
            StorageType::Double | StorageType::StrL => 8,
            StorageType::Str(n) => n as usize,
        }
    }

    pub fn is_numeric(self) -> bool {
        !matches!(self, StorageType::Str(_) | StorageType::StrL)
    }

    /// The name Stata uses for the type: `byte`, `str12`, `strL`.
    pub fn name(self) -> String {
        match self {
            StorageType::Byte => "byte".into(),
            StorageType::Int => "int".into(),
            StorageType::Long => "long".into(),
            StorageType::Float => "float".into(),
            StorageType::Double => "double".into(),
            StorageType::Str(n) => format!("str{n}"),
            StorageType::StrL => "strL".into(),
        }
    }

    /// The type code releases 117 and later store.
    pub(crate) fn from_code_117(code: u16) -> Option<Self> {
        Some(match code {
            1..=2045 => StorageType::Str(code),
            32768 => StorageType::StrL,
            65526 => StorageType::Double,
            65527 => StorageType::Float,
            65528 => StorageType::Long,
            65529 => StorageType::Int,
            65530 => StorageType::Byte,
            _ => return None,
        })
    }

    pub(crate) fn code_117(self) -> u16 {
        match self {
            StorageType::Str(n) => n,
            StorageType::StrL => 32768,
            StorageType::Double => 65526,
            StorageType::Float => 65527,
            StorageType::Long => 65528,
            StorageType::Int => 65529,
            StorageType::Byte => 65530,
        }
    }
}
