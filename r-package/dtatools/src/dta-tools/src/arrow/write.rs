//! The dtatools Arrow profile writer: bounded record batches through the
//! official `arrow-ipc` `FileWriter`, with `dtatools:*` schema and field
//! metadata and per-buffer checksums in the footer.

use std::collections::{BTreeMap, HashMap};
use std::fs::File;
use std::hash::Hasher;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;

use arrow_array::{Array, ArrayRef, RecordBatch};
use arrow_ipc::convert::{metadata_to_fb, IpcSchemaEncoder};
use arrow_ipc::writer::{DictionaryTracker, FileWriter, IpcWriteOptions};
use arrow_ipc::{Block, CompressionType, FooterBuilder, MetadataVersion};
use arrow_schema::{DataType, Field, Schema};
use flatbuffers::FlatBufferBuilder;

use super::checksum::canonical_array_hashes;
use super::profile::{
    checksum_to_hex, validate_dataset_document, validate_field_document,
    validate_value_label_reference, ArrowFieldDocument, BatchChecksums, ChecksumsDocument,
    DatasetDocument, ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY, ARROW_FIELD_KEY,
    ARROW_PROFILE_VERSION, ARROW_PROFILE_VERSION_KEY, DOCUMENT_VERSION,
};
use super::ArrowProfileError;
use super::MAX_IPC_METADATA_BYTES;

/// Canonical rows per record batch, pinned by benchmark. The multiple of 64
/// keeps sliced validity and boolean bitmaps byte-aligned.
pub const ARROW_ROWS_PER_BATCH: usize = 65_536;

/// The IPC body compression to apply. The default is uncompressed; readers
/// detect the codec from the file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArrowCompression {
    Uncompressed,
    Lz4,
    Zstd,
}

impl ArrowCompression {
    pub fn from_label(label: &str) -> Option<Self> {
        match label {
            "uncompressed" => Some(Self::Uncompressed),
            "lz4" => Some(Self::Lz4),
            "zstd" => Some(Self::Zstd),
            _ => None,
        }
    }

    fn compression_type(self) -> Option<CompressionType> {
        match self {
            Self::Uncompressed => None,
            Self::Lz4 => Some(CompressionType::LZ4_FRAME),
            Self::Zstd => Some(CompressionType::ZSTD),
        }
    }
}

/// One output column: its Arrow array with the optional `dtatools:field`
/// document carrying the semantics standard Arrow types do not express.
pub struct ArrowWriteColumn {
    pub name: String,
    pub field: Option<ArrowFieldDocument>,
    pub array: ArrayRef,
}

/// A complete dataset to save: the `dtatools:dataset` document and the
/// ordered columns.
pub struct ArrowWriteDataset {
    pub dataset: DatasetDocument,
    pub columns: Vec<ArrowWriteColumn>,
}

fn supported_write_type(data_type: &DataType) -> bool {
    match data_type {
        DataType::Boolean
        | DataType::Int8
        | DataType::Int16
        | DataType::Int32
        | DataType::Int64
        | DataType::UInt8
        | DataType::Float32
        | DataType::Float64
        | DataType::Date32
        | DataType::Timestamp(_, _)
        | DataType::Duration(_)
        | DataType::Utf8
        | DataType::LargeUtf8 => true,
        DataType::Dictionary(key, value) => {
            matches!(key.as_ref(), DataType::Int32)
                && matches!(value.as_ref(), DataType::Utf8 | DataType::LargeUtf8)
        }
        _ => false,
    }
}

fn dictionary_values(array: &ArrayRef) -> Option<ArrayRef> {
    let data = array.to_data();
    let child = data.child_data().first()?;
    Some(arrow_array::make_array(child.clone()))
}

// Automatic-parallelism thresholds for checksum hashing: skip thread spawns
// for small datasets, and cap automatic fan-out.
const MIN_PARALLEL_HASH_CELLS: u64 = 1_000_000;
const MAX_AUTOMATIC_HASH_THREADS: usize = 8;

