//! The dtatools Arrow profile reader.
//!
//! The reader parses the IPC file footer and each record batch's flatbuffer
//! header itself, then reads only the buffer byte ranges of the selected
//! columns. A projected read therefore costs I/O proportional to the selected
//! columns' buffers; whole batches outside the requested row window are
//! skipped after their small headers are read.

use std::collections::HashMap;
use std::fs::File;
use std::io::{self, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;

use arrow_array::types::{ArrowDictionaryKeyType, Int16Type, Int32Type, Int64Type, Int8Type};
use arrow_array::{make_array, Array, ArrayRef, DictionaryArray, Int32Array, PrimitiveArray};
use arrow_buffer::{Buffer, MutableBuffer};
use arrow_data::ArrayData;
use arrow_ipc::{root_as_footer, root_as_message, CompressionType, MessageHeader};
use arrow_schema::{DataType, Field, Schema};

use super::checksum::canonical_array_hashes;
use super::profile::{
    checksum_to_hex, parse_checksums_document, parse_dataset_document, parse_field_document,
    validate_value_label_reference, ArrowFieldDocument, ChecksumsDocument, DatasetDocument,
    ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY, ARROW_FIELD_KEY, ARROW_PROFILE_VERSION,
    ARROW_PROFILE_VERSION_KEY,
};
use super::ArrowProfileError;

const FILE_MAGIC: &[u8; 6] = b"ARROW1";
const CONTINUATION_MARKER: [u8; 4] = [0xff, 0xff, 0xff, 0xff];
const MAX_IPC_METADATA_BYTES: u64 = 64 * 1024 * 1024;

fn metadata_buffer(length: u64, location: &str) -> Result<Vec<u8>, ArrowProfileError> {
    if length > MAX_IPC_METADATA_BYTES {
        return Err(invalid(format!(
            "{location} metadata length exceeds the 64 MiB safety limit"
        )));
    }
    let length = usize::try_from(length).map_err(|_| invalid("metadata length is too large"))?;
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(length)
        .map_err(|_| invalid(format!("could not allocate {location} metadata buffer")))?;
    bytes.resize(length, 0);
    Ok(bytes)
}

/// Selection and safety options for one Arrow read.
#[derive(Debug, Clone, Default)]
pub struct ArrowReadOptions {
    /// Projected column indices in output order, or `None` for all columns.
    pub columns: Option<Vec<u32>>,
    /// Rows to skip before the first returned row.
    pub row_start: u64,
    /// Maximum rows to return, or `None` for all remaining rows.
    pub row_count: Option<u64>,
    /// Reject a selected window larger than this before decoding IPC bodies.
    /// `None` leaves the output size unconstrained.
    pub max_output_rows: Option<u64>,
    /// Verify the checksums of every buffer the read touches.
    pub verify: bool,
    /// Apply `dtatools:*` profile metadata. `false` is the escape hatch that
    /// reads the raw storage arrays as plain Arrow data.
    pub profile: bool,
    /// Derive the complete file's stored signature from this read's open file
    /// snapshot and return it with the decoded selection.
    pub record_signature: bool,
    /// Decoder threads for path-backed reads: zero selects an automatic
    /// count for sufficiently large selections, one forces serial decoding,
    /// and larger values cap the worker count. Reads from a generic seekable
    /// source are always serial.
    pub threads: usize,
}

/// One decoded output column: its Arrow chunks in row order plus the parsed
/// `dtatools:field` document when the file is profiled.
#[derive(Debug)]
pub struct ArrowReadColumn {
    pub name: String,
    pub data_type: DataType,
    pub nullable: bool,
    /// Whether the IPC dictionary encoding declares ordered values.
    pub dictionary_ordered: bool,
    pub field: Option<ArrowFieldDocument>,
    pub chunks: Vec<ArrayRef>,
}

/// A decoded Arrow file selection.
#[derive(Debug)]
pub struct ArrowReadResult {
    /// The file's profile version when it is a dtatools Arrow profile file
    /// and `profile` was requested.
    pub profile_version: Option<String>,
    pub dataset: Option<DatasetDocument>,
    pub row_count: u64,
    pub columns: Vec<ArrowReadColumn>,
    pub stored_signature: Option<String>,
}

/// One column's name and the R type family used for selection proxies.
pub struct ArrowColumnSummary {
    pub name: String,
    pub r_type: &'static str,
}

/// Column names and proxy types read from the schema and, when needed, the
/// values of plain Int32 columns whose R storage depends on their contents.
pub struct ArrowFileSummary {
    pub columns: Vec<ArrowColumnSummary>,
}

/// One open Arrow file whose identity remains stable if its path is replaced.
pub struct ArrowFileSnapshot {
    path: PathBuf,
    file: File,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Compression {
    Lz4,
    Zstd,
}

struct FieldLayout {
    node: usize,
    buffer: usize,
    buffer_count: usize,
    dictionary_id: Option<i64>,
    dictionary_ordered: bool,
}

struct Footer {
    schema: Schema,
    layouts: Vec<FieldLayout>,
    record_blocks: Vec<BlockInfo>,
    dictionary_blocks: Vec<BlockInfo>,
    custom_metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Copy)]
struct BlockInfo {
    offset: u64,
    metadata_length: u32,
    body_length: u64,
}

struct BatchHeader {
    rows: u64,
    compression: Option<Compression>,
    nodes: Vec<(u64, u64)>,
    buffers: Vec<(u64, u64)>,
}

struct Profile {
    version: String,
    dataset: DatasetDocument,
    fields: Vec<Option<ArrowFieldDocument>>,
    checksums: Option<ChecksumsDocument>,
}

fn invalid(detail: impl Into<String>) -> ArrowProfileError {
    ArrowProfileError::InvalidFile(detail.into())
}

fn buffer_count_for(data_type: &DataType) -> Option<usize> {
    match data_type {
        DataType::Boolean
        | DataType::Int8
        | DataType::Int16
        | DataType::Int32
        | DataType::Int64
        | DataType::UInt8
        | DataType::UInt16
        | DataType::UInt32
        | DataType::UInt64
        | DataType::Float32
        | DataType::Float64
        | DataType::Date32
        | DataType::Timestamp(_, _)
        | DataType::Duration(_) => Some(2),
        DataType::Utf8 | DataType::LargeUtf8 => Some(3),
        DataType::Dictionary(key, value) => {
            (matches!(
                key.as_ref(),
                DataType::Int8 | DataType::Int16 | DataType::Int32 | DataType::Int64
            ) && matches!(value.as_ref(), DataType::Utf8 | DataType::LargeUtf8))
            .then_some(2)
        }
        _ => None,
    }
}

fn read_exact_at<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    buffer: &mut [u8],
) -> Result<(), ArrowProfileError> {
    reader.seek(SeekFrom::Start(offset))?;
    reader.read_exact(buffer)?;
    Ok(())
}

/// A cloned file handle with an independent logical cursor. `File::try_clone`
/// can share the operating system cursor with the original handle, so each
/// parallel decoder uses positioned reads instead.
struct PositionedFile {
    file: File,
    position: u64,
}

impl PositionedFile {
    fn new(file: File) -> Self {
        Self { file, position: 0 }
    }
}

#[cfg(unix)]
fn file_read_at(file: &File, buffer: &mut [u8], offset: u64) -> io::Result<usize> {
    use std::os::unix::fs::FileExt;
    file.read_at(buffer, offset)
}

#[cfg(windows)]
fn file_read_at(file: &File, buffer: &mut [u8], offset: u64) -> io::Result<usize> {
    use std::os::windows::fs::FileExt;
    file.seek_read(buffer, offset)
}

impl Read for PositionedFile {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let read = file_read_at(&self.file, buffer, self.position)?;
        self.position = self
            .position
            .checked_add(read as u64)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "file offset overflow"))?;
        Ok(read)
    }
}

impl Seek for PositionedFile {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        let next = match position {
            SeekFrom::Start(offset) => i128::from(offset),
            SeekFrom::Current(offset) => i128::from(self.position) + i128::from(offset),
            SeekFrom::End(offset) => i128::from(self.file.metadata()?.len()) + i128::from(offset),
        };
        if !(0..=i128::from(u64::MAX)).contains(&next) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid file seek",
            ));
        }
        self.position = next as u64;
        Ok(self.position)
    }
}

fn valid_time_unit(unit: arrow_ipc::TimeUnit) -> bool {
    matches!(
        unit,
        arrow_ipc::TimeUnit::SECOND
            | arrow_ipc::TimeUnit::MILLISECOND
            | arrow_ipc::TimeUnit::MICROSECOND
            | arrow_ipc::TimeUnit::NANOSECOND
    )
}

fn validate_ipc_endianness(endianness: arrow_ipc::Endianness) -> Result<(), ArrowProfileError> {
    if !endianness.equals_to_target_endianness() {
        return Err(invalid(
            "Arrow IPC endianness does not match this host; byte-swapping is not supported",
        ));
    }
    Ok(())
}

