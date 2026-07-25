use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{ErrorKind, Read, Seek, SeekFrom};
use std::path::Path;

use encoding_rs::{CoderResult, Encoding, UTF_8, WINDOWS_1252};

use crate::endian::{read_i16, read_i32, read_i8, read_u16, read_u32, read_u64};
use crate::legacy::{
    format_width, legacy_fixed_metadata_end, legacy_type, HEADER_SIZE, SORTLIST_WIDTH,
    VALUE_LABEL_NAME_WIDTH, VARIABLE_LABEL_WIDTH, VARNAME_WIDTH,
};
use crate::metadata::{field_widths, resolve_type};
use crate::text::{decode_utf8, decode_windows_1252, field_bytes};
use crate::{
    classify_byte_missing, classify_double_missing_bits, classify_float_missing_bits,
    classify_int_missing, classify_long_missing, ByteOrder, Column, ColumnValues, DtaData,
    DtaError, DtaMetadata, DtaType, FormatVersion, ReadOptions, SectionOffsets, ValueLabelEntry,
    ValueLabelTable, VariableInfo,
};

const DEFAULT_MAX_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const MIN_MAX_BUFFER_BYTES: usize = 1024;
const MODERN_SIGNATURE: &[u8] = b"<stata_dta><header><release>";

/// Configuration for seekable file-backed reads.
///
/// `max_buffer_bytes` bounds each temporary raw-byte staging allocation and
/// every read issued to the underlying reader. It must be at least 1024 bytes.
/// The bound does not cap caller-visible results or the derived indexes and
/// caches needed to build selected results.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileOptions {
    pub max_buffer_bytes: usize,
}

impl Default for FileOptions {
    fn default() -> Self {
        Self {
            max_buffer_bytes: DEFAULT_MAX_BUFFER_BYTES,
        }
    }
}

#[derive(Debug)]
struct Scratch {
    limit: usize,
    peak: usize,
}

struct FileModernHeaderMap {
    format_version: FormatVersion,
    byte_order: ByteOrder,
    nvar: u32,
    nobs: u64,
    dataset_label: String,
    section_offsets: SectionOffsets,
}

impl Scratch {
    fn new(limit: usize) -> Self {
        Self { limit, peak: 0 }
    }

