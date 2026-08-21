use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{ErrorKind, Read, Seek, SeekFrom};
use std::path::Path;

use encoding_rs::CoderResult;

use crate::endian::{read_i16, read_i32, read_i8, read_u16, read_u32, read_u64};
use crate::legacy::{legacy_fixed_offsets, legacy_type, LegacyLayout, LegacyValueLabelLayout};
use crate::metadata::{field_widths, resolve_type};
use crate::selection::{resolve_columns, row_window};
use crate::text::{field_bytes, is_dataset_note, is_utf8_boundary, TextDecoder, TextEncoding};
use crate::value_labels::has_legacy_offset_table_framing;
use crate::{
    missing::{
        classify_byte_missing_for_version, classify_double_missing_bits_for_version,
        classify_float_missing_bits_for_version, classify_int_missing_for_version,
        classify_long_missing_for_version,
    },
    ByteOrder, Column, ColumnValues, DtaData, DtaError, DtaMetadata, DtaType, FormatVersion,
    ReadOptions, SectionOffsets, ValueLabelEntry, ValueLabelTable, VariableInfo,
};

const DEFAULT_MAX_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const MIN_MAX_BUFFER_BYTES: usize = 1024;
const STRL_CANCEL_CHECK_INTERVAL: usize = 1024;
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
            return Err(DtaError::BufferLimitExceeded {
                requested: length,
                limit: self.limit,
            });
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
        values: Vec<String>,
    },
}

/// Destination for typed cells decoded by [`DtaFile`].
///
/// Implementations can retain ordinary Rust vectors, write directly into a
/// foreign column store, or stream values elsewhere. Calls are monomorphized,
/// so the shared decoder does not add a dynamic callback boundary per cell.
/// On a successful read, each selected `(column, row)` pair is written exactly
/// once, rows ascend within each column, and `StrL` pushes are deferred until
/// after all other cells.
pub trait DtaSink: Sized {
    type Output;

