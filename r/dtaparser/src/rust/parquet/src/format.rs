//! Parquet's footer and page headers (`parquet.thrift`), read from and
//! written to the Thrift compact protocol.
//!
//! Only the fields this crate uses are kept; others are skipped on read.
//! Enumerations keep values they do not know as `Other`, so a file from a
//! newer writer still opens and the column that uses the new value is
//! the one that fails.

use crate::thrift::{self, In, Out};
use dta::Result;

/// A column's physical type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PhysicalType {
    Boolean,
    Int32,
    Int64,
    Int96,
    Float,
    Double,
    ByteArray,
    FixedLenByteArray,
    Other(i32),
}

impl PhysicalType {
    fn from_i32(v: i32) -> Self {
        use PhysicalType::*;
        match v {
            0 => Boolean,
            1 => Int32,
            2 => Int64,
            3 => Int96,
            4 => Float,
            5 => Double,
            6 => ByteArray,
            7 => FixedLenByteArray,
            v => Other(v),
        }
    }

    fn to_i32(self) -> i32 {
        use PhysicalType::*;
        match self {
            Boolean => 0,
            Int32 => 1,
            Int64 => 2,
            Int96 => 3,
            Float => 4,
            Double => 5,
            ByteArray => 6,
            FixedLenByteArray => 7,
            Other(v) => v,
        }
    }

    /// The name used in the format's specification.
    pub fn name(self) -> String {
        use PhysicalType::*;
        match self {
            Boolean => "BOOLEAN".into(),
            Int32 => "INT32".into(),
            Int64 => "INT64".into(),
            Int96 => "INT96".into(),
            Float => "FLOAT".into(),
            Double => "DOUBLE".into(),
            ByteArray => "BYTE_ARRAY".into(),
            FixedLenByteArray => "FIXED_LEN_BYTE_ARRAY".into(),
            Other(v) => format!("physical type {v}"),
        }
    }
}

/// Whether a field may be null or repeat.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Repetition {
    Required,
    Optional,
    Repeated,
}

/// A compression codec.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Codec {
    Uncompressed,
    Snappy,
    Gzip,
    Lzo,
    Brotli,
    /// The deprecated Hadoop framing of LZ4.
    Lz4,
    Zstd,
    Lz4Raw,
    Other(i32),
}

impl Codec {
    fn from_i32(v: i32) -> Self {
        use Codec::*;
        match v {
            0 => Uncompressed,
            1 => Snappy,
            2 => Gzip,
            3 => Lzo,
            4 => Brotli,
            5 => Lz4,
            6 => Zstd,
            7 => Lz4Raw,
            v => Other(v),
        }
    }

    fn to_i32(self) -> i32 {
        use Codec::*;
        match self {
            Uncompressed => 0,
            Snappy => 1,
            Gzip => 2,
            Lzo => 3,
            Brotli => 4,
            Lz4 => 5,
            Zstd => 6,
            Lz4Raw => 7,
            Other(v) => v,
        }
    }

    /// The codec's name as the format's specification writes it.
    pub fn name(self) -> String {
        use Codec::*;
        match self {
            Uncompressed => "UNCOMPRESSED".into(),
            Snappy => "SNAPPY".into(),
            Gzip => "GZIP".into(),
            Lzo => "LZO".into(),
            Brotli => "BROTLI".into(),
            Lz4 => "LZ4 (Hadoop framing)".into(),
            Zstd => "ZSTD".into(),
            Lz4Raw => "LZ4_RAW".into(),
            Other(v) => format!("codec {v}"),
        }
    }
}

/// A value or level encoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Plain,
    PlainDictionary,
    Rle,
    BitPacked,
    DeltaBinaryPacked,
    DeltaLengthByteArray,
    DeltaByteArray,
    RleDictionary,
    ByteStreamSplit,
    Other(i32),
}

impl Encoding {
    fn from_i32(v: i32) -> Self {
        use Encoding::*;
        match v {
            0 => Plain,
            2 => PlainDictionary,
            3 => Rle,
            4 => BitPacked,
            5 => DeltaBinaryPacked,
            6 => DeltaLengthByteArray,
            7 => DeltaByteArray,
            8 => RleDictionary,
            9 => ByteStreamSplit,
            v => Other(v),
        }
    }

    fn to_i32(self) -> i32 {
        use Encoding::*;
        match self {
            Plain => 0,
            PlainDictionary => 2,
            Rle => 3,
            BitPacked => 4,
            DeltaBinaryPacked => 5,
            DeltaLengthByteArray => 6,
            DeltaByteArray => 7,
            RleDictionary => 8,
            ByteStreamSplit => 9,
            Other(v) => v,
        }
    }

    /// The encoding's name as the format's specification writes it.
    pub fn name(self) -> String {
        use Encoding::*;
        match self {
            Plain => "PLAIN".into(),
            PlainDictionary => "PLAIN_DICTIONARY".into(),
            Rle => "RLE".into(),
            BitPacked => "BIT_PACKED".into(),
            DeltaBinaryPacked => "DELTA_BINARY_PACKED".into(),
            DeltaLengthByteArray => "DELTA_LENGTH_BYTE_ARRAY".into(),
            DeltaByteArray => "DELTA_BYTE_ARRAY".into(),
            RleDictionary => "RLE_DICTIONARY".into(),
            ByteStreamSplit => "BYTE_STREAM_SPLIT".into(),
            Other(v) => format!("encoding {v}"),
        }
    }
}