/// `arrow_ipc::convert::fb_to_schema` assumes every FlatBuffer enum and
/// parameter is valid and panics otherwise. Validate the flat scalar types
/// this reader supports before calling it so hostile files remain ordinary
/// `InvalidFile` errors.
fn validate_flatbuffer_field(field: arrow_ipc::Field<'_>) -> Result<(), ArrowProfileError> {
    if let Some(dictionary) = field.dictionary() {
        let index = dictionary
            .indexType()
            .ok_or_else(|| invalid("dictionary encoding has no index type"))?;
        if !matches!(
            (index.bitWidth(), index.is_signed()),
            (8 | 16 | 32 | 64, true)
        ) {
            return Err(invalid("unsupported dictionary index type"));
        }
        if !matches!(
            field.type_type(),
            arrow_ipc::Type::Utf8 | arrow_ipc::Type::LargeUtf8
        ) {
            return Err(invalid("unsupported dictionary value type"));
        }
    }

    match field.type_type() {
        arrow_ipc::Type::Bool | arrow_ipc::Type::Utf8 | arrow_ipc::Type::LargeUtf8 => Ok(()),
        arrow_ipc::Type::Int => {
            let integer = field
                .type_as_int()
                .ok_or_else(|| invalid("integer field has no type parameters"))?;
            matches!(integer.bitWidth(), 8 | 16 | 32 | 64)
                .then_some(())
                .ok_or_else(|| invalid("unsupported integer bit width"))
        }
        arrow_ipc::Type::FloatingPoint => {
            let floating = field
                .type_as_floating_point()
                .ok_or_else(|| invalid("floating-point field has no type parameters"))?;
            matches!(
                floating.precision(),
                arrow_ipc::Precision::SINGLE | arrow_ipc::Precision::DOUBLE
            )
            .then_some(())
            .ok_or_else(|| invalid("unsupported floating-point precision"))
        }
        arrow_ipc::Type::Date => {
            let date = field
                .type_as_date()
                .ok_or_else(|| invalid("date field has no type parameters"))?;
            (date.unit() == arrow_ipc::DateUnit::DAY)
                .then_some(())
                .ok_or_else(|| invalid("unsupported date unit"))
        }
        arrow_ipc::Type::Timestamp => {
            let timestamp = field
                .type_as_timestamp()
                .ok_or_else(|| invalid("timestamp field has no type parameters"))?;
            valid_time_unit(timestamp.unit())
                .then_some(())
                .ok_or_else(|| invalid("unsupported timestamp unit"))
        }
        arrow_ipc::Type::Duration => {
            let duration = field
                .type_as_duration()
                .ok_or_else(|| invalid("duration field has no type parameters"))?;
            valid_time_unit(duration.unit())
                .then_some(())
                .ok_or_else(|| invalid("unsupported duration unit"))
        }
        other => Err(invalid(format!("unsupported Arrow field type {other:?}"))),
    }
}

fn read_footer<R: Read + Seek>(reader: &mut R) -> Result<Footer, ArrowProfileError> {
    let file_length = reader.seek(SeekFrom::End(0))?;
    let mut head = [0_u8; 6];
    if file_length < 8 + 10 {
        return Err(ArrowProfileError::NotAnArrowFile("the input".to_owned()));
    }
    read_exact_at(reader, 0, &mut head)?;
    if &head != FILE_MAGIC {
        return Err(ArrowProfileError::NotAnArrowFile("the input".to_owned()));
    }
    let mut tail = [0_u8; 10];
    read_exact_at(reader, file_length - 10, &mut tail)?;
    if &tail[4..] != FILE_MAGIC {
        return Err(ArrowProfileError::NotAnArrowFile("the input".to_owned()));
    }
    let footer_length = u64::from(u32::from_le_bytes(tail[..4].try_into().expect("4 bytes")));
    if footer_length == 0 || footer_length > file_length - 10 - 8 {
        return Err(invalid("footer length is out of bounds"));
    }
    let footer_start = file_length - 10 - footer_length;
    let mut footer_bytes = metadata_buffer(footer_length, "footer")?;
    read_exact_at(reader, footer_start, &mut footer_bytes)?;
    let footer =
        root_as_footer(&footer_bytes).map_err(|error| invalid(format!("bad footer: {error}")))?;

    let fb_schema = footer
        .schema()
        .ok_or_else(|| invalid("footer has no schema"))?;
    validate_ipc_endianness(fb_schema.endianness())?;
    let fb_fields = fb_schema
        .fields()
        .ok_or_else(|| invalid("footer schema has no fields vector"))?;
    for field in fb_fields {
        validate_flatbuffer_field(field)?;
    }
    let schema = arrow_ipc::convert::fb_to_schema(fb_schema);

    let mut layouts = Vec::with_capacity(schema.fields().len());
    let mut buffer = 0_usize;
    for (index, field) in schema.fields().iter().enumerate() {
        let buffer_count = buffer_count_for(field.data_type()).ok_or_else(|| {
            ArrowProfileError::UnsupportedColumn {
                column: field.name().clone(),
                data_type: field.data_type().to_string(),
            }
        })?;
        let dictionary = (index < fb_fields.len())
            .then(|| fb_fields.get(index).dictionary())
            .flatten();
        let dictionary_id = dictionary.map(|encoding| encoding.id());
        let dictionary_ordered = dictionary.is_some_and(|encoding| encoding.isOrdered());
        // The supported types are all flat, so each field is one node.
        layouts.push(FieldLayout {
            node: index,
            buffer,
            buffer_count,
            dictionary_id,
            dictionary_ordered,
        });
        buffer += buffer_count;
    }

    let block_info = |block: &arrow_ipc::Block| -> Result<BlockInfo, ArrowProfileError> {
        let info = BlockInfo {
            offset: u64::try_from(block.offset()).map_err(|_| invalid("negative block offset"))?,
            metadata_length: u32::try_from(block.metaDataLength())
                .map_err(|_| invalid("negative block metadata length"))?,
            body_length: u64::try_from(block.bodyLength())
                .map_err(|_| invalid("negative block body length"))?,
        };
        if u64::from(info.metadata_length) > MAX_IPC_METADATA_BYTES {
            return Err(invalid(
                "IPC block metadata length exceeds the 64 MiB safety limit",
            ));
        }
        let block_end = info
            .offset
            .checked_add(u64::from(info.metadata_length))
            .and_then(|end| end.checked_add(info.body_length))
            .ok_or_else(|| invalid("IPC block extent overflows"))?;
        if info.offset < 8 || block_end > footer_start {
            return Err(invalid("IPC block extends outside the file body"));
        }
        Ok(info)
    };
    let record_blocks = footer
        .recordBatches()
        .map(|blocks| blocks.iter().map(&block_info).collect())
        .transpose()?
        .unwrap_or_default();
    let dictionary_blocks = footer
        .dictionaries()
        .map(|blocks| blocks.iter().map(&block_info).collect())
        .transpose()?
        .unwrap_or_default();

    let mut custom_metadata = HashMap::new();
    if let Some(entries) = footer.custom_metadata() {
        for entry in entries {
            if let (Some(key), Some(value)) = (entry.key(), entry.value()) {
                custom_metadata.insert(key.to_owned(), value.to_owned());
            }
        }
    }

    Ok(Footer {
        schema,
        layouts,
        record_blocks,
        dictionary_blocks,
        custom_metadata,
    })
}

fn parse_profile(
    footer: &Footer,
    apply_profile: bool,
    verify: bool,
) -> Result<Option<Profile>, ArrowProfileError> {
    if !apply_profile {
        return Ok(None);
    }
    let Some(version) = footer.schema.metadata().get(ARROW_PROFILE_VERSION_KEY) else {
        // A plain Arrow file never acquires Stata semantics.
        return Ok(None);
    };
    if version != ARROW_PROFILE_VERSION {
        return Err(ArrowProfileError::NewerProfile(version.clone()));
    }
    let dataset = parse_dataset_document(
        version,
        footer
            .schema
            .metadata()
            .get(ARROW_DATASET_KEY)
            .map(String::as_str),
    )?;
    let mut fields = Vec::with_capacity(footer.schema.fields().len());
    for field in footer.schema.fields() {
        let document = field
            .metadata()
            .get(ARROW_FIELD_KEY)
            .map(|json| parse_field_document(version, field, json))
            .transpose()?;
        fields.push(document);
    }
    for (field, document) in footer.schema.fields().iter().zip(&fields) {
        if let Some(document) = document {
            validate_value_label_reference(version, field, document, &dataset)?;
        }
    }
    let checksums = if verify {
        let json = footer
            .custom_metadata
            .get(ARROW_CHECKSUMS_KEY)
            .ok_or_else(|| {
                super::profile::malformed(
                    version,
                    "missing checksums document; the file was written without checksums, \
                     so read it with verification off"
                        .to_owned(),
                )
            })?;
        let document = parse_checksums_document(version, json)?;
        if document.batches.len() != footer.record_blocks.len() {
            return Err(super::profile::malformed(
                version,
                "checksums document does not cover every record batch",
            ));
        }
        Some(document)
    } else {
        None
    };
    Ok(Some(Profile {
        version: version.clone(),
        dataset,
        fields,
        checksums,
    }))
}