fn hash_thread_count(requested: usize, task_count: usize, cells: u64) -> usize {
    if requested == 1 || task_count < 2 {
        return 1;
    }
    if requested == 0 && cells < MIN_PARALLEL_HASH_CELLS {
        return 1;
    }
    let available = thread::available_parallelism().map_or(1, usize::from);
    let threads = if requested == 0 {
        available.min(MAX_AUTOMATIC_HASH_THREADS)
    } else {
        requested.min(available)
    };
    threads.min(task_count).max(1)
}

/// One checksum unit: a column's slice within one batch, or a dictionary
/// column's values array.
enum HashTask {
    Batch { batch: usize, column: usize },
    Dictionary { column: usize },
}

fn run_hash_task(
    dataset: &ArrowWriteDataset,
    row_count: usize,
    task: &HashTask,
) -> Result<Vec<String>, ArrowProfileError> {
    let hashes = match task {
        HashTask::Batch { batch, column } => {
            let row_start = batch * ARROW_ROWS_PER_BATCH;
            let batch_rows = ARROW_ROWS_PER_BATCH.min(row_count - row_start);
            let slice = dataset.columns[*column].array.slice(row_start, batch_rows);
            canonical_array_hashes(slice.as_ref())?
        }
        HashTask::Dictionary { column } => {
            let column = &dataset.columns[*column];
            let values = dictionary_values(&column.array).ok_or_else(|| {
                ArrowProfileError::Invalid(format!(
                    "dictionary column `{}` has no values array",
                    column.name
                ))
            })?;
            canonical_array_hashes(values.as_ref())?
        }
    };
    Ok(hashes.into_iter().map(checksum_to_hex).collect())
}

/// Claim hash tasks from the shared queue. `poll` runs between tasks: the
/// caller's thread checks the interrupt callback, workers only observe the
/// cancel flag the other loops set.
#[allow(clippy::type_complexity)]
fn hash_task_loop(
    dataset: &ArrowWriteDataset,
    row_count: usize,
    tasks: &[HashTask],
    next: &AtomicUsize,
    cancelled: &AtomicBool,
    mut poll: impl FnMut() -> bool,
) -> Result<Vec<(usize, Vec<String>)>, ArrowProfileError> {
    let mut results = Vec::new();
    loop {
        if poll() {
            cancelled.store(true, Ordering::Relaxed);
            return Err(ArrowProfileError::Interrupted);
        }
        if cancelled.load(Ordering::Relaxed) {
            return Ok(results);
        }
        let index = next.fetch_add(1, Ordering::Relaxed);
        let Some(task) = tasks.get(index) else {
            return Ok(results);
        };
        match run_hash_task(dataset, row_count, task) {
            Ok(hashes) => results.push((index, hashes)),
            Err(error) => {
                cancelled.store(true, Ordering::Relaxed);
                return Err(error);
            }
        }
    }
}

/// Every hash unit in write order: all batch slices, then one task per
/// dictionary column.
fn build_hash_tasks(
    batch_count: usize,
    column_count: usize,
    dictionary_columns: &[usize],
) -> Vec<HashTask> {
    let mut tasks = Vec::with_capacity(batch_count * column_count + dictionary_columns.len());
    for batch in 0..batch_count {
        for column in 0..column_count {
            tasks.push(HashTask::Batch { batch, column });
        }
    }
    for &column in dictionary_columns {
        tasks.push(HashTask::Dictionary { column });
    }
    tasks
}