    fn push_byte(
        &mut self,
        column: usize,
        row: usize,
        value: i8,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_int(
        &mut self,
        column: usize,
        row: usize,
        value: i16,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_long(
        &mut self,
        column: usize,
        row: usize,
        value: i32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_float(
        &mut self,
        column: usize,
        row: usize,
        value: f32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_double(
        &mut self,
        column: usize,
        row: usize,
        value: f64,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_fixed_string(
        &mut self,
        column: usize,
        row: usize,
        value: String,
    ) -> Result<(), DtaError>;
    fn push_strl(&mut self, column: usize, row: usize, value: &str) -> Result<(), DtaError>;

    fn finish(
        self,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError>;
}

struct VecSink {
    columns: Vec<ColumnBuilder>,
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
            Self::StrL { index, values } => Column {
                variable_index: index,
                values: ColumnValues::StrL { values },
            },
        }
    }
}

impl VecSink {
    fn new(metadata: &DtaMetadata, indices: &[u32], capacity: usize) -> Self {
        let columns = indices
            .iter()
            .map(|index| {
                let variable = &metadata.variables[*index as usize];
                ColumnBuilder::new(*index, &variable.dta_type, capacity)
            })
            .collect();
        Self { columns }
    }

    #[inline(always)]
    fn column(&mut self, index: usize) -> Result<&mut ColumnBuilder, DtaError> {
        self.columns
            .get_mut(index)
            .ok_or(DtaError::ArithmeticOverflow("output column index"))
    }
}

impl DtaSink for VecSink {
    type Output = DtaData;

    #[inline(always)]
    fn push_byte(
        &mut self,
        column: usize,
        _row: usize,
        value: i8,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::Byte {
            values,
            missing_tags,
            ..
        } = self.column(column)?
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    #[inline(always)]
    fn push_int(
        &mut self,
        column: usize,
        _row: usize,
        value: i16,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::Int {
            values,
            missing_tags,
            ..
        } = self.column(column)?
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    #[inline(always)]
    fn push_long(
        &mut self,
        column: usize,
        _row: usize,
        value: i32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::Long {
            values,
            missing_tags,
            ..
        } = self.column(column)?
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    #[inline(always)]
    fn push_float(
        &mut self,
        column: usize,
        _row: usize,
        value: f32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::Float {
            values,
            missing_tags,
            ..
        } = self.column(column)?
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    #[inline(always)]
    fn push_double(
        &mut self,
        column: usize,
        _row: usize,
        value: f64,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::Double {
            values,
            missing_tags,
            ..
        } = self.column(column)?
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    #[inline(always)]
    fn push_fixed_string(
        &mut self,
        column: usize,
        _row: usize,
        value: String,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::FixedString { values, .. } = self.column(column)? else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        Ok(())
    }

    #[inline(always)]
    fn push_strl(&mut self, column: usize, _row: usize, value: &str) -> Result<(), DtaError> {
        let ColumnBuilder::StrL { values, .. } = self.column(column)? else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value.to_owned());
        Ok(())
    }

    fn finish(
        self,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        Ok(DtaData {
            metadata,
            row_start,
            row_count,
            columns: self
                .columns
                .into_iter()
                .map(ColumnBuilder::finish)
                .collect(),
            value_label_tables,
        })
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
    text_encoding: TextEncoding,
}

impl DtaFile<File> {
    /// Open a path and retain the file handle for subsequent projected reads.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, DtaError> {
        Self::open_with_encoding(path, TextEncoding::Auto)
    }

    /// Open a path with an explicit source-text encoding.
    pub fn open_with_encoding(
        path: impl AsRef<Path>,
        encoding: TextEncoding,
    ) -> Result<Self, DtaError> {
        let file = File::open(path).map_err(|error| DtaError::Io {
            context: "opening file",
            offset: 0,
            kind: error.kind(),
        })?;
        Self::from_reader_with_encoding(file, encoding)
    }
}

impl<R: Read + Seek> DtaFile<R> {
    /// Construct a file-backed reader with the default 8 MiB scratch bound.
    pub fn from_reader(reader: R) -> Result<Self, DtaError> {
        Self::from_reader_with_options_and_encoding(
            reader,
            FileOptions::default(),
            TextEncoding::Auto,
        )
    }

    /// Construct a reader with an explicit source-text encoding and the
    /// default 8 MiB scratch bound.
    pub fn from_reader_with_encoding(reader: R, encoding: TextEncoding) -> Result<Self, DtaError> {
        Self::from_reader_with_options_and_encoding(reader, FileOptions::default(), encoding)
    }

    /// Construct a file-backed reader with an explicit scratch-read bound.
    pub fn from_reader_with_options(reader: R, options: FileOptions) -> Result<Self, DtaError> {
        Self::from_reader_with_options_and_encoding(reader, options, TextEncoding::Auto)
    }

    /// Construct a file-backed reader with explicit scratch and source-text
    /// decoding options.
    pub fn from_reader_with_options_and_encoding(
        mut reader: R,
        options: FileOptions,
        encoding: TextEncoding,
    ) -> Result<Self, DtaError> {
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
        let metadata = if matches!(first[0], 105 | 108 | 110 | 111 | 113..=115) {
            read_legacy_metadata(&mut reader, file_length, &mut scratch, encoding)?
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
            read_modern_metadata(&mut reader, file_length, &mut scratch, encoding)?
        };
        if metadata.section_offsets.end_of_file != file_length {
            return Err(DtaError::MapOffsetMismatch {
                section: "file length",
                expected: metadata.section_offsets.end_of_file,
                actual: file_length,
            });
        }
        let text_encoding = encoding.resolve(metadata.format_version);
        Ok(Self {
            reader,
            metadata,
            file_length,
            scratch,
            value_label_tables: None,
            text_encoding,
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
        should_interrupt: F,
    ) -> Result<DtaData, DtaError>
    where
        F: FnMut() -> bool,
    {
        self.read_with_sink_and_interrupt(
            options,
            |metadata, _row_start, row_count, indices| {
                let capacity = usize::try_from(row_count)
                    .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
                Ok(VecSink::new(metadata, indices, capacity))
            },
            should_interrupt,
        )
    }

    /// Decode through a caller-provided typed output collector.
    ///
    /// The collector is constructed after metadata, projection, and row bounds
    /// are resolved but before observation data are read. Both the built-in
    /// [`DtaData`] path and foreign-runtime adapters therefore share the same
    /// validation, I/O, cell decoding, `strL`, and value-label logic.
    pub fn read_with_sink_and_interrupt<S, B, F>(
        &mut self,
        options: &ReadOptions,
        build_sink: B,
        mut should_interrupt: F,
    ) -> Result<S::Output, DtaError>
    where
        S: DtaSink,
        B: FnOnce(&DtaMetadata, u64, u64, &[u32]) -> Result<S, DtaError>,
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
        let mut sink = build_sink(&self.metadata, row_start, row_count, &indices)?;
        let mut strl_pointers = indices
            .iter()
            .map(|index| {
                let variable = &self.metadata.variables[*index as usize];
                if variable.dta_type == DtaType::StrL {
                    Some(Vec::with_capacity(capacity))
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        let payload_start = if self.metadata.format_version.is_modern() {
            checked_add_u64(self.metadata.section_offsets.data, 6, "data payload offset")?
        } else {
            self.metadata.section_offsets.data
        };
        let mut cell_decoder = CellDecoder {
            sink: &mut sink,
            strl_pointers: &mut strl_pointers,
            metadata: &self.metadata,
            text_encoding: self.text_encoding,
        };

        if !indices.is_empty()
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
                    let output_row = usize::try_from(row)
                        .map_err(|_| DtaError::ArithmeticOverflow("output row"))?
                        .checked_add(local_row)
                        .ok_or(DtaError::ArithmeticOverflow("output row"))?;
                    for (output_column, &index) in indices.iter().enumerate() {
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
                        cell_decoder.push_staged_cell(
                            output_column,
                            output_row,
                            cell,
                            absolute_offset,
                            variable,
                        )?;
                    }
                }
                row = row
                    .checked_add(chunk_rows)
                    .ok_or(DtaError::ArithmeticOverflow("projected row"))?;
            }
        } else {
            for row in 0..row_count {
                check_cancel(&mut should_interrupt)?;
                let output_row =
                    usize::try_from(row).map_err(|_| DtaError::ArithmeticOverflow("output row"))?;
                let source_row = row_start
                    .checked_add(row)
                    .ok_or(DtaError::ArithmeticOverflow("source row"))?;
                let row_offset = source_row
                    .checked_mul(self.metadata.obs_length)
                    .ok_or(DtaError::ArithmeticOverflow("row offset"))?;
                for (output_column, &index) in indices.iter().enumerate() {
                    let variable = &self.metadata.variables[index as usize];
                    let cell_offset = payload_start
                        .checked_add(row_offset)
                        .and_then(|value| value.checked_add(variable.byte_offset))
                        .ok_or(DtaError::ArithmeticOverflow("cell offset"))?;
                    let width = usize::try_from(variable.byte_width)
                        .map_err(|_| DtaError::ArithmeticOverflow("cell width"))?;
                    if matches!(variable.dta_type, DtaType::FixedString(_)) {
                        let (value, _) = decode_range(
                            &mut self.reader,
                            cell_offset,
                            width,
                            self.text_encoding,
                            true,
                            &mut self.scratch,
                            &mut should_interrupt,
                            "reading fixed-string observation",
                        )?;
                        cell_decoder
                            .sink
                            .push_fixed_string(output_column, output_row, value)?;
                        continue;
                    }
                    let cell = read_exact_at(
                        &mut self.reader,
                        cell_offset,
                        width,
                        &mut self.scratch,
                        "reading observation cell",
                    )?;
                    cell_decoder.push_cell(
                        output_column,
                        output_row,
                        &cell,
                        cell_offset,
                        &variable.dta_type,
                    )?;
                }
            }
        }
        resolve_file_strls(
            &mut self.reader,
            &self.metadata,
            &mut self.scratch,
            &mut strl_pointers,
            &mut sink,
            &mut should_interrupt,
            self.text_encoding,
        )?;
        check_cancel(&mut should_interrupt)?;
        self.ensure_value_labels(&mut should_interrupt)?;
        let value_label_tables = self
            .value_label_tables
            .clone()
            .expect("value-label cache was initialized");
        sink.finish(
            self.metadata.clone(),
            row_start,
            row_count,
            value_label_tables,
        )
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
            self.text_encoding,
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
    encoding: TextEncoding,
    stop_at_nul: bool,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    context: &'static str,
) -> Result<(String, bool), DtaError> {
    let mut output = String::new();
    let mut decoder = encoding.new_decoder();
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
            let (result, read) = decoder.decode_to_string(&input[consumed..], &mut output, last);
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

#[allow(clippy::too_many_arguments)]
fn decode_range_with_offsets<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    offset: u64,
    length: usize,
    encoding: TextEncoding,
    requested_offsets: &[usize],
    requested_offset_positions: &[usize],
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    context: &'static str,
) -> Result<(String, Vec<usize>), DtaError> {
    if requested_offsets.len() != requested_offset_positions.len() {
        return Err(DtaError::ArithmeticOverflow("value-label offset positions"));
    }
    let mut ordered = requested_offsets
        .iter()
        .copied()
        .enumerate()
        .map(|(index, offset)| (offset, index))
        .collect::<Vec<_>>();
    // Equal raw offsets retain table-entry order so a malformed shared offset
    // reports the same first entry as the slice parser.
    ordered.sort_by_key(|(offset, _)| *offset);
    let mut mapped = vec![0; requested_offsets.len()];
    let mut next_mapping = 0;
    let mut output = String::new();
    let mut decoder = encoding.new_decoder();
    let mut completed = 0_usize;
    let mut first_invalid_boundary: Option<(usize, usize)> = None;

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
        let chunk_end = completed
            .checked_add(chunk_length)
            .ok_or(DtaError::ArithmeticOverflow("string read length"))?;
        let mut input_start = 0;
        while next_mapping < ordered.len() && ordered[next_mapping].0 < chunk_end {
            let boundary = ordered[next_mapping].0;
            let input_end = boundary.saturating_sub(completed).min(bytes.len());
            let original_index = ordered[next_mapping].1;
            if encoding.is_utf8()
                && bytes.get(input_end).is_some_and(|byte| byte & 0xc0 == 0x80)
                && !utf8_file_boundary(reader, offset, length, boundary, scratch, context)?
                && match first_invalid_boundary {
                    Some((index, _)) => original_index < index,
                    None => true,
                }
            {
                first_invalid_boundary = Some((original_index, boundary));
            }
            decode_into_string(
                &mut decoder,
                &bytes[input_start..input_end],
                true,
                &mut output,
            )?;
            input_start = input_end;
            while next_mapping < ordered.len() && ordered[next_mapping].0 == boundary {
                mapped[ordered[next_mapping].1] = output.len();
                next_mapping += 1;
            }
            decoder = encoding.new_decoder();
        }
        let last = chunk_end == length;
        decode_into_string(&mut decoder, &bytes[input_start..], last, &mut output)?;
        completed = chunk_end;
        if last {
            if let Some((entry_index, boundary)) = first_invalid_boundary {
                return Err(DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: requested_offset_positions[entry_index],
                    text_offset: i32::try_from(boundary).unwrap_or(i32::MAX),
                    text_length: length,
                });
            }
            output.shrink_to_fit();
            return Ok((output, mapped));
        }
    }
}

fn utf8_file_boundary<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    length: usize,
    boundary: usize,
    scratch: &mut Scratch,
    context: &'static str,
) -> Result<bool, DtaError> {
    if boundary == 0 || boundary >= length {
        return Ok(true);
    }
    let probe_start = boundary.saturating_sub(3);
    let probe_end = boundary
        .checked_add(4)
        .ok_or(DtaError::ArithmeticOverflow("UTF-8 boundary probe"))?
        .min(length);
    let probe_offset = offset
        .checked_add(
            u64::try_from(probe_start)
                .map_err(|_| DtaError::ArithmeticOverflow("UTF-8 boundary probe"))?,
        )
        .ok_or(DtaError::ArithmeticOverflow("UTF-8 boundary probe"))?;
    let probe = read_exact_at(
        reader,
        probe_offset,
        probe_end - probe_start,
        scratch,
        context,
    )?;
    Ok(is_utf8_boundary(&probe, boundary - probe_start))
}

fn decode_into_string(
    decoder: &mut TextDecoder,
    input: &[u8],
    last: bool,
    output: &mut String,
) -> Result<(), DtaError> {
    let useful_capacity = input
        .len()
        .checked_mul(3)
        .and_then(|value| value.checked_add(3))
        .ok_or(DtaError::ArithmeticOverflow("decoded string capacity"))?;
    output
        .try_reserve(useful_capacity)
        .map_err(|_| DtaError::ArithmeticOverflow("decoded string allocation"))?;
    let mut consumed = 0;
    loop {
        let (result, read) = decoder.decode_to_string(&input[consumed..], output, last);
        consumed = consumed
            .checked_add(read)
            .ok_or(DtaError::ArithmeticOverflow("decoded string input"))?;
        match result {
            CoderResult::InputEmpty => return Ok(()),
            CoderResult::OutputFull => output
                .try_reserve(input.len().saturating_mul(3).max(4))
                .map_err(|_| DtaError::ArithmeticOverflow("decoded string allocation"))?,
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

fn read_modern_notes<R: Read + Seek>(
    reader: &mut R,
    header: &FileModernHeaderMap,
    encoding: TextEncoding,
    scratch: &mut Scratch,
) -> Result<Vec<String>, DtaError> {
    let width = if header.format_version == FormatVersion::V117 {
        33_usize
    } else {
        129_usize
    };
    let names_length = width
        .checked_mul(2)
        .ok_or(DtaError::ArithmeticOverflow("characteristic names length"))?;
    let mut cursor = expect_file_tag(
        reader,
        header.section_offsets.characteristics,
        b"<characteristics>",
        "<characteristics>",
        scratch,
    )?;
    let mut notes = Vec::new();

    loop {
        let marker = read_exact_at(reader, cursor, 4, scratch, "reading characteristic tag")?;
        if marker == b"</ch" {
            cursor = expect_file_tag(
                reader,
                cursor,
                b"</characteristics>",
                "</characteristics>",
                scratch,
            )?;
            ensure_absolute("data", cursor, header.section_offsets.data)?;
            return Ok(notes);
        }
        if marker != b"<ch>" {
            return Err(DtaError::UnexpectedTag {
                expected: "<ch> or </characteristics>",
                offset: error_offset(cursor),
            });
        }
        cursor = checked_add_u64(cursor, 4, "characteristic opening tag")?;
        let length_bytes =
            read_exact_at(reader, cursor, 4, scratch, "reading characteristic length")?;
        let payload_length = usize::try_from(read_u32(
            &length_bytes,
            0,
            header.byte_order,
            "characteristic length",
        )?)
        .map_err(|_| DtaError::ArithmeticOverflow("characteristic length"))?;
        cursor = checked_add_u64(cursor, 4, "characteristic length")?;
        if payload_length < names_length {
            return Err(DtaError::Truncated {
                context: "characteristic names",
                offset: error_offset(cursor),
                needed: names_length,
                available: payload_length,
            });
        }
        let close = checked_add_u64(
            cursor,
            u64::try_from(payload_length)
                .map_err(|_| DtaError::ArithmeticOverflow("characteristic payload length"))?,
            "characteristic payload",
        )?;
        let after_close = checked_add_u64(close, 5, "characteristic closing tag")?;
        if after_close > header.section_offsets.data {
            return Err(DtaError::Truncated {
                context: "characteristic payload",
                offset: error_offset(cursor),
                needed: payload_length.saturating_add(5),
                available: usize::try_from(header.section_offsets.data.saturating_sub(cursor))
                    .unwrap_or(usize::MAX),
            });
        }
        let names = read_exact_at(
            reader,
            cursor,
            names_length,
            scratch,
            "reading characteristic names",
        )?;
        if is_dataset_note(&names[..width], &names[width..]) {
            let value_offset = checked_add_u64(
                cursor,
                u64::try_from(names_length)
                    .map_err(|_| DtaError::ArithmeticOverflow("characteristic value offset"))?,
                "characteristic value offset",
            )?;
            let value_length = payload_length - names_length;
            let mut never_cancel = || false;
            let note = decode_range(
                reader,
                value_offset,
                value_length,
                encoding,
                true,
                scratch,
                &mut never_cancel,
                "reading characteristic value",
            )?
            .0;
            if !note.is_empty() {
                notes.push(note);
            }
        }
        cursor = expect_file_tag(reader, close, b"</ch>", "</ch>", scratch)?;
    }
}

fn read_modern_header_map<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
    encoding: TextEncoding,
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
    let encoding = encoding.resolve(format_version);
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
        encoding,
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
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    let header = read_modern_header_map(reader, scratch, encoding)?;
    let encoding = encoding.resolve(header.format_version);
    if header.section_offsets.end_of_file > file_length
        && file_length >= header.section_offsets.stata_data_close
    {
        return Err(DtaError::Truncated {
            context: "</stata_dta>",
            offset: error_offset(header.section_offsets.stata_data_close),
            needed: 12,
            available: usize::try_from(
                file_length.saturating_sub(header.section_offsets.stata_data_close),
            )
            .unwrap_or(usize::MAX),
        });
    }
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
    let notes = read_modern_notes(reader, &header, encoding, scratch)?;

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
                encoding,
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
        notes,
        variables,
        section_offsets: header.section_offsets,
        obs_length: byte_offset,
    })
}

fn read_legacy_metadata<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    let release = read_exact_at(reader, 0, 1, scratch, "reading legacy release")?[0];
    let version = FormatVersion::try_from(u16::from(release))
        .map_err(|_| DtaError::InvalidRelease(release.to_string()))?;
    let layout = LegacyLayout::for_version(version);
    let header = read_exact_at(
        reader,
        0,
        layout.header_size,
        scratch,
        "reading legacy header",
    )?;
    let encoding = encoding.resolve(version);
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
    let fixed = legacy_fixed_offsets(nvar_usize, version)?;
    let fixed_end = fixed.end;
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

    let to_u64 = |offset: usize, context: &'static str| {
        u64::try_from(offset).map_err(|_| DtaError::ArithmeticOverflow(context))
    };
    let variable_types = to_u64(fixed.variable_types, "legacy variable_types offset")?;
    let varnames = to_u64(fixed.varnames, "legacy varnames offset")?;
    let sortlist = to_u64(fixed.sortlist, "legacy sortlist offset")?;
    let formats = to_u64(fixed.formats, "legacy formats offset")?;
    let value_label_names = to_u64(fixed.value_label_names, "legacy value_label_names offset")?;
    let variable_labels = to_u64(fixed.variable_labels, "legacy variable_labels offset")?;

    let mut never_cancel = || false;
    let dataset_label = decode_range(
        reader,
        10,
        layout.dataset_label_width,
        encoding,
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
                encoding,
                true,
                scratch,
                &mut never_cancel,
                context,
            )
            .map(|value| value.0)
        };
        let name = decode_field(varnames, layout.varname_width, "reading legacy varname")?;
        let format = decode_field(
            formats,
            layout.format_width,
            "reading legacy display format",
        )?;
        let value_label_name = decode_field(
            value_label_names,
            layout.value_label_name_width,
            "reading legacy value-label name",
        )?;
        let label = decode_field(
            variable_labels,
            layout.variable_label_width,
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
    let mut notes = Vec::new();
    loop {
        let expansion = read_exact_at(
            reader,
            cursor,
            layout.expansion_header_width(),
            scratch,
            "reading legacy expansion field",
        )?;
        let data_type = expansion[0];
        let length = if layout.expansion_length_width == 2 {
            i32::from(read_i16(
                &expansion,
                1,
                byte_order,
                "legacy expansion-field length",
            )?)
        } else {
            read_i32(&expansion, 1, byte_order, "legacy expansion-field length")?
        };
        if data_type == 0 && length == 0 {
            cursor = checked_add_u64(
                cursor,
                layout.expansion_header_width() as u64,
                "legacy expansion terminator",
            )?;
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
        cursor = checked_add_u64(
            cursor,
            layout.expansion_header_width() as u64,
            "legacy expansion header",
        )?;
        let payload_length = usize::try_from(length)
            .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion length"))?;
        let payload_end = checked_add_u64(
            cursor,
            u64::try_from(payload_length)
                .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion length"))?,
            "legacy expansion payload",
        )?;
        if payload_end > file_length {
            return Err(DtaError::Truncated {
                context: "legacy expansion-field payload",
                offset: error_offset(cursor),
                needed: payload_length,
                available: usize::try_from(file_length.saturating_sub(cursor))
                    .unwrap_or(usize::MAX),
            });
        }
        if data_type == 1 && payload_length >= 2 * layout.varname_width {
            let names = read_exact_at(
                reader,
                cursor,
                2 * layout.varname_width,
                scratch,
                "reading legacy characteristic names",
            )?;
            if is_dataset_note(
                &names[..layout.varname_width],
                &names[layout.varname_width..],
            ) {
                let value_offset = checked_add_u64(
                    cursor,
                    u64::try_from(2 * layout.varname_width).map_err(|_| {
                        DtaError::ArithmeticOverflow("legacy characteristic value offset")
                    })?,
                    "legacy characteristic value offset",
                )?;
                let value_length = payload_length - 2 * layout.varname_width;
                let note = decode_range(
                    reader,
                    value_offset,
                    value_length,
                    encoding,
                    true,
                    scratch,
                    &mut never_cancel,
                    "reading legacy characteristic value",
                )?
                .0;
                if !note.is_empty() {
                    notes.push(note);
                }
            }
        }
        cursor = payload_end;
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
        notes,
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

fn remaining_is_zero_padding<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    start: u64,
    end: u64,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
) -> Result<bool, DtaError> {
    let mut cursor = start;
    while cursor < end {
        check_cancel(should_interrupt)?;
        let remaining = end - cursor;
        let length = usize::try_from(remaining.min(scratch.limit as u64))
            .map_err(|_| DtaError::ArithmeticOverflow("value-label trailing bytes"))?;
        let bytes = read_exact_at(
            reader,
            cursor,
            length,
            scratch,
            "reading value-label trailing bytes",
        )?;
        if bytes.iter().any(|byte| *byte != 0) {
            return Ok(false);
        }
        cursor = checked_add_u64(
            cursor,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label trailing bytes"))?,
            "value-label trailing bytes",
        )?;
    }
    Ok(true)
}

fn read_fixed8_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    const NAME_WIDTH: usize = 9;
    const PADDING_WIDTH: usize = 1;
    const LABEL_WIDTH: usize = 8;

    let section_end = metadata.section_offsets.end_of_file;
    let mut cursor = metadata.section_offsets.value_labels;
    let mut tables = Vec::new();
    while cursor < section_end {
        check_cancel(should_interrupt)?;
        if remaining_is_zero_padding(reader, cursor, section_end, scratch, should_interrupt)? {
            cursor = section_end;
            break;
        }
        let count_bytes = read_exact_at(
            reader,
            cursor,
            2,
            scratch,
            "reading legacy value-label entry count",
        )?;
        let entry_count = usize::from(read_u16(
            &count_bytes,
            0,
            metadata.byte_order,
            "legacy value-label entry count",
        )?);
        cursor = checked_add_u64(cursor, 2, "legacy value-label entry count")?;
        let (name, _) = decode_range(
            reader,
            cursor,
            NAME_WIDTH,
            encoding,
            true,
            scratch,
            should_interrupt,
            "reading legacy value-label table name",
        )?;
        cursor = checked_add_u64(cursor, NAME_WIDTH as u64, "legacy value-label table name")?;
        read_exact_at(
            reader,
            cursor,
            PADDING_WIDTH,
            scratch,
            "reading legacy value-label padding",
        )?;
        cursor = checked_add_u64(cursor, PADDING_WIDTH as u64, "legacy value-label padding")?;
        let values_start = cursor;
        let labels_start = checked_add_u64(
            values_start,
            u64::try_from(
                entry_count
                    .checked_mul(2)
                    .ok_or(DtaError::ArithmeticOverflow("legacy value-label values"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label values"))?,
            "legacy value-label labels",
        )?;
        let table_end = checked_add_u64(
            labels_start,
            u64::try_from(
                entry_count
                    .checked_mul(LABEL_WIDTH)
                    .ok_or(DtaError::ArithmeticOverflow("legacy value-label labels"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label labels"))?,
            "legacy value-label table",
        )?;
        if table_end > section_end {
            return Err(DtaError::Io {
                context: "reading legacy value-label table",
                offset: values_start,
                kind: ErrorKind::UnexpectedEof,
            });
        }
        let mut entries = Vec::with_capacity(entry_count);
        for entry_index in 0..entry_count {
            check_cancel(should_interrupt)?;
            let relative = u64::try_from(
                entry_index
                    .checked_mul(2)
                    .ok_or(DtaError::ArithmeticOverflow("legacy value-label value"))?,
            )
            .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label value"))?;
            let value_bytes = read_exact_at(
                reader,
                checked_add_u64(values_start, relative, "legacy value-label value")?,
                2,
                scratch,
                "reading legacy value-label value",
            )?;
            let value = i32::from(read_i16(
                &value_bytes,
                0,
                metadata.byte_order,
                "legacy value-label value",
            )?);
            let label_offset = checked_add_u64(
                labels_start,
                u64::try_from(
                    entry_index
                        .checked_mul(LABEL_WIDTH)
                        .ok_or(DtaError::ArithmeticOverflow("legacy value-label text"))?,
                )
                .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label text"))?,
                "legacy value-label text",
            )?;
            let (label, _) = decode_range(
                reader,
                label_offset,
                LABEL_WIDTH,
                encoding,
                true,
                scratch,
                should_interrupt,
                "reading legacy value-label text",
            )?;
            entries.push(ValueLabelEntry {
                value,
                missing_tag: classify_long_missing_for_version(value, metadata.format_version),
                label,
            });
        }
        tables.push(ValueLabelTable { name, entries });
        cursor = table_end;
    }
    ensure_absolute("end_of_file", cursor, section_end)?;
    Ok(tables)
}

fn read_offset_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
    legacy_name_width: usize,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    const RESERVED_WIDTH: usize = 3;
    let modern = metadata.format_version.is_modern();
    let name_width = if modern {
        match metadata.format_version {
            FormatVersion::V117 => 33_u16,
            FormatVersion::V118 | FormatVersion::V119 => 129_u16,
            _ => unreachable!("modern release expected"),
        }
    } else {
        u16::try_from(legacy_name_width)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label table name width"))?
    };
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
        if !modern
            && remaining_is_zero_padding(reader, cursor, section_end, scratch, should_interrupt)?
        {
            cursor = section_end;
            break;
        }
        let table_start = cursor;
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
            usize::from(name_width),
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
        cursor = checked_add_u64(cursor, u64::from(name_width), "value-label table name")?;
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
        let mut text_offsets = Vec::with_capacity(entry_count);
        let mut text_offset_positions = Vec::with_capacity(entry_count);
        let mut values = Vec::with_capacity(entry_count);
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
            text_offsets.push(text_offset_usize);
            text_offset_positions.push(error_offset(offset_position));
            values.push(value);
        }
        let (decoded_text, decoded_offsets) = decode_range_with_offsets(
            reader,
            text_start,
            text_length,
            encoding,
            &text_offsets,
            &text_offset_positions,
            scratch,
            should_interrupt,
            "reading value-label text",
        )?;
        let mut entries = Vec::with_capacity(entry_count);
        for (entry_index, ((value, text_offset), decoded_offset)) in values
            .into_iter()
            .zip(text_offsets)
            .zip(decoded_offsets)
            .enumerate()
        {
            check_cancel(should_interrupt)?;
            let label_start = checked_add_u64(
                text_start,
                u64::try_from(text_offset)
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label text offset"))?,
                "value-label text offset",
            )?;
            let suffix = decoded_text.get(decoded_offset..).ok_or(
                DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: error_offset(label_start),
                    text_offset: i32::try_from(text_offset).unwrap_or(i32::MAX),
                    text_length,
                },
            )?;
            let Some(nul) = suffix.find('\0') else {
                return Err(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: error_offset(label_start),
                });
            };
            let mut label = suffix[..nul].to_owned();
            label.shrink_to_fit();
            entries.push(ValueLabelEntry {
                value,
                missing_tag: classify_long_missing_for_version(value, metadata.format_version),
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

fn select_legacy_value_label_layout<R: Read + Seek>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
) -> Result<(LegacyValueLabelLayout, usize), DtaError> {
    let layout = LegacyLayout::for_version(metadata.format_version);
    if !matches!(
        metadata.format_version,
        FormatVersion::V105 | FormatVersion::V108
    ) {
        return Ok((
            layout.value_label_layout,
            layout.value_label_table_name_width,
        ));
    }
    let section_length = metadata
        .section_offsets
        .end_of_file
        .checked_sub(metadata.section_offsets.value_labels)
        .ok_or(DtaError::ArithmeticOverflow("value-label section length"))?;
    let section_length = usize::try_from(section_length)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label section length"))?;
    let probe_length = section_length.min(4 + 33 + 3 + 8);
    let probe = read_exact_at(
        reader,
        metadata.section_offsets.value_labels,
        probe_length,
        scratch,
        "probing legacy value-label layout",
    )?;
    let short_framing =
        has_legacy_offset_table_framing(&probe, metadata.byte_order, section_length, 9);
    let long_framing =
        has_legacy_offset_table_framing(&probe, metadata.byte_order, section_length, 33);
    Ok(match metadata.format_version {
        FormatVersion::V105 if long_framing => (LegacyValueLabelLayout::OffsetTable, 33),
        FormatVersion::V105 => (LegacyValueLabelLayout::Fixed8, 9),
        FormatVersion::V108 if !short_framing && long_framing => {
            (LegacyValueLabelLayout::OffsetTable, 33)
        }
        _ => (
            layout.value_label_layout,
            layout.value_label_table_name_width,
        ),
    })
}

fn read_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    if metadata.format_version.is_modern() {
        return read_offset_value_labels_streaming(
            reader,
            metadata,
            scratch,
            should_interrupt,
            encoding,
            0,
        );
    }
    let (value_label_layout, table_name_width) =
        select_legacy_value_label_layout(reader, metadata, scratch)?;
    match value_label_layout {
        LegacyValueLabelLayout::Fixed8 => read_fixed8_value_labels_streaming(
            reader,
            metadata,
            scratch,
            should_interrupt,
            encoding,
        ),
        LegacyValueLabelLayout::OffsetTable => read_offset_value_labels_streaming(
            reader,
            metadata,
            scratch,
            should_interrupt,
            encoding,
            table_name_width,
        ),
    }
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
    let bytes = bytes.get(..8).ok_or(DtaError::Truncated {
        context: "strL pointer",
        offset: error_offset(offset),
        needed: 8,
        available: bytes.len(),
    })?;
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

struct CellDecoder<'a, S> {
    sink: &'a mut S,
    strl_pointers: &'a mut [Option<Vec<Option<FileGsoKey>>>],
    metadata: &'a DtaMetadata,
    text_encoding: TextEncoding,
}

impl<S: DtaSink> CellDecoder<'_, S> {
    #[inline(always)]
    fn push_staged_cell(
        &mut self,
        output_column: usize,
        output_row: usize,
        cell: &[u8],
        absolute_offset: u64,
        variable: &VariableInfo,
    ) -> Result<(), DtaError> {
        if matches!(variable.dta_type, DtaType::FixedString(_)) {
            let mut value = self.text_encoding.decode(field_bytes(cell));
            value.shrink_to_fit();
            return self
                .sink
                .push_fixed_string(output_column, output_row, value);
        }
        self.push_cell(
            output_column,
            output_row,
            cell,
            absolute_offset,
            &variable.dta_type,
        )
    }

    #[inline(always)]
    fn push_cell(
        &mut self,
        output_column: usize,
        output_row: usize,
        cell: &[u8],
        absolute_offset: u64,
        dta_type: &DtaType,
    ) -> Result<(), DtaError> {
        match dta_type {
            DtaType::Byte => {
                let value = read_i8(cell, 0, "byte observation")?;
                self.sink.push_byte(
                    output_column,
                    output_row,
                    value,
                    classify_byte_missing_for_version(value, self.metadata.format_version),
                )?;
            }
            DtaType::Int => {
                let value = read_i16(cell, 0, self.metadata.byte_order, "int observation")?;
                self.sink.push_int(
                    output_column,
                    output_row,
                    value,
                    classify_int_missing_for_version(value, self.metadata.format_version),
                )?;
            }
            DtaType::Long => {
                let value = read_i32(cell, 0, self.metadata.byte_order, "long observation")?;
                self.sink.push_long(
                    output_column,
                    output_row,
                    value,
                    classify_long_missing_for_version(value, self.metadata.format_version),
                )?;
            }
            DtaType::Float => {
                let bits = read_u32(cell, 0, self.metadata.byte_order, "float observation")?;
                self.sink.push_float(
                    output_column,
                    output_row,
                    f32::from_bits(bits),
                    classify_float_missing_bits_for_version(bits, self.metadata.format_version),
                )?;
            }
            DtaType::Double => {
                let bits = read_u64(cell, 0, self.metadata.byte_order, "double observation")?;
                self.sink.push_double(
                    output_column,
                    output_row,
                    f64::from_bits(bits),
                    classify_double_missing_bits_for_version(bits, self.metadata.format_version),
                )?;
            }
            DtaType::FixedString(_) => {
                return Err(DtaError::ArithmeticOverflow("fixed string streaming path"));
            }
            DtaType::StrL => {
                let pointers = self
                    .strl_pointers
                    .get_mut(output_column)
                    .and_then(Option::as_mut)
                    .ok_or(DtaError::ArithmeticOverflow("strL output column"))?;
                pointers.push(parse_pointer(cell, absolute_offset, self.metadata)?);
            }
        }
        Ok(())
    }
}

fn resolve_file_strls<R: Read + Seek, F: FnMut() -> bool, S: DtaSink>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    pointers: &mut [Option<Vec<Option<FileGsoKey>>>],
    sink: &mut S,
    should_interrupt: &mut F,
    encoding: TextEncoding,
) -> Result<(), DtaError> {
    if !pointers.iter().any(Option::is_some) {
        return Ok(());
    }
    let requested = pointers
        .iter()
        .filter_map(Option::as_ref)
        .flat_map(|column| column.iter().flatten().copied())
        .collect::<HashSet<_>>();

    let mut entries = HashMap::new();
    let mut seen = HashSet::new();
    let mut cursor = checked_add_u64(metadata.section_offsets.strls, 7, "GSO section start")?;
    let end = metadata
        .section_offsets
        .value_labels
        .checked_sub(8)
        .ok_or(DtaError::ArithmeticOverflow("GSO section end"))?;
    let header_length = if metadata.format_version == FormatVersion::V117 {
        16
    } else {
        20
    };
    while cursor < end {
        check_cancel(should_interrupt)?;
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

    materialize_file_strls(
        reader,
        scratch,
        &entries,
        pointers,
        sink,
        should_interrupt,
        encoding,
    )
}

fn materialize_file_strls<R: Read + Seek, F: FnMut() -> bool, S: DtaSink>(
    reader: &mut R,
    scratch: &mut Scratch,
    entries: &HashMap<FileGsoKey, FileGsoEntry>,
    pointers: &mut [Option<Vec<Option<FileGsoKey>>>],
    sink: &mut S,
    should_interrupt: &mut F,
    encoding: TextEncoding,
) -> Result<(), DtaError> {
    let mut decoded = HashMap::<FileGsoKey, String>::new();
    let mut pointer_count = 0_usize;
    for (column_index, column_pointers) in pointers.iter_mut().enumerate() {
        let Some(column_pointers) = column_pointers else {
            continue;
        };
        for (row_index, pointer) in column_pointers.iter().copied().enumerate() {
            if pointer_count % STRL_CANCEL_CHECK_INTERVAL == 0 {
                check_cancel(should_interrupt)?;
            }
            pointer_count = pointer_count
                .checked_add(1)
                .ok_or(DtaError::ArithmeticOverflow("strL pointer count"))?;
            let Some(key) = pointer else {
                sink.push_strl(column_index, row_index, "")?;
                continue;
            };
            if let Some(value) = decoded.get(&key) {
                sink.push_strl(column_index, row_index, value)?;
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
                encoding,
                false,
                scratch,
                should_interrupt,
                "reading selected GSO content",
            )?
            .0;
            sink.push_strl(column_index, row_index, &value)?;
            decoded.insert(key, value);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn short_strl_pointer_cells_return_a_truncation_error() {
        let metadata = DtaMetadata {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 1,
            nobs: 1,
            dataset_label: String::new(),
            notes: Vec::new(),
            variables: vec![VariableInfo {
                name: "text".to_owned(),
                dta_type: DtaType::StrL,
                type_code: 32_768,
                format: "%9s".to_owned(),
                label: String::new(),
                value_label_name: String::new(),
                byte_width: 8,
                byte_offset: 0,
            }],
            section_offsets: SectionOffsets::from_array([0; 14]),
            obs_length: 8,
        };
        assert_eq!(
            parse_pointer(&[0; 7], 42, &metadata),
            Err(DtaError::Truncated {
                context: "strL pointer",
                offset: 42,
                needed: 8,
                available: 7,
            })
        );
    }

    #[test]
    fn scratch_limit_has_a_dedicated_error() {
        let mut scratch = Scratch::new(1024);
        assert_eq!(
            scratch.record(1025),
            Err(DtaError::BufferLimitExceeded {
                requested: 1025,
                limit: 1024,
            })
        );
    }

    #[test]
    fn strl_materialization_polls_during_long_null_and_cache_hit_runs() {
        let pointer_count = STRL_CANCEL_CHECK_INTERVAL * 3;
        let mut null_pointers = vec![Some(vec![None; pointer_count])];
        let mut null_sink = VecSink {
            columns: vec![ColumnBuilder::StrL {
                index: 0,
                values: Vec::with_capacity(pointer_count),
            }],
        };
        let mut null_checks = 0;
        assert_eq!(
            materialize_file_strls(
                &mut Cursor::new(Vec::<u8>::new()),
                &mut Scratch::new(1024),
                &HashMap::new(),
                &mut null_pointers,
                &mut null_sink,
                &mut || {
                    null_checks += 1;
                    null_checks >= 2
                },
                TextEncoding::Utf8,
            ),
            Err(DtaError::Cancelled)
        );
        let ColumnBuilder::StrL { values, .. } = &null_sink.columns[0] else {
            unreachable!()
        };
        assert_eq!(values.len(), STRL_CANCEL_CHECK_INTERVAL);

        let key = FileGsoKey {
            variable: 1,
            observation: 1,
        };
        let entries = HashMap::from([(
            key,
            FileGsoEntry {
                content_offset: 0,
                content_length: 2,
                gso_type: 130,
            },
        )]);
        let mut repeated_pointers = vec![Some(vec![Some(key); pointer_count])];
        let mut repeated_sink = VecSink {
            columns: vec![ColumnBuilder::StrL {
                index: 0,
                values: Vec::with_capacity(pointer_count),
            }],
        };
        let mut repeated_checks = 0;
        assert_eq!(
            materialize_file_strls(
                &mut Cursor::new(b"x\0".to_vec()),
                &mut Scratch::new(1024),
                &entries,
                &mut repeated_pointers,
                &mut repeated_sink,
                &mut || {
                    repeated_checks += 1;
                    repeated_checks >= 4
                },
                TextEncoding::Utf8,
            ),
            Err(DtaError::Cancelled)
        );
        let ColumnBuilder::StrL { values, .. } = &repeated_sink.columns[0] else {
            unreachable!()
        };
        assert_eq!(values.len(), STRL_CANCEL_CHECK_INTERVAL);
        assert!(values.iter().all(|value| value == "x"));
    }
}