fn parse_message_header(bytes: &[u8]) -> Result<arrow_ipc::Message<'_>, ArrowProfileError> {
    let flatbuffer = if bytes.len() >= 8 && bytes[..4] == CONTINUATION_MARKER {
        &bytes[8..]
    } else if bytes.len() >= 4 {
        &bytes[4..]
    } else {
        return Err(invalid("record batch header is too short"));
    };
    root_as_message(flatbuffer).map_err(|error| invalid(format!("bad message header: {error}")))
}

fn read_batch_header<R: Read + Seek>(
    reader: &mut R,
    block: BlockInfo,
) -> Result<BatchHeader, ArrowProfileError> {
    let mut bytes = metadata_buffer(u64::from(block.metadata_length), "record batch")?;
    read_exact_at(reader, block.offset, &mut bytes)?;
    let message = parse_message_header(&bytes)?;
    let batch = message
        .header_as_record_batch()
        .ok_or_else(|| invalid("block does not contain a record batch"))?;
    batch_header_from(batch)
}

fn batch_header_from(batch: arrow_ipc::RecordBatch<'_>) -> Result<BatchHeader, ArrowProfileError> {
    let compression = match batch.compression() {
        None => None,
        Some(body) => match body.codec() {
            CompressionType::LZ4_FRAME => Some(Compression::Lz4),
            CompressionType::ZSTD => Some(Compression::Zstd),
            other => {
                return Err(invalid(format!(
                    "unsupported IPC body compression {other:?}"
                )))
            }
        },
    };
    let nodes = batch
        .nodes()
        .map(|nodes| {
            nodes
                .iter()
                .map(|node| {
                    Ok((
                        u64::try_from(node.length())
                            .map_err(|_| invalid("negative field length"))?,
                        u64::try_from(node.null_count())
                            .map_err(|_| invalid("negative field null count"))?,
                    ))
                })
                .collect::<Result<Vec<_>, ArrowProfileError>>()
        })
        .transpose()?
        .unwrap_or_default();
    let buffers = batch
        .buffers()
        .map(|buffers| {
            buffers
                .iter()
                .map(|buffer| {
                    Ok((
                        u64::try_from(buffer.offset())
                            .map_err(|_| invalid("negative buffer offset"))?,
                        u64::try_from(buffer.length())
                            .map_err(|_| invalid("negative buffer length"))?,
                    ))
                })
                .collect::<Result<Vec<_>, ArrowProfileError>>()
        })
        .transpose()?
        .unwrap_or_default();
    Ok(BatchHeader {
        rows: u64::try_from(batch.length()).map_err(|_| invalid("negative batch length"))?,
        compression,
        nodes,
        buffers,
    })
}

fn read_ipc_buffer<R: Read + Seek>(
    reader: &mut R,
    body_start: u64,
    body_length: u64,
    entry: (u64, u64),
    compression: Option<Compression>,
    expected_length: usize,
) -> Result<Buffer, ArrowProfileError> {
    let (offset, length) = entry;
    if offset
        .checked_add(length)
        .is_none_or(|end| end > body_length)
    {
        return Err(invalid("buffer extends past the record batch body"));
    }
    let stored_length = usize::try_from(length).map_err(|_| invalid("buffer is too large"))?;
    let read_start = body_start
        .checked_add(offset)
        .ok_or_else(|| invalid("buffer offset overflows"))?;
    match compression {
        None => {
            if stored_length != expected_length {
                return Err(invalid("buffer length does not match its field layout"));
            }
            let mut bytes = Vec::new();
            bytes
                .try_reserve_exact(expected_length)
                .map_err(|_| invalid("could not allocate an Arrow buffer"))?;
            bytes.resize(expected_length, 0);
            read_exact_at(reader, read_start, &mut bytes)?;
            Ok(buffer_from_bytes(bytes))
        }
        Some(codec) => {
            if stored_length == 0 && expected_length == 0 {
                return Ok(buffer_from_bytes(Vec::new()));
            }
            let mut raw = Vec::new();
            raw.try_reserve_exact(stored_length)
                .map_err(|_| invalid("could not allocate a compressed Arrow buffer"))?;
            raw.resize(stored_length, 0);
            read_exact_at(reader, read_start, &mut raw)?;
            if raw.len() < 8 {
                return Err(invalid("compressed buffer is too short"));
            }
            let declared = i64::from_le_bytes(raw[..8].try_into().expect("8 bytes"));
            let payload = &raw[8..];
            if declared == -1 {
                if payload.len() != expected_length {
                    return Err(invalid("uncompressed buffer length mismatch"));
                }
                return Ok(buffer_from_bytes(payload.to_vec()));
            }
            let declared =
                usize::try_from(declared).map_err(|_| invalid("bad compressed length"))?;
            if declared != expected_length {
                return Err(invalid("declared decompressed buffer length mismatch"));
            }
            let read_limit = u64::try_from(expected_length)
                .ok()
                .and_then(|length| length.checked_add(1))
                .ok_or_else(|| invalid("decompressed buffer is too large"))?;
            let mut decompressed = Vec::new();
            match codec {
                Compression::Lz4 => {
                    let decoder = lz4_flex::frame::FrameDecoder::new(payload);
                    decoder
                        .take(read_limit)
                        .read_to_end(&mut decompressed)
                        .map_err(|error| invalid(format!("LZ4 decompression failed: {error}")))?;
                }
                Compression::Zstd => {
                    let decoder = zstd::stream::Decoder::new(payload)
                        .map_err(|error| invalid(format!("zstd decompression failed: {error}")))?;
                    decoder
                        .take(read_limit)
                        .read_to_end(&mut decompressed)
                        .map_err(|error| invalid(format!("zstd decompression failed: {error}")))?;
                }
            }
            if decompressed.len() != declared {
                return Err(invalid("decompressed buffer length mismatch"));
            }
            Ok(buffer_from_bytes(decompressed))
        }
    }
}

fn buffer_from_bytes(bytes: Vec<u8>) -> Buffer {
    if bytes.is_empty() {
        Buffer::from(MutableBuffer::new(0))
    } else {
        Buffer::from(bytes)
    }
}

fn checked_buffer_length(
    rows: usize,
    extra: usize,
    width: usize,
) -> Result<usize, ArrowProfileError> {
    rows.checked_add(extra)
        .and_then(|values| values.checked_mul(width))
        .ok_or_else(|| invalid("Arrow buffer length overflows"))
}

fn string_values_length(offsets: &Buffer, width: usize) -> Result<usize, ArrowProfileError> {
    let bytes = offsets.as_slice();
    let tail = bytes
        .get(
            bytes
                .len()
                .checked_sub(width)
                .ok_or_else(|| invalid("string offsets are empty"))?..,
        )
        .ok_or_else(|| invalid("string offsets are truncated"))?;
    match width {
        4 => usize::try_from(i32::from_le_bytes(tail.try_into().expect("four bytes")))
            .map_err(|_| invalid("negative string offset")),
        8 => usize::try_from(i64::from_le_bytes(tail.try_into().expect("eight bytes")))
            .map_err(|_| invalid("negative or oversized string offset")),
        _ => unreachable!("supported string offsets are 32- or 64-bit"),
    }
}

fn expected_data_buffer_length(
    data_type: &DataType,
    index: usize,
    rows: usize,
    decoded: &[Buffer],
) -> Result<usize, ArrowProfileError> {
    match data_type {
        DataType::Boolean if index == 0 => Ok(rows.div_ceil(8)),
        DataType::Utf8 | DataType::LargeUtf8 => {
            let width = if matches!(data_type, DataType::Utf8) {
                4
            } else {
                8
            };
            match index {
                0 => checked_buffer_length(rows, 1, width),
                1 => string_values_length(
                    decoded
                        .first()
                        .ok_or_else(|| invalid("string values precede their offsets"))?,
                    width,
                ),
                _ => Err(invalid("unexpected string buffer")),
            }
        }
        DataType::Dictionary(key, _) if index == 0 => key
            .primitive_width()
            .ok_or_else(|| invalid("unsupported dictionary key type"))
            .and_then(|width| checked_buffer_length(rows, 0, width)),
        data_type if index == 0 => data_type
            .primitive_width()
            .ok_or_else(|| invalid("unsupported fixed-width buffer"))
            .and_then(|width| checked_buffer_length(rows, 0, width)),
        _ => Err(invalid("unexpected field buffer")),
    }
}