/// Fold completed hash slots (in `build_hash_tasks` order) into the footer
/// document.
fn assemble_checksums(
    slots: Vec<Option<Vec<String>>>,
    batch_count: usize,
    column_count: usize,
    dictionary_columns: &[usize],
) -> Result<ChecksumsDocument, ArrowProfileError> {
    let mut hashes = slots.into_iter().map(|slot| {
        slot.ok_or_else(|| ArrowProfileError::Invalid("a checksum task produced no result".into()))
    });
    let mut checksums = ChecksumsDocument {
        version: DOCUMENT_VERSION,
        algorithm: "xxh64".to_owned(),
        batches: Vec::with_capacity(batch_count),
        dictionaries: BTreeMap::new(),
    };
    for _ in 0..batch_count {
        let mut batch_checksums = BatchChecksums {
            columns: Vec::with_capacity(column_count),
        };
        for _ in 0..column_count {
            batch_checksums.columns.push(hashes.next().unwrap()?);
        }
        checksums.batches.push(batch_checksums);
    }
    for column in dictionary_columns {
        checksums
            .dictionaries
            .insert(column.to_string(), hashes.next().unwrap()?);
    }
    Ok(checksums)
}

/// Folded into every signature payload; a change to the payload definition
/// bumps this so signatures recorded under the old definition mismatch
/// loudly instead of comparing across definitions.
const DATASIG_PAYLOAD_VERSION: &str = "2";