/// The unit of a time or timestamp.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TimeUnit {
    Millis,
    Micros,
    Nanos,
}

impl TimeUnit {
    /// Units in one second.
    pub fn per_second(self) -> i64 {
        match self {
            TimeUnit::Millis => 1_000,
            TimeUnit::Micros => 1_000_000,
            TimeUnit::Nanos => 1_000_000_000,
        }
    }
}

/// A logical type annotation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LogicalType {
    String,
    Map,
    List,
    Enum,
    Decimal {
        scale: i32,
        precision: i32,
    },
    Date,
    Time {
        utc: bool,
        unit: Option<TimeUnit>,
    },
    Timestamp {
        utc: bool,
        unit: Option<TimeUnit>,
    },
    Integer {
        bits: i8,
        signed: bool,
    },
    Null,
    Json,
    Bson,
    Uuid,
    Float16,
    /// A logical type this crate does not know, by its field id.
    Other(i16),
}

/// Converted types (the older annotations), by number.
pub mod converted {
    pub const UTF8: i32 = 0;
    pub const MAP: i32 = 1;
    pub const MAP_KEY_VALUE: i32 = 2;
    pub const LIST: i32 = 3;
    pub const ENUM: i32 = 4;
    pub const DECIMAL: i32 = 5;
    pub const DATE: i32 = 6;
    pub const TIME_MILLIS: i32 = 7;
    pub const TIME_MICROS: i32 = 8;
    pub const TIMESTAMP_MILLIS: i32 = 9;
    pub const TIMESTAMP_MICROS: i32 = 10;
    pub const UINT_8: i32 = 11;
    pub const UINT_16: i32 = 12;
    pub const UINT_32: i32 = 13;
    pub const UINT_64: i32 = 14;
    pub const INT_8: i32 = 15;
    pub const INT_16: i32 = 16;
    pub const INT_32: i32 = 17;
    pub const INT_64: i32 = 18;
    pub const JSON: i32 = 19;
    pub const BSON: i32 = 20;
    pub const INTERVAL: i32 = 21;
}

/// One node of the schema tree, in depth-first order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct SchemaElement {
    pub physical: Option<PhysicalType>,
    pub type_length: Option<i32>,
    pub repetition: Option<Repetition>,
    pub name: String,
    pub num_children: Option<i32>,
    pub converted: Option<i32>,
    pub scale: Option<i32>,
    pub precision: Option<i32>,
    pub logical: Option<LogicalType>,
}

/// Minimum, maximum and null count of a column chunk.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Statistics {
    /// The deprecated fields, in signed byte order.
    pub max: Option<Vec<u8>>,
    pub min: Option<Vec<u8>>,
    pub null_count: Option<i64>,
    pub distinct_count: Option<i64>,
    pub max_value: Option<Vec<u8>>,
    pub min_value: Option<Vec<u8>>,
}

/// What one column chunk holds and where.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnMetaData {
    pub physical: PhysicalType,
    pub encodings: Vec<Encoding>,
    pub path: Vec<String>,
    pub codec: Codec,
    pub num_values: i64,
    pub total_uncompressed_size: i64,
    pub total_compressed_size: i64,
    pub data_page_offset: i64,
    pub dictionary_page_offset: Option<i64>,
    pub statistics: Option<Statistics>,
}

/// One column of one row group.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnChunk {
    /// Set when the chunk is in another file, which this crate does not
    /// read.
    pub file_path: Option<String>,
    pub meta: Option<ColumnMetaData>,
    /// Offset and length of the chunk's offset index.
    pub offset_index: Option<(i64, i32)>,
    /// The chunk is encrypted.
    pub encrypted: bool,
}

/// A horizontal slice of the table.
#[derive(Debug, Clone, PartialEq)]
pub struct RowGroup {
    pub columns: Vec<ColumnChunk>,
    pub total_byte_size: i64,
    pub num_rows: i64,
    pub file_offset: Option<i64>,
    pub total_compressed_size: Option<i64>,
    pub ordinal: Option<i16>,
}

/// An entry of the file's key-value metadata.
#[derive(Debug, Clone, PartialEq)]
pub struct KeyValue {
    pub key: String,
    pub value: Option<Vec<u8>>,
}

/// How a column's statistics are ordered.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColumnOrder {
    TypeDefined,
    Other,
}

/// The file's footer.
#[derive(Debug, Clone, PartialEq)]
pub struct FileMetaData {
    pub version: i32,
    pub schema: Vec<SchemaElement>,
    pub num_rows: i64,
    pub row_groups: Vec<RowGroup>,
    pub key_value: Vec<KeyValue>,
    pub created_by: Option<String>,
    pub column_orders: Option<Vec<ColumnOrder>>,
    /// The footer names an encryption algorithm.
    pub encrypted: bool,
}

/// The kind of a page.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageType {
    Data,
    Index,
    Dictionary,
    DataV2,
    Other(i32),
}