#[allow(clippy::too_many_arguments)]
fn decode_field_array<R: Read + Seek>(
    reader: &mut R,
    body_start: u64,
    body_length: u64,
    header: &BatchHeader,
    layout: &FieldLayout,
    data_type: &DataType,
    nullable: bool,
    dictionary: Option<&ArrayData>,
) -> Result<ArrayRef, ArrowProfileError> {
    let (rows, null_count) = *header
        .nodes
        .get(layout.node)
        .ok_or_else(|| invalid("record batch header is missing a field node"))?;
    let entries = header
        .buffers
        .get(layout.buffer..layout.buffer + layout.buffer_count)
        .ok_or_else(|| invalid("record batch header is missing buffers"))?;
    let rows = usize::try_from(rows).map_err(|_| invalid("batch is too large"))?;

    if null_count > rows as u64 {
        return Err(invalid("null count exceeds the field length"));
    }
    if null_count > 0 && !nullable {
        return Err(invalid("non-nullable field contains nulls"));
    }

    let validity = if null_count > 0 {
        if entries[0].1 == 0 {
            return Err(invalid("null field has no validity buffer"));
        }
        Some(read_ipc_buffer(
            reader,
            body_start,
            body_length,
            entries[0],
            header.compression,
            rows.div_ceil(8),
        )?)
    } else {
        None
    };
    let null_count = if validity.is_some() {
        usize::try_from(null_count).map_err(|_| invalid("bad null count"))?
    } else {
        0
    };

    let mut builder = ArrayData::builder(data_type.clone())
        .len(rows)
        .null_count(null_count)
        .null_bit_buffer(validity);
    let mut decoded = Vec::with_capacity(entries.len().saturating_sub(1));
    for (index, entry) in entries[1..].iter().enumerate() {
        let expected_length = expected_data_buffer_length(data_type, index, rows, &decoded)?;
        let buffer = read_ipc_buffer(
            reader,
            body_start,
            body_length,
            *entry,
            header.compression,
            expected_length,
        )?;
        decoded.push(buffer.clone());
        builder = builder.add_buffer(buffer);
    }
    if let Some(dictionary) = dictionary {
        builder = builder.add_child_data(dictionary.clone());
    }
    let data = builder
        .build()
        .map_err(|error| invalid(format!("invalid array data: {error}")))?;
    Ok(make_array(data))
}

fn verify_hashes(
    array: &ArrayRef,
    expected: &[String],
    column: &str,
    batch: usize,
) -> Result<(), ArrowProfileError> {
    let actual: Vec<String> = canonical_array_hashes(array.as_ref())?
        .into_iter()
        .map(checksum_to_hex)
        .collect();
    if actual != expected {
        return Err(ArrowProfileError::ChecksumMismatch {
            column: column.to_owned(),
            batch,
        });
    }
    Ok(())
}

fn read_dictionaries<R: Read + Seek>(
    reader: &mut R,
    footer: &Footer,
    needed_ids: &[i64],
) -> Result<HashMap<i64, ArrayData>, ArrowProfileError> {
    let mut dictionaries = HashMap::new();
    if needed_ids.is_empty() {
        return Ok(dictionaries);
    }
    let value_types: HashMap<i64, DataType> = footer
        .schema
        .fields()
        .iter()
        .zip(&footer.layouts)
        .filter_map(|(field, layout)| {
            let id = layout.dictionary_id?;
            let DataType::Dictionary(_, value) = field.data_type() else {
                return None;
            };
            Some((id, value.as_ref().clone()))
        })
        .collect();
    for block in &footer.dictionary_blocks {
        let mut bytes = metadata_buffer(u64::from(block.metadata_length), "dictionary batch")?;
        read_exact_at(reader, block.offset, &mut bytes)?;
        let message = parse_message_header(&bytes)?;
        if message.header_type() != MessageHeader::DictionaryBatch {
            return Err(invalid("dictionary block does not contain a dictionary"));
        }
        let batch = message
            .header_as_dictionary_batch()
            .ok_or_else(|| invalid("bad dictionary batch"))?;
        let is_delta = batch.isDelta();
        let id = batch.id();
        if !needed_ids.contains(&id) {
            continue;
        }
        let value_type = value_types
            .get(&id)
            .ok_or_else(|| invalid("dictionary id does not match any field"))?;
        let header = batch_header_from(
            batch
                .data()
                .ok_or_else(|| invalid("dictionary batch has no data"))?,
        )?;
        let layout = FieldLayout {
            node: 0,
            buffer: 0,
            buffer_count: buffer_count_for(value_type)
                .ok_or_else(|| invalid("unsupported dictionary value type"))?,
            dictionary_id: None,
            dictionary_ordered: false,
        };
        let body_start = block.offset + u64::from(block.metadata_length);
        let values = decode_field_array(
            reader,
            body_start,
            block.body_length,
            &header,
            &layout,
            value_type,
            true,
            None,
        )?;
        let values = if is_delta {
            let previous = dictionaries
                .get(&id)
                .ok_or_else(|| invalid("delta dictionary has no preceding dictionary"))?;
            let previous = make_array(previous.clone());
            arrow_select::concat::concat(&[previous.as_ref(), values.as_ref()])
                .map_err(|error| invalid(format!("invalid delta dictionary: {error}")))?
        } else {
            values
        };
        dictionaries.insert(id, values.to_data());
    }
    for id in needed_ids {
        if !dictionaries.contains_key(id) {
            return Err(invalid("a dictionary-encoded column has no dictionary"));
        }
    }
    Ok(dictionaries)
}

// Automatic-parallelism thresholds, matching the DTA reader's policy: small
// selections stay serial, and automatic counts leave headroom on very wide
// machines.
const MIN_PARALLEL_DECODE_BYTES: u64 = 16 * 1024 * 1024;
const MIN_PARALLEL_DECODE_CELLS: u64 = 1_000_000;
const MAX_AUTOMATIC_DECODE_THREADS: usize = 8;

/// One record batch that overlaps the requested row window: its parsed
/// header plus the slice of its rows to return.
struct BlockPlan {
    batch_index: usize,
    block: BlockInfo,
    header: BatchHeader,
    slice_offset: usize,
    slice_length: usize,
}

/// Everything a decode needs that is shared across blocks and columns.
struct DecodeContext<'a> {
    footer: &'a Footer,
    profile: Option<&'a Profile>,
    selected: &'a [usize],
    dictionaries: &'a HashMap<i64, ArrayData>,
}

/// The footer-derived state of one read, before any batch body is decoded.
struct PreparedRead {
    footer: Footer,
    profile: Option<Profile>,
    selected: Vec<usize>,
    dictionaries: HashMap<i64, ArrayData>,
    plans: Vec<BlockPlan>,
    produced: u64,
    stored_signature: Option<String>,
}

