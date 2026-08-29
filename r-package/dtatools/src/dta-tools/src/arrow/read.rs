//! The dtatools Arrow profile reader.
//!
//! The reader parses the IPC file footer and each record batch's flatbuffer
//! header itself, then reads only the buffer byte ranges of the selected
//! columns. A projected read therefore costs I/O proportional to the selected
//! columns' buffers; whole batches outside the requested row window are
//! skipped after their small headers are read.

use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::thread;

use arrow_array::{make_array, ArrayRef};
use arrow_buffer::{Buffer, MutableBuffer};
use arrow_data::ArrayData;
use arrow_ipc::{root_as_footer, root_as_message, CompressionType, MessageHeader};
use arrow_schema::{DataType, Field, Schema};

use super::checksum::canonical_array_hashes;
use super::profile::{
    checksum_to_hex, parse_checksums_document, parse_dataset_document, parse_field_document,
    ArrowFieldDocument, ChecksumsDocument, DatasetDocument, ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY,
    ARROW_FIELD_KEY, ARROW_PROFILE_VERSION, ARROW_PROFILE_VERSION_KEY,
};
use super::ArrowProfileError;

const FILE_MAGIC: &[u8; 6] = b"ARROW1";
const CONTINUATION_MARKER: [u8; 4] = [0xff, 0xff, 0xff, 0xff];

/// Selection and safety options for one Arrow read.
#[derive(Debug, Clone, Default)]
pub struct ArrowReadOptions {
    /// Projected column indices in output order, or `None` for all columns.
    pub columns: Option<Vec<u32>>,
    /// Rows to skip before the first returned row.
    pub row_start: u64,
    /// Maximum rows to return, or `None` for all remaining rows.
    pub row_count: Option<u64>,
    /// Verify the checksums of every buffer the read touches.
    pub verify: bool,
    /// Apply `dtatools:*` profile metadata. `false` is the escape hatch that
    /// reads the raw storage arrays as plain Arrow data.
    pub profile: bool,
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
}

/// One column's name and the R type family used for selection proxies.
pub struct ArrowColumnSummary {
    pub name: String,
    pub r_type: &'static str,
}

/// Column names and proxy types read from the file footer alone.
pub struct ArrowFileSummary {
    pub columns: Vec<ArrowColumnSummary>,
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
        DataType::Dictionary(key, value) => (matches!(key.as_ref(), DataType::Int32)
            && matches!(value.as_ref(), DataType::Utf8 | DataType::LargeUtf8))
        .then_some(2),
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
    let mut footer_bytes =
        vec![0_u8; usize::try_from(footer_length).map_err(|_| { invalid("footer is too large") })?];
    read_exact_at(reader, file_length - 10 - footer_length, &mut footer_bytes)?;
    let footer =
        root_as_footer(&footer_bytes).map_err(|error| invalid(format!("bad footer: {error}")))?;

    let fb_schema = footer
        .schema()
        .ok_or_else(|| invalid("footer has no schema"))?;
    if fb_schema.endianness() != arrow_ipc::Endianness::Little {
        return Err(invalid("big-endian Arrow files are not supported"));
    }
    let schema = arrow_ipc::convert::fb_to_schema(fb_schema);

    let mut layouts = Vec::with_capacity(schema.fields().len());
    let mut buffer = 0_usize;
    let fb_fields = fb_schema.fields().unwrap_or_default();
    for (index, field) in schema.fields().iter().enumerate() {
        let buffer_count = buffer_count_for(field.data_type()).ok_or_else(|| {
            ArrowProfileError::UnsupportedColumn {
                column: field.name().clone(),
                data_type: field.data_type().to_string(),
            }
        })?;
        let dictionary_id = (index < fb_fields.len())
            .then(|| {
                fb_fields
                    .get(index)
                    .dictionary()
                    .map(|encoding| encoding.id())
            })
            .flatten();
        // The supported types are all flat, so each field is one node.
        layouts.push(FieldLayout {
            node: index,
            buffer,
            buffer_count,
            dictionary_id,
        });
        buffer += buffer_count;
    }

