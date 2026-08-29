//! The dtatools Arrow profile writer: bounded record batches through the
//! official `arrow-ipc` `FileWriter`, with `dtatools:*` schema and field
//! metadata and per-buffer checksums in the footer.

use std::collections::{BTreeMap, HashMap};
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;

use arrow_array::{Array, ArrayRef, RecordBatch};
use arrow_ipc::writer::{FileWriter, IpcWriteOptions};
use arrow_ipc::CompressionType;
use arrow_schema::{DataType, Field, Schema};

use super::checksum::{canonical_array_hashes, xxh64};
use super::profile::{
    checksum_to_hex, ArrowFieldDocument, BatchChecksums, ChecksumsDocument, DatasetDocument,
    ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY, ARROW_FIELD_KEY, ARROW_PROFILE_VERSION,
    ARROW_PROFILE_VERSION_KEY, DOCUMENT_VERSION,
};
use super::ArrowProfileError;

/// Rows per record batch. Provisional until pinned by benchmark; a multiple
/// of 64 so sliced validity and boolean bitmaps stay byte-aligned.
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
    rows_per_batch: usize,
    task: &HashTask,
) -> Result<Vec<String>, ArrowProfileError> {
    let hashes = match task {
        HashTask::Batch { batch, column } => {
            let row_start = batch * rows_per_batch;
            let batch_rows = rows_per_batch.min(row_count - row_start);
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
    rows_per_batch: usize,
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
        match run_hash_task(dataset, row_count, rows_per_batch, task) {
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
const DATASIG_PAYLOAD_VERSION: &str = "1";

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
    rows_per_batch: usize,
    threads: usize,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<String, ArrowProfileError> {
    if !rows_per_batch.is_multiple_of(64) || rows_per_batch == 0 {
        return Err(ArrowProfileError::Invalid(
            "rows per record batch must be a positive multiple of 64".to_owned(),
        ));
    }
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
    }

    let column_count = dataset.columns.len();
    let batch_count = row_count.div_ceil(rows_per_batch);
    let dictionary_columns: Vec<usize> = dataset
        .columns
        .iter()
        .enumerate()
        .filter(|(_, column)| matches!(column.array.data_type(), DataType::Dictionary(_, _)))
        .map(|(index, _)| index)
        .collect();
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
            rows_per_batch,
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
                        hash_task_loop(
                            dataset,
                            row_count,
                            rows_per_batch,
                            tasks,
                            next,
                            cancelled,
                            || false,
                        )
                    })
                })
                .collect();
            let own_result = hash_task_loop(
                dataset,
                row_count,
                rows_per_batch,
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
    let mut payload = String::new();
    payload.push_str("dtatools-datasig:");
    payload.push_str(DATASIG_PAYLOAD_VERSION);
    payload.push_str(&format!(
        "\nrows:{row_count}\ncolumns:{column_count}\ndataset:"
    ));
    payload.push_str(&serialize_json(&dataset)?);
    for (name, data_type, field) in columns {
        payload.push_str("\nname:");
        payload.push_str(&serialize_json(&name)?);
        payload.push_str(&format!("\ntype:{data_type}\nfield:"));
        if let Some(document) = field {
            payload.push_str(&serialize_json(document)?);
        }
    }
    payload.push_str("\nchecksums:");
    payload.push_str(&serialize_json(checksums)?);
    let digest = xxh64(payload.as_bytes());
    Ok(format!("{row_count}:{column_count}:{digest:016x}"))
}

fn serialize_json<T: serde::Serialize>(value: &T) -> Result<String, ArrowProfileError> {
    serde_json::to_string(value).map_err(|error| ArrowProfileError::Invalid(error.to_string()))
}