    fn record(&mut self, length: usize) -> Result<(), DtaError> {
        if length > self.limit {
            return Err(DtaError::ArithmeticOverflow(
                "file scratch buffer exceeds configured limit",
            ));
        }
        self.peak = self.peak.max(length);
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct FileGsoKey {
    variable: u32,
    observation: u64,
}

#[derive(Debug, Clone, Copy)]
struct FileGsoEntry {
    content_offset: u64,
    content_length: usize,
    gso_type: u8,
}

enum ColumnBuilder {
    Byte {
        index: u32,
        values: Vec<i8>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Int {
        index: u32,
        values: Vec<i16>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Long {
        index: u32,
        values: Vec<i32>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Float {
        index: u32,
        values: Vec<f32>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    Double {
        index: u32,
        values: Vec<f64>,
        missing_tags: Vec<Option<crate::MissingTag>>,
    },
    FixedString {
        index: u32,
        values: Vec<String>,
    },
    StrL {
        index: u32,
        pointers: Vec<Option<FileGsoKey>>,
        values: Vec<String>,
    },
}

impl ColumnBuilder {
    fn new(index: u32, dta_type: &DtaType, capacity: usize) -> Self {
        match dta_type {
            DtaType::Byte => Self::Byte {
                index,
                values: Vec::with_capacity(capacity),
                missing_tags: Vec::with_capacity(capacity),
            },
            DtaType::Int => Self::Int {
                index,
                values: Vec::with_capacity(capacity),
                missing_tags: Vec::with_capacity(capacity),
            },
            DtaType::Long => Self::Long {
                index,
                values: Vec::with_capacity(capacity),
                missing_tags: Vec::with_capacity(capacity),
            },
            DtaType::Float => Self::Float {
                index,
                values: Vec::with_capacity(capacity),
                missing_tags: Vec::with_capacity(capacity),
            },
            DtaType::Double => Self::Double {
                index,
                values: Vec::with_capacity(capacity),
                missing_tags: Vec::with_capacity(capacity),
            },
            DtaType::FixedString(_) => Self::FixedString {
                index,
                values: Vec::with_capacity(capacity),
            },
            DtaType::StrL => Self::StrL {
                index,
                pointers: Vec::with_capacity(capacity),
                values: Vec::with_capacity(capacity),
            },
        }
    }

    fn finish(self) -> Column {
        match self {
            Self::Byte {
                index,
                values,
                missing_tags,
            } => Column {
                variable_index: index,
                values: ColumnValues::Byte {
                    values,
                    missing_tags,
                },
            },
            Self::Int {
                index,
                values,
                missing_tags,
            } => Column {
                variable_index: index,
                values: ColumnValues::Int {
                    values,
                    missing_tags,
                },
            },
            Self::Long {
                index,
                values,
                missing_tags,
            } => Column {
                variable_index: index,
                values: ColumnValues::Long {
                    values,
                    missing_tags,
                },
            },
            Self::Float {
                index,
                values,
                missing_tags,
            } => Column {
                variable_index: index,
                values: ColumnValues::Float {
                    values,
                    missing_tags,
                },
            },
            Self::Double {
                index,
                values,
                missing_tags,
            } => Column {
                variable_index: index,
                values: ColumnValues::Double {
                    values,
                    missing_tags,
                },
            },
            Self::FixedString { index, values } => Column {
                variable_index: index,
                values: ColumnValues::FixedString { values },
            },
            Self::StrL { index, values, .. } => Column {
                variable_index: index,
                values: ColumnValues::StrL { values },
            },
        }
    }
}

/// A synchronous, bounded-buffer `.dta` reader over any seekable source.
///
/// Construction reads only metadata. Observation data, GSO payloads, and
/// value-label tables remain on the source until requested.
pub struct DtaFile<R: Read + Seek> {
    reader: R,
    metadata: DtaMetadata,
    file_length: u64,
    scratch: Scratch,
    value_label_tables: Option<Vec<ValueLabelTable>>,
}

impl DtaFile<File> {
    /// Open a path and retain the file handle for subsequent projected reads.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, DtaError> {
        let file = File::open(path).map_err(|error| DtaError::Io {
            context: "opening file",
            offset: 0,
            kind: error.kind(),
        })?;
        Self::from_reader(file)
    }
}

impl<R: Read + Seek> DtaFile<R> {
    /// Construct a file-backed reader with the default 8 MiB scratch bound.
    pub fn from_reader(reader: R) -> Result<Self, DtaError> {
        Self::from_reader_with_options(reader, FileOptions::default())
    }

    /// Construct a file-backed reader with an explicit scratch-read bound.
    pub fn from_reader_with_options(mut reader: R, options: FileOptions) -> Result<Self, DtaError> {
        if options.max_buffer_bytes < MIN_MAX_BUFFER_BYTES {
            return Err(DtaError::InvalidBufferSize);
        }
        let mut scratch = Scratch::new(options.max_buffer_bytes);
        let file_length = reader
            .seek(SeekFrom::End(0))
            .map_err(|error| DtaError::Io {
                context: "determining file length",
                offset: 0,
                kind: error.kind(),
            })?;
        if file_length == 0 {
            return Err(DtaError::InvalidSignature);
        }
        let first = read_exact_at(&mut reader, 0, 1, &mut scratch, "reading signature")?;
        let metadata = if matches!(first[0], 113..=115) {
            read_legacy_metadata(&mut reader, file_length, &mut scratch)?
        } else {
            let signature_length = MODERN_SIGNATURE.len();
            if file_length < signature_length as u64
                || read_exact_at(
                    &mut reader,
                    0,
                    signature_length,
                    &mut scratch,
                    "reading signature",
                )? != MODERN_SIGNATURE
            {
                return Err(DtaError::InvalidSignature);
            }
            read_modern_metadata(&mut reader, file_length, &mut scratch)?
        };
        if metadata.section_offsets.end_of_file != file_length {
            return Err(DtaError::MapOffsetMismatch {
                section: "file length",
                expected: metadata.section_offsets.end_of_file,
                actual: file_length,
            });
        }
        Ok(Self {
            reader,
            metadata,
            file_length,
            scratch,
            value_label_tables: None,
        })
    }

    /// Parsed dataset and variable metadata.
    pub fn metadata(&self) -> &DtaMetadata {
        &self.metadata
    }

    /// Largest temporary raw-byte staging allocation used so far. This
    /// excludes caller-visible results and derived indexes and caches.
    pub fn max_scratch_bytes_used(&self) -> usize {
        self.scratch.peak
    }

    /// Load and cache value-label tables without reading observation data.
    pub fn value_label_tables(&mut self) -> Result<&[ValueLabelTable], DtaError> {
        let mut never_cancel = || false;
        self.ensure_value_labels(&mut never_cancel)?;
        Ok(self
            .value_label_tables
            .as_deref()
            .expect("value-label cache was initialized"))
    }

    /// Read all rows and columns.
    pub fn read(&mut self) -> Result<DtaData, DtaError> {
        self.read_with_options(&ReadOptions::default())
    }

    /// Read a projected row window and column set.
    pub fn read_with_options(&mut self, options: &ReadOptions) -> Result<DtaData, DtaError> {
        self.read_with_interrupt(options, || false)
    }

    /// Read with cooperative interruption. Returning `true` from the callback
    /// aborts with [`DtaError::Cancelled`] and never exposes partial data.
    pub fn read_with_interrupt<F>(
        &mut self,
        options: &ReadOptions,
        mut should_interrupt: F,
    ) -> Result<DtaData, DtaError>
    where
        F: FnMut() -> bool,
    {
        check_cancel(&mut should_interrupt)?;
        validate_layout(
            &mut self.reader,
            &self.metadata,
            self.file_length,
            &mut self.scratch,
        )?;
        let indices = resolve_columns(&self.metadata, options)?;
        let (row_start, row_count) = row_window(&self.metadata, options);
        let capacity = usize::try_from(row_count)
            .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
        let mut builders = indices
            .iter()
            .map(|index| {
                let variable = &self.metadata.variables[*index as usize];
                ColumnBuilder::new(*index, &variable.dta_type, capacity)
            })
            .collect::<Vec<_>>();
        let payload_start = if self.metadata.format_version.is_modern() {
            checked_add_u64(self.metadata.section_offsets.data, 6, "data payload offset")?
        } else {
            self.metadata.section_offsets.data
        };

        if !builders.is_empty()
            && self.metadata.obs_length > 0
            && self.metadata.obs_length <= self.scratch.limit as u64
        {
            let obs_length = usize::try_from(self.metadata.obs_length)
                .map_err(|_| DtaError::ArithmeticOverflow("observation length"))?;
            let rows_per_chunk = self.scratch.limit / obs_length;
            let rows_per_chunk = u64::try_from(rows_per_chunk)
                .map_err(|_| DtaError::ArithmeticOverflow("rows per chunk"))?;
            let mut row = 0_u64;
            while row < row_count {
                check_cancel(&mut should_interrupt)?;
                let chunk_rows = (row_count - row).min(rows_per_chunk);
                let chunk_rows_usize = usize::try_from(chunk_rows)
                    .map_err(|_| DtaError::ArithmeticOverflow("chunk row count"))?;
                let chunk_length = obs_length
                    .checked_mul(chunk_rows_usize)
                    .ok_or(DtaError::ArithmeticOverflow("observation chunk length"))?;
                let source_row = row_start
                    .checked_add(row)
                    .ok_or(DtaError::ArithmeticOverflow("source row"))?;
                let chunk_offset = payload_start
                    .checked_add(
                        source_row
                            .checked_mul(self.metadata.obs_length)
                            .ok_or(DtaError::ArithmeticOverflow("row offset"))?,
                    )
                    .ok_or(DtaError::ArithmeticOverflow("observation chunk offset"))?;
                let staged = read_exact_at(
                    &mut self.reader,
                    chunk_offset,
                    chunk_length,
                    &mut self.scratch,
                    "reading observation rows",
                )?;
                for local_row in 0..chunk_rows_usize {
                    check_cancel(&mut should_interrupt)?;
                    let row_at = local_row
                        .checked_mul(obs_length)
                        .ok_or(DtaError::ArithmeticOverflow("staged row offset"))?;
                    for (builder, &index) in builders.iter_mut().zip(&indices) {
                        check_cancel(&mut should_interrupt)?;
                        let variable = &self.metadata.variables[index as usize];
                        let width = usize::try_from(variable.byte_width)
                            .map_err(|_| DtaError::ArithmeticOverflow("cell width"))?;
                        let variable_at = usize::try_from(variable.byte_offset)
                            .map_err(|_| DtaError::ArithmeticOverflow("cell offset"))?;
                        let cell_at = row_at
                            .checked_add(variable_at)
                            .ok_or(DtaError::ArithmeticOverflow("staged cell offset"))?;
                        let cell_end = cell_at
                            .checked_add(width)
                            .ok_or(DtaError::ArithmeticOverflow("staged cell end"))?;
                        let absolute_offset = chunk_offset
                            .checked_add(u64::try_from(cell_at).map_err(|_| {
                                DtaError::ArithmeticOverflow("absolute cell offset")
                            })?)
                            .ok_or(DtaError::ArithmeticOverflow("absolute cell offset"))?;
                        let cell = staged.get(cell_at..cell_end).ok_or(DtaError::Truncated {
                            context: "observation cell",
                            offset: error_offset(absolute_offset),
                            needed: width,
                            available: staged.len().saturating_sub(cell_at),
                        })?;
                        push_staged_cell(builder, cell, absolute_offset, &self.metadata, variable)?;
                    }
                }
                row = row
                    .checked_add(chunk_rows)
                    .ok_or(DtaError::ArithmeticOverflow("projected row"))?;
            }
        } else {
            for row in 0..row_count {
                check_cancel(&mut should_interrupt)?;
                let source_row = row_start
                    .checked_add(row)
                    .ok_or(DtaError::ArithmeticOverflow("source row"))?;
                let row_offset = source_row
                    .checked_mul(self.metadata.obs_length)
                    .ok_or(DtaError::ArithmeticOverflow("row offset"))?;
                for (builder, &index) in builders.iter_mut().zip(&indices) {
                    check_cancel(&mut should_interrupt)?;
                    let variable = &self.metadata.variables[index as usize];
                    let cell_offset = payload_start
                        .checked_add(row_offset)
                        .and_then(|value| value.checked_add(variable.byte_offset))
                        .ok_or(DtaError::ArithmeticOverflow("cell offset"))?;
                    let width = usize::try_from(variable.byte_width)
                        .map_err(|_| DtaError::ArithmeticOverflow("cell width"))?;
                    if matches!(variable.dta_type, DtaType::FixedString(_)) {
                        let encoding = if self.metadata.format_version.is_modern() {
                            UTF_8
                        } else {
                            WINDOWS_1252
                        };
                        let (value, _) = decode_range(
                            &mut self.reader,
                            cell_offset,
                            width,
                            encoding,
                            true,
                            &mut self.scratch,
                            &mut should_interrupt,
                            "reading fixed-string observation",
                        )?;
                        let ColumnBuilder::FixedString { values, .. } = builder else {
                            return Err(DtaError::ArithmeticOverflow("column builder type"));
                        };
                        values.push(value);
                        continue;
                    }
                    let cell = read_exact_at(
                        &mut self.reader,
                        cell_offset,
                        width,
                        &mut self.scratch,
                        "reading observation cell",
                    )?;
                    push_cell(
                        builder,
                        &cell,
                        cell_offset,
                        &self.metadata,
                        &variable.dta_type,
                    )?;
                }
            }
        }

        resolve_file_strls(
            &mut self.reader,
            &self.metadata,
            &mut self.scratch,
            &mut builders,
            &mut should_interrupt,
        )?;
        check_cancel(&mut should_interrupt)?;
        self.ensure_value_labels(&mut should_interrupt)?;
        let value_label_tables = self
            .value_label_tables
            .clone()
            .expect("value-label cache was initialized");
        let columns = builders.into_iter().map(ColumnBuilder::finish).collect();
        Ok(DtaData {
            metadata: self.metadata.clone(),
            row_start,
            row_count,
            columns,
            value_label_tables,
        })
    }

    /// Return ownership of the underlying reader.
    pub fn into_inner(self) -> R {
        self.reader
    }

    fn ensure_value_labels<F>(&mut self, should_interrupt: &mut F) -> Result<(), DtaError>
    where
        F: FnMut() -> bool,
    {
        if self.value_label_tables.is_some() {
            return Ok(());
        }
        check_cancel(should_interrupt)?;
        let tables = read_value_labels_streaming(
            &mut self.reader,
            &self.metadata,
            &mut self.scratch,
            should_interrupt,
        )?;
        check_cancel(should_interrupt)?;
        self.value_label_tables = Some(tables);
        Ok(())
    }
}

fn check_cancel<F: FnMut() -> bool>(should_interrupt: &mut F) -> Result<(), DtaError> {
    if should_interrupt() {
        Err(DtaError::Cancelled)
    } else {
        Ok(())
    }
}

fn checked_add_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_add(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn error_offset(offset: u64) -> usize {
    usize::try_from(offset).unwrap_or(usize::MAX)
}

fn read_exact_at<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    length: usize,
    scratch: &mut Scratch,
    context: &'static str,
) -> Result<Vec<u8>, DtaError> {
    scratch.record(length)?;
    reader
        .seek(SeekFrom::Start(offset))
        .map_err(|error| DtaError::Io {
            context,
            offset,
            kind: error.kind(),
        })?;
    let mut bytes = Vec::new();
    bytes
        .try_reserve_exact(length)
        .map_err(|_| DtaError::ArithmeticOverflow("file read allocation"))?;
    bytes.resize(length, 0);
    let mut completed = 0_usize;
    while completed < length {
        let chunk = length - completed;
        let read_offset = offset
            .checked_add(
                u64::try_from(completed)
                    .map_err(|_| DtaError::ArithmeticOverflow("file read offset"))?,
            )
            .ok_or(DtaError::ArithmeticOverflow("file read offset"))?;
        let count = reader
            .read(&mut bytes[completed..completed + chunk])
            .map_err(|error| DtaError::Io {
                context,
                offset: read_offset,
                kind: error.kind(),
            })?;
        if count == 0 {
            return Err(DtaError::Io {
                context,
                offset: read_offset,
                kind: ErrorKind::UnexpectedEof,
            });
        }
        completed = completed
            .checked_add(count)
            .ok_or(DtaError::ArithmeticOverflow("file read length"))?;
    }
    Ok(bytes)
}

#[allow(clippy::too_many_arguments)]
fn decode_range<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    offset: u64,
    length: usize,
    encoding: &'static Encoding,
    stop_at_nul: bool,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    context: &'static str,
) -> Result<(String, bool), DtaError> {
    let mut output = String::new();
    let mut decoder = encoding.new_decoder_without_bom_handling();
    let mut completed = 0_usize;
    let mut found_nul = false;

    loop {
        check_cancel(should_interrupt)?;
        let remaining = length.saturating_sub(completed);
        let chunk_length = remaining.min(scratch.limit);
        let bytes = if chunk_length == 0 {
            Vec::new()
        } else {
            let chunk_offset = offset
                .checked_add(
                    u64::try_from(completed)
                        .map_err(|_| DtaError::ArithmeticOverflow("string read offset"))?,
                )
                .ok_or(DtaError::ArithmeticOverflow("string read offset"))?;
            read_exact_at(reader, chunk_offset, chunk_length, scratch, context)?
        };
        let input = if stop_at_nul {
            if let Some(nul) = bytes.iter().position(|byte| *byte == 0) {
                found_nul = true;
                &bytes[..nul]
            } else {
                &bytes
            }
        } else {
            &bytes
        };
        let useful_capacity = input
            .len()
            .checked_mul(3)
            .and_then(|value| value.checked_add(3))
            .ok_or(DtaError::ArithmeticOverflow("decoded string capacity"))?;
        output
            .try_reserve(useful_capacity)
            .map_err(|_| DtaError::ArithmeticOverflow("decoded string allocation"))?;
        let last = found_nul || completed.saturating_add(chunk_length) == length;
        let mut consumed = 0_usize;
        loop {
            let (result, read, _) = decoder.decode_to_string(&input[consumed..], &mut output, last);
            consumed = consumed
                .checked_add(read)
                .ok_or(DtaError::ArithmeticOverflow("decoded string input"))?;
            match result {
                CoderResult::InputEmpty => break,
                CoderResult::OutputFull => output
                    .try_reserve(input.len().saturating_mul(3).max(4))
                    .map_err(|_| DtaError::ArithmeticOverflow("decoded string allocation"))?,
            }
        }
        completed = completed
            .checked_add(chunk_length)
            .ok_or(DtaError::ArithmeticOverflow("string read length"))?;
        if found_nul || completed == length {
            output.shrink_to_fit();
            return Ok((output, found_nul));
        }
    }
}

fn expect_file_tag<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    tag: &'static [u8],
    expected: &'static str,
    scratch: &mut Scratch,
) -> Result<u64, DtaError> {
    let actual = read_exact_at(reader, offset, tag.len(), scratch, "reading structural tag")?;
    if actual != tag {
        return Err(DtaError::UnexpectedTag {
            expected,
            offset: error_offset(offset),
        });
    }
    checked_add_u64(
        offset,
        u64::try_from(tag.len()).map_err(|_| DtaError::ArithmeticOverflow("tag length"))?,
        "tag end",
    )
}

fn ensure_absolute(section: &'static str, actual: u64, expected: u64) -> Result<(), DtaError> {
    if actual != expected {
        return Err(DtaError::MapOffsetMismatch {
            section,
            expected,
            actual,
        });
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn modern_string_payload<R: Read + Seek>(
    reader: &mut R,
    section_offset: u64,
    next_offset: u64,
    count: usize,
    width: usize,
    open: &'static [u8],
    close: &'static [u8],
    section_name: &'static str,
    scratch: &mut Scratch,
) -> Result<u64, DtaError> {
    let payload = expect_file_tag(reader, section_offset, open, section_name, scratch)?;
    let close_offset = checked_add_u64(
        payload,
        u64::try_from(
            count
                .checked_mul(width)
                .ok_or(DtaError::ArithmeticOverflow("string section length"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("string section length"))?,
        "string section length",
    )?;
    let after_close = expect_file_tag(reader, close_offset, close, section_name, scratch)?;
    ensure_absolute(section_name, after_close, next_offset)?;
    Ok(payload)
}

fn validate_modern_sortlist<R: Read + Seek>(
    reader: &mut R,
    header: &FileModernHeaderMap,
    nvar: usize,
    scratch: &mut Scratch,
) -> Result<(), DtaError> {
    let payload = expect_file_tag(
        reader,
        header.section_offsets.sortlist,
        b"<sortlist>",
        "<sortlist>",
        scratch,
    )?;
    let element_width = if header.format_version == FormatVersion::V119 {
        4
    } else {
        2
    };
    let length = nvar
        .checked_add(1)
        .and_then(|value| value.checked_mul(element_width))
        .ok_or(DtaError::ArithmeticOverflow("sortlist length"))?;
    let close_offset = checked_add_u64(
        payload,
        u64::try_from(length).map_err(|_| DtaError::ArithmeticOverflow("sortlist length"))?,
        "sortlist length",
    )?;
    let after_close =
        expect_file_tag(reader, close_offset, b"</sortlist>", "</sortlist>", scratch)?;
    ensure_absolute("formats", after_close, header.section_offsets.formats)
}

fn read_modern_header_map<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
) -> Result<FileModernHeaderMap, DtaError> {
    let mut cursor = expect_file_tag(
        reader,
        0,
        b"<stata_dta><header><release>",
        "<stata_dta><header><release>",
        scratch,
    )?;
    let release = read_exact_at(reader, cursor, 3, scratch, "reading release number")?;
    let release_text = String::from_utf8_lossy(&release).into_owned();
    let format_version = release_text
        .parse::<u16>()
        .ok()
        .and_then(|release| FormatVersion::try_from(release).ok())
        .filter(|version| version.is_modern())
        .ok_or(DtaError::InvalidRelease(release_text))?;
    cursor = checked_add_u64(cursor, 3, "release number")?;
    cursor = expect_file_tag(reader, cursor, b"</release>", "</release>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"<byteorder>", "<byteorder>", scratch)?;
    let byte_order_bytes = read_exact_at(reader, cursor, 3, scratch, "reading byte order")?;
    let byte_order = match byte_order_bytes.as_slice() {
        b"MSF" => ByteOrder::Msf,
        b"LSF" => ByteOrder::Lsf,
        invalid => {
            return Err(DtaError::InvalidByteOrder(
                String::from_utf8_lossy(invalid).into_owned(),
            ));
        }
    };
    cursor = checked_add_u64(cursor, 3, "byte order")?;
    cursor = expect_file_tag(reader, cursor, b"</byteorder>", "</byteorder>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"<K>", "<K>", scratch)?;
    let k_width = if format_version == FormatVersion::V119 {
        4
    } else {
        2
    };
    let k_bytes = read_exact_at(reader, cursor, k_width, scratch, "reading variable count")?;
    let nvar = if format_version == FormatVersion::V119 {
        read_u32(&k_bytes, 0, byte_order, "variable count")?
    } else {
        u32::from(read_u16(&k_bytes, 0, byte_order, "variable count")?)
    };
    cursor = checked_add_u64(cursor, k_width as u64, "variable count")?;
    cursor = expect_file_tag(reader, cursor, b"</K>", "</K>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"<N>", "<N>", scratch)?;
    let n_width = if format_version == FormatVersion::V117 {
        4
    } else {
        8
    };
    let n_bytes = read_exact_at(
        reader,
        cursor,
        n_width,
        scratch,
        "reading observation count",
    )?;
    let nobs = if format_version == FormatVersion::V117 {
        u64::from(read_u32(&n_bytes, 0, byte_order, "observation count")?)
    } else {
        read_u64(&n_bytes, 0, byte_order, "observation count")?
    };
    cursor = checked_add_u64(cursor, n_width as u64, "observation count")?;
    cursor = expect_file_tag(reader, cursor, b"</N>", "</N>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"<label>", "<label>", scratch)?;
    let label_length_width = if format_version == FormatVersion::V117 {
        1
    } else {
        2
    };
    let label_length_bytes = read_exact_at(
        reader,
        cursor,
        label_length_width,
        scratch,
        "reading dataset label length",
    )?;
    let label_length = if format_version == FormatVersion::V117 {
        usize::from(label_length_bytes[0])
    } else {
        usize::from(read_u16(
            &label_length_bytes,
            0,
            byte_order,
            "dataset label length",
        )?)
    };
    cursor = checked_add_u64(cursor, label_length_width as u64, "dataset label length")?;
    let mut never_cancel = || false;
    let dataset_label = decode_range(
        reader,
        cursor,
        label_length,
        UTF_8,
        false,
        scratch,
        &mut never_cancel,
        "reading dataset label",
    )?
    .0;
    cursor = checked_add_u64(
        cursor,
        u64::try_from(label_length)
            .map_err(|_| DtaError::ArithmeticOverflow("dataset label length"))?,
        "dataset label",
    )?;
    cursor = expect_file_tag(reader, cursor, b"</label>", "</label>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"<timestamp>", "<timestamp>", scratch)?;
    let timestamp_length =
        usize::from(read_exact_at(reader, cursor, 1, scratch, "reading timestamp length")?[0]);
    cursor = checked_add_u64(cursor, 1, "timestamp length")?;
    cursor = checked_add_u64(
        cursor,
        u64::try_from(timestamp_length)
            .map_err(|_| DtaError::ArithmeticOverflow("timestamp length"))?,
        "timestamp",
    )?;
    cursor = expect_file_tag(reader, cursor, b"</timestamp>", "</timestamp>", scratch)?;
    cursor = expect_file_tag(reader, cursor, b"</header>", "</header>", scratch)?;
    let map_start = cursor;
    cursor = expect_file_tag(reader, cursor, b"<map>", "<map>", scratch)?;
    let mut map_values = [0_u64; 14];
    for value in &mut map_values {
        let bytes = read_exact_at(reader, cursor, 8, scratch, "reading section map")?;
        *value = read_u64(&bytes, 0, byte_order, "section map")?;
        cursor = checked_add_u64(cursor, 8, "section map")?;
    }
    cursor = expect_file_tag(reader, cursor, b"</map>", "</map>", scratch)?;
    let section_offsets = SectionOffsets::from_array(map_values);
    if section_offsets.stata_data != 0 {
        return Err(DtaError::MapOffsetMismatch {
            section: "stata_data",
            expected: 0,
            actual: section_offsets.stata_data,
        });
    }
    ensure_absolute("map", section_offsets.map, map_start)?;
    let offsets = section_offsets.as_array();
    for index in 1..offsets.len() {
        if offsets[index] <= offsets[index - 1] {
            return Err(DtaError::SectionOrder {
                section: SectionOffsets::NAMES[index],
                previous_offset: offsets[index - 1],
                offset: offsets[index],
            });
        }
    }
    ensure_absolute("variable_types", cursor, section_offsets.variable_types)?;
    Ok(FileModernHeaderMap {
        format_version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        section_offsets,
    })
}

fn read_modern_metadata<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
) -> Result<DtaMetadata, DtaError> {
    let header = read_modern_header_map(reader, scratch)?;
    if header.section_offsets.end_of_file != file_length {
        return Err(DtaError::MapOffsetMismatch {
            section: "file length",
            expected: header.section_offsets.end_of_file,
            actual: file_length,
        });
    }
    let nvar =
        usize::try_from(header.nvar).map_err(|_| DtaError::ArithmeticOverflow("variable count"))?;
    let widths = field_widths(header.format_version);

    let types_start = expect_file_tag(
        reader,
        header.section_offsets.variable_types,
        b"<variable_types>",
        "<variable_types>",
        scratch,
    )?;
    let types_close = checked_add_u64(
        types_start,
        u64::try_from(
            nvar.checked_mul(2)
                .ok_or(DtaError::ArithmeticOverflow("variable types length"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("variable types length"))?,
        "variable types length",
    )?;
    let after_types = expect_file_tag(
        reader,
        types_close,
        b"</variable_types>",
        "</variable_types>",
        scratch,
    )?;
    ensure_absolute("varnames", after_types, header.section_offsets.varnames)?;

    let varnames = modern_string_payload(
        reader,
        header.section_offsets.varnames,
        header.section_offsets.sortlist,
        nvar,
        widths.varname,
        b"<varnames>",
        b"</varnames>",
        "varnames",
        scratch,
    )?;
    validate_modern_sortlist(reader, &header, nvar, scratch)?;
    let formats = modern_string_payload(
        reader,
        header.section_offsets.formats,
        header.section_offsets.value_label_names,
        nvar,
        widths.format,
        b"<formats>",
        b"</formats>",
        "formats",
        scratch,
    )?;
    let value_label_names = modern_string_payload(
        reader,
        header.section_offsets.value_label_names,
        header.section_offsets.variable_labels,
        nvar,
        widths.value_label_name,
        b"<value_label_names>",
        b"</value_label_names>",
        "value_label_names",
        scratch,
    )?;
    let variable_labels = modern_string_payload(
        reader,
        header.section_offsets.variable_labels,
        header.section_offsets.characteristics,
        nvar,
        widths.variable_label,
        b"<variable_labels>",
        b"</variable_labels>",
        "variable_labels",
        scratch,
    )?;

    let mut byte_offset = 0_u64;
    let mut variables = Vec::with_capacity(nvar);
    let mut never_cancel = || false;
    for index in 0..nvar {
        let field_offset = |start: u64, width: usize, context: &'static str| {
            checked_add_u64(
                start,
                u64::try_from(
                    index
                        .checked_mul(width)
                        .ok_or(DtaError::ArithmeticOverflow(context))?,
                )
                .map_err(|_| DtaError::ArithmeticOverflow(context))?,
                context,
            )
        };
        let type_bytes = read_exact_at(
            reader,
            field_offset(types_start, 2, "variable type offset")?,
            2,
            scratch,
            "reading variable type",
        )?;
        let type_code = read_u16(&type_bytes, 0, header.byte_order, "variable type")?;
        let (dta_type, byte_width) = resolve_type(type_code, header.format_version)?;
        let mut decode_field = |start, width, context| {
            decode_range(
                reader,
                field_offset(start, width, context)?,
                width,
                UTF_8,
                true,
                scratch,
                &mut never_cancel,
                context,
            )
            .map(|value| value.0)
        };
        let name = decode_field(varnames, widths.varname, "reading variable name")?;
        let format = decode_field(formats, widths.format, "reading variable format")?;
        let value_label_name = decode_field(
            value_label_names,
            widths.value_label_name,
            "reading variable value-label name",
        )?;
        let label = decode_field(
            variable_labels,
            widths.variable_label,
            "reading variable label",
        )?;
        variables.push(VariableInfo {
            name,
            dta_type,
            type_code,
            format,
            label,
            value_label_name,
            byte_width,
            byte_offset,
        });
        byte_offset = checked_add_u64(byte_offset, u64::from(byte_width), "observation length")?;
    }
    Ok(DtaMetadata {
        format_version: header.format_version,
        byte_order: header.byte_order,
        nvar: header.nvar,
        nobs: header.nobs,
        dataset_label: header.dataset_label,
        variables,
        section_offsets: header.section_offsets,
        obs_length: byte_offset,
    })
}

fn read_legacy_metadata<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
) -> Result<DtaMetadata, DtaError> {
    let header = read_exact_at(reader, 0, HEADER_SIZE, scratch, "reading legacy header")?;
    let version = FormatVersion::try_from(u16::from(header[0]))
        .map_err(|_| DtaError::InvalidRelease(header[0].to_string()))?;
    let byte_order = match header[1] {
        1 => ByteOrder::Msf,
        2 => ByteOrder::Lsf,
        other => return Err(DtaError::InvalidByteOrder(format!("0x{other:02x}"))),
    };
    if header[2] != 1 {
        return Err(DtaError::InvalidFileType(header[2]));
    }
    let nvar = u32::from(read_u16(&header, 4, byte_order, "legacy variable count")?);
    let nobs_signed = read_i32(&header, 6, byte_order, "legacy observation count")?;
    if nobs_signed < 0 {
        return Err(DtaError::NegativeObservationCount(nobs_signed));
    }
    let nobs = u64::try_from(nobs_signed)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy observation count"))?;
    let nvar_usize =
        usize::try_from(nvar).map_err(|_| DtaError::ArithmeticOverflow("legacy variable count"))?;
    let fixed_end = legacy_fixed_metadata_end(nvar_usize, version)?;
    let fixed_end_u64 = u64::try_from(fixed_end)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy fixed metadata length"))?;
    if fixed_end_u64 > file_length {
        return Err(DtaError::Truncated {
            context: "legacy fixed metadata sections",
            offset: 0,
            needed: fixed_end,
            available: usize::try_from(file_length).unwrap_or(usize::MAX),
        });
    }

    let format_width = format_width(version);
    let variable_types = u64::try_from(HEADER_SIZE)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy variable_types offset"))?;
    let varnames = checked_add_u64(variable_types, u64::from(nvar), "legacy varnames")?;
    let sortlist = checked_add_u64(
        varnames,
        u64::try_from(
            nvar_usize
                .checked_mul(VARNAME_WIDTH)
                .ok_or(DtaError::ArithmeticOverflow("legacy varnames"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("legacy varnames"))?,
        "legacy sortlist",
    )?;
    let formats = checked_add_u64(
        sortlist,
        u64::try_from(
            nvar_usize
                .checked_add(1)
                .and_then(|value| value.checked_mul(SORTLIST_WIDTH))
                .ok_or(DtaError::ArithmeticOverflow("legacy sortlist"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("legacy sortlist"))?,
        "legacy formats",
    )?;
    let value_label_names = checked_add_u64(
        formats,
        u64::try_from(
            nvar_usize
                .checked_mul(format_width)
                .ok_or(DtaError::ArithmeticOverflow("legacy formats"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("legacy formats"))?,
        "legacy value-label names",
    )?;
    let variable_labels = checked_add_u64(
        value_label_names,
        u64::try_from(
            nvar_usize
                .checked_mul(VALUE_LABEL_NAME_WIDTH)
                .ok_or(DtaError::ArithmeticOverflow("legacy value-label names"))?,
        )
        .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label names"))?,
        "legacy variable labels",
    )?;

    let mut never_cancel = || false;
    let dataset_label = decode_range(
        reader,
        10,
        81,
        WINDOWS_1252,
        true,
        scratch,
        &mut never_cancel,
        "reading legacy dataset label",
    )?
    .0;
    let mut variables = Vec::with_capacity(nvar_usize);
    let mut byte_offset = 0_u64;
    for index in 0..nvar_usize {
        let type_offset = checked_add_u64(
            variable_types,
            u64::try_from(index)
                .map_err(|_| DtaError::ArithmeticOverflow("legacy variable type offset"))?,
            "legacy variable type offset",
        )?;
        let code = read_exact_at(
            reader,
            type_offset,
            1,
            scratch,
            "reading legacy variable type",
        )?[0];
        let (dta_type, byte_width) = legacy_type(code, version)?;
        let field_offset = |start: u64, width: usize, context: &'static str| {
            checked_add_u64(
                start,
                u64::try_from(
                    index
                        .checked_mul(width)
                        .ok_or(DtaError::ArithmeticOverflow(context))?,
                )
                .map_err(|_| DtaError::ArithmeticOverflow(context))?,
                context,
            )
        };
        let mut decode_field = |start, width, context| {
            decode_range(
                reader,
                field_offset(start, width, context)?,
                width,
                WINDOWS_1252,
                true,
                scratch,
                &mut never_cancel,
                context,
            )
            .map(|value| value.0)
        };
        let name = decode_field(varnames, VARNAME_WIDTH, "reading legacy varname")?;
        let format = decode_field(formats, format_width, "reading legacy display format")?;
        let value_label_name = decode_field(
            value_label_names,
            VALUE_LABEL_NAME_WIDTH,
            "reading legacy value-label name",
        )?;
        let label = decode_field(
            variable_labels,
            VARIABLE_LABEL_WIDTH,
            "reading legacy variable label",
        )?;
        variables.push(VariableInfo {
            name,
            dta_type,
            type_code: u16::from(code),
            format,
            label,
            value_label_name,
            byte_width,
            byte_offset,
        });
        byte_offset = checked_add_u64(
            byte_offset,
            u64::from(byte_width),
            "legacy observation length",
        )?;
    }

    let mut cursor = u64::try_from(fixed_end)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion offset"))?;
    loop {
        let expansion =
            read_exact_at(reader, cursor, 5, scratch, "reading legacy expansion field")?;
        let data_type = expansion[0];
        let length = read_i32(&expansion, 1, byte_order, "legacy expansion-field length")?;
        if data_type == 0 && length == 0 {
            cursor = checked_add_u64(cursor, 5, "legacy expansion terminator")?;
            break;
        }
        if length < 0 {
            return Err(DtaError::NegativeExpansionLength {
                value: length,
                offset: error_offset(cursor.saturating_add(1)),
            });
        }
        if data_type == 0 {
            return Err(DtaError::InvalidExpansionTerminator {
                value: length,
                offset: error_offset(cursor),
            });
        }
        cursor = checked_add_u64(cursor, 5, "legacy expansion header")?;
        cursor = checked_add_u64(
            cursor,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion length"))?,
            "legacy expansion payload",
        )?;
        if cursor > file_length {
            return Err(DtaError::Io {
                context: "reading legacy expansion field",
                offset: cursor,
                kind: ErrorKind::UnexpectedEof,
            });
        }
    }
    let observation_bytes = nobs
        .checked_mul(byte_offset)
        .ok_or(DtaError::ArithmeticOverflow(
            "legacy observation data length",
        ))?;
    let value_labels = checked_add_u64(cursor, observation_bytes, "legacy value-label offset")?;
    if value_labels > file_length {
        return Err(DtaError::Truncated {
            context: "legacy observation data",
            offset: error_offset(cursor),
            needed: usize::try_from(observation_bytes).unwrap_or(usize::MAX),
            available: usize::try_from(file_length.saturating_sub(cursor)).unwrap_or(usize::MAX),
        });
    }
    Ok(DtaMetadata {
        format_version: version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        variables,
        section_offsets: SectionOffsets {
            stata_data: 0,
            map: 0,
            variable_types,
            varnames,
            sortlist,
            formats,
            value_label_names,
            variable_labels,
            characteristics: fixed_end_u64,
            data: cursor,
            strls: value_labels,
            value_labels,
            stata_data_close: file_length,
            end_of_file: file_length,
        },
        obs_length: byte_offset,
    })
}

fn read_i32_at<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    byte_order: ByteOrder,
    scratch: &mut Scratch,
    context: &'static str,
) -> Result<i32, DtaError> {
    let bytes = read_exact_at(reader, offset, 4, scratch, context)?;
    read_i32(&bytes, 0, byte_order, context)
}

fn read_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    const RESERVED_WIDTH: usize = 3;
    let modern = metadata.format_version.is_modern();
    let name_width = match metadata.format_version {
        FormatVersion::V113 | FormatVersion::V114 | FormatVersion::V115 | FormatVersion::V117 => 33,
        FormatVersion::V118 | FormatVersion::V119 => 129,
    };
    let encoding = if modern { UTF_8 } else { WINDOWS_1252 };
    let section_end = if modern {
        metadata.section_offsets.stata_data_close
    } else {
        metadata.section_offsets.end_of_file
    };
    let mut cursor = metadata.section_offsets.value_labels;
    if modern {
        cursor = expect_file_tag(reader, cursor, b"<value_labels>", "<value_labels>", scratch)?;
    }
    let mut tables = Vec::new();

    while cursor < section_end {
        check_cancel(should_interrupt)?;
        if modern {
            let marker = read_exact_at(
                reader,
                cursor,
                5,
                scratch,
                "reading value-label table marker",
            )?;
            if marker != b"<lbl>" {
                cursor = expect_file_tag(
                    reader,
                    cursor,
                    b"</value_labels>",
                    "</value_labels>",
                    scratch,
                )?;
                break;
            }
            cursor = checked_add_u64(cursor, 5, "value-label table open")?;
        }
        let table_start = cursor;
        let declared_i32 = read_i32_at(
            reader,
            cursor,
            metadata.byte_order,
            scratch,
            "reading value-label table length",
        )?;
        if declared_i32 < 0 {
            return Err(DtaError::NegativeValueLabelField {
                field: "table length",
                value: declared_i32,
                offset: error_offset(cursor),
            });
        }
        let declared = usize::try_from(declared_i32)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label table length"))?;
        cursor = checked_add_u64(cursor, 4, "value-label table length")?;
        let name_start = cursor;
        let (name, found_name_nul) = decode_range(
            reader,
            name_start,
            name_width,
            encoding,
            true,
            scratch,
            should_interrupt,
            "reading value-label table name",
        )?;
        if modern && !found_name_nul {
            return Err(DtaError::MissingNulTerminator {
                context: "value-label table name",
                offset: error_offset(name_start),
            });
        }
        cursor = checked_add_u64(
            cursor,
            u64::try_from(name_width)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label table name"))?,
            "value-label table name",
        )?;
        read_exact_at(
            reader,
            cursor,
            RESERVED_WIDTH,
            scratch,
            "reading value-label reserved bytes",
        )?;
        cursor = checked_add_u64(cursor, RESERVED_WIDTH as u64, "value-label reserved bytes")?;
        let payload_start = cursor;
        if declared < 8 {
            return Err(DtaError::InvalidValueLabelLength {
                offset: error_offset(table_start),
                declared,
                expected: 8,
            });
        }
        let payload_header = read_exact_at(
            reader,
            payload_start,
            8,
            scratch,
            "reading value-label payload header",
        )?;
        let entry_count_i32 = read_i32(
            &payload_header,
            0,
            metadata.byte_order,
            "value-label entry count",
        )?;
        if entry_count_i32 < 0 {
            return Err(DtaError::NegativeValueLabelField {
                field: "entry count",
                value: entry_count_i32,
                offset: error_offset(payload_start),
            });
        }
        let text_length_i32 = read_i32(
            &payload_header,
            4,
            metadata.byte_order,
            "value-label text length",
        )?;
        if text_length_i32 < 0 {
            return Err(DtaError::NegativeValueLabelField {
                field: "text length",
                value: text_length_i32,
                offset: error_offset(payload_start.saturating_add(4)),
            });
        }
        let entry_count = usize::try_from(entry_count_i32)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label entry count"))?;
        let text_length = usize::try_from(text_length_i32)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label text length"))?;
        let arrays_length = entry_count
            .checked_mul(8)
            .ok_or(DtaError::ArithmeticOverflow("value-label arrays length"))?;
        let expected = 8_usize
            .checked_add(arrays_length)
            .and_then(|value| value.checked_add(text_length))
            .ok_or(DtaError::ArithmeticOverflow("value-label payload length"))?;
        if declared != expected {
            return Err(DtaError::InvalidValueLabelLength {
                offset: error_offset(table_start),
                declared,
                expected,
            });
        }
        let table_end = checked_add_u64(
            payload_start,
            u64::try_from(declared)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label table end"))?,
            "value-label table end",
        )?;
        if table_end > section_end {
            return Err(DtaError::Io {
                context: "reading value-label table payload",
                offset: payload_start,
                kind: ErrorKind::UnexpectedEof,
            });
        }
        let offsets_start = checked_add_u64(payload_start, 8, "value-label offsets")?;
        let values_start = checked_add_u64(
            offsets_start,
            u64::try_from(
                entry_count
                    .checked_mul(4)
                    .ok_or(DtaError::ArithmeticOverflow("value-label offsets length"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("value-label offsets length"))?,
            "value-label values",
        )?;
        let text_start = checked_add_u64(
            values_start,
            u64::try_from(
                entry_count
                    .checked_mul(4)
                    .ok_or(DtaError::ArithmeticOverflow("value-label values length"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("value-label values length"))?,
            "value-label text",
        )?;
        let mut previous_value = None;
        let mut entries = Vec::with_capacity(entry_count);
        for entry_index in 0..entry_count {
            check_cancel(should_interrupt)?;
            let relative = u64::try_from(
                entry_index
                    .checked_mul(4)
                    .ok_or(DtaError::ArithmeticOverflow("value-label entry offset"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("value-label entry offset"))?;
            let offset_position =
                checked_add_u64(offsets_start, relative, "value-label text offset position")?;
            let text_offset = read_i32_at(
                reader,
                offset_position,
                metadata.byte_order,
                scratch,
                "reading value-label text offset",
            )?;
            let Some(text_offset_usize) = usize::try_from(text_offset)
                .ok()
                .filter(|offset| *offset < text_length)
            else {
                return Err(DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: error_offset(offset_position),
                    text_offset,
                    text_length,
                });
            };
            let value = read_i32_at(
                reader,
                checked_add_u64(values_start, relative, "value-label value position")?,
                metadata.byte_order,
                scratch,
                "reading value-label value",
            )?;
            if let Some(previous) = previous_value {
                if value <= previous {
                    return Err(DtaError::UnsortedValueLabelValues {
                        table_offset: error_offset(table_start),
                        entry_index,
                        previous,
                        value,
                    });
                }
            }
            previous_value = Some(value);
            let label_start = checked_add_u64(
                text_start,
                u64::try_from(text_offset_usize)
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label text offset"))?,
                "value-label text offset",
            )?;
            let (label, found_nul) = decode_range(
                reader,
                label_start,
                text_length - text_offset_usize,
                encoding,
                true,
                scratch,
                should_interrupt,
                "reading value-label text",
            )?;
            if !found_nul {
                return Err(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: error_offset(label_start),
                });
            }
            entries.push(ValueLabelEntry {
                value,
                missing_tag: classify_long_missing(value),
                label,
            });
        }
        cursor = table_end;
        if modern {
            cursor = expect_file_tag(reader, cursor, b"</lbl>", "</lbl>", scratch)?;
        }
        tables.push(ValueLabelTable { name, entries });
    }

    ensure_absolute("stata_data_close", cursor, section_end)?;
    if modern {
        cursor = expect_file_tag(reader, cursor, b"</stata_dta>", "</stata_dta>", scratch)?;
        ensure_absolute("end_of_file", cursor, metadata.section_offsets.end_of_file)?;
    }
    Ok(tables)
}

fn resolve_columns(metadata: &DtaMetadata, options: &ReadOptions) -> Result<Vec<u32>, DtaError> {
    let requested = options
        .column_indices
        .clone()
        .unwrap_or_else(|| (0..metadata.nvar).collect());
    let mut seen = HashSet::with_capacity(requested.len());
    let mut result = Vec::with_capacity(requested.len());
    for index in requested {
        if index >= metadata.nvar {
            return Err(DtaError::InvalidColumnIndex {
                index,
                nvar: metadata.nvar,
            });
        }
        if seen.insert(index) {
            result.push(index);
        }
    }
    Ok(result)
}

fn row_window(metadata: &DtaMetadata, options: &ReadOptions) -> (u64, u64) {
    let start = options.row_start.min(metadata.nobs);
    let available = metadata.nobs - start;
    (start, options.row_count.unwrap_or(available).min(available))
}

fn validate_layout<R: Read + Seek>(
    reader: &mut R,
    metadata: &DtaMetadata,
    file_length: u64,
    scratch: &mut Scratch,
) -> Result<(), DtaError> {
    if !metadata.format_version.is_modern() {
        return Ok(());
    }
    let data_open = read_exact_at(
        reader,
        metadata.section_offsets.data,
        6,
        scratch,
        "reading <data>",
    )?;
    if data_open != b"<data>" {
        return Err(DtaError::UnexpectedTag {
            expected: "<data>",
            offset: error_offset(metadata.section_offsets.data),
        });
    }
    let payload_length = metadata
        .nobs
        .checked_mul(metadata.obs_length)
        .ok_or(DtaError::ArithmeticOverflow("observation data length"))?;
    let data_close = metadata
        .section_offsets
        .data
        .checked_add(6)
        .and_then(|value| value.checked_add(payload_length))
        .ok_or(DtaError::ArithmeticOverflow("data close offset"))?;
    let close = read_exact_at(reader, data_close, 7, scratch, "reading </data>")?;
    if close != b"</data>" {
        return Err(DtaError::UnexpectedTag {
            expected: "</data>",
            offset: error_offset(data_close),
        });
    }
    if data_close.saturating_add(7) != metadata.section_offsets.strls {
        return Err(DtaError::MapOffsetMismatch {
            section: "strls",
            expected: data_close.saturating_add(7),
            actual: metadata.section_offsets.strls,
        });
    }
    for (offset, expected, name) in [
        (
            metadata.section_offsets.strls,
            b"<strls>".as_slice(),
            "<strls>",
        ),
        (
            metadata
                .section_offsets
                .value_labels
                .checked_sub(8)
                .ok_or(DtaError::ArithmeticOverflow("strls close offset"))?,
            b"</strls>".as_slice(),
            "</strls>",
        ),
    ] {
        let tag = read_exact_at(reader, offset, expected.len(), scratch, "reading tag")?;
        if tag != expected {
            return Err(DtaError::UnexpectedTag {
                expected: name,
                offset: error_offset(offset),
            });
        }
    }
    if metadata.section_offsets.end_of_file != file_length {
        return Err(DtaError::MapOffsetMismatch {
            section: "file length",
            expected: metadata.section_offsets.end_of_file,
            actual: file_length,
        });
    }
    Ok(())
}

fn parse_pointer(
    bytes: &[u8],
    offset: u64,
    metadata: &DtaMetadata,
) -> Result<Option<FileGsoKey>, DtaError> {
    let (variable, observation) = if metadata.format_version == FormatVersion::V117 {
        (
            read_u32(bytes, 0, metadata.byte_order, "strL variable pointer")?,
            u64::from(read_u32(
                bytes,
                4,
                metadata.byte_order,
                "strL observation pointer",
            )?),
        )
    } else {
        let variable = u32::from(read_u16(
            bytes,
            0,
            metadata.byte_order,
            "strL variable pointer",
        )?);
        let mut observation = 0_u64;
        match metadata.byte_order {
            ByteOrder::Lsf => {
                for (shift, byte) in bytes[2..8].iter().enumerate() {
                    observation |= u64::from(*byte) << (shift * 8);
                }
            }
            ByteOrder::Msf => {
                for byte in &bytes[2..8] {
                    observation = (observation << 8) | u64::from(*byte);
                }
            }
        }
        (variable, observation)
    };
    if variable == 0 && observation == 0 {
        return Ok(None);
    }
    let key = FileGsoKey {
        variable,
        observation,
    };
    validate_gso_key(metadata, key, offset, true)?;
    Ok(Some(key))
}

fn validate_gso_key(
    metadata: &DtaMetadata,
    key: FileGsoKey,
    offset: u64,
    pointer: bool,
) -> Result<(), DtaError> {
    let valid_variable = key
        .variable
        .checked_sub(1)
        .and_then(|index| usize::try_from(index).ok())
        .and_then(|index| metadata.variables.get(index))
        .is_some_and(|variable| variable.dta_type == DtaType::StrL);
    let valid_observation = key.observation >= 1 && key.observation <= metadata.nobs;
    if valid_variable && valid_observation {
        return Ok(());
    }
    if pointer {
        Err(DtaError::InvalidStrlPointer {
            variable: key.variable,
            observation: key.observation,
            offset: error_offset(offset),
        })
    } else {
        Err(DtaError::InvalidGsoKey {
            variable: key.variable,
            observation: key.observation,
            offset: error_offset(offset),
        })
    }
}

fn push_staged_cell(
    builder: &mut ColumnBuilder,
    cell: &[u8],
    absolute_offset: u64,
    metadata: &DtaMetadata,
    variable: &VariableInfo,
) -> Result<(), DtaError> {
    if matches!(variable.dta_type, DtaType::FixedString(_)) {
        let mut value = if metadata.format_version.is_modern() {
            decode_utf8(field_bytes(cell))
        } else {
            decode_windows_1252(field_bytes(cell))
        };
        value.shrink_to_fit();
        let ColumnBuilder::FixedString { values, .. } = builder else {
            return Err(DtaError::ArithmeticOverflow("column builder type"));
        };
        values.push(value);
        return Ok(());
    }
    push_cell(builder, cell, absolute_offset, metadata, &variable.dta_type)
}

fn push_cell(
    builder: &mut ColumnBuilder,
    cell: &[u8],
    absolute_offset: u64,
    metadata: &DtaMetadata,
    dta_type: &DtaType,
) -> Result<(), DtaError> {
    match builder {
        ColumnBuilder::Byte {
            values,
            missing_tags,
            ..
        } => {
            let value = read_i8(cell, 0, "byte observation")?;
            values.push(value);
            missing_tags.push(classify_byte_missing(value));
        }
        ColumnBuilder::Int {
            values,
            missing_tags,
            ..
        } => {
            let value = read_i16(cell, 0, metadata.byte_order, "int observation")?;
            values.push(value);
            missing_tags.push(classify_int_missing(value));
        }
        ColumnBuilder::Long {
            values,
            missing_tags,
            ..
        } => {
            let value = read_i32(cell, 0, metadata.byte_order, "long observation")?;
            values.push(value);
            missing_tags.push(classify_long_missing(value));
        }
        ColumnBuilder::Float {
            values,
            missing_tags,
            ..
        } => {
            let bits = read_u32(cell, 0, metadata.byte_order, "float observation")?;
            values.push(f32::from_bits(bits));
            missing_tags.push(classify_float_missing_bits(bits));
        }
        ColumnBuilder::Double {
            values,
            missing_tags,
            ..
        } => {
            let bits = read_u64(cell, 0, metadata.byte_order, "double observation")?;
            values.push(f64::from_bits(bits));
            missing_tags.push(classify_double_missing_bits(bits));
        }
        ColumnBuilder::FixedString { .. } => {
            return Err(DtaError::ArithmeticOverflow("fixed string streaming path"));
        }
        ColumnBuilder::StrL { pointers, .. } => {
            if *dta_type != DtaType::StrL {
                return Err(DtaError::ArithmeticOverflow("column builder type"));
            }
            pointers.push(parse_pointer(cell, absolute_offset, metadata)?);
        }
    }
    Ok(())
}

fn resolve_file_strls<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    builders: &mut [ColumnBuilder],
    should_interrupt: &mut F,
) -> Result<(), DtaError> {
    let requested = builders
        .iter()
        .filter_map(|builder| match builder {
            ColumnBuilder::StrL { pointers, .. } => Some(pointers.iter().flatten().copied()),
            _ => None,
        })
        .flatten()
        .collect::<HashSet<_>>();
    if !builders
        .iter()
        .any(|builder| matches!(builder, ColumnBuilder::StrL { .. }))
    {
        return Ok(());
    }

    let mut entries = HashMap::new();
    let mut seen = HashSet::new();
    let mut cursor = checked_add_u64(metadata.section_offsets.strls, 7, "GSO section start")?;
    let end = metadata
        .section_offsets
        .value_labels
        .checked_sub(8)
        .ok_or(DtaError::ArithmeticOverflow("GSO section end"))?;
    while cursor < end {
        check_cancel(should_interrupt)?;
        let header_length = if metadata.format_version == FormatVersion::V117 {
            16
        } else {
            20
        };
        let header = read_exact_at(reader, cursor, header_length, scratch, "reading GSO header")?;
        if &header[..3] != b"GSO" {
            return Err(DtaError::InvalidGsoMarker {
                offset: error_offset(cursor),
            });
        }
        let variable = read_u32(&header, 3, metadata.byte_order, "GSO variable")?;
        let (observation, type_offset) = if metadata.format_version == FormatVersion::V117 {
            (
                u64::from(read_u32(
                    &header,
                    7,
                    metadata.byte_order,
                    "GSO observation",
                )?),
                11,
            )
        } else {
            (
                read_u64(&header, 7, metadata.byte_order, "GSO observation")?,
                15,
            )
        };
        let gso_type = header[type_offset];
        if !matches!(gso_type, 129 | 130) {
            return Err(DtaError::InvalidGsoType {
                gso_type,
                offset: error_offset(cursor.saturating_add(type_offset as u64)),
            });
        }
        let length = read_u32(
            &header,
            type_offset + 1,
            metadata.byte_order,
            "GSO content length",
        )?;
        let content_length = usize::try_from(length)
            .map_err(|_| DtaError::ArithmeticOverflow("GSO content length"))?;
        let content_offset = checked_add_u64(
            cursor,
            u64::try_from(header_length)
                .map_err(|_| DtaError::ArithmeticOverflow("GSO header length"))?,
            "GSO content offset",
        )?;
        let next = checked_add_u64(content_offset, u64::from(length), "GSO content end")?;
        let file_end = metadata.section_offsets.end_of_file;
        if next > file_end {
            return Err(DtaError::Truncated {
                context: "GSO content",
                offset: error_offset(content_offset),
                needed: content_length,
                available: usize::try_from(file_end.saturating_sub(content_offset))
                    .unwrap_or(usize::MAX),
            });
        }
        if next > end {
            return Err(DtaError::Truncated {
                context: "GSO content",
                offset: error_offset(content_offset),
                needed: content_length,
                available: usize::try_from(end.saturating_sub(content_offset))
                    .unwrap_or(usize::MAX),
            });
        }
        if gso_type == 130 {
            if content_length == 0 {
                return Err(DtaError::InvalidGsoText {
                    offset: error_offset(content_offset),
                });
            }
            let final_byte = read_exact_at(
                reader,
                next - 1,
                1,
                scratch,
                "validating GSO text terminator",
            )?;
            if final_byte[0] != 0 {
                return Err(DtaError::InvalidGsoText {
                    offset: error_offset(content_offset),
                });
            }
        }
        let key = FileGsoKey {
            variable,
            observation,
        };
        validate_gso_key(metadata, key, cursor, false)?;
        if !seen.insert(key) {
            return Err(DtaError::DuplicateGsoKey {
                variable,
                observation,
                offset: error_offset(cursor),
            });
        }
        if requested.contains(&key) {
            entries.insert(
                key,
                FileGsoEntry {
                    content_offset,
                    content_length,
                    gso_type,
                },
            );
        }
        cursor = next;
    }
    if cursor != end {
        return Err(DtaError::InvalidGsoMarker {
            offset: error_offset(cursor),
        });
    }

    let mut decoded = HashMap::<FileGsoKey, String>::new();
    for builder in builders {
        let ColumnBuilder::StrL {
            pointers, values, ..
        } = builder
        else {
            continue;
        };
        for pointer in pointers.iter().copied() {
            let Some(key) = pointer else {
                values.push(String::new());
                continue;
            };
            if let Some(value) = decoded.get(&key) {
                values.push(value.clone());
                continue;
            }
            let entry = entries.get(&key).ok_or(DtaError::DanglingStrlPointer {
                variable: key.variable,
                observation: key.observation,
            })?;
            check_cancel(should_interrupt)?;
            let decoded_length = if entry.gso_type == 130 {
                entry.content_length - 1
            } else {
                entry.content_length
            };
            let value = decode_range(
                reader,
                entry.content_offset,
                decoded_length,
                UTF_8,
                false,
                scratch,
                should_interrupt,
                "reading selected GSO content",
            )?
            .0;
            decoded.insert(key, value.clone());
            values.push(value);
        }
    }
    Ok(())
}