#[derive(Debug, Clone, PartialEq)]
pub struct DataPageHeader {
    pub num_values: i32,
    pub encoding: Encoding,
    pub definition_level_encoding: Encoding,
    pub repetition_level_encoding: Encoding,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DictionaryPageHeader {
    pub num_values: i32,
    pub encoding: Encoding,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DataPageHeaderV2 {
    pub num_values: i32,
    pub num_nulls: i32,
    pub num_rows: i32,
    pub encoding: Encoding,
    pub definition_levels_byte_length: i32,
    pub repetition_levels_byte_length: i32,
    pub is_compressed: bool,
}

/// The header before each page.
#[derive(Debug, Clone, PartialEq)]
pub struct PageHeader {
    pub kind: PageType,
    pub uncompressed_page_size: i32,
    pub compressed_page_size: i32,
    pub data: Option<DataPageHeader>,
    pub dictionary: Option<DictionaryPageHeader>,
    pub data_v2: Option<DataPageHeaderV2>,
}

/// Where one page of a column chunk is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PageLocation {
    pub offset: i64,
    pub compressed_page_size: i32,
    pub first_row_index: i64,
}

/// The pages of a column chunk, for reading a window of rows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OffsetIndex {
    pub pages: Vec<PageLocation>,
}

// ---- reading ----

fn i32_field(i: &mut In, ty: u8) -> Result<Option<i32>> {
    if ty == thrift::I32 {
        return Ok(Some(i.i32()?));
    }
    i.skip(ty)?;
    Ok(None)
}

fn i64_field(i: &mut In, ty: u8) -> Result<Option<i64>> {
    if ty == thrift::I64 || ty == thrift::I32 {
        return Ok(Some(i.i64()?));
    }
    i.skip(ty)?;
    Ok(None)
}

fn binary_field(i: &mut In, ty: u8) -> Result<Option<Vec<u8>>> {
    if ty == thrift::BINARY {
        return Ok(Some(i.binary()?.to_vec()));
    }
    i.skip(ty)?;
    Ok(None)
}

fn string_field(i: &mut In, ty: u8) -> Result<Option<String>> {
    if ty == thrift::BINARY {
        return Ok(Some(i.string()?));
    }
    i.skip(ty)?;
    Ok(None)
}

fn bool_field(i: &mut In, ty: u8) -> Result<Option<bool>> {
    if ty == thrift::TRUE || ty == thrift::FALSE {
        return Ok(Some(i.bool(ty)?));
    }
    i.skip(ty)?;
    Ok(None)
}

fn struct_field(
    i: &mut In,
    ty: u8,
    f: impl FnMut(&mut In, i16, u8) -> Result<bool>,
) -> Result<bool> {
    if ty != thrift::STRUCT {
        i.skip(ty)?;
        return Ok(false);
    }
    i.read_struct(f)?;
    Ok(true)
}

fn list_field<T>(
    i: &mut In,
    ty: u8,
    f: impl FnMut(&mut In, u8) -> Result<T>,
) -> Result<Option<Vec<T>>> {
    if ty != thrift::LIST && ty != thrift::SET {
        i.skip(ty)?;
        return Ok(None);
    }
    i.read_list(f).map(Some)
}

/// A list element that should be an i32; other types read as `None`.
fn i32_element(i: &mut In, ty: u8) -> Result<Option<i32>> {
    if ty == thrift::I32 {
        return Ok(Some(i.i32()?));
    }
    i.skip(ty)?;
    Ok(None)
}

fn time_unit(i: &mut In) -> Result<Option<TimeUnit>> {
    let mut unit = None;
    i.read_struct(|i, id, ty| {
        if ty != thrift::STRUCT {
            return Ok(false);
        }
        i.skip_struct()?;
        unit = match id {
            1 => Some(TimeUnit::Millis),
            2 => Some(TimeUnit::Micros),
            3 => Some(TimeUnit::Nanos),
            _ => None,
        };
        Ok(true)
    })?;
    Ok(unit)
}

#[inline(never)]
fn logical_type(i: &mut In) -> Result<Option<LogicalType>> {
    let mut out = None;
    i.read_struct(|i, id, ty| {
        if ty != thrift::STRUCT {
            return Ok(false);
        }
        out = Some(match id {
            1 => LogicalType::String,
            2 => LogicalType::Map,
            3 => LogicalType::List,
            4 => LogicalType::Enum,
            5 => {
                let (mut scale, mut precision) = (0, 0);
                i.read_struct(|i, id, ty| {
                    match id {
                        1 => scale = i32_field(i, ty)?.unwrap_or(0),
                        2 => precision = i32_field(i, ty)?.unwrap_or(0),
                        _ => return Ok(false),
                    }
                    Ok(true)
                })?;
                return {
                    out = Some(LogicalType::Decimal { scale, precision });
                    Ok(true)
                };
            }
            6 => LogicalType::Date,
            7 | 8 => {
                let (mut utc, mut unit) = (false, None);
                i.read_struct(|i, f, ty| {
                    match (f, ty) {
                        (1, _) => utc = bool_field(i, ty)?.unwrap_or(false),
                        (2, thrift::STRUCT) => unit = time_unit(i)?,
                        _ => return Ok(false),
                    }
                    Ok(true)
                })?;
                out = Some(if id == 7 {
                    LogicalType::Time { utc, unit }
                } else {
                    LogicalType::Timestamp { utc, unit }
                });
                return Ok(true);
            }
            10 => {
                let (mut bits, mut signed) = (0, true);
                i.read_struct(|i, f, ty| {
                    match (f, ty) {
                        (1, thrift::BYTE) => bits = i.i8()?,
                        (2, _) => signed = bool_field(i, ty)?.unwrap_or(true),
                        _ => return Ok(false),
                    }
                    Ok(true)
                })?;
                out = Some(LogicalType::Integer { bits, signed });
                return Ok(true);
            }
            11 => LogicalType::Null,
            12 => LogicalType::Json,
            13 => LogicalType::Bson,
            14 => LogicalType::Uuid,
            15 => LogicalType::Float16,
            other => LogicalType::Other(other),
        });
        i.skip_struct()?;
        Ok(true)
    })?;
    Ok(out)
}