    let block_info = |block: &arrow_ipc::Block| -> Result<BlockInfo, ArrowProfileError> {
        Ok(BlockInfo {
            offset: u64::try_from(block.offset()).map_err(|_| invalid("negative block offset"))?,
            metadata_length: u32::try_from(block.metaDataLength())
                .map_err(|_| invalid("negative block metadata length"))?,
            body_length: u64::try_from(block.bodyLength())
                .map_err(|_| invalid("negative block body length"))?,
        })
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
            .map(|json| parse_field_document(version, field.name(), json))
            .transpose()?;
        fields.push(document);
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
    let mut bytes = vec![0_u8; block.metadata_length as usize];
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
                        u64::try_from(node.null_count().max(0)).expect("clamped"),
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
) -> Result<Buffer, ArrowProfileError> {
    let (offset, length) = entry;
    if offset
        .checked_add(length)
        .is_none_or(|end| end > body_length)
    {
        return Err(invalid("buffer extends past the record batch body"));
    }
    if length == 0 {
        return Ok(Buffer::from(MutableBuffer::new(0)));
    }
    let length = usize::try_from(length).map_err(|_| invalid("buffer is too large"))?;
    match compression {
        None => {
            let mut buffer = MutableBuffer::from_len_zeroed(length);
            read_exact_at(reader, body_start + offset, buffer.as_slice_mut())?;
            Ok(Buffer::from(buffer))
        }
        Some(codec) => {
            let mut raw = vec![0_u8; length];
            read_exact_at(reader, body_start + offset, &mut raw)?;
            if raw.len() < 8 {
                return Err(invalid("compressed buffer is too short"));
            }
            let declared = i64::from_le_bytes(raw[..8].try_into().expect("8 bytes"));
            let payload = &raw[8..];
            if declared == -1 {
                let mut buffer = MutableBuffer::from_len_zeroed(payload.len());
                buffer.as_slice_mut().copy_from_slice(payload);
                return Ok(Buffer::from(buffer));
            }
            let declared =
                usize::try_from(declared).map_err(|_| invalid("bad compressed length"))?;
            let decompressed = match codec {
                Compression::Lz4 => {
                    let mut output = Vec::with_capacity(declared);
                    let mut decoder = lz4_flex::frame::FrameDecoder::new(payload);
                    decoder
                        .read_to_end(&mut output)
                        .map_err(|error| invalid(format!("LZ4 decompression failed: {error}")))?;
                    output
                }
                Compression::Zstd => zstd::stream::decode_all(payload)
                    .map_err(|error| invalid(format!("zstd decompression failed: {error}")))?,
            };
            if decompressed.len() != declared {
                return Err(invalid("decompressed buffer length mismatch"));
            }
            let mut buffer = MutableBuffer::from_len_zeroed(decompressed.len());
            buffer.as_slice_mut().copy_from_slice(&decompressed);
            Ok(Buffer::from(buffer))
        }
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

    let validity = if null_count > 0 && entries[0].1 > 0 {
        Some(read_ipc_buffer(
            reader,
            body_start,
            body_length,
            entries[0],
            header.compression,
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
    for entry in &entries[1..] {
        builder = builder.add_buffer(read_ipc_buffer(
            reader,
            body_start,
            body_length,
            *entry,
            header.compression,
        )?);
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
        let mut bytes = vec![0_u8; block.metadata_length as usize];
        read_exact_at(reader, block.offset, &mut bytes)?;
        let message = parse_message_header(&bytes)?;
        if message.header_type() != MessageHeader::DictionaryBatch {
            return Err(invalid("dictionary block does not contain a dictionary"));
        }
        let batch = message
            .header_as_dictionary_batch()
            .ok_or_else(|| invalid("bad dictionary batch"))?;
        if batch.isDelta() {
            return Err(invalid("delta dictionaries are not supported"));
        }
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
        };
        let body_start = block.offset + u64::from(block.metadata_length);
        let values = decode_field_array(
            reader,
            body_start,
            block.body_length,
            &header,
            &layout,
            value_type,
            None,
        )?;
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
}

fn prepare_read<R: Read + Seek>(
    reader: &mut R,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<PreparedRead, ArrowProfileError> {
    let footer = read_footer(reader)?;
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

    Ok(PreparedRead {
        footer,
        profile,
        selected,
        dictionaries,
        plans,
        produced,
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
        dictionary,
    )?;
    if array.len() as u64 != plan.header.rows {
        return Err(invalid("field length does not match the batch length"));
    }
    if let Some(profile) = context.profile {
        if let Some(checksums) = &profile.checksums {
            let expected = checksums.batches[plan.batch_index]
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
    path: &Path,
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
        worker_files.push(File::open(path)?);
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
        let own = File::open(path)
            .map_err(ArrowProfileError::from)
            .and_then(|file| {
                let mut reader = BufReader::new(file);
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

fn columns_skeleton(prepared: &PreparedRead) -> Vec<ArrowReadColumn> {
    prepared
        .selected
        .iter()
        .map(|&index| {
            let field: &Field = prepared.footer.schema.field(index);
            ArrowReadColumn {
                name: field.name().clone(),
                data_type: field.data_type().clone(),
                nullable: field.is_nullable(),
                field: prepared
                    .profile
                    .as_ref()
                    .and_then(|profile| profile.fields[index].clone()),
                chunks: Vec::new(),
            }
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
    }
}

/// Read a dtatools Arrow profile file or a plain Arrow IPC file. Batch
/// bodies decode (and verify) in parallel when `options.threads` allows it.
pub fn read_arrow_file(
    path: impl AsRef<Path>,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<ArrowReadResult, ArrowProfileError> {
    let path = path.as_ref();
    let mut read = || -> Result<ArrowReadResult, ArrowProfileError> {
        let mut reader = BufReader::new(File::open(path)?);
        let prepared = prepare_read(&mut reader, options, interrupt)?;
        let mut columns = columns_skeleton(&prepared);
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
                path,
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
            ArrowProfileError::NotAnArrowFile(path.display().to_string())
        }
        other => other,
    })
}

/// Read from any seekable source. Always serial: parallel decoding needs
/// independent file handles, which only the path entry point can open.
pub fn read_arrow_file_from<R: Read + Seek>(
    reader: &mut R,
    options: &ArrowReadOptions,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<ArrowReadResult, ArrowProfileError> {
    let prepared = prepare_read(reader, options, interrupt)?;
    let mut columns = columns_skeleton(&prepared);
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
fn r_type_for(field: &Field, document: Option<&ArrowFieldDocument>) -> &'static str {
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

/// Column names and proxy types from the footer, for tidyselect resolution.
pub fn summarize_arrow_file(path: impl AsRef<Path>) -> Result<ArrowFileSummary, ArrowProfileError> {
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
    let profile = parse_profile(&footer, true, false)?;
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
            ),
        })
        .collect();
    Ok(ArrowFileSummary { columns })
}