/// Compute an order-sensitive content signature: `rows:columns:digest` where
/// the digest is the xxHash64 of a canonical payload covering the row and
/// column counts, the `dtatools:dataset` document (label, notes, value-label
/// tables), and each column's name, Arrow type, `dtatools:field` document
/// (storage type, format, labels), and canonical per-batch buffer checksums
/// in row order. Unlike Stata's `datasignature`, reordering rows or swapping
/// values within a column changes the signature. The signature is a function
/// of the logical dataset, not its container, so the same data hashed from
/// memory or after a `.dta` or `.arrow` round trip signs identically.
pub fn dataset_signature(
    dataset: &ArrowWriteDataset,
    threads: usize,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<String, ArrowProfileError> {
    let row_count = validated_row_count(dataset)?;

    let column_count = dataset.columns.len();
    let dictionary_columns: Vec<usize> = dataset
        .columns
        .iter()
        .enumerate()
        .filter(|(_, column)| matches!(column.array.data_type(), DataType::Dictionary(_, _)))
        .map(|(index, _)| index)
        .collect();
    let batch_count = if row_count == 0 && !dictionary_columns.is_empty() {
        1
    } else {
        row_count.div_ceil(ARROW_ROWS_PER_BATCH)
    };
    let tasks = build_hash_tasks(batch_count, column_count, &dictionary_columns);
    let cells = (row_count as u64).saturating_mul(column_count as u64);
    let threads = hash_thread_count(threads, tasks.len(), cells);
    let next = AtomicUsize::new(0);
    let cancelled = AtomicBool::new(false);
    let mut completed = Vec::new();
    if threads <= 1 {
        completed.push(hash_task_loop(
            dataset,
            row_count,
            &tasks,
            &next,
            &cancelled,
            &mut *interrupt,
        )?);
    } else {
        // Unlike the save path there is no write pass to overlap, so this
        // thread hashes alongside the workers and stays the only interrupt
        // poller.
        let (own_result, worker_results) = thread::scope(|scope| {
            let handles: Vec<_> = (0..threads - 1)
                .map(|_| {
                    let next = &next;
                    let cancelled = &cancelled;
                    let tasks = &tasks;
                    scope.spawn(move || {
                        hash_task_loop(dataset, row_count, tasks, next, cancelled, || false)
                    })
                })
                .collect();
            let own_result = hash_task_loop(
                dataset,
                row_count,
                &tasks,
                &next,
                &cancelled,
                &mut *interrupt,
            );
            let worker_results: Vec<_> = handles
                .into_iter()
                .map(|handle| {
                    handle.join().unwrap_or_else(|_| {
                        Err(ArrowProfileError::Invalid(
                            "an Arrow checksum worker panicked".to_owned(),
                        ))
                    })
                })
                .collect();
            (own_result, worker_results)
        });
        completed.push(own_result?);
        for result in worker_results {
            completed.push(result?);
        }
    }
    let mut slots: Vec<Option<Vec<String>>> = tasks.iter().map(|_| None).collect();
    for hashes in completed {
        for (index, hash) in hashes {
            slots[index] = Some(hash);
        }
    }
    let checksums = assemble_checksums(slots, batch_count, column_count, &dictionary_columns)?;

    signature_from_parts(
        row_count as u64,
        dataset.columns.iter().map(|column| {
            (
                column.name.as_str(),
                column.array.data_type(),
                column.field.as_ref(),
            )
        }),
        column_count,
        &dataset.dataset,
        &checksums,
    )
}

/// The canonical signature payload and final digest. Shared by
/// [`dataset_signature`], which recomputes the checksums from in-memory
/// arrays, and the read side's stored-footer derivation, so both produce
/// identical signatures for identical logical datasets.
pub(crate) fn signature_from_parts<'a>(
    row_count: u64,
    columns: impl Iterator<Item = (&'a str, &'a DataType, Option<&'a ArrowFieldDocument>)>,
    column_count: usize,
    dataset: &DatasetDocument,
    checksums: &ChecksumsDocument,
) -> Result<String, ArrowProfileError> {
    let mut payload = SignatureHasher(twox_hash::XxHash64::with_seed(0));
    write!(
        payload,
        "dtatools-datasig:{DATASIG_PAYLOAD_VERSION}\nrows:{row_count}\ncolumns:{column_count}\ndataset:"
    )
    .map_err(signature_io_error)?;
    serialize_json_into(&mut payload, dataset)?;
    for (name, data_type, field) in columns {
        payload.write_all(b"\nname:").map_err(signature_io_error)?;
        serialize_json_into(&mut payload, &name)?;
        write!(payload, "\ntype:{data_type}\nfield:").map_err(signature_io_error)?;
        if let Some(document) = field {
            serialize_json_into(&mut payload, document)?;
        }
    }
    payload
        .write_all(b"\nchecksums:")
        .map_err(signature_io_error)?;
    serialize_json_into(&mut payload, checksums)?;
    let digest = payload.0.finish();
    Ok(format!("{row_count}:{column_count}:{digest:016x}"))
}

struct SignatureHasher(twox_hash::XxHash64);

impl Write for SignatureHasher {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.write(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn signature_io_error(error: std::io::Error) -> ArrowProfileError {
    ArrowProfileError::Invalid(error.to_string())
}

fn serialize_json_into<T: serde::Serialize>(
    writer: &mut impl Write,
    value: &T,
) -> Result<(), ArrowProfileError> {
    serde_json::to_writer(writer, value)
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))
}

fn footer_too_large() -> ArrowProfileError {
    ArrowProfileError::Invalid(
        "Arrow footer metadata exceeds the 64 MiB reader safety limit".to_owned(),
    )
}

struct BoundedMetadataJson {
    value: Vec<u8>,
    exceeded: bool,
}

impl BoundedMetadataJson {
    fn new() -> Self {
        Self {
            value: Vec::new(),
            exceeded: false,
        }
    }

    fn push(&mut self, value: &str) -> Result<(), ArrowProfileError> {
        self.push_bytes(value.as_bytes())
    }

    fn push_bytes(&mut self, value: &[u8]) -> Result<(), ArrowProfileError> {
        let Some(length) = self.value.len().checked_add(value.len()) else {
            self.exceeded = true;
            return Err(footer_too_large());
        };
        if length > MAX_IPC_METADATA_BYTES {
            self.exceeded = true;
            return Err(footer_too_large());
        }
        self.value.try_reserve(value.len()).map_err(|_| {
            ArrowProfileError::Invalid("could not allocate Arrow footer metadata".to_owned())
        })?;
        self.value.extend_from_slice(value);
        Ok(())
    }

    fn into_string(self) -> Result<String, ArrowProfileError> {
        String::from_utf8(self.value).map_err(|_| {
            ArrowProfileError::Invalid("JSON serializer produced invalid UTF-8".into())
        })
    }
}

impl Write for BoundedMetadataJson {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.push_bytes(bytes)
            .map_err(|error| std::io::Error::other(error.to_string()))?;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn serialize_footer_json<T: serde::Serialize>(value: &T) -> Result<String, ArrowProfileError> {
    let mut output = BoundedMetadataJson::new();
    if let Err(error) = serde_json::to_writer(&mut output, value) {
        return if output.exceeded {
            Err(footer_too_large())
        } else {
            Err(ArrowProfileError::Invalid(error.to_string()))
        };
    }
    output.into_string()
}

fn dictionary_columns(dataset: &ArrowWriteDataset) -> Vec<usize> {
    dataset
        .columns
        .iter()
        .enumerate()
        .filter(|(_, column)| matches!(column.array.data_type(), DataType::Dictionary(_, _)))
        .map(|(index, _)| index)
        .collect()
}

fn record_batch_count(row_count: usize, dictionary_columns: &[usize]) -> usize {
    if row_count == 0 && !dictionary_columns.is_empty() {
        1
    } else {
        row_count.div_ceil(ARROW_ROWS_PER_BATCH)
    }
}

fn append_placeholder_hashes(
    output: &mut BoundedMetadataJson,
    count: usize,
) -> Result<(), ArrowProfileError> {
    output.push("[")?;
    for index in 0..count {
        if index != 0 {
            output.push(",")?;
        }
        output.push("\"0000000000000000\"")?;
    }
    output.push("]")
}

fn placeholder_checksums_json(
    dataset: &ArrowWriteDataset,
    batch_count: usize,
    dictionary_columns: &[usize],
) -> Result<String, ArrowProfileError> {
    let column_hash_counts: Vec<usize> = dataset
        .columns
        .iter()
        .map(|column| {
            let empty = column.array.slice(0, 0);
            canonical_array_hashes(empty.as_ref()).map(|hashes| hashes.len())
        })
        .collect::<Result<_, _>>()?;
    let dictionary_hash_counts: Vec<(usize, usize)> = dictionary_columns
        .iter()
        .map(|&column| {
            let values = dictionary_values(&dataset.columns[column].array).ok_or_else(|| {
                ArrowProfileError::Invalid(format!(
                    "dictionary column `{}` has no values array",
                    dataset.columns[column].name
                ))
            })?;
            let empty = values.slice(0, 0);
            Ok((column, canonical_array_hashes(empty.as_ref())?.len()))
        })
        .collect::<Result<_, ArrowProfileError>>()?;

    let mut output = BoundedMetadataJson::new();
    output.push("{\"version\":")?;
    output.push(&DOCUMENT_VERSION.to_string())?;
    output.push(",\"algorithm\":\"xxh64\",\"batches\":[")?;
    for batch in 0..batch_count {
        if batch != 0 {
            output.push(",")?;
        }
        output.push("{\"columns\":[")?;
        for (column, &hash_count) in column_hash_counts.iter().enumerate() {
            if column != 0 {
                output.push(",")?;
            }
            append_placeholder_hashes(&mut output, hash_count)?;
        }
        output.push("]}")?;
    }
    output.push("]")?;
    if !dictionary_hash_counts.is_empty() {
        output.push(",\"dictionaries\":{")?;
        for (entry, &(column, hash_count)) in dictionary_hash_counts.iter().enumerate() {
            if entry != 0 {
                output.push(",")?;
            }
            output.push("\"")?;
            output.push(&column.to_string())?;
            output.push("\":")?;
            append_placeholder_hashes(&mut output, hash_count)?;
        }
        output.push("}")?;
    }
    output.push("}")?;
    output.into_string()
}

fn validate_footer_size(
    schema: &Schema,
    record_batch_count: usize,
    dictionary_count: usize,
    checksum_json: Option<String>,
) -> Result<(), ArrowProfileError> {
    let block_bytes = record_batch_count
        .checked_add(dictionary_count)
        .and_then(|count| count.checked_mul(size_of::<Block>()))
        .ok_or_else(footer_too_large)?;
    if block_bytes > MAX_IPC_METADATA_BYTES {
        return Err(footer_too_large());
    }
    let mut builder = FlatBufferBuilder::new();
    let dictionary_blocks = vec![Block::new(0, 0, 0); dictionary_count];
    let record_blocks = vec![Block::new(0, 0, 0); record_batch_count];
    let dictionaries = builder.create_vector(&dictionary_blocks);
    let record_batches = builder.create_vector(&record_blocks);
    let mut tracker = DictionaryTracker::new(true);
    let schema = IpcSchemaEncoder::new()
        .with_dictionary_tracker(&mut tracker)
        .schema_to_fb_offset(&mut builder, schema);
    let custom_metadata =
        checksum_json.map(|json| HashMap::from([(ARROW_CHECKSUMS_KEY.to_owned(), json)]));
    let custom_metadata = custom_metadata
        .as_ref()
        .map(|metadata| metadata_to_fb(&mut builder, metadata));
    let footer = {
        let mut footer = FooterBuilder::new(&mut builder);
        footer.add_version(MetadataVersion::V5);
        footer.add_schema(schema);
        footer.add_dictionaries(dictionaries);
        footer.add_recordBatches(record_batches);
        if let Some(custom_metadata) = custom_metadata {
            footer.add_custom_metadata(custom_metadata);
        }
        footer.finish()
    };
    builder.finish(footer, None);
    if builder.finished_data().len() > MAX_IPC_METADATA_BYTES {
        return Err(footer_too_large());
    }
    Ok(())
}

fn validate_fields_with(
    dataset: &ArrowWriteDataset,
    mut accept: impl FnMut(Field, Option<&ArrowFieldDocument>) -> Result<(), ArrowProfileError>,
) -> Result<usize, ArrowProfileError> {
    validate_dataset_document(ARROW_PROFILE_VERSION, &dataset.dataset)?;
    let row_count = dataset
        .columns
        .first()
        .map_or(0, |column| column.array.len());
    for column in &dataset.columns {
        if column.array.len() != row_count {
            return Err(ArrowProfileError::Invalid(format!(
                "column `{}` has {} rows; expected {row_count}",
                column.name,
                column.array.len()
            )));
        }
        let data_type = column.array.data_type();
        if !supported_write_type(data_type) {
            return Err(ArrowProfileError::UnsupportedColumn {
                column: column.name.clone(),
                data_type: data_type.to_string(),
            });
        }
        // Raw Stata missing storage never uses Arrow nulls, so profiled
        // columns are declared non-nullable.
        let nullable = column
            .field
            .as_ref()
            .is_none_or(|document| document.missing.is_none());
        if !nullable && column.array.null_count() > 0 {
            return Err(ArrowProfileError::Invalid(format!(
                "profiled column `{}` is non-nullable but contains {} nulls",
                column.name,
                column.array.null_count()
            )));
        }
        let field = Field::new(column.name.clone(), data_type.clone(), nullable);
        if let Some(document) = &column.field {
            validate_field_document(ARROW_PROFILE_VERSION, &field, document)?;
            validate_value_label_reference(
                ARROW_PROFILE_VERSION,
                &field,
                document,
                &dataset.dataset,
            )?;
        }
        accept(field, column.field.as_ref())?;
    }
    Ok(row_count)
}

fn validated_row_count(dataset: &ArrowWriteDataset) -> Result<usize, ArrowProfileError> {
    validate_fields_with(dataset, |_field, _document| Ok(()))
}

fn validated_fields(
    dataset: &ArrowWriteDataset,
) -> Result<(usize, Vec<Field>, usize), ArrowProfileError> {
    let mut fields = Vec::with_capacity(dataset.columns.len());
    let mut metadata_bytes = 0_usize;
    let row_count = validate_fields_with(dataset, |mut field, document| {
        if let Some(document) = document {
            let json = serialize_footer_json(document)?;
            metadata_bytes = metadata_bytes
                .checked_add(json.len())
                .filter(|&bytes| bytes <= MAX_IPC_METADATA_BYTES)
                .ok_or_else(footer_too_large)?;
            field.set_metadata(HashMap::from([(ARROW_FIELD_KEY.to_owned(), json)]));
        }
        fields.push(field);
        Ok(())
    })?;
    Ok((row_count, fields, metadata_bytes))
}

struct ValidatedArrowWrite {
    row_count: usize,
    schema: Arc<Schema>,
}

fn validated_arrow_write(
    dataset: &ArrowWriteDataset,
    checksums: bool,
) -> Result<ValidatedArrowWrite, ArrowProfileError> {
    let (row_count, fields, field_metadata_bytes) = validated_fields(dataset)?;
    let dataset_json = serialize_footer_json(&dataset.dataset)?;
    field_metadata_bytes
        .checked_add(dataset_json.len())
        .filter(|&bytes| bytes <= MAX_IPC_METADATA_BYTES)
        .ok_or_else(footer_too_large)?;

    let schema = Arc::new(Schema::new(fields).with_metadata(HashMap::from([
        (
            ARROW_PROFILE_VERSION_KEY.to_owned(),
            ARROW_PROFILE_VERSION.to_owned(),
        ),
        (ARROW_DATASET_KEY.to_owned(), dataset_json),
    ])));
    let dictionary_columns = dictionary_columns(dataset);
    let record_batch_count = record_batch_count(row_count, &dictionary_columns);
    let checksum_json = checksums
        .then(|| placeholder_checksums_json(dataset, record_batch_count, &dictionary_columns))
        .transpose()?;
    validate_footer_size(
        &schema,
        record_batch_count,
        dictionary_columns.len(),
        checksum_json,
    )?;
    Ok(ValidatedArrowWrite { row_count, schema })
}

/// Save a dataset as a dtatools Arrow profile file at `path`, replacing any
/// existing file. Callers that need atomic replacement write to a sibling
/// temporary path and rename, as the R adapter does. Validation rejects a
/// prospective footer above the reader's 64 MiB metadata limit before the
/// destination is opened.
pub fn save_arrow_file(
    path: impl AsRef<Path>,
    dataset: &ArrowWriteDataset,
    compression: ArrowCompression,
    threads: usize,
    checksums: bool,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let validated = validated_arrow_write(dataset, checksums)?;
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);
    save_arrow_file_to_validated(
        &mut writer,
        dataset,
        validated,
        compression,
        threads,
        checksums,
        interrupt,
    )?;
    writer.flush()?;
    writer
        .into_inner()
        .map_err(|error| ArrowProfileError::Io(error.into_error()))?
        .sync_all()?;
    Ok(())
}

/// Save a dataset as a dtatools Arrow profile file into `output`. `threads`
/// bounds checksum hashing: `0` selects a count automatically, `1` forces
/// serial hashing. `checksums: false` omits the footer checksums document
/// entirely; such files read back only with verification off.
/// Validation rejects a prospective footer above the reader's 64 MiB metadata
/// limit before writing to `output`.
pub fn save_arrow_file_to<W: Write>(
    output: W,
    dataset: &ArrowWriteDataset,
    compression: ArrowCompression,
    threads: usize,
    checksums: bool,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let validated = validated_arrow_write(dataset, checksums)?;
    save_arrow_file_to_validated(
        output,
        dataset,
        validated,
        compression,
        threads,
        checksums,
        interrupt,
    )
}

fn save_arrow_file_to_validated<W: Write>(
    output: W,
    dataset: &ArrowWriteDataset,
    validated: ValidatedArrowWrite,
    compression: ArrowCompression,
    threads: usize,
    checksums: bool,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let ValidatedArrowWrite { row_count, schema } = validated;

    let options = IpcWriteOptions::default()
        .try_with_compression(compression.compression_type())
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
    let mut writer = FileWriter::try_new_with_options(output, &schema, options)
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;

    let checksum_document = if !checksums {
        write_batches(&mut writer, &schema, dataset, row_count, interrupt)?;
        None
    } else {
        let column_count = dataset.columns.len();
        let dictionary_columns = dictionary_columns(dataset);
        let batch_count = record_batch_count(row_count, &dictionary_columns);
        let tasks = build_hash_tasks(batch_count, column_count, &dictionary_columns);
        let cells = (row_count as u64).saturating_mul(column_count as u64);
        let threads = hash_thread_count(threads, tasks.len(), cells);
        let mut slots: Vec<Option<Vec<String>>> = tasks.iter().map(|_| None).collect();
        if threads <= 1 {
            for (index, task) in tasks.iter().enumerate() {
                if interrupt() {
                    return Err(ArrowProfileError::Interrupted);
                }
                slots[index] = Some(run_hash_task(dataset, row_count, task)?);
            }
            write_batches(&mut writer, &schema, dataset, row_count, interrupt)?;
        } else {
            // Hash on workers while this thread streams the batches to the
            // output, so the checksum pass hides behind the write pass. This
            // thread stays the only interrupt poller; a write error cancels
            // the workers.
            let next = AtomicUsize::new(0);
            let cancelled = AtomicBool::new(false);
            let (write_result, worker_results) = thread::scope(|scope| {
                let handles: Vec<_> = (0..threads)
                    .map(|_| {
                        let next = &next;
                        let cancelled = &cancelled;
                        let tasks = &tasks;
                        scope.spawn(move || {
                            hash_task_loop(dataset, row_count, tasks, next, cancelled, || false)
                        })
                    })
                    .collect();
                let write_result =
                    write_batches(&mut writer, &schema, dataset, row_count, interrupt);
                if write_result.is_err() {
                    cancelled.store(true, Ordering::Relaxed);
                }
                let worker_results: Vec<_> = handles
                    .into_iter()
                    .map(|handle| {
                        handle.join().unwrap_or_else(|_| {
                            Err(ArrowProfileError::Invalid(
                                "an Arrow checksum worker panicked".to_owned(),
                            ))
                        })
                    })
                    .collect();
                (write_result, worker_results)
            });
            // Surface the write error (interrupts included) first, then any
            // worker error.
            write_result?;
            for result in worker_results {
                for (index, hashes) in result? {
                    slots[index] = Some(hashes);
                }
            }
        }
        Some(assemble_checksums(
            slots,
            batch_count,
            column_count,
            &dictionary_columns,
        )?)
    };

    if let Some(checksums) = checksum_document {
        writer.write_metadata(
            ARROW_CHECKSUMS_KEY,
            serde_json::to_string(&checksums)
                .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?,
        );
    }
    writer
        .finish()
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
    Ok(())
}

/// Stream every record batch through the IPC writer, polling for interrupts
/// between batches.
fn write_batches<W: Write>(
    writer: &mut FileWriter<W>,
    schema: &Arc<Schema>,
    dataset: &ArrowWriteDataset,
    row_count: usize,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    if row_count == 0
        && dataset
            .columns
            .iter()
            .any(|column| matches!(column.array.data_type(), DataType::Dictionary(_, _)))
    {
        if interrupt() {
            return Err(ArrowProfileError::Interrupted);
        }
        let batch_columns = dataset
            .columns
            .iter()
            .map(|column| column.array.slice(0, 0))
            .collect();
        let batch = RecordBatch::try_new(schema.clone(), batch_columns)
            .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
        writer
            .write(&batch)
            .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
        return Ok(());
    }
    let mut row_start = 0_usize;
    while row_start < row_count {
        if interrupt() {
            return Err(ArrowProfileError::Interrupted);
        }
        let batch_rows = ARROW_ROWS_PER_BATCH.min(row_count - row_start);
        let mut batch_columns = Vec::with_capacity(dataset.columns.len());
        for column in &dataset.columns {
            batch_columns.push(column.array.slice(row_start, batch_rows));
        }
        let batch = RecordBatch::try_new(schema.clone(), batch_columns)
            .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
        writer
            .write(&batch)
            .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
        row_start += batch_rows;
    }
    Ok(())
}