/// Save a dataset as a dtatools Arrow profile file at `path`, replacing any
/// existing file. Callers that need atomic replacement write to a sibling
/// temporary path and rename, as the R adapter does.
pub fn save_arrow_file(
    path: impl AsRef<Path>,
    dataset: &ArrowWriteDataset,
    compression: ArrowCompression,
    rows_per_batch: usize,
    threads: usize,
    checksums: bool,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);
    save_arrow_file_to(
        &mut writer,
        dataset,
        compression,
        rows_per_batch,
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
pub fn save_arrow_file_to<W: Write>(
    output: W,
    dataset: &ArrowWriteDataset,
    compression: ArrowCompression,
    rows_per_batch: usize,
    threads: usize,
    checksums: bool,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    if !rows_per_batch.is_multiple_of(64) || rows_per_batch == 0 {
        return Err(ArrowProfileError::Invalid(
            "rows per record batch must be a positive multiple of 64".to_owned(),
        ));
    }
    let row_count = dataset
        .columns
        .first()
        .map_or(0, |column| column.array.len());

    let mut fields = Vec::with_capacity(dataset.columns.len());
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
        let mut field = Field::new(column.name.clone(), data_type.clone(), nullable);
        if let Some(document) = &column.field {
            let json = serde_json::to_string(document)
                .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
            field.set_metadata(HashMap::from([(ARROW_FIELD_KEY.to_owned(), json)]));
        }
        fields.push(field);
    }

    let mut schema_metadata = HashMap::new();
    schema_metadata.insert(
        ARROW_PROFILE_VERSION_KEY.to_owned(),
        ARROW_PROFILE_VERSION.to_owned(),
    );
    schema_metadata.insert(
        ARROW_DATASET_KEY.to_owned(),
        serde_json::to_string(&dataset.dataset)
            .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?,
    );
    let schema = Arc::new(Schema::new(fields).with_metadata(schema_metadata));

    let options = IpcWriteOptions::default()
        .try_with_compression(compression.compression_type())
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
    let mut writer = FileWriter::try_new_with_options(output, &schema, options)
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;

    let checksum_document = if !checksums {
        write_batches(
            &mut writer,
            &schema,
            dataset,
            row_count,
            rows_per_batch,
            interrupt,
        )?;
        None
    } else {
        let column_count = dataset.columns.len();
        let batch_count = row_count.div_ceil(rows_per_batch);
        let dictionary_columns: Vec<usize> = dataset
            .columns
            .iter()
            .enumerate()
            .filter(|(_, column)| matches!(column.array.data_type(), DataType::Dictionary(_, _)))
            .map(|(index, _)| index)
            .collect();
        let tasks = build_hash_tasks(batch_count, column_count, &dictionary_columns);
        let cells = (row_count as u64).saturating_mul(column_count as u64);
        let threads = hash_thread_count(threads, tasks.len(), cells);
        let mut slots: Vec<Option<Vec<String>>> = tasks.iter().map(|_| None).collect();
        if threads <= 1 {
            for (index, task) in tasks.iter().enumerate() {
                if interrupt() {
                    return Err(ArrowProfileError::Interrupted);
                }
                slots[index] = Some(run_hash_task(dataset, row_count, rows_per_batch, task)?);
            }
            write_batches(
                &mut writer,
                &schema,
                dataset,
                row_count,
                rows_per_batch,
                interrupt,
            )?;
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
                            hash_task_loop(
                                dataset,
                                row_count,
                                rows_per_batch,
                                tasks,
                                next,
                                cancelled,
                                || false,
                            )
                        })
                    })
                    .collect();
                let write_result = write_batches(
                    &mut writer,
                    &schema,
                    dataset,
                    row_count,
                    rows_per_batch,
                    interrupt,
                );
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
    rows_per_batch: usize,
    interrupt: &mut dyn FnMut() -> bool,
) -> Result<(), ArrowProfileError> {
    let mut row_start = 0_usize;
    while row_start < row_count {
        if interrupt() {
            return Err(ArrowProfileError::Interrupted);
        }
        let batch_rows = rows_per_batch.min(row_count - row_start);
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