#[inline(never)]
fn schema_element(i: &mut In) -> Result<SchemaElement> {
    let mut e = SchemaElement::default();
    i.read_struct(|i, id, ty| {
        match id {
            1 => e.physical = i32_field(i, ty)?.map(PhysicalType::from_i32),
            2 => e.type_length = i32_field(i, ty)?,
            3 => {
                e.repetition = match i32_field(i, ty)? {
                    Some(0) => Some(Repetition::Required),
                    Some(1) => Some(Repetition::Optional),
                    Some(2) => Some(Repetition::Repeated),
                    _ => None,
                }
            }
            4 => e.name = string_field(i, ty)?.unwrap_or_default(),
            5 => e.num_children = i32_field(i, ty)?,
            6 => e.converted = i32_field(i, ty)?,
            7 => e.scale = i32_field(i, ty)?,
            8 => e.precision = i32_field(i, ty)?,
            10 if ty == thrift::STRUCT => e.logical = logical_type(i)?,
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    Ok(e)
}

#[inline(never)]
fn statistics(i: &mut In) -> Result<Statistics> {
    let mut s = Statistics::default();
    i.read_struct(|i, id, ty| {
        match id {
            1 => s.max = binary_field(i, ty)?,
            2 => s.min = binary_field(i, ty)?,
            3 => s.null_count = i64_field(i, ty)?,
            4 => s.distinct_count = i64_field(i, ty)?,
            5 => s.max_value = binary_field(i, ty)?,
            6 => s.min_value = binary_field(i, ty)?,
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    Ok(s)
}

#[inline(never)]
fn column_meta(i: &mut In) -> Result<ColumnMetaData> {
    let mut m = ColumnMetaData {
        physical: PhysicalType::Other(-1),
        encodings: Vec::new(),
        path: Vec::new(),
        codec: Codec::Uncompressed,
        num_values: 0,
        total_uncompressed_size: 0,
        total_compressed_size: 0,
        data_page_offset: 0,
        dictionary_page_offset: None,
        statistics: None,
    };
    i.read_struct(|i, id, ty| {
        match id {
            1 => {
                m.physical =
                    i32_field(i, ty)?.map_or(PhysicalType::Other(-1), PhysicalType::from_i32)
            }
            2 => {
                let list = list_field(i, ty, i32_element)?.unwrap_or_default();
                m.encodings = list.into_iter().flatten().map(Encoding::from_i32).collect();
            }
            3 => {
                m.path = list_field(i, ty, |i, ty| {
                    string_field(i, ty).map(Option::unwrap_or_default)
                })?
                .unwrap_or_default()
            }
            4 => m.codec = i32_field(i, ty)?.map_or(Codec::Other(-1), Codec::from_i32),
            5 => m.num_values = i64_field(i, ty)?.unwrap_or(0),
            6 => m.total_uncompressed_size = i64_field(i, ty)?.unwrap_or(0),
            7 => m.total_compressed_size = i64_field(i, ty)?.unwrap_or(0),
            9 => m.data_page_offset = i64_field(i, ty)?.unwrap_or(0),
            11 => m.dictionary_page_offset = i64_field(i, ty)?,
            12 if ty == thrift::STRUCT => m.statistics = Some(statistics(i)?),
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    Ok(m)
}

#[inline(never)]
fn column_chunk(i: &mut In) -> Result<ColumnChunk> {
    let mut c = ColumnChunk {
        file_path: None,
        meta: None,
        offset_index: None,
        encrypted: false,
    };
    let (mut oi_offset, mut oi_len) = (None, None);
    i.read_struct(|i, id, ty| {
        match id {
            1 => c.file_path = string_field(i, ty)?,
            3 if ty == thrift::STRUCT => c.meta = Some(column_meta(i)?),
            4 => oi_offset = i64_field(i, ty)?,
            5 => oi_len = i32_field(i, ty)?,
            8 | 9 => {
                c.encrypted = true;
                return Ok(false);
            }
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    if let (Some(o), Some(l)) = (oi_offset, oi_len) {
        c.offset_index = Some((o, l));
    }
    Ok(c)
}

#[inline(never)]
fn row_group(i: &mut In) -> Result<RowGroup> {
    let mut g = RowGroup {
        columns: Vec::new(),
        total_byte_size: 0,
        num_rows: 0,
        file_offset: None,
        total_compressed_size: None,
        ordinal: None,
    };
    i.read_struct(|i, id, ty| {
        match id {
            1 => {
                g.columns = list_field(i, ty, |i, ty| {
                    if ty != thrift::STRUCT {
                        return Err(i.fail("a column chunk is not a struct"));
                    }
                    column_chunk(i)
                })?
                .unwrap_or_default()
            }
            2 => g.total_byte_size = i64_field(i, ty)?.unwrap_or(0),
            3 => g.num_rows = i64_field(i, ty)?.unwrap_or(0),
            5 => g.file_offset = i64_field(i, ty)?,
            6 => g.total_compressed_size = i64_field(i, ty)?,
            7 if ty == thrift::I16 => g.ordinal = Some(i.i16()?),
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    Ok(g)
}

fn key_value(i: &mut In) -> Result<KeyValue> {
    let mut kv = KeyValue {
        key: String::new(),
        value: None,
    };
    i.read_struct(|i, id, ty| {
        match id {
            1 => kv.key = string_field(i, ty)?.unwrap_or_default(),
            2 => kv.value = binary_field(i, ty)?,
            _ => return Ok(false),
        }
        Ok(true)
    })?;
    Ok(kv)
}

impl FileMetaData {
    /// Parse a footer. `base` is its offset in the file, for errors.
    pub fn parse(buf: &[u8], base: u64) -> Result<Self> {
        let mut i = In::new(buf, base);
        let mut m = FileMetaData {
            version: 0,
            schema: Vec::new(),
            num_rows: 0,
            row_groups: Vec::new(),
            key_value: Vec::new(),
            created_by: None,
            column_orders: None,
            encrypted: false,
        };
        i.read_struct(|i, id, ty| {
            match id {
                1 => m.version = i32_field(i, ty)?.unwrap_or(0),
                2 => {
                    m.schema = list_field(i, ty, |i, ty| {
                        if ty != thrift::STRUCT {
                            return Err(i.fail("a schema element is not a struct"));
                        }
                        schema_element(i)
                    })?
                    .unwrap_or_default()
                }
                3 => m.num_rows = i64_field(i, ty)?.unwrap_or(0),
                4 => {
                    m.row_groups = list_field(i, ty, |i, ty| {
                        if ty != thrift::STRUCT {
                            return Err(i.fail("a row group is not a struct"));
                        }
                        row_group(i)
                    })?
                    .unwrap_or_default()
                }
                5 => {
                    m.key_value = list_field(i, ty, |i, ty| {
                        if ty != thrift::STRUCT {
                            return Err(i.fail("a key-value entry is not a struct"));
                        }
                        key_value(i)
                    })?
                    .unwrap_or_default()
                }
                6 => m.created_by = string_field(i, ty)?,
                7 => {
                    m.column_orders = list_field(i, ty, |i, ty| {
                        if ty != thrift::STRUCT {
                            i.skip(ty)?;
                            return Ok(ColumnOrder::Other);
                        }
                        let mut order = ColumnOrder::Other;
                        i.read_struct(|_, id, _| {
                            if id == 1 {
                                order = ColumnOrder::TypeDefined;
                            }
                            Ok(false)
                        })?;
                        Ok(order)
                    })?
                }
                8 => {
                    m.encrypted = true;
                    return Ok(false);
                }
                _ => return Ok(false),
            }
            Ok(true)
        })?;
        Ok(m)
    }

    /// The footer as Thrift bytes.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut o = Out::new();
        o.begin(None);
        o.i32(1, self.version);
        o.list(2, thrift::STRUCT, self.schema.len());
        for e in &self.schema {
            write_schema_element(&mut o, e);
        }
        o.i64(3, self.num_rows);
        o.list(4, thrift::STRUCT, self.row_groups.len());
        for g in &self.row_groups {
            write_row_group(&mut o, g);
        }
        if !self.key_value.is_empty() {
            o.list(5, thrift::STRUCT, self.key_value.len());
            for kv in &self.key_value {
                o.begin(None);
                o.binary(1, kv.key.as_bytes());
                if let Some(v) = &kv.value {
                    o.binary(2, v);
                }
                o.end();
            }
        }
        if let Some(c) = &self.created_by {
            o.binary(6, c.as_bytes());
        }
        if let Some(orders) = &self.column_orders {
            o.list(7, thrift::STRUCT, orders.len());
            for _ in orders {
                o.begin(None);
                o.begin(Some(1));
                o.end();
                o.end();
            }
        }
        o.end();
        o.buf
    }
}

fn write_schema_element(o: &mut Out, e: &SchemaElement) {
    o.begin(None);
    if let Some(p) = e.physical {
        o.i32(1, p.to_i32());
    }
    if let Some(l) = e.type_length {
        o.i32(2, l);
    }
    if let Some(r) = e.repetition {
        o.i32(3, r as i32);
    }
    o.binary(4, e.name.as_bytes());
    if let Some(n) = e.num_children {
        o.i32(5, n);
    }
    if let Some(c) = e.converted {
        o.i32(6, c);
    }
    if let Some(s) = e.scale {
        o.i32(7, s);
    }
    if let Some(p) = e.precision {
        o.i32(8, p);
    }
    if let Some(l) = &e.logical {
        o.begin(Some(10));
        write_logical(o, l);
        o.end();
    }
    o.end();
}

fn write_unit(o: &mut Out, id: i16, unit: TimeUnit) {
    o.begin(Some(id));
    let which = match unit {
        TimeUnit::Millis => 1,
        TimeUnit::Micros => 2,
        TimeUnit::Nanos => 3,
    };
    o.begin(Some(which));
    o.end();
    o.end();
}

fn write_logical(o: &mut Out, l: &LogicalType) {
    let empty = |o: &mut Out, id| {
        o.begin(Some(id));
        o.end();
    };
    match l {
        LogicalType::String => empty(o, 1),
        LogicalType::Map => empty(o, 2),
        LogicalType::List => empty(o, 3),
        LogicalType::Enum => empty(o, 4),
        LogicalType::Decimal { scale, precision } => {
            o.begin(Some(5));
            o.i32(1, *scale);
            o.i32(2, *precision);
            o.end();
        }
        LogicalType::Date => empty(o, 6),
        LogicalType::Time { utc, unit } | LogicalType::Timestamp { utc, unit } => {
            o.begin(Some(if matches!(l, LogicalType::Time { .. }) {
                7
            } else {
                8
            }));
            o.bool(1, *utc);
            write_unit(o, 2, unit.unwrap_or(TimeUnit::Micros));
            o.end();
        }
        LogicalType::Integer { bits, signed } => {
            o.begin(Some(10));
            o.i8(1, *bits);
            o.bool(2, *signed);
            o.end();
        }
        LogicalType::Null => empty(o, 11),
        LogicalType::Json => empty(o, 12),
        LogicalType::Bson => empty(o, 13),
        LogicalType::Uuid => empty(o, 14),
        LogicalType::Float16 => empty(o, 15),
        LogicalType::Other(id) => empty(o, *id),
    }
}

fn write_statistics(o: &mut Out, id: i16, s: &Statistics) {
    o.begin(Some(id));
    if let Some(v) = &s.max {
        o.binary(1, v);
    }
    if let Some(v) = &s.min {
        o.binary(2, v);
    }
    if let Some(n) = s.null_count {
        o.i64(3, n);
    }
    if let Some(n) = s.distinct_count {
        o.i64(4, n);
    }
    if let Some(v) = &s.max_value {
        o.binary(5, v);
    }
    if let Some(v) = &s.min_value {
        o.binary(6, v);
    }
    o.end();
}

fn write_row_group(o: &mut Out, g: &RowGroup) {
    o.begin(None);
    o.list(1, thrift::STRUCT, g.columns.len());
    for c in &g.columns {
        o.begin(None);
        if let Some(p) = &c.file_path {
            o.binary(1, p.as_bytes());
        }
        let m = c.meta.as_ref();
        // file_offset is deprecated but required; writers set it to the
        // chunk's first byte.
        let start = m.map_or(0, |m| {
            m.dictionary_page_offset.unwrap_or(m.data_page_offset)
        });
        o.i64(2, start);
        if let Some(m) = m {
            o.begin(Some(3));
            o.i32(1, m.physical.to_i32());
            o.list(2, thrift::I32, m.encodings.len());
            for e in &m.encodings {
                o.i32_value(e.to_i32());
            }
            o.list(3, thrift::BINARY, m.path.len());
            for p in &m.path {
                o.binary_value(p.as_bytes());
            }
            o.i32(4, m.codec.to_i32());
            o.i64(5, m.num_values);
            o.i64(6, m.total_uncompressed_size);
            o.i64(7, m.total_compressed_size);
            o.i64(9, m.data_page_offset);
            if let Some(d) = m.dictionary_page_offset {
                o.i64(11, d);
            }
            if let Some(s) = &m.statistics {
                write_statistics(o, 12, s);
            }
            o.end();
        }
        if let Some((offset, len)) = c.offset_index {
            o.i64(4, offset);
            o.i32(5, len);
        }
        o.end();
    }
    o.i64(2, g.total_byte_size);
    o.i64(3, g.num_rows);
    if let Some(f) = g.file_offset {
        o.i64(5, f);
    }
    if let Some(t) = g.total_compressed_size {
        o.i64(6, t);
    }
    if let Some(n) = g.ordinal {
        o.i16(7, n);
    }
    o.end();
}

impl PageHeader {
    /// Parse a page header from the start of `buf`; returns it and its
    /// length in bytes. `base` is its offset in the file, for errors.
    pub fn parse(buf: &[u8], base: u64) -> Result<(Self, usize)> {
        let mut i = In::new(buf, base);
        let mut h = PageHeader {
            kind: PageType::Other(-1),
            uncompressed_page_size: -1,
            compressed_page_size: -1,
            data: None,
            dictionary: None,
            data_v2: None,
        };
        i.read_struct(|i, id, ty| {
            match id {
                1 => {
                    h.kind = match i32_field(i, ty)? {
                        Some(0) => PageType::Data,
                        Some(1) => PageType::Index,
                        Some(2) => PageType::Dictionary,
                        Some(3) => PageType::DataV2,
                        Some(v) => PageType::Other(v),
                        None => PageType::Other(-1),
                    }
                }
                2 => h.uncompressed_page_size = i32_field(i, ty)?.unwrap_or(-1),
                3 => h.compressed_page_size = i32_field(i, ty)?.unwrap_or(-1),
                5 => {
                    let mut d = DataPageHeader {
                        num_values: -1,
                        encoding: Encoding::Plain,
                        definition_level_encoding: Encoding::Rle,
                        repetition_level_encoding: Encoding::Rle,
                    };
                    if struct_field(i, ty, |i, id, ty| {
                        match id {
                            1 => d.num_values = i32_field(i, ty)?.unwrap_or(-1),
                            2 => d.encoding = Encoding::from_i32(i32_field(i, ty)?.unwrap_or(-1)),
                            3 => {
                                d.definition_level_encoding =
                                    Encoding::from_i32(i32_field(i, ty)?.unwrap_or(-1))
                            }
                            4 => {
                                d.repetition_level_encoding =
                                    Encoding::from_i32(i32_field(i, ty)?.unwrap_or(-1))
                            }
                            _ => return Ok(false),
                        }
                        Ok(true)
                    })? {
                        h.data = Some(d);
                    }
                }
                7 => {
                    let mut d = DictionaryPageHeader {
                        num_values: -1,
                        encoding: Encoding::Plain,
                    };
                    if struct_field(i, ty, |i, id, ty| {
                        match id {
                            1 => d.num_values = i32_field(i, ty)?.unwrap_or(-1),
                            2 => d.encoding = Encoding::from_i32(i32_field(i, ty)?.unwrap_or(-1)),
                            _ => return Ok(false),
                        }
                        Ok(true)
                    })? {
                        h.dictionary = Some(d);
                    }
                }
                8 => {
                    let mut d = DataPageHeaderV2 {
                        num_values: -1,
                        num_nulls: -1,
                        num_rows: -1,
                        encoding: Encoding::Plain,
                        definition_levels_byte_length: -1,
                        repetition_levels_byte_length: -1,
                        is_compressed: true,
                    };
                    if struct_field(i, ty, |i, id, ty| {
                        match id {
                            1 => d.num_values = i32_field(i, ty)?.unwrap_or(-1),
                            2 => d.num_nulls = i32_field(i, ty)?.unwrap_or(-1),
                            3 => d.num_rows = i32_field(i, ty)?.unwrap_or(-1),
                            4 => d.encoding = Encoding::from_i32(i32_field(i, ty)?.unwrap_or(-1)),
                            5 => d.definition_levels_byte_length = i32_field(i, ty)?.unwrap_or(-1),
                            6 => d.repetition_levels_byte_length = i32_field(i, ty)?.unwrap_or(-1),
                            7 => d.is_compressed = bool_field(i, ty)?.unwrap_or(true),
                            _ => return Ok(false),
                        }
                        Ok(true)
                    })? {
                        h.data_v2 = Some(d);
                    }
                }
                _ => return Ok(false),
            }
            Ok(true)
        })?;
        Ok((h, i.position()))
    }

    /// The header as Thrift bytes, appended to `out`.
    pub fn write(&self, out: &mut Vec<u8>) {
        let mut o = Out::new();
        o.buf = std::mem::take(out);
        o.begin(None);
        o.i32(
            1,
            match self.kind {
                PageType::Data => 0,
                PageType::Index => 1,
                PageType::Dictionary => 2,
                PageType::DataV2 => 3,
                PageType::Other(v) => v,
            },
        );
        o.i32(2, self.uncompressed_page_size);
        o.i32(3, self.compressed_page_size);
        if let Some(d) = &self.data {
            o.begin(Some(5));
            o.i32(1, d.num_values);
            o.i32(2, d.encoding.to_i32());
            o.i32(3, d.definition_level_encoding.to_i32());
            o.i32(4, d.repetition_level_encoding.to_i32());
            o.end();
        }
        if let Some(d) = &self.dictionary {
            o.begin(Some(7));
            o.i32(1, d.num_values);
            o.i32(2, d.encoding.to_i32());
            o.end();
        }
        if let Some(d) = &self.data_v2 {
            o.begin(Some(8));
            o.i32(1, d.num_values);
            o.i32(2, d.num_nulls);
            o.i32(3, d.num_rows);
            o.i32(4, d.encoding.to_i32());
            o.i32(5, d.definition_levels_byte_length);
            o.i32(6, d.repetition_levels_byte_length);
            o.bool(7, d.is_compressed);
            o.end();
        }
        o.end();
        *out = o.buf;
    }
}

impl OffsetIndex {
    pub fn parse(buf: &[u8], base: u64) -> Result<Self> {
        let mut i = In::new(buf, base);
        let mut pages = Vec::new();
        i.read_struct(|i, id, ty| {
            if id != 1 {
                return Ok(false);
            }
            pages = list_field(i, ty, |i, ty| {
                if ty != thrift::STRUCT {
                    return Err(i.fail("a page location is not a struct"));
                }
                let mut p = PageLocation {
                    offset: -1,
                    compressed_page_size: -1,
                    first_row_index: -1,
                };
                i.read_struct(|i, id, ty| {
                    match id {
                        1 => p.offset = i64_field(i, ty)?.unwrap_or(-1),
                        2 => p.compressed_page_size = i32_field(i, ty)?.unwrap_or(-1),
                        3 => p.first_row_index = i64_field(i, ty)?.unwrap_or(-1),
                        _ => return Ok(false),
                    }
                    Ok(true)
                })?;
                Ok(p)
            })?
            .unwrap_or_default();
            Ok(true)
        })?;
        Ok(OffsetIndex { pages })
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut o = Out::new();
        o.begin(None);
        o.list(1, thrift::STRUCT, self.pages.len());
        for p in &self.pages {
            o.begin(None);
            o.i64(1, p.offset);
            o.i32(2, p.compressed_page_size);
            o.i64(3, p.first_row_index);
            o.end();
        }
        o.end();
        o.buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> FileMetaData {
        FileMetaData {
            version: 2,
            schema: vec![
                SchemaElement {
                    name: "schema".into(),
                    num_children: Some(3),
                    ..Default::default()
                },
                SchemaElement {
                    name: "age".into(),
                    physical: Some(PhysicalType::Int32),
                    repetition: Some(Repetition::Optional),
                    converted: Some(converted::INT_8),
                    logical: Some(LogicalType::Integer {
                        bits: 8,
                        signed: true,
                    }),
                    ..Default::default()
                },
                SchemaElement {
                    name: "when".into(),
                    physical: Some(PhysicalType::Int64),
                    repetition: Some(Repetition::Optional),
                    logical: Some(LogicalType::Timestamp {
                        utc: true,
                        unit: Some(TimeUnit::Nanos),
                    }),
                    ..Default::default()
                },
                SchemaElement {
                    name: "amount".into(),
                    physical: Some(PhysicalType::FixedLenByteArray),
                    type_length: Some(16),
                    repetition: Some(Repetition::Required),
                    scale: Some(2),
                    precision: Some(30),
                    logical: Some(LogicalType::Decimal {
                        scale: 2,
                        precision: 30,
                    }),
                    ..Default::default()
                },
            ],
            num_rows: 1_000_000_000_000,
            row_groups: vec![RowGroup {
                columns: vec![ColumnChunk {
                    file_path: None,
                    meta: Some(ColumnMetaData {
                        physical: PhysicalType::Int32,
                        encodings: vec![Encoding::Rle, Encoding::Plain, Encoding::RleDictionary],
                        path: vec!["age".into()],
                        codec: Codec::Zstd,
                        num_values: 10,
                        total_uncompressed_size: 100,
                        total_compressed_size: 80,
                        data_page_offset: 40,
                        dictionary_page_offset: Some(4),
                        statistics: Some(Statistics {
                            null_count: Some(3),
                            min_value: Some(vec![1, 0, 0, 0]),
                            max_value: Some(vec![9, 0, 0, 0]),
                            ..Default::default()
                        }),
                    }),
                    offset_index: Some((1000, 30)),
                    encrypted: false,
                }],
                total_byte_size: 100,
                num_rows: 10,
                file_offset: Some(4),
                total_compressed_size: Some(80),
                ordinal: Some(300),
            }],
            key_value: vec![
                KeyValue {
                    key: "dta".into(),
                    value: Some(b"{}".to_vec()),
                },
                KeyValue {
                    key: "empty".into(),
                    value: None,
                },
            ],
            created_by: Some("test".into()),
            column_orders: Some(vec![ColumnOrder::TypeDefined; 3]),
            encrypted: false,
        }
    }

    #[test]
    fn footer_round_trips() {
        let m = sample();
        let bytes = m.to_bytes();
        assert_eq!(FileMetaData::parse(&bytes, 0).unwrap(), m);
    }

    #[test]
    fn footer_prefixes_fail_cleanly() {
        let bytes = sample().to_bytes();
        for n in 0..bytes.len() {
            assert!(FileMetaData::parse(&bytes[..n], 0).is_err(), "prefix {n}");
        }
    }

    #[test]
    fn page_headers_round_trip() {
        let headers = [
            PageHeader {
                kind: PageType::Data,
                uncompressed_page_size: 1 << 20,
                compressed_page_size: 1000,
                data: Some(DataPageHeader {
                    num_values: 5000,
                    encoding: Encoding::RleDictionary,
                    definition_level_encoding: Encoding::Rle,
                    repetition_level_encoding: Encoding::BitPacked,
                }),
                dictionary: None,
                data_v2: None,
            },
            PageHeader {
                kind: PageType::Dictionary,
                uncompressed_page_size: 10,
                compressed_page_size: 10,
                data: None,
                dictionary: Some(DictionaryPageHeader {
                    num_values: 2,
                    encoding: Encoding::Plain,
                }),
                data_v2: None,
            },
            PageHeader {
                kind: PageType::DataV2,
                uncompressed_page_size: 10,
                compressed_page_size: 8,
                data: None,
                dictionary: None,
                data_v2: Some(DataPageHeaderV2 {
                    num_values: 4,
                    num_nulls: 1,
                    num_rows: 4,
                    encoding: Encoding::Plain,
                    definition_levels_byte_length: 2,
                    repetition_levels_byte_length: 0,
                    is_compressed: false,
                }),
            },
        ];
        for h in headers {
            let mut buf = vec![7u8];
            h.write(&mut buf);
            buf.extend_from_slice(b"page bytes");
            let (got, len) = PageHeader::parse(&buf[1..], 1).unwrap();
            assert_eq!(got, h);
            assert_eq!(&buf[1 + len..], b"page bytes");
        }
    }

    #[test]
    fn offset_index_round_trips() {
        let oi = OffsetIndex {
            pages: (0..40)
                .map(|k| PageLocation {
                    offset: 4 + k * 1000,
                    compressed_page_size: 999,
                    first_row_index: k * 20_000,
                })
                .collect(),
        };
        assert_eq!(OffsetIndex::parse(&oi.to_bytes(), 0).unwrap(), oi);
    }

    #[test]
    fn unknown_logical_types_and_fields_are_kept_or_skipped() {
        // A schema element with logical type field 99 (unknown) and an
        // unknown field 42.
        let mut o = Out::new();
        o.begin(None);
        o.binary(4, b"x");
        o.begin(Some(10));
        o.begin(Some(99));
        o.i32(1, 5);
        o.end();
        o.end();
        o.i32(42, 1);
        o.end();
        let mut i = In::new(&o.buf, 0);
        let e = schema_element(&mut i).unwrap();
        assert_eq!(e.name, "x");
        assert_eq!(e.logical, Some(LogicalType::Other(99)));
    }
}