fn prepare_read<R: Read + Seek>(
    reader: &mut R,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<PreparedRead, ArrowProfileError> {
    let footer = read_footer(reader)?;
    let stored_signature = options
        .record_signature
        .then(|| stored_signature_from_footer(reader, &footer))
        .transpose()?;
    let profile = parse_profile(&footer, options.profile, options.verify)?;

    let field_count = footer.schema.fields().len();
    let selected: Vec<usize> = match &options.columns {
        None => (0..field_count).collect(),
        Some(indices) => indices
            .iter()
            .map(|&index| {
                let index = index as usize;
                (index < field_count)
                    .then_some(index)
                    .ok_or_else(|| invalid("projected column index is out of range"))
            })
            .collect::<Result<_, _>>()?,
    };

    // Batch headers are small; reading them all up front fixes each block's
    // slice of the requested window so block bodies can decode in any order.
    let limit = options.row_count.unwrap_or(u64::MAX);
    let mut plans = Vec::new();
    let mut produced = 0_u64;
    let mut seen_rows = 0_u64;
    for (batch_index, block) in footer.record_blocks.iter().enumerate() {
        if produced >= limit {
            break;
        }
        if interrupt() {
            return Err(ArrowProfileError::Interrupted);
        }
        let header = read_batch_header(reader, *block)?;
        let batch_start = seen_rows;
        seen_rows = seen_rows
            .checked_add(header.rows)
            .ok_or_else(|| invalid("row count overflow"))?;
        if header.rows == 0 {
            plans.push(BlockPlan {
                batch_index,
                block: *block,
                header,
                slice_offset: 0,
                slice_length: 0,
            });
            continue;
        }
        // The requested window is [row_start, row_start + limit).
        let select_start = options.row_start.max(batch_start);
        let select_end = seen_rows.min(options.row_start.saturating_add(limit));
        if select_start >= select_end {
            continue;
        }
        plans.push(BlockPlan {
            batch_index,
            block: *block,
            header,
            slice_offset: usize::try_from(select_start - batch_start)
                .map_err(|_| invalid("batch is too large"))?,
            slice_length: usize::try_from(select_end - select_start)
                .map_err(|_| invalid("batch is too large"))?,
        });
        produced += select_end - select_start;
    }

    if let Some(maximum) = options.max_output_rows {
        if produced > maximum {
            return Err(invalid(format!(
                "selected row window contains {produced} rows; the maximum is {maximum}"
            )));
        }
    }

    // Only decode dictionary bodies after the selected output size is known
    // to be safe for the caller.
    let needed_ids: Vec<i64> = selected
        .iter()
        .filter_map(|&index| footer.layouts[index].dictionary_id)
        .collect();
    let dictionaries = read_dictionaries(reader, &footer, &needed_ids)?;

    // Verify each projected dictionary's values once, before any batch.
    if let Some(profile) = &profile {
        if let Some(checksums) = &profile.checksums {
            for &index in &selected {
                let Some(id) = footer.layouts[index].dictionary_id else {
                    continue;
                };
                let expected = checksums
                    .dictionaries
                    .get(&index.to_string())
                    .ok_or_else(|| {
                        super::profile::malformed(
                            &profile.version,
                            "checksums document is missing a dictionary entry",
                        )
                    })?;
                let values = make_array(dictionaries[&id].clone());
                verify_hashes(
                    &values,
                    expected,
                    footer.schema.field(index).name(),
                    usize::MAX,
                )
                .map_err(|error| match error {
                    ArrowProfileError::ChecksumMismatch { column, .. } => {
                        ArrowProfileError::ChecksumMismatch { column, batch: 0 }
                    }
                    other => other,
                })?;
            }
        }
    }

    Ok(PreparedRead {
        footer,
        profile,
        selected,
        dictionaries,
        plans,
        produced,
        stored_signature,
    })
}

/// Decode one selected column of one planned block, verify it when the
/// profile carries checksums, and slice it to the requested window.
fn decode_planned_column<R: Read + Seek>(
    reader: &mut R,
    context: &DecodeContext<'_>,
    plan: &BlockPlan,
    output_index: usize,
) -> Result<ArrayRef, ArrowProfileError> {
    let field_index = context.selected[output_index];
    let field = context.footer.schema.field(field_index);
    let layout = &context.footer.layouts[field_index];
    let dictionary = layout
        .dictionary_id
        .and_then(|id| context.dictionaries.get(&id));
    let body_start = plan.block.offset + u64::from(plan.block.metadata_length);
    let array = decode_field_array(
        reader,
        body_start,
        plan.block.body_length,
        &plan.header,
        layout,
        field.data_type(),
        field.is_nullable(),
        dictionary,
    )?;
    if array.len() as u64 != plan.header.rows {
        return Err(invalid("field length does not match the batch length"));
    }
    if let Some(profile) = context.profile {
        if let Some(checksums) = &profile.checksums {
            let expected = checksums
                .batches
                .get(plan.batch_index)
                .ok_or_else(|| {
                    super::profile::malformed(
                        &profile.version,
                        "checksums document is missing a record batch",
                    )
                })?
                .columns
                .get(field_index)
                .ok_or_else(|| {
                    super::profile::malformed(
                        &profile.version,
                        "checksums document is missing a column entry",
                    )
                })?;
            verify_hashes(&array, expected, field.name(), plan.batch_index)?;
        }
    }
    Ok(
        if plan.slice_offset == 0 && plan.slice_length == array.len() {
            array
        } else {
            array.slice(plan.slice_offset, plan.slice_length)
        },
    )
}

fn decode_blocks_serial<R: Read + Seek>(
    reader: &mut R,
    context: &DecodeContext<'_>,
    plans: &[BlockPlan],
    columns: &mut [ArrowReadColumn],
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    for plan in plans {
        if interrupt() {
            return Err(ArrowProfileError::Interrupted);
        }
        for (output_index, column) in columns.iter_mut().enumerate() {
            let chunk = decode_planned_column(reader, context, plan, output_index)?;
            column.chunks.push(chunk);
        }
    }
    Ok(())
}

/// The selected buffer bytes of every planned block, before decompression.
fn planned_selected_bytes(context: &DecodeContext<'_>, plans: &[BlockPlan]) -> u64 {
    let mut bytes = 0_u64;
    for plan in plans {
        for &field_index in context.selected {
            let layout = &context.footer.layouts[field_index];
            if let Some(entries) = plan
                .header
                .buffers
                .get(layout.buffer..layout.buffer + layout.buffer_count)
            {
                bytes = bytes.saturating_add(entries.iter().map(|&(_, length)| length).sum());
            }
        }
    }
    bytes
}

/// Resolve the decode worker count. Zero requests an automatic count, which
/// stays serial for small selections.
fn decode_thread_count(
    requested: usize,
    context: &DecodeContext<'_>,
    plans: &[BlockPlan],
    produced: u64,
) -> usize {
    if requested == 1 || plans.is_empty() || context.selected.is_empty() {
        return 1;
    }
    let bytes = planned_selected_bytes(context, plans);
    let cells = produced.saturating_mul(context.selected.len() as u64);
    if requested == 0 && bytes < MIN_PARALLEL_DECODE_BYTES && cells < MIN_PARALLEL_DECODE_CELLS {
        return 1;
    }
    let available = thread::available_parallelism().map_or(1, usize::from);
    let threads = if requested == 0 {
        available.min(MAX_AUTOMATIC_DECODE_THREADS)
    } else {
        requested.min(available)
    };
    threads
        .min(plans.len().saturating_mul(context.selected.len()))
        .max(1)
}

/// One parallel work unit: a contiguous range of selected columns within one
/// planned block.
struct DecodeTask {
    plan: usize,
    outputs: std::ops::Range<usize>,
}

fn decode_tasks(plans: &[BlockPlan], output_count: usize, threads: usize) -> Vec<DecodeTask> {
    // Split columns so both narrow-but-deep and wide-but-shallow selections
    // produce enough tasks to occupy every worker.
    let target_groups = (threads * 4).div_ceil(plans.len().max(1)).max(1);
    let group_count = target_groups.min(output_count.max(1));
    let group_size = output_count.div_ceil(group_count).max(1);
    let mut tasks = Vec::with_capacity(plans.len() * group_count);
    for plan in 0..plans.len() {
        let mut start = 0_usize;
        while start < output_count {
            let end = (start + group_size).min(output_count);
            tasks.push(DecodeTask {
                plan,
                outputs: start..end,
            });
            start = end;
        }
    }
    tasks
}

/// Claim tasks from the shared queue and decode them with a private reader.
/// `poll` runs between tasks; on the coordinating thread it checks R
/// interrupts, on workers it only observes the shared cancel flag.
fn decode_task_loop<R: Read + Seek>(
    reader: &mut R,
    context: &DecodeContext<'_>,
    plans: &[BlockPlan],
    tasks: &[DecodeTask],
    next: &AtomicUsize,
    cancelled: &AtomicBool,
    mut poll: impl FnMut() -> bool,
) -> Result<Vec<(usize, Vec<ArrayRef>)>, ArrowProfileError> {
    let mut results = Vec::new();
    loop {
        if poll() {
            cancelled.store(true, Ordering::Relaxed);
            return Err(ArrowProfileError::Interrupted);
        }
        if cancelled.load(Ordering::Relaxed) {
            return Ok(results);
        }
        let task_index = next.fetch_add(1, Ordering::Relaxed);
        let Some(task) = tasks.get(task_index) else {
            return Ok(results);
        };
        let plan = &plans[task.plan];
        let mut chunks = Vec::with_capacity(task.outputs.len());
        for output_index in task.outputs.clone() {
            match decode_planned_column(reader, context, plan, output_index) {
                Ok(chunk) => chunks.push(chunk),
                Err(error) => {
                    cancelled.store(true, Ordering::Relaxed);
                    return Err(error);
                }
            }
        }
        results.push((task_index, chunks));
    }
}

/// Decode planned blocks with `threads` workers, each reading through its own
/// file handle. The calling thread participates and is the only one that
/// polls `interrupt`.
fn decode_blocks_parallel(
    source: &File,
    context: &DecodeContext<'_>,
    plans: &[BlockPlan],
    columns: &mut [ArrowReadColumn],
    threads: usize,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let output_count = context.selected.len();
    let tasks = decode_tasks(plans, output_count, threads);
    let next = AtomicUsize::new(0);
    let cancelled = AtomicBool::new(false);

    let mut worker_files = Vec::with_capacity(threads.saturating_sub(1));
    for _ in 1..threads {
        worker_files.push(PositionedFile::new(source.try_clone()?));
    }

    let (own_result, worker_results) = thread::scope(|scope| {
        let handles: Vec<_> = worker_files
            .into_iter()
            .map(|file| {
                let next = &next;
                let cancelled = &cancelled;
                let tasks = &tasks;
                scope.spawn(move || {
                    let mut reader = BufReader::new(file);
                    decode_task_loop(&mut reader, context, plans, tasks, next, cancelled, || {
                        false
                    })
                })
            })
            .collect();
        let own = source
            .try_clone()
            .map_err(ArrowProfileError::from)
            .and_then(|file| {
                let mut reader = BufReader::new(PositionedFile::new(file));
                decode_task_loop(
                    &mut reader,
                    context,
                    plans,
                    &tasks,
                    &next,
                    &cancelled,
                    &mut *interrupt,
                )
            });
        if own.is_err() {
            cancelled.store(true, Ordering::Relaxed);
        }
        let worker_results: Vec<_> = handles
            .into_iter()
            .map(|handle| match handle.join() {
                Ok(result) => result,
                Err(_) => Err(invalid("a decode worker panicked")),
            })
            .collect();
        (own, worker_results)
    });

    let mut task_chunks: Vec<Option<Vec<ArrayRef>>> = (0..tasks.len()).map(|_| None).collect();
    let mut store = |results: Vec<(usize, Vec<ArrayRef>)>| {
        for (task_index, chunks) in results {
            task_chunks[task_index] = Some(chunks);
        }
    };
    // Surface the coordinating thread's error (interrupts included) first,
    // then any worker error.
    store(own_result?);
    for result in worker_results {
        store(result?);
    }

    for (task_index, task) in tasks.iter().enumerate() {
        let chunks = task_chunks[task_index]
            .take()
            .ok_or_else(|| invalid("a decode task produced no result"))?;
        if chunks.len() != task.outputs.len() {
            return Err(invalid("a decode task produced a partial result"));
        }
        for (chunk, output_index) in chunks.into_iter().zip(task.outputs.clone()) {
            columns[output_index].chunks.push(chunk);
        }
    }
    Ok(())
}

fn empty_dictionary<K: ArrowDictionaryKeyType>(
    values: ArrayRef,
) -> Result<ArrayRef, ArrowProfileError> {
    let keys = PrimitiveArray::<K>::from_iter_values(std::iter::empty());
    DictionaryArray::try_new(keys, values)
        .map(|array| Arc::new(array) as ArrayRef)
        .map_err(|error| invalid(format!("invalid dictionary: {error}")))
}

fn empty_dictionary_for(
    data_type: &DataType,
    values: ArrayRef,
) -> Result<ArrayRef, ArrowProfileError> {
    let DataType::Dictionary(key, _) = data_type else {
        return Err(invalid("dictionary layout has a non-dictionary field"));
    };
    match key.as_ref() {
        DataType::Int8 => empty_dictionary::<Int8Type>(values),
        DataType::Int16 => empty_dictionary::<Int16Type>(values),
        DataType::Int32 => empty_dictionary::<Int32Type>(values),
        DataType::Int64 => empty_dictionary::<Int64Type>(values),
        _ => Err(invalid("unsupported dictionary key type")),
    }
}

fn columns_skeleton(prepared: &PreparedRead) -> Result<Vec<ArrowReadColumn>, ArrowProfileError> {
    prepared
        .selected
        .iter()
        .map(|&index| {
            let field: &Field = prepared.footer.schema.field(index);
            let chunks = if prepared.plans.is_empty() {
                prepared.footer.layouts[index]
                    .dictionary_id
                    .map(|id| -> Result<ArrayRef, ArrowProfileError> {
                        let values = prepared.dictionaries.get(&id).ok_or_else(|| {
                            invalid("a dictionary-encoded column has no dictionary")
                        })?;
                        empty_dictionary_for(field.data_type(), make_array(values.clone()))
                    })
                    .transpose()?
                    .into_iter()
                    .collect()
            } else {
                Vec::new()
            };
            Ok(ArrowReadColumn {
                name: field.name().clone(),
                data_type: field.data_type().clone(),
                nullable: field.is_nullable(),
                dictionary_ordered: prepared.footer.layouts[index].dictionary_ordered,
                field: prepared
                    .profile
                    .as_ref()
                    .and_then(|profile| profile.fields[index].clone()),
                chunks,
            })
        })
        .collect()
}

fn finish_result(prepared: PreparedRead, columns: Vec<ArrowReadColumn>) -> ArrowReadResult {
    ArrowReadResult {
        profile_version: prepared
            .profile
            .as_ref()
            .map(|profile| profile.version.clone()),
        dataset: prepared.profile.map(|profile| profile.dataset),
        row_count: prepared.produced,
        columns,
        stored_signature: prepared.stored_signature,
    }
}

/// Read a dtatools Arrow profile file or a plain Arrow IPC file. Batch
/// bodies decode (and verify) in parallel when `options.threads` allows it.
pub fn read_arrow_file(
    path: impl AsRef<Path>,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<ArrowReadResult, ArrowProfileError> {
    ArrowFileSnapshot::open(path)?.read(options, interrupt)
}

impl ArrowFileSnapshot {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, ArrowProfileError> {
        let path = path.as_ref().to_owned();
        let file = File::open(&path)?;
        Ok(Self { path, file })
    }

    /// Read from the file identity captured by [`Self::open`].
    pub fn read(
        &self,
        options: &ArrowReadOptions,
        interrupt: &mut dyn FnMut() -> bool,
    ) -> Result<ArrowReadResult, ArrowProfileError> {
        let mut read = || -> Result<ArrowReadResult, ArrowProfileError> {
            let mut reader = BufReader::new(self.file.try_clone()?);
            let prepared = prepare_read(&mut reader, options, interrupt)?;
            let mut columns = columns_skeleton(&prepared)?;
            let context = DecodeContext {
                footer: &prepared.footer,
                profile: prepared.profile.as_ref(),
                selected: &prepared.selected,
                dictionaries: &prepared.dictionaries,
            };
            let threads = decode_thread_count(
                options.threads,
                &context,
                &prepared.plans,
                prepared.produced,
            );
            if threads > 1 {
                decode_blocks_parallel(
                    reader.get_ref(),
                    &context,
                    &prepared.plans,
                    &mut columns,
                    threads,
                    interrupt,
                )?;
            } else {
                decode_blocks_serial(
                    &mut reader,
                    &context,
                    &prepared.plans,
                    &mut columns,
                    interrupt,
                )?;
            }
            Ok(finish_result(prepared, columns))
        };
        read().map_err(|error| match error {
            ArrowProfileError::NotAnArrowFile(_) => {
                ArrowProfileError::NotAnArrowFile(self.path.display().to_string())
            }
            other => other,
        })
    }
}

/// Read from any seekable source. Always serial: parallel decoding needs
/// independent file handles, which only the path entry point can open.
pub fn read_arrow_file_from<R: Read + Seek>(
    reader: &mut R,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<ArrowReadResult, ArrowProfileError> {
    let prepared = prepare_read(reader, options, interrupt)?;
    let mut columns = columns_skeleton(&prepared)?;
    let context = DecodeContext {
        footer: &prepared.footer,
        profile: prepared.profile.as_ref(),
        selected: &prepared.selected,
        dictionaries: &prepared.dictionaries,
    };
    decode_blocks_serial(reader, &context, &prepared.plans, &mut columns, interrupt)?;
    Ok(finish_result(prepared, columns))
}

/// The R type family used to build tidyselect proxies for one field.
fn r_type_for(
    field: &Field,
    document: Option<&ArrowFieldDocument>,
    int32_requires_double: bool,
) -> &'static str {
    if document.and_then(|document| document.storage).is_some() || int32_requires_double {
        return "double";
    }
    if let Some(class) = document
        .and_then(|document| document.r.as_ref())
        .map(|semantics| semantics.class.as_str())
    {
        return match class {
            "logical" => "logical",
            "integer" => "integer",
            "character" => "character",
            "factor" => "factor",
            "raw" => "raw",
            _ => "double",
        };
    }
    match field.data_type() {
        DataType::Boolean => "logical",
        DataType::Int8 | DataType::Int16 | DataType::Int32 | DataType::UInt8 => "integer",
        DataType::Utf8 | DataType::LargeUtf8 => "character",
        DataType::Dictionary(_, _) => "factor",
        _ => "double",
    }
}

fn checksum_hash_count(data_type: &DataType, null_count: u64) -> Result<usize, ArrowProfileError> {
    let ipc_buffers = buffer_count_for(data_type)
        .ok_or_else(|| invalid(format!("unsupported Arrow type {data_type}")))?;
    Ok(ipc_buffers - 1 + usize::from(null_count > 0))
}

fn validate_checksum_hashes(
    version: &str,
    hashes: &[String],
    expected: usize,
    location: &str,
) -> Result<(), ArrowProfileError> {
    let valid_hex = hashes.iter().all(|hash| {
        hash.len() == 16
            && hash
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    });
    if hashes.len() != expected || !valid_hex {
        return Err(super::profile::malformed(
            version,
            format!("checksums document does not cover every buffer of {location}"),
        ));
    }
    Ok(())
}

/// Validate that the stored checksums cover the full schema, using only IPC
/// batch headers. Return the file row count while those headers are in hand.
fn validate_stored_checksum_coverage<R: Read + Seek>(
    reader: &mut R,
    footer: &Footer,
    version: &str,
    checksums: &ChecksumsDocument,
) -> Result<u64, ArrowProfileError> {
    if checksums.batches.len() != footer.record_blocks.len() {
        return Err(super::profile::malformed(
            version,
            "checksums document does not cover every record batch",
        ));
    }

    let field_count = footer.schema.fields().len();
    let canonical_rows = super::write::ARROW_ROWS_PER_BATCH as u64;
    let has_dictionary = footer
        .layouts
        .iter()
        .any(|layout| layout.dictionary_id.is_some());
    let mut row_count = 0_u64;
    for (batch_index, (block, batch_checksums)) in footer
        .record_blocks
        .iter()
        .zip(&checksums.batches)
        .enumerate()
    {
        if batch_checksums.columns.len() != field_count {
            return Err(super::profile::malformed(
                version,
                format!(
                    "checksums document does not cover every column of record batch {batch_index}"
                ),
            ));
        }
        let header = read_batch_header(reader, *block)?;
        let final_batch = batch_index + 1 == checksums.batches.len();
        let canonical_geometry = if header.rows == 0 {
            final_batch && batch_index == 0 && has_dictionary
        } else if final_batch {
            header.rows <= canonical_rows
        } else {
            header.rows == canonical_rows
        };
        if !canonical_geometry {
            return Err(super::profile::malformed(
                version,
                format!(
                    "record batch {batch_index} has {} rows instead of the canonical record-batch geometry",
                    header.rows
                ),
            ));
        }
        row_count = row_count
            .checked_add(header.rows)
            .ok_or_else(|| invalid("row count overflows"))?;
        for (field_index, hashes) in batch_checksums.columns.iter().enumerate() {
            let field = footer.schema.field(field_index);
            let layout = &footer.layouts[field_index];
            let &(length, null_count) = header
                .nodes
                .get(layout.node)
                .ok_or_else(|| invalid("record batch is missing a field node"))?;
            if length != header.rows {
                return Err(invalid("field length does not match the batch length"));
            }
            if null_count > 0 && !field.is_nullable() {
                return Err(super::profile::malformed(
                    version,
                    format!(
                        "non-nullable field `{}` contains nulls in record batch {batch_index}",
                        field.name()
                    ),
                ));
            }
            if header
                .buffers
                .get(layout.buffer..layout.buffer + layout.buffer_count)
                .is_none()
            {
                return Err(invalid("record batch is missing field buffers"));
            }
            validate_checksum_hashes(
                version,
                hashes,
                checksum_hash_count(field.data_type(), null_count)?,
                &format!("column `{}`, record batch {batch_index}", field.name()),
            )?;
        }
    }

    let mut dictionary_types = HashMap::<i64, &DataType>::new();
    let mut dictionary_columns = Vec::new();
    for (index, (field, layout)) in footer
        .schema
        .fields()
        .iter()
        .zip(&footer.layouts)
        .enumerate()
    {
        let Some(id) = layout.dictionary_id else {
            continue;
        };
        let DataType::Dictionary(_, value_type) = field.data_type() else {
            return Err(invalid("dictionary layout has a non-dictionary field"));
        };
        if let Some(existing) = dictionary_types.insert(id, value_type.as_ref()) {
            if existing != value_type.as_ref() {
                return Err(invalid("one dictionary id has conflicting value types"));
            }
        }
        dictionary_columns.push((index, id, field.name().as_str()));
    }
    if checksums.dictionaries.len() != dictionary_columns.len()
        || dictionary_columns
            .iter()
            .any(|(index, _, _)| !checksums.dictionaries.contains_key(&index.to_string()))
    {
        return Err(super::profile::malformed(
            version,
            "checksums document does not cover every dictionary column",
        ));
    }

    let mut dictionary_nulls = HashMap::<i64, bool>::new();
    for block in &footer.dictionary_blocks {
        let mut bytes = metadata_buffer(u64::from(block.metadata_length), "dictionary batch")?;
        read_exact_at(reader, block.offset, &mut bytes)?;
        let message = parse_message_header(&bytes)?;
        let batch = message
            .header_as_dictionary_batch()
            .ok_or_else(|| invalid("dictionary block does not contain a dictionary"))?;
        let id = batch.id();
        if !dictionary_types.contains_key(&id) {
            continue;
        }
        let header = batch_header_from(
            batch
                .data()
                .ok_or_else(|| invalid("dictionary batch has no data"))?,
        )?;
        let &(_, null_count) = header
            .nodes
            .first()
            .ok_or_else(|| invalid("dictionary batch is missing a field node"))?;
        if batch.isDelta() {
            let has_nulls = dictionary_nulls
                .get_mut(&id)
                .ok_or_else(|| invalid("delta dictionary has no preceding dictionary"))?;
            *has_nulls |= null_count > 0;
        } else {
            dictionary_nulls.insert(id, null_count > 0);
        }
    }
    for (index, id, name) in dictionary_columns {
        let has_nulls = dictionary_nulls
            .get(&id)
            .ok_or_else(|| invalid("a dictionary-encoded column has no dictionary"))?;
        let hashes = &checksums.dictionaries[&index.to_string()];
        validate_checksum_hashes(
            version,
            hashes,
            checksum_hash_count(dictionary_types[&id], u64::from(*has_nulls))?,
            &format!("dictionary column `{name}`"),
        )?;
    }
    Ok(row_count)
}

fn stored_signature_from_footer<R: Read + Seek>(
    reader: &mut R,
    footer: &Footer,
) -> Result<String, ArrowProfileError> {
    let profile = parse_profile(footer, true, false)?.ok_or_else(|| {
        ArrowProfileError::InvalidFile(
            "the file carries no dtatools Arrow profile, so it stores no checksums to derive \
             a signature from"
                .to_owned(),
        )
    })?;
    let json = footer
        .custom_metadata
        .get(ARROW_CHECKSUMS_KEY)
        .ok_or_else(|| {
            ArrowProfileError::InvalidFile(
                "the file was written without checksums, so its signature cannot be derived \
                 from the footer; read the data and compute it with datasig() instead"
                    .to_owned(),
            )
        })?;
    let checksums = parse_checksums_document(&profile.version, json)?;
    let row_count =
        validate_stored_checksum_coverage(reader, footer, &profile.version, &checksums)?;
    super::write::signature_from_parts(
        row_count,
        footer
            .schema
            .fields()
            .iter()
            .zip(&profile.fields)
            .map(|(field, document)| (field.name().as_str(), field.data_type(), document.as_ref())),
        footer.schema.fields().len(),
        &profile.dataset,
        &checksums,
    )
}

/// Derive the dataset signature from an Arrow file's stored metadata alone:
/// the schema documents plus the footer checksums document. No data buffers
/// are read or rehashed, so the result records what the file declares about
/// its own content; pair it with a verifying read to also validate the
/// declared checksums against the stored bytes. Identical to
/// [`super::dataset_signature`] over the same logical dataset.
pub fn arrow_stored_signature(path: impl AsRef<Path>) -> Result<String, ArrowProfileError> {
    let path = path.as_ref();
    let mut reader = BufReader::new(File::open(path)?);
    let footer = match read_footer(&mut reader) {
        Err(ArrowProfileError::NotAnArrowFile(_)) => {
            return Err(ArrowProfileError::NotAnArrowFile(
                path.display().to_string(),
            ))
        }
        other => other?,
    };
    stored_signature_from_footer(&mut reader, &footer)
}

pub fn summarize_arrow_file(
    path: impl AsRef<Path>,
    apply_profile: bool,
    scan_ambiguous_int32: bool,
    row_start: u64,
    row_count: Option<u64>,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<ArrowFileSummary, ArrowProfileError> {
    ArrowFileSnapshot::open(path)?.summarize(
        apply_profile,
        scan_ambiguous_int32,
        row_start,
        row_count,
        interrupt,
    )
}

impl ArrowFileSnapshot {
    /// Read selection metadata from this snapshot, scanning ambiguous Int32
    /// values only when a tidyselect predicate needs their concrete R type.
    pub fn summarize(
        &self,
        apply_profile: bool,
        scan_ambiguous_int32: bool,
        row_start: u64,
        row_count: Option<u64>,
        interrupt: &mut dyn FnMut() -> bool,
    ) -> Result<ArrowFileSummary, ArrowProfileError> {
        let mut reader = BufReader::new(self.file.try_clone()?);
        let footer = match read_footer(&mut reader) {
            Err(ArrowProfileError::NotAnArrowFile(_)) => {
                return Err(ArrowProfileError::NotAnArrowFile(
                    self.path.display().to_string(),
                ))
            }
            other => other?,
        };
        let profile = parse_profile(&footer, apply_profile, false)?;
        let ambiguous_int32: Vec<u32> = if scan_ambiguous_int32 {
            footer
                .schema
                .fields()
                .iter()
                .enumerate()
                .filter(|(index, field)| {
                    let document = profile
                        .as_ref()
                        .and_then(|profile| profile.fields[*index].as_ref());
                    field.data_type() == &DataType::Int32
                        && document.and_then(|document| document.storage).is_none()
                        && document
                            .and_then(|document| document.r.as_ref())
                            .is_none_or(|semantics| semantics.class != "integer")
                })
                .map(|(index, _)| {
                    u32::try_from(index)
                        .map_err(|_| invalid("an Arrow file has too many columns to summarize"))
                })
                .collect::<Result<_, _>>()?
        } else {
            Vec::new()
        };
        let mut int32_requires_double = vec![false; footer.schema.fields().len()];
        if !ambiguous_int32.is_empty() {
            let mut scan_reader = BufReader::new(self.file.try_clone()?);
            let prepared = prepare_read(
                &mut scan_reader,
                &ArrowReadOptions {
                    columns: Some(ambiguous_int32.clone()),
                    row_start,
                    row_count,
                    max_output_rows: None,
                    verify: false,
                    profile: apply_profile,
                    record_signature: false,
                    threads: 1,
                },
                interrupt,
            )?;
            let context = DecodeContext {
                footer: &prepared.footer,
                profile: prepared.profile.as_ref(),
                selected: &prepared.selected,
                dictionaries: &prepared.dictionaries,
            };
            let mut found = vec![false; ambiguous_int32.len()];
            for plan in &prepared.plans {
                if interrupt() {
                    return Err(ArrowProfileError::Interrupted);
                }
                for (output_index, found) in found.iter_mut().enumerate() {
                    if *found {
                        continue;
                    }
                    let chunk =
                        decode_planned_column(&mut scan_reader, &context, plan, output_index)?;
                    let values = chunk.as_any().downcast_ref::<Int32Array>().ok_or_else(|| {
                        invalid("an Int32 summary decoded a different Arrow type")
                    })?;
                    *found = (0..values.len())
                        .any(|row| !values.is_null(row) && values.value(row) == i32::MIN);
                }
                if found.iter().all(|found| *found) {
                    break;
                }
            }
            for (&index, found) in ambiguous_int32.iter().zip(found) {
                int32_requires_double[index as usize] = found;
            }
        }
        let columns = footer
            .schema
            .fields()
            .iter()
            .enumerate()
            .map(|(index, field)| ArrowColumnSummary {
                name: field.name().clone(),
                r_type: r_type_for(
                    field,
                    profile
                        .as_ref()
                        .and_then(|profile| profile.fields[index].as_ref()),
                    int32_requires_double[index],
                ),
            })
            .collect();
        Ok(ArrowFileSummary { columns })
    }
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use arrow_array::Int32Array;
    use flatbuffers::FlatBufferBuilder;

    use super::*;
    use crate::arrow::{
        save_arrow_file, ArrowCompression, ArrowWriteColumn, ArrowWriteDataset,
        ARROW_ROWS_PER_BATCH,
    };

    #[cfg(unix)]
    #[test]
    fn parallel_decode_uses_the_prepared_file_snapshot() {
        let directory =
            std::env::temp_dir().join(format!("dtatools-arrow-snapshot-{}", std::process::id()));
        std::fs::create_dir_all(&directory).expect("temp directory");
        let path = directory.join("source.arrow");
        let replacement = directory.join("replacement.arrow");
        let write = |path: &Path, first: i32| {
            let dataset = ArrowWriteDataset {
                dataset: DatasetDocument::default(),
                columns: vec![
                    ArrowWriteColumn {
                        name: "x".to_owned(),
                        field: None,
                        array: Arc::new(Int32Array::from(vec![first, first + 1])),
                    },
                    ArrowWriteColumn {
                        name: "y".to_owned(),
                        field: None,
                        array: Arc::new(Int32Array::from(vec![first + 2, first + 3])),
                    },
                ],
            };
            save_arrow_file(
                path,
                &dataset,
                ArrowCompression::Uncompressed,
                ARROW_ROWS_PER_BATCH,
                1,
                true,
                &mut || false,
            )
            .expect("fixture writes");
        };
        write(&path, 1);
        write(&replacement, 101);

        let mut reader = BufReader::new(File::open(&path).expect("source opens"));
        let options = ArrowReadOptions {
            verify: false,
            threads: 2,
            ..ArrowReadOptions::default()
        };
        let prepared =
            prepare_read(&mut reader, &options, &mut || false).expect("source metadata reads");
        std::fs::rename(&replacement, &path).expect("path is atomically replaced");
        let mut columns = columns_skeleton(&prepared).expect("column skeletons");
        {
            let context = DecodeContext {
                footer: &prepared.footer,
                profile: prepared.profile.as_ref(),
                selected: &prepared.selected,
                dictionaries: &prepared.dictionaries,
            };
            decode_blocks_parallel(
                reader.get_ref(),
                &context,
                &prepared.plans,
                &mut columns,
                2,
                &mut || false,
            )
            .expect("parallel decode succeeds");
        }
        let result = finish_result(prepared, columns);
        let values = result.columns[0].chunks[0]
            .as_any()
            .downcast_ref::<Int32Array>()
            .expect("Int32 result");
        assert_eq!(values.values(), &[1, 2]);
        std::fs::remove_dir_all(directory).expect("temp directory removed");
    }

    #[test]
    fn ipc_metadata_allocations_are_bounded() {
        let error = metadata_buffer(MAX_IPC_METADATA_BYTES + 1, "record batch")
            .expect_err("oversized metadata is rejected before allocation");
        assert!(error.to_string().contains("64 MiB safety limit"));
    }

    #[test]
    fn negative_field_null_counts_are_rejected() {
        let mut builder = FlatBufferBuilder::new();
        let nodes = builder.create_vector(&[arrow_ipc::FieldNode::new(1, -1)]);
        let buffers =
            builder.create_vector(&[arrow_ipc::Buffer::new(0, 0), arrow_ipc::Buffer::new(0, 4)]);
        let batch = arrow_ipc::RecordBatch::create(
            &mut builder,
            &arrow_ipc::RecordBatchArgs {
                length: 1,
                nodes: Some(nodes),
                buffers: Some(buffers),
                ..Default::default()
            },
        );
        builder.finish(batch, None);
        let batch = flatbuffers::root::<arrow_ipc::RecordBatch<'_>>(builder.finished_data())
            .expect("the test batch is a valid FlatBuffer");

        let error = match batch_header_from(batch) {
            Err(error) => error,
            Ok(_) => panic!("negative null count must be rejected"),
        };
        assert!(error.to_string().contains("negative field null count"));
    }

    #[test]
    fn ipc_endianness_validation_follows_the_target_host() {
        let matching = if cfg!(target_endian = "little") {
            arrow_ipc::Endianness::Little
        } else {
            arrow_ipc::Endianness::Big
        };
        let mismatched = if cfg!(target_endian = "little") {
            arrow_ipc::Endianness::Big
        } else {
            arrow_ipc::Endianness::Little
        };

        validate_ipc_endianness(matching).expect("matching endianness is supported");
        let error = validate_ipc_endianness(mismatched)
            .expect_err("mismatched endianness must be rejected");
        assert!(error.to_string().contains("does not match this host"));
    }

    #[test]
    fn malformed_flatbuffer_field_types_are_rejected_without_panicking() {
        let mut builder = FlatBufferBuilder::new();
        let name = builder.create_string("broken");
        let field = arrow_ipc::Field::create(
            &mut builder,
            &arrow_ipc::FieldArgs {
                name: Some(name),
                type_type: arrow_ipc::Type::NONE,
                ..Default::default()
            },
        );
        builder.finish(field, None);
        let field = flatbuffers::root::<arrow_ipc::Field<'_>>(builder.finished_data())
            .expect("the test field is a valid FlatBuffer");

        let error =
            validate_flatbuffer_field(field).expect_err("an absent field type must be rejected");
        assert!(error
            .to_string()
            .contains("unsupported Arrow field type NONE"));

        let mut builder = FlatBufferBuilder::new();
        let name = builder.create_string("broken integer");
        let integer = arrow_ipc::Int::create(
            &mut builder,
            &arrow_ipc::IntArgs {
                bitWidth: 24,
                is_signed: true,
            },
        );
        let field = arrow_ipc::Field::create(
            &mut builder,
            &arrow_ipc::FieldArgs {
                name: Some(name),
                type_type: arrow_ipc::Type::Int,
                type_: Some(integer.as_union_value()),
                ..Default::default()
            },
        );
        builder.finish(field, None);
        let field = flatbuffers::root::<arrow_ipc::Field<'_>>(builder.finished_data())
            .expect("the test integer field is a valid FlatBuffer");

        let error = validate_flatbuffer_field(field)
            .expect_err("an invalid integer width must be rejected");
        assert!(error.to_string().contains("unsupported integer bit width"));
    }

    #[test]
    fn oversized_uncompressed_buffer_is_rejected_before_allocation() {
        let mut reader = Cursor::new([0_u8; 1]);
        let error = read_ipc_buffer(&mut reader, 0, 1_u64 << 40, (0, 1_u64 << 40), None, 4)
            .expect_err("the field layout bounds the allocation");
        assert!(error
            .to_string()
            .contains("buffer length does not match its field layout"));
    }

    #[test]
    fn oversized_compressed_declaration_is_rejected_before_decompression() {
        let declared = (1_i64 << 40).to_le_bytes();
        let mut reader = Cursor::new(declared);
        let error = read_ipc_buffer(
            &mut reader,
            0,
            declared.len() as u64,
            (0, declared.len() as u64),
            Some(Compression::Zstd),
            4,
        )
        .expect_err("the field layout bounds decompression");
        assert!(error
            .to_string()
            .contains("declared decompressed buffer length mismatch"));
    }
}
