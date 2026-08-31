use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{ErrorKind, Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::{mpsc::sync_channel, Arc};
use std::thread;

use encoding_rs::CoderResult;

use crate::endian::{read_i16, read_i32, read_i8, read_u16, read_u32, read_u64};
use crate::legacy::{legacy_fixed_offsets, legacy_type, LegacyLayout, LegacyValueLabelLayout};
use crate::metadata::{field_widths, resolve_type};
use crate::selection::{resolve_columns, row_window};
use crate::stata_metadata::{
    validate_raw_value_bytes, validate_raw_value_length, CharacteristicPlan,
    CharacteristicValueUse, DecodedCharacteristics, VariableTargetIndexes,
    MAX_METADATA_VALUE_BYTES,
};
use crate::text::{field_bytes, is_utf8_boundary, TextDecoder, TextEncoding};
use crate::value_labels::{frame_offset_value_label_payload, has_legacy_offset_table_framing};
use crate::{
    missing::{
        classify_byte_missing_for_version, classify_double_missing_bits_for_version,
        classify_float_missing_bits_for_version, classify_int_missing_for_version,
        classify_long_missing_for_version,
    },
    ByteOrder, Column, ColumnValues, DtaData, DtaError, DtaMetadata, DtaType, FormatVersion,
    ReadOptions, SectionOffsets, ValueLabelEntry, ValueLabelTable, VariableInfo,
};

fn selected_value_label_names(metadata: &DtaMetadata, indices: &[u32]) -> HashSet<String> {
    indices
        .iter()
        .filter_map(|&index| {
            let name = &metadata.variables.get(index as usize)?.value_label_name;
            (!name.is_empty()).then(|| name.clone())
        })
        .collect()
}

#[derive(Debug, Clone, Copy)]
enum IndexedValueLabelLayout {
    Fixed8,
    OffsetTable { legacy_name_width: usize },
}

#[derive(Debug, Clone)]
struct ValueLabelLocation {
    name: Arc<str>,
    start: u64,
    end: u64,
}

#[derive(Debug)]
struct IndexedValueLabelCache {
    layout: IndexedValueLabelLayout,
    locations: Vec<ValueLabelLocation>,
    indices_by_name: HashMap<Arc<str>, Vec<usize>>,
    tables: HashMap<usize, ValueLabelTable>,
}

#[derive(Debug)]
struct FullValueLabelCache {
    tables: Vec<ValueLabelTable>,
    indices_by_name: HashMap<Arc<str>, Vec<usize>>,
}

#[cfg(test)]
fn index_value_label_locations(locations: &[ValueLabelLocation]) -> HashMap<Arc<str>, Vec<usize>> {
    let mut indices_by_name = HashMap::<Arc<str>, Vec<usize>>::new();
    for (index, location) in locations.iter().enumerate() {
        indices_by_name
            .entry(Arc::clone(&location.name))
            .or_default()
            .push(index);
    }
    indices_by_name
}

fn selected_value_label_location_indices(
    indices_by_name: &HashMap<Arc<str>, Vec<usize>>,
    selected: &HashSet<String>,
) -> Result<Vec<usize>, DtaError> {
    let selected_count = selected
        .iter()
        .filter_map(|name| indices_by_name.get(name.as_str()))
        .map(Vec::len)
        .sum();
    let mut indices = Vec::new();
    indices
        .try_reserve_exact(selected_count)
        .map_err(|_| DtaError::ArithmeticOverflow("selected value-label index allocation"))?;
    for name in selected {
        if let Some(named_indices) = indices_by_name.get(name.as_str()) {
            indices.extend_from_slice(named_indices);
        }
    }
    indices.sort_unstable();
    Ok(indices)
}

fn index_value_label_tables(tables: &[ValueLabelTable]) -> HashMap<Arc<str>, Vec<usize>> {
    let mut indices_by_name = HashMap::<Arc<str>, Vec<usize>>::new();
    for (index, table) in tables.iter().enumerate() {
        if let Some(indices) = indices_by_name.get_mut(table.name.as_str()) {
            indices.push(index);
        } else {
            indices_by_name.insert(Arc::from(table.name.as_str()), vec![index]);
        }
    }
    indices_by_name
}

#[derive(Debug)]
enum ValueLabelCache {
    Empty,
    Indexed(IndexedValueLabelCache),
    Full(FullValueLabelCache),
}

// Small tables remain cached so repeated projections avoid source I/O. Large
// tables move into owning sinks, avoiding a second large allocation while the
// reader and result coexist.
const VALUE_LABEL_MOVE_THRESHOLD_BYTES: usize = 64 * 1024;

fn accumulate_value_label_table_heap_bytes<F: FnMut()>(
    table: &ValueLabelTable,
    bytes: &mut usize,
    mut visited_entry: F,
) -> bool {
    *bytes = bytes.saturating_add(table.name.len());
    if *bytes >= VALUE_LABEL_MOVE_THRESHOLD_BYTES {
        return true;
    }
    for entry in &table.entries {
        visited_entry();
        *bytes = bytes
            .saturating_add(std::mem::size_of::<ValueLabelEntry>())
            .saturating_add(entry.label.len());
        if *bytes >= VALUE_LABEL_MOVE_THRESHOLD_BYTES {
            return true;
        }
    }
    false
}

fn value_label_table_should_move(table: &ValueLabelTable) -> bool {
    let mut bytes = 0;
    accumulate_value_label_table_heap_bytes(table, &mut bytes, || {})
}

fn take_projected_tables(
    value_labels: &mut ValueLabelCache,
    indices: &[usize],
) -> Result<Vec<ValueLabelTable>, DtaError> {
    let mut selected = Vec::new();
    selected
        .try_reserve_exact(indices.len())
        .map_err(|_| DtaError::ArithmeticOverflow("projected value-label allocation"))?;
    match value_labels {
        ValueLabelCache::Indexed(cache) => {
            for index in indices {
                selected.push(
                    cache
                        .tables
                        .remove(index)
                        .expect("selected value-label table was cached"),
                );
            }
        }
        ValueLabelCache::Full(_) => {
            let ValueLabelCache::Full(cache) =
                std::mem::replace(value_labels, ValueLabelCache::Empty)
            else {
                unreachable!()
            };
            let mut next = indices.iter().copied().peekable();
            for (index, table) in cache.tables.into_iter().enumerate() {
                if next.peek() == Some(&index) {
                    selected.push(table);
                    next.next();
                }
            }
            debug_assert!(next.next().is_none());
        }
        ValueLabelCache::Empty => unreachable!("value-label cache was initialized"),
    }
    Ok(selected)
}

enum ValueLabelStreamingMode<'a> {
    Full,
    Projected {
        selected: &'a HashSet<String>,
        locations: &'a mut Vec<ValueLabelLocation>,
        indices_by_name: &'a mut HashMap<Arc<str>, Vec<usize>>,
    },
    Indexed {
        range: (u64, u64),
    },
}

impl ValueLabelStreamingMode<'_> {
    fn section_range(&self, full: (u64, u64)) -> (u64, u64) {
        match self {
            Self::Indexed { range } => *range,
            Self::Full | Self::Projected { .. } => full,
        }
    }

    fn scans_section(&self) -> bool {
        !matches!(self, Self::Indexed { .. })
    }

    fn retains(&self, name: &str) -> bool {
        match self {
            Self::Projected { selected, .. } => selected.contains(name),
            Self::Full | Self::Indexed { .. } => true,
        }
    }

    fn record_location(&mut self, name: &str, start: u64, end: u64) {
        match self {
            Self::Projected {
                locations,
                indices_by_name,
                ..
            } => {
                let index = locations.len();
                let shared_name = indices_by_name
                    .get_key_value(name)
                    .map_or_else(|| Arc::<str>::from(name), |(stored, _)| Arc::clone(stored));
                indices_by_name
                    .entry(Arc::clone(&shared_name))
                    .or_default()
                    .push(index);
                locations.push(ValueLabelLocation {
                    name: shared_name,
                    start,
                    end,
                });
            }
            Self::Full | Self::Indexed { .. } => {}
        }
    }
}

const DEFAULT_MAX_BUFFER_BYTES: usize = 8 * 1024 * 1024;
const METADATA_SECTION_BUFFER_BYTES: usize = 64 * 1024;
const MIN_MAX_BUFFER_BYTES: usize = 1024;
const STRL_CANCEL_CHECK_INTERVAL: usize = 1024;
const COLUMNAR_CANCEL_CHECK_INTERVAL: usize = 16_384;
const MIN_PARALLEL_DATA_BYTES: u64 = 16 * 1024 * 1024;
const MIN_PARALLEL_CELLS: u64 = 1_000_000;
const MAX_AUTOMATIC_THREADS: usize = 8;
const MODERN_SIGNATURE: &[u8] = b"<stata_dta><header><release>";

fn automatic_parallel_workload(selected_bytes: u64, cells: u64) -> bool {
    selected_bytes >= MIN_PARALLEL_DATA_BYTES || cells >= MIN_PARALLEL_CELLS
}

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

#[derive(Debug, Clone, Copy)]
struct FileTextRange {
    offset: u64,
    length: usize,
}

struct FileModernHeaderMap {
    format_version: FormatVersion,
    byte_order: ByteOrder,
    nvar: u32,
    nobs: u64,
    dataset_label: FileTextRange,
    section_offsets: SectionOffsets,
}

struct ParsedSchemaVariable {
    name: String,
    dta_type: DtaType,
    type_code: u16,
    byte_width: u32,
    byte_offset: u64,
}

struct ParsedSchema {
    format_version: FormatVersion,
    variables: Vec<ParsedSchemaVariable>,
    obs_length: u64,
}

impl ParsedSchema {
    fn into_summary(self) -> DtaSchemaSummary {
        DtaSchemaSummary {
            format_version: self.format_version,
            variables: self
                .variables
                .into_iter()
                .map(|variable| DtaSchemaVariable {
                    name: variable.name,
                    dta_type: variable.dta_type,
                })
                .collect(),
        }
    }

    fn into_variables(
        self,
        formats: Vec<String>,
        value_label_names: Vec<String>,
        labels: Vec<String>,
    ) -> Result<(Vec<VariableInfo>, u64), DtaError> {
        let count = self.variables.len();
        if formats.len() != count || value_label_names.len() != count || labels.len() != count {
            return Err(DtaError::ArithmeticOverflow("metadata schema field count"));
        }
        let mut variables = Vec::new();
        variables
            .try_reserve_exact(count)
            .map_err(|_| DtaError::ArithmeticOverflow("metadata variables"))?;
        for (((schema, format), value_label_name), label) in self
            .variables
            .into_iter()
            .zip(formats)
            .zip(value_label_names)
            .zip(labels)
        {
            variables.push(VariableInfo {
                name: schema.name,
                dta_type: schema.dta_type,
                type_code: schema.type_code,
                format,
                label,
                value_label_name,
                notes: Vec::new(),
                characteristics: Vec::new(),
                byte_width: schema.byte_width,
                byte_offset: schema.byte_offset,
            });
        }
        Ok((variables, self.obs_length))
    }
}

fn build_parsed_schema<F>(
    format_version: FormatVersion,
    type_codes: Vec<u16>,
    names: Vec<String>,
    mut resolve: F,
) -> Result<ParsedSchema, DtaError>
where
    F: FnMut(u16) -> Result<(DtaType, u32), DtaError>,
{
    if type_codes.len() != names.len() {
        return Err(DtaError::ArithmeticOverflow("metadata schema field count"));
    }
    let mut variables = Vec::new();
    variables
        .try_reserve_exact(type_codes.len())
        .map_err(|_| DtaError::ArithmeticOverflow("metadata schema variables"))?;
    let mut byte_offset = 0_u64;
    for (type_code, name) in type_codes.into_iter().zip(names) {
        let (dta_type, byte_width) = resolve(type_code)?;
        variables.push(ParsedSchemaVariable {
            name,
            dta_type,
            type_code,
            byte_width,
            byte_offset,
        });
        byte_offset = checked_add_u64(byte_offset, u64::from(byte_width), "observation length")?;
    }
    Ok(ParsedSchema {
        format_version,
        variables,
        obs_length: byte_offset,
    })
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

#[derive(Debug, Clone, Copy)]
enum ObservationKind {
    Byte,
    Int,
    Long,
    Float,
    Double,
    FixedString,
    StrL,
}

#[derive(Debug, Clone, Copy)]
struct ObservationColumnPlan {
    output_index: usize,
    source_index: u32,
    byte_offset: usize,
    byte_width: usize,
    kind: ObservationKind,
}

#[derive(Debug)]
struct ObservationPlan {
    row_width: usize,
    columns: Vec<ObservationColumnPlan>,
}

trait InterruptChecks {
    fn coarse(&mut self) -> bool;
    fn frequent(&mut self) -> bool;
}

struct SharedInterrupt<F> {
    callback: F,
}

impl<F: FnMut() -> bool> InterruptChecks for SharedInterrupt<F> {
    fn coarse(&mut self) -> bool {
        (self.callback)()
    }

    fn frequent(&mut self) -> bool {
        (self.callback)()
    }
}

struct SplitInterrupt<C, F> {
    coarse: C,
    frequent: F,
}

impl<C: FnMut() -> bool, F: FnMut() -> bool> InterruptChecks for SplitInterrupt<C, F> {
    fn coarse(&mut self) -> bool {
        (self.coarse)()
    }

    fn frequent(&mut self) -> bool {
        (self.frequent)()
    }
}

impl ObservationPlan {
    fn new(metadata: &DtaMetadata, indices: &[u32]) -> Result<Self, DtaError> {
        let row_width = usize::try_from(metadata.obs_length)
            .map_err(|_| DtaError::ArithmeticOverflow("observation length"))?;
        let mut columns = Vec::new();
        columns
            .try_reserve_exact(indices.len())
            .map_err(|_| DtaError::ArithmeticOverflow("observation plan columns"))?;
        for (output_index, &source_index) in indices.iter().enumerate() {
            let variable = metadata.variables.get(source_index as usize).ok_or(
                DtaError::ArithmeticOverflow("observation plan source column"),
            )?;
            let byte_offset = usize::try_from(variable.byte_offset)
                .map_err(|_| DtaError::ArithmeticOverflow("cell offset"))?;
            let byte_width = usize::try_from(variable.byte_width)
                .map_err(|_| DtaError::ArithmeticOverflow("cell width"))?;
            let cell_end = byte_offset
                .checked_add(byte_width)
                .ok_or(DtaError::ArithmeticOverflow("cell end"))?;
            if cell_end > row_width {
                return Err(DtaError::Truncated {
                    context: "observation cell",
                    offset: byte_offset,
                    needed: byte_width,
                    available: row_width.saturating_sub(byte_offset),
                });
            }
            let kind = match variable.dta_type {
                DtaType::Byte => ObservationKind::Byte,
                DtaType::Int => ObservationKind::Int,
                DtaType::Long => ObservationKind::Long,
                DtaType::Float => ObservationKind::Float,
                DtaType::Double => ObservationKind::Double,
                DtaType::FixedString(_) => ObservationKind::FixedString,
                DtaType::StrL => ObservationKind::StrL,
            };
            columns.push(ObservationColumnPlan {
                output_index,
                source_index,
                byte_offset,
                byte_width,
                kind,
            });
        }
        Ok(Self { row_width, columns })
    }

    fn has_strls(&self) -> bool {
        self.columns
            .iter()
            .any(|column| matches!(column.kind, ObservationKind::StrL))
    }

    fn selected_data_bytes(&self, row_count: u64) -> u64 {
        let row_bytes = self.columns.iter().fold(0_u64, |total, column| {
            total.saturating_add(column.byte_width as u64)
        });
        row_count.saturating_mul(row_bytes)
    }
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

    /// Whether the sink can consume value-label tables by ownership. Readers
    /// use this to move cached tables into an owning result without retaining
    /// a second copy. The default keeps custom sinks on the borrowed path.
    const TAKES_VALUE_LABEL_TABLES: bool = false;

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
    fn push_fixed_string(&mut self, column: usize, row: usize, value: &str)
        -> Result<(), DtaError>;

    /// Consume an undecoded fixed-string field when the destination has a
    /// representation-aware fast path. Returning `false` asks the shared
    /// decoder to perform the normal text conversion and call
    /// [`DtaSink::push_fixed_string`].
    fn try_push_fixed_string_bytes(
        &mut self,
        _column: usize,
        _row: usize,
        _value: &[u8],
        _encoding: TextEncoding,
    ) -> Result<bool, DtaError> {
        Ok(false)
    }

    fn push_strl(&mut self, column: usize, row: usize, value: &str) -> Result<(), DtaError>;

    fn finish(
        self,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError>;

    /// Finish from one uniform view of owned, contiguous borrowed, or
    /// projected borrowed value-label tables. The default preserves the
    /// original owned [`DtaSink::finish`] contract for external sinks.
    fn finish_with_value_labels(
        self,
        metadata: &DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        self.finish(
            metadata.clone(),
            row_start,
            row_count,
            value_label_tables.into_owned()?,
        )
    }
}

/// Value-label tables presented to a sink without imposing a clone or a
/// contiguous temporary allocation on projected reads.
pub enum ValueLabelTableView<'a> {
    Owned(Vec<ValueLabelTable>),
    Borrowed(&'a [ValueLabelTable]),
    Projected(&'a [&'a ValueLabelTable]),
}

impl ValueLabelTableView<'_> {
    pub fn len(&self) -> usize {
        match self {
            Self::Owned(tables) => tables.len(),
            Self::Borrowed(tables) => tables.len(),
            Self::Projected(tables) => tables.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn iter(&self) -> ValueLabelTableIter<'_> {
        match self {
            Self::Owned(tables) => ValueLabelTableIter::Contiguous(tables.iter()),
            Self::Borrowed(tables) => ValueLabelTableIter::Contiguous(tables.iter()),
            Self::Projected(tables) => ValueLabelTableIter::Projected(tables.iter()),
        }
    }

    fn into_owned(self) -> Result<Vec<ValueLabelTable>, DtaError> {
        match self {
            Self::Owned(tables) => Ok(tables),
            Self::Borrowed(tables) => {
                let mut owned = Vec::new();
                owned
                    .try_reserve_exact(tables.len())
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label allocation"))?;
                owned.extend_from_slice(tables);
                Ok(owned)
            }
            Self::Projected(tables) => {
                let mut owned = Vec::new();
                owned.try_reserve_exact(tables.len()).map_err(|_| {
                    DtaError::ArithmeticOverflow("projected value-label allocation")
                })?;
                owned.extend(tables.iter().map(|table| (*table).clone()));
                Ok(owned)
            }
        }
    }
}

pub enum ValueLabelTableIter<'a> {
    Contiguous(std::slice::Iter<'a, ValueLabelTable>),
    Projected(std::slice::Iter<'a, &'a ValueLabelTable>),
}

impl<'a> Iterator for ValueLabelTableIter<'a> {
    type Item = &'a ValueLabelTable;

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Contiguous(tables) => tables.next(),
            Self::Projected(tables) => tables.next().copied(),
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        match self {
            Self::Contiguous(tables) => tables.size_hint(),
            Self::Projected(tables) => tables.size_hint(),
        }
    }
}

impl ExactSizeIterator for ValueLabelTableIter<'_> {}

/// One independently owned output column used by the block executor.
///
/// Implementations must not call a foreign runtime from these methods when
/// they are used by the parallel executor. Numeric and fixed-string values are
/// written by exactly one worker; deferred `strL` values are written by the
/// coordinator after workers join. Rows ascend within every column.
pub trait DtaColumnSink: Send {
    fn push_byte(
        &mut self,
        row: usize,
        value: i8,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_int(
        &mut self,
        row: usize,
        value: i16,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_long(
        &mut self,
        row: usize,
        value: i32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_float(
        &mut self,
        row: usize,
        value: f32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_double(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError>;
    fn push_fixed_string(&mut self, row: usize, value: &str) -> Result<(), DtaError>;
    fn try_push_fixed_string_bytes(
        &mut self,
        _row: usize,
        _value: &[u8],
        _encoding: TextEncoding,
    ) -> Result<bool, DtaError> {
        Ok(false)
    }
    fn push_strl(&mut self, _row: usize, _value: &str) -> Result<(), DtaError> {
        Err(DtaError::Output(
            "parallel output sink does not support strL values".to_owned(),
        ))
    }
}

/// Destination that can transfer independent columns to worker threads.
pub trait ParallelDtaSink: Sized {
    type Output;
    type Column: DtaColumnSink;
    type State;

    const TAKES_VALUE_LABEL_TABLES: bool = false;

    fn split(self) -> (Self::State, Vec<Self::Column>);

    fn finish_parallel(
        state: Self::State,
        columns: Vec<Self::Column>,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError>;

    fn finish_parallel_with_value_labels(
        state: Self::State,
        columns: Vec<Self::Column>,
        metadata: &DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        Self::finish_parallel(
            state,
            columns,
            metadata.clone(),
            row_start,
            row_count,
            value_label_tables.into_owned()?,
        )
    }
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

impl DtaColumnSink for ColumnBuilder {
    fn push_byte(
        &mut self,
        _row: usize,
        value: i8,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Byte {
            values,
            missing_tags,
            ..
        } = self
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    fn push_int(
        &mut self,
        _row: usize,
        value: i16,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Int {
            values,
            missing_tags,
            ..
        } = self
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    fn push_long(
        &mut self,
        _row: usize,
        value: i32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Long {
            values,
            missing_tags,
            ..
        } = self
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    fn push_float(
        &mut self,
        _row: usize,
        value: f32,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Float {
            values,
            missing_tags,
            ..
        } = self
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    fn push_double(
        &mut self,
        _row: usize,
        value: f64,
        missing: Option<crate::MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Double {
            values,
            missing_tags,
            ..
        } = self
        else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value);
        missing_tags.push(missing);
        Ok(())
    }

    fn push_fixed_string(&mut self, _row: usize, value: &str) -> Result<(), DtaError> {
        let Self::FixedString { values, .. } = self else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value.to_owned());
        Ok(())
    }

    fn push_strl(&mut self, _row: usize, value: &str) -> Result<(), DtaError> {
        let Self::StrL { values, .. } = self else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value.to_owned());
        Ok(())
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

    const TAKES_VALUE_LABEL_TABLES: bool = true;

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
        value: &str,
    ) -> Result<(), DtaError> {
        let ColumnBuilder::FixedString { values, .. } = self.column(column)? else {
            return Err(DtaError::ArithmeticOverflow("output column type"));
        };
        values.push(value.to_owned());
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

    fn finish_with_value_labels(
        self,
        metadata: &DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        self.finish(
            metadata.clone(),
            row_start,
            row_count,
            value_label_tables.into_owned()?,
        )
    }
}

impl ParallelDtaSink for VecSink {
    type Output = DtaData;
    type Column = ColumnBuilder;
    type State = ();

    const TAKES_VALUE_LABEL_TABLES: bool = true;

    fn split(self) -> (Self::State, Vec<Self::Column>) {
        ((), self.columns)
    }

    fn finish_parallel(
        _state: Self::State,
        columns: Vec<Self::Column>,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        DtaSink::finish(
            VecSink { columns },
            metadata,
            row_start,
            row_count,
            value_label_tables,
        )
    }

    fn finish_parallel_with_value_labels(
        _state: Self::State,
        columns: Vec<Self::Column>,
        metadata: &DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        DtaSink::finish_with_value_labels(
            VecSink { columns },
            metadata,
            row_start,
            row_count,
            value_label_tables,
        )
    }
}

struct ParallelColumn<C> {
    plan: ObservationColumnPlan,
    sink: C,
    strl_pointers: Option<Vec<Option<FileGsoKey>>>,
}

struct ObservationBlock {
    bytes: Vec<u8>,
    source_offset: u64,
    output_row_start: usize,
    row_count: usize,
}

enum WorkerMessage {
    Block(Arc<ObservationBlock>),
    Finish,
}

fn receive_worker_acks(
    receivers: &[std::sync::mpsc::Receiver<Result<(), DtaError>>],
) -> Result<(), DtaError> {
    let mut stopped = None;
    let mut errors = Vec::new();
    for (worker, receiver) in receivers.iter().enumerate() {
        match receiver.recv() {
            Ok(Err(error)) => errors.push((worker, error)),
            Ok(Ok(())) => {}
            Err(_) if stopped.is_none() => {
                stopped = Some(DtaError::Output(format!(
                    "parallel decoder worker {worker} stopped"
                )));
            }
            Err(_) => {}
        }
    }
    if let Some(error) = stopped {
        return Err(error);
    }
    errors.sort_by_key(|(worker, _)| *worker);
    errors
        .into_iter()
        .next()
        .map_or(Ok(()), |(_, error)| Err(error))
}

#[inline(always)]
unsafe fn read_unaligned_u16(bytes: &[u8], offset: usize, byte_order: ByteOrder) -> u16 {
    let raw = unsafe { std::ptr::read_unaligned(bytes.as_ptr().add(offset).cast::<u16>()) };
    match byte_order {
        ByteOrder::Lsf => u16::from_le(raw),
        ByteOrder::Msf => u16::from_be(raw),
    }
}

#[inline(always)]
unsafe fn read_unaligned_u32(bytes: &[u8], offset: usize, byte_order: ByteOrder) -> u32 {
    let raw = unsafe { std::ptr::read_unaligned(bytes.as_ptr().add(offset).cast::<u32>()) };
    match byte_order {
        ByteOrder::Lsf => u32::from_le(raw),
        ByteOrder::Msf => u32::from_be(raw),
    }
}

#[inline(always)]
unsafe fn read_unaligned_u64(bytes: &[u8], offset: usize, byte_order: ByteOrder) -> u64 {
    let raw = unsafe { std::ptr::read_unaligned(bytes.as_ptr().add(offset).cast::<u64>()) };
    match byte_order {
        ByteOrder::Lsf => u64::from_le(raw),
        ByteOrder::Msf => u64::from_be(raw),
    }
}

fn decode_worker_block<C: DtaColumnSink>(
    columns: &mut [ParallelColumn<C>],
    block: &ObservationBlock,
    row_width: usize,
    metadata: &DtaMetadata,
    encoding: TextEncoding,
    mut should_interrupt: Option<&mut dyn FnMut() -> bool>,
) -> Result<(), DtaError> {
    if block.row_count == 0 {
        return Ok(());
    }
    for (column_index, column) in columns.iter_mut().enumerate() {
        let last_row = block
            .row_count
            .checked_sub(1)
            .and_then(|row| row.checked_mul(row_width))
            .ok_or(DtaError::ArithmeticOverflow("parallel cell offset"))?;
        let last_cell = last_row
            .checked_add(column.plan.byte_offset)
            .ok_or(DtaError::ArithmeticOverflow("parallel cell offset"))?;
        let input_end = last_cell
            .checked_add(column.plan.byte_width)
            .ok_or(DtaError::ArithmeticOverflow("parallel cell end"))?;
        if input_end > block.bytes.len() {
            return Err(DtaError::Truncated {
                context: "observation cell",
                offset: last_cell,
                needed: column.plan.byte_width,
                available: block.bytes.len().saturating_sub(last_cell),
            });
        }
        block
            .output_row_start
            .checked_add(block.row_count)
            .ok_or(DtaError::ArithmeticOverflow("parallel output row"))?;

        let mut input_at = column.plan.byte_offset;
        let mut output_row = block.output_row_start;
        macro_rules! decode_numeric_rows {
            ($body:expr) => {{
                for local_row in 0..block.row_count {
                    if column_index == 0 && local_row.is_multiple_of(COLUMNAR_CANCEL_CHECK_INTERVAL)
                    {
                        if let Some(callback) = should_interrupt.as_deref_mut() {
                            if callback() {
                                return Err(DtaError::Cancelled);
                            }
                        }
                    }
                    $body(input_at, output_row)?;
                    input_at += row_width;
                    output_row += 1;
                }
            }};
        }
        match column.plan.kind {
            ObservationKind::Byte => decode_numeric_rows!(|offset, row| {
                // SAFETY: the complete strided column range was checked above.
                let value = unsafe { *block.bytes.get_unchecked(offset) } as i8;
                column.sink.push_byte(
                    row,
                    value,
                    classify_byte_missing_for_version(value, metadata.format_version),
                )
            }),
            ObservationKind::Int => decode_numeric_rows!(|offset, row| {
                // SAFETY: the complete strided column range was checked above.
                let value =
                    unsafe { read_unaligned_u16(&block.bytes, offset, metadata.byte_order) } as i16;
                column.sink.push_int(
                    row,
                    value,
                    classify_int_missing_for_version(value, metadata.format_version),
                )
            }),
            ObservationKind::Long => decode_numeric_rows!(|offset, row| {
                // SAFETY: the complete strided column range was checked above.
                let value =
                    unsafe { read_unaligned_u32(&block.bytes, offset, metadata.byte_order) } as i32;
                column.sink.push_long(
                    row,
                    value,
                    classify_long_missing_for_version(value, metadata.format_version),
                )
            }),
            ObservationKind::Float => decode_numeric_rows!(|offset, row| {
                // SAFETY: the complete strided column range was checked above.
                let bits = unsafe { read_unaligned_u32(&block.bytes, offset, metadata.byte_order) };
                column.sink.push_float(
                    row,
                    f32::from_bits(bits),
                    classify_float_missing_bits_for_version(bits, metadata.format_version),
                )
            }),
            ObservationKind::Double => decode_numeric_rows!(|offset, row| {
                // SAFETY: the complete strided column range was checked above.
                let bits = unsafe { read_unaligned_u64(&block.bytes, offset, metadata.byte_order) };
                column.sink.push_double(
                    row,
                    f64::from_bits(bits),
                    classify_double_missing_bits_for_version(bits, metadata.format_version),
                )
            }),
            ObservationKind::FixedString => {
                for local_row in 0..block.row_count {
                    if column_index == 0 && local_row.is_multiple_of(COLUMNAR_CANCEL_CHECK_INTERVAL)
                    {
                        if let Some(callback) = should_interrupt.as_deref_mut() {
                            if callback() {
                                return Err(DtaError::Cancelled);
                            }
                        }
                    }
                    // SAFETY: the complete strided column range was checked above.
                    let cell = unsafe {
                        std::slice::from_raw_parts(
                            block.bytes.as_ptr().add(input_at),
                            column.plan.byte_width,
                        )
                    };
                    let field = field_bytes(cell);
                    if !column
                        .sink
                        .try_push_fixed_string_bytes(output_row, field, encoding)?
                    {
                        let value = encoding.decode_cow(field);
                        column.sink.push_fixed_string(output_row, &value)?;
                    }
                    input_at += row_width;
                    output_row += 1;
                }
            }
            ObservationKind::StrL => {
                let pointers = column
                    .strl_pointers
                    .as_mut()
                    .ok_or(DtaError::ArithmeticOverflow("parallel strL output column"))?;
                for local_row in 0..block.row_count {
                    if column_index == 0 && local_row.is_multiple_of(COLUMNAR_CANCEL_CHECK_INTERVAL)
                    {
                        if let Some(callback) = should_interrupt.as_deref_mut() {
                            if callback() {
                                return Err(DtaError::Cancelled);
                            }
                        }
                    }
                    // SAFETY: the complete strided column range was checked above.
                    let cell = unsafe {
                        std::slice::from_raw_parts(
                            block.bytes.as_ptr().add(input_at),
                            column.plan.byte_width,
                        )
                    };
                    let absolute_offset = block
                        .source_offset
                        .checked_add(u64::try_from(input_at).map_err(|_| {
                            DtaError::ArithmeticOverflow("parallel strL cell offset")
                        })?)
                        .ok_or(DtaError::ArithmeticOverflow("parallel strL cell offset"))?;
                    pointers.push(parse_pointer(cell, absolute_offset, metadata)?);
                    input_at += row_width;
                }
            }
        }
    }
    Ok(())
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
    value_labels: ValueLabelCache,
    text_encoding: TextEncoding,
}

/// The schema-only result used for inexpensive column selection preflight.
/// It deliberately excludes dataset metadata values, notes, characteristics,
/// and section offsets, which are available only after a full [`DtaFile`]
/// open.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaSchemaSummary {
    pub format_version: FormatVersion,
    pub variables: Vec<DtaSchemaVariable>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaSchemaVariable {
    pub name: String,
    pub dta_type: DtaType,
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

    /// Read the schema fields needed for column selection without decoding
    /// note and characteristic payloads.
    pub fn metadata_summary_with_encoding(
        path: impl AsRef<Path>,
        encoding: TextEncoding,
    ) -> Result<DtaSchemaSummary, DtaError> {
        let mut file = File::open(path).map_err(|error| DtaError::Io {
            context: "opening file",
            offset: 0,
            kind: error.kind(),
        })?;
        let mut scratch = Scratch::new(DEFAULT_MAX_BUFFER_BYTES);
        read_file_schema_summary(&mut file, &mut scratch, encoding)
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
        let (metadata, file_length) = read_file_metadata(&mut reader, &mut scratch, encoding)?;
        let text_encoding = encoding.resolve(metadata.format_version);
        Ok(Self {
            reader,
            metadata,
            file_length,
            scratch,
            value_labels: ValueLabelCache::Empty,
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
        match &self.value_labels {
            ValueLabelCache::Full(cache) => Ok(&cache.tables),
            _ => unreachable!("value-label cache was initialized"),
        }
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

    /// Read with separate callbacks for bounded work and high-frequency row
    /// polling. This lets foreign-runtime adapters throttle only the latter;
    /// the coarse callback remains responsive during large strings, `strL`
    /// values, and value-label sections.
    pub fn read_with_interrupts<C, F>(
        &mut self,
        options: &ReadOptions,
        coarse_interrupt: C,
        frequent_interrupt: F,
    ) -> Result<DtaData, DtaError>
    where
        C: FnMut() -> bool,
        F: FnMut() -> bool,
    {
        self.read_with_sink_and_interrupts(
            options,
            |metadata, _row_start, row_count, indices| {
                let capacity = usize::try_from(row_count)
                    .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
                Ok(VecSink::new(metadata, indices, capacity))
            },
            coarse_interrupt,
            frequent_interrupt,
        )
    }

    /// Resolve the worker count for the validated parallel path.
    ///
    /// A requested value of zero selects an automatic count. Oversized rows
    /// and small automatic workloads deliberately return one so callers can
    /// use the serial path.
    pub fn parallel_thread_count(
        &self,
        options: &ReadOptions,
        requested: usize,
    ) -> Result<usize, DtaError> {
        if requested == 1 {
            return Ok(1);
        }
        let indices = resolve_columns(&self.metadata, options)?;
        let plan = ObservationPlan::new(&self.metadata, &indices)?;
        let (_, row_count) = row_window(&self.metadata, options);
        if plan.columns.len() < 2 || plan.row_width == 0 || plan.row_width > self.scratch.limit {
            return Ok(1);
        }
        let data_bytes = plan.selected_data_bytes(row_count);
        let cells = row_count.saturating_mul(plan.columns.len() as u64);
        if requested == 0 && !automatic_parallel_workload(data_bytes, cells) {
            return Ok(1);
        }
        let available = thread::available_parallelism().map_or(1, usize::from);
        let threads = if requested == 0 {
            available.min(MAX_AUTOMATIC_THREADS)
        } else {
            requested.min(available)
        };
        Ok(threads.min(plan.columns.len()).max(1))
    }

    /// Return whether the selected observations can use the column-oriented
    /// block decoder, including its single-worker path.
    pub fn supports_columnar_sink(&self, options: &ReadOptions) -> Result<bool, DtaError> {
        let indices = resolve_columns(&self.metadata, options)?;
        let plan = ObservationPlan::new(&self.metadata, &indices)?;
        Ok(!plan.columns.is_empty() && plan.row_width > 0 && plan.row_width <= self.scratch.limit)
    }

    /// Decode a projection into ordinary Rust vectors with the shared parallel
    /// block executor.
    pub fn read_with_parallel_interrupt<F>(
        &mut self,
        options: &ReadOptions,
        thread_count: usize,
        should_interrupt: F,
    ) -> Result<DtaData, DtaError>
    where
        F: FnMut() -> bool,
    {
        self.read_with_parallel_sink_and_interrupt(
            options,
            thread_count,
            |metadata, _row_start, row_count, indices| {
                let capacity = usize::try_from(row_count)
                    .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
                Ok(VecSink::new(metadata, indices, capacity))
            },
            should_interrupt,
        )
    }

    /// Decode a projection through independently owned columns.
    ///
    /// Each block is validated once before its type-specialized column kernels
    /// run. Workers only partition columns and never call a foreign runtime.
    /// A thread count of one executes the same kernels synchronously.
    pub fn read_with_parallel_sink_and_interrupt<S, B, F>(
        &mut self,
        options: &ReadOptions,
        thread_count: usize,
        build_sink: B,
        mut should_interrupt: F,
    ) -> Result<S::Output, DtaError>
    where
        S: ParallelDtaSink,
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
        let plan = ObservationPlan::new(&self.metadata, &indices)?;
        if thread_count == 0
            || plan.columns.is_empty()
            || plan.row_width == 0
            || plan.row_width > self.scratch.limit
        {
            return Err(DtaError::Output(
                "parallel decoder eligibility was not satisfied".to_owned(),
            ));
        }
        let worker_count = thread_count.min(plan.columns.len());
        let sink = build_sink(&self.metadata, row_start, row_count, &indices)?;
        let (state, columns) = sink.split();
        if columns.len() != plan.columns.len() {
            return Err(DtaError::Output(
                "parallel output column count mismatch".to_owned(),
            ));
        }

        let mut shards = (0..worker_count)
            .map(|_| Vec::<ParallelColumn<S::Column>>::new())
            .collect::<Vec<_>>();
        let mut shard_weights = vec![0_usize; worker_count];
        let output_capacity = usize::try_from(row_count)
            .map_err(|_| DtaError::ArithmeticOverflow("parallel output row count"))?;
        for (column_plan, column_sink) in plan.columns.iter().copied().zip(columns) {
            let worker = shard_weights
                .iter()
                .enumerate()
                .min_by_key(|&(index, weight)| (*weight, index))
                .map(|(index, _)| index)
                .unwrap_or(0);
            shard_weights[worker] =
                shard_weights[worker].saturating_add(column_plan.byte_width.max(8));
            let strl_pointers = if matches!(column_plan.kind, ObservationKind::StrL) {
                let mut pointers = Vec::new();
                pointers
                    .try_reserve_exact(output_capacity)
                    .map_err(|_| DtaError::ArithmeticOverflow("parallel strL pointers"))?;
                Some(pointers)
            } else {
                None
            };
            shards[worker].push(ParallelColumn {
                plan: column_plan,
                sink: column_sink,
                strl_pointers,
            });
        }

        let payload_start = observation_payload_start(&self.metadata)?;
        let rows_per_block = self.scratch.limit / plan.row_width;
        let rows_per_block = u64::try_from(rows_per_block)
            .map_err(|_| DtaError::ArithmeticOverflow("parallel rows per block"))?;
        let metadata = &self.metadata;
        let encoding = self.text_encoding;
        let mut observation_buffer = Vec::new();

        let decoded_columns = if worker_count == 1 {
            let mut shard = shards
                .pop()
                .expect("one worker has exactly one column shard");
            let mut row = 0_u64;
            while row < row_count {
                check_cancel(&mut should_interrupt)?;
                let block_rows = (row_count - row).min(rows_per_block);
                let block_row_count = usize::try_from(block_rows)
                    .map_err(|_| DtaError::ArithmeticOverflow("columnar block row count"))?;
                let block_length = plan
                    .row_width
                    .checked_mul(block_row_count)
                    .ok_or(DtaError::ArithmeticOverflow("columnar block length"))?;
                let source_row = row_start
                    .checked_add(row)
                    .ok_or(DtaError::ArithmeticOverflow("columnar source row"))?;
                let block_offset = payload_start
                    .checked_add(
                        source_row
                            .checked_mul(self.metadata.obs_length)
                            .ok_or(DtaError::ArithmeticOverflow("columnar row offset"))?,
                    )
                    .ok_or(DtaError::ArithmeticOverflow("columnar block offset"))?;
                read_exact_at_into(
                    &mut self.reader,
                    block_offset,
                    block_length,
                    &mut self.scratch,
                    &mut observation_buffer,
                    "reading observation rows",
                )?;
                let block = ObservationBlock {
                    bytes: std::mem::take(&mut observation_buffer),
                    source_offset: block_offset,
                    output_row_start: usize::try_from(row)
                        .map_err(|_| DtaError::ArithmeticOverflow("columnar output row"))?,
                    row_count: block_row_count,
                };
                decode_worker_block(
                    &mut shard,
                    &block,
                    plan.row_width,
                    metadata,
                    encoding,
                    Some(&mut should_interrupt),
                )?;
                observation_buffer = block.bytes;
                row = row
                    .checked_add(block_rows)
                    .ok_or(DtaError::ArithmeticOverflow("columnar projected row"))?;
            }
            shard
        } else {
            thread::scope(
                |scope| -> Result<Vec<ParallelColumn<S::Column>>, DtaError> {
                    let mut senders = Vec::with_capacity(worker_count);
                    let mut ack_receivers = Vec::with_capacity(worker_count);
                    let mut handles = Vec::with_capacity(worker_count);
                    for mut shard in shards {
                        // One buffered acknowledgement lets the coordinator
                        // finish the next read while workers complete the
                        // current block. It also lets workers unwind if that
                        // read fails before acknowledgements are collected.
                        let (sender, receiver) = sync_channel::<WorkerMessage>(1);
                        let (worker_ack, ack_receiver) = sync_channel::<Result<(), DtaError>>(1);
                        senders.push(sender);
                        ack_receivers.push(ack_receiver);
                        handles.push(scope.spawn(move || {
                            while let Ok(message) = receiver.recv() {
                                match message {
                                    WorkerMessage::Block(block) => {
                                        let result = decode_worker_block(
                                            &mut shard,
                                            &block,
                                            plan.row_width,
                                            metadata,
                                            encoding,
                                            None,
                                        );
                                        drop(block);
                                        let failed = result.is_err();
                                        if worker_ack.send(result).is_err() || failed {
                                            break;
                                        }
                                    }
                                    WorkerMessage::Finish => break,
                                }
                            }
                            shard
                        }));
                    }

                    let execution = (|| -> Result<(), DtaError> {
                        let mut row = 0_u64;
                        let mut inflight_block: Option<Arc<ObservationBlock>> = None;
                        while row < row_count {
                            let ready = (|| -> Result<(u64, usize, u64), DtaError> {
                                check_cancel(&mut should_interrupt)?;
                                let block_rows = (row_count - row).min(rows_per_block);
                                let block_row_count =
                                    usize::try_from(block_rows).map_err(|_| {
                                        DtaError::ArithmeticOverflow("parallel block row count")
                                    })?;
                                let block_length = plan
                                    .row_width
                                    .checked_mul(block_row_count)
                                    .ok_or(DtaError::ArithmeticOverflow("parallel block length"))?;
                                let source_row = row_start
                                    .checked_add(row)
                                    .ok_or(DtaError::ArithmeticOverflow("parallel source row"))?;
                                let block_offset = payload_start
                                    .checked_add(
                                        source_row.checked_mul(self.metadata.obs_length).ok_or(
                                            DtaError::ArithmeticOverflow("parallel row offset"),
                                        )?,
                                    )
                                    .ok_or(DtaError::ArithmeticOverflow("parallel block offset"))?;
                                read_exact_at_into(
                                    &mut self.reader,
                                    block_offset,
                                    block_length,
                                    &mut self.scratch,
                                    &mut observation_buffer,
                                    "reading observation rows",
                                )?;
                                Ok((block_rows, block_row_count, block_offset))
                            })();

                            // The read above overlaps worker decoding of the
                            // preceding block. Once those workers finish,
                            // recycle its allocation for the following read.
                            let reusable_buffer = if let Some(block) = inflight_block.take() {
                                receive_worker_acks(&ack_receivers)?;
                                Arc::try_unwrap(block)
                                    .map_err(|_| {
                                        DtaError::Output(
                                            "parallel input block remained borrowed".to_owned(),
                                        )
                                    })?
                                    .bytes
                            } else {
                                Vec::new()
                            };
                            // An error from the earlier block takes precedence
                            // over a later read or cancellation error, matching
                            // the non-pipelined executor's ordering.
                            let (block_rows, block_row_count, block_offset) = ready?;
                            // An interrupt can arrive while the speculative
                            // read overlaps the earlier decode. Do not dispatch
                            // that newly read block after such an interrupt.
                            check_cancel(&mut should_interrupt)?;
                            let ready_buffer =
                                std::mem::replace(&mut observation_buffer, reusable_buffer);
                            let block = Arc::new(ObservationBlock {
                                bytes: ready_buffer,
                                source_offset: block_offset,
                                output_row_start: usize::try_from(row).map_err(|_| {
                                    DtaError::ArithmeticOverflow("parallel output row")
                                })?,
                                row_count: block_row_count,
                            });
                            for sender in &senders {
                                sender
                                    .send(WorkerMessage::Block(Arc::clone(&block)))
                                    .map_err(|_| {
                                        DtaError::Output(
                                            "parallel decoder worker stopped".to_owned(),
                                        )
                                    })?;
                            }
                            inflight_block = Some(block);
                            row = row
                                .checked_add(block_rows)
                                .ok_or(DtaError::ArithmeticOverflow("parallel projected row"))?;
                        }

                        if let Some(block) = inflight_block {
                            receive_worker_acks(&ack_receivers)?;
                            Arc::try_unwrap(block).map_err(|_| {
                                DtaError::Output(
                                    "parallel input block remained borrowed".to_owned(),
                                )
                            })?;
                        }
                        Ok(())
                    })();

                    if execution.is_ok() {
                        for sender in &senders {
                            let _ = sender.send(WorkerMessage::Finish);
                        }
                    }
                    drop(senders);
                    let mut completed = Vec::with_capacity(plan.columns.len());
                    let mut worker_panicked = false;
                    for handle in handles {
                        match handle.join() {
                            Ok(shard) => completed.extend(shard),
                            Err(_) => worker_panicked = true,
                        }
                    }
                    if worker_panicked {
                        return Err(DtaError::Output(
                            "parallel decoder worker panicked".to_owned(),
                        ));
                    }
                    execution?;
                    Ok(completed)
                },
            )?
        };

        let mut ordered = (0..plan.columns.len())
            .map(|_| None)
            .collect::<Vec<Option<ParallelColumn<S::Column>>>>();
        for column in decoded_columns {
            let output_index = column.plan.output_index;
            ordered[output_index] = Some(column);
        }
        let mut ordered = ordered
            .into_iter()
            .map(|column| {
                column.ok_or_else(|| {
                    DtaError::Output("parallel output column was not returned".to_owned())
                })
            })
            .collect::<Result<Vec<_>, _>>()?;

        if plan.has_strls() {
            check_cancel(&mut should_interrupt)?;
            resolve_parallel_file_strls(
                &mut self.reader,
                &self.metadata,
                &mut self.scratch,
                &mut ordered,
                &mut should_interrupt,
                self.text_encoding,
            )?;
        }
        let columns = ordered
            .into_iter()
            .map(|column| column.sink)
            .collect::<Vec<_>>();

        check_cancel(&mut should_interrupt)?;
        if options.column_indices.is_some() {
            let selected = selected_value_label_names(&self.metadata, &indices);
            let value_label_indices =
                self.ensure_projected_value_labels(&selected, &mut should_interrupt)?;
            if S::TAKES_VALUE_LABEL_TABLES
                && self.projected_value_labels_should_move(&value_label_indices)
            {
                let tables = self.take_projected_value_label_tables(&value_label_indices)?;
                S::finish_parallel_with_value_labels(
                    state,
                    columns,
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Owned(tables),
                )
            } else {
                let tables = self.projected_value_label_tables(&value_label_indices)?;
                S::finish_parallel_with_value_labels(
                    state,
                    columns,
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Projected(&tables),
                )
            }
        } else {
            self.ensure_value_labels(&mut should_interrupt)?;
            if S::TAKES_VALUE_LABEL_TABLES && self.all_value_labels_should_move() {
                let tables = self.take_all_value_label_tables();
                S::finish_parallel_with_value_labels(
                    state,
                    columns,
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Owned(tables),
                )
            } else {
                let ValueLabelCache::Full(value_label_cache) = &self.value_labels else {
                    unreachable!("value-label cache was initialized")
                };
                S::finish_parallel_with_value_labels(
                    state,
                    columns,
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Borrowed(&value_label_cache.tables),
                )
            }
        }
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
        should_interrupt: F,
    ) -> Result<S::Output, DtaError>
    where
        S: DtaSink,
        B: FnOnce(&DtaMetadata, u64, u64, &[u32]) -> Result<S, DtaError>,
        F: FnMut() -> bool,
    {
        self.read_with_sink_and_interrupt_controller(
            options,
            build_sink,
            SharedInterrupt {
                callback: should_interrupt,
            },
        )
    }

    /// Decode through a typed output collector with separate coarse and
    /// high-frequency interrupt callbacks.
    pub fn read_with_sink_and_interrupts<S, B, C, F>(
        &mut self,
        options: &ReadOptions,
        build_sink: B,
        coarse_interrupt: C,
        frequent_interrupt: F,
    ) -> Result<S::Output, DtaError>
    where
        S: DtaSink,
        B: FnOnce(&DtaMetadata, u64, u64, &[u32]) -> Result<S, DtaError>,
        C: FnMut() -> bool,
        F: FnMut() -> bool,
    {
        self.read_with_sink_and_interrupt_controller(
            options,
            build_sink,
            SplitInterrupt {
                coarse: coarse_interrupt,
                frequent: frequent_interrupt,
            },
        )
    }

    fn read_with_sink_and_interrupt_controller<S, B, I>(
        &mut self,
        options: &ReadOptions,
        build_sink: B,
        mut interrupts: I,
    ) -> Result<S::Output, DtaError>
    where
        S: DtaSink,
        B: FnOnce(&DtaMetadata, u64, u64, &[u32]) -> Result<S, DtaError>,
        I: InterruptChecks,
    {
        check_coarse_cancel(&mut interrupts)?;
        validate_layout(
            &mut self.reader,
            &self.metadata,
            self.file_length,
            &mut self.scratch,
        )?;
        let indices = resolve_columns(&self.metadata, options)?;
        let (row_start, row_count) = row_window(&self.metadata, options);
        let plan = ObservationPlan::new(&self.metadata, &indices)?;
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
        let payload_start = observation_payload_start(&self.metadata)?;
        let mut cell_decoder = CellDecoder {
            sink: &mut sink,
            strl_pointers: &mut strl_pointers,
            metadata: &self.metadata,
            text_encoding: self.text_encoding,
        };

        if !plan.columns.is_empty() && plan.row_width > 0 && plan.row_width <= self.scratch.limit {
            let obs_length = plan.row_width;
            let rows_per_chunk = self.scratch.limit / obs_length;
            let rows_per_chunk = u64::try_from(rows_per_chunk)
                .map_err(|_| DtaError::ArithmeticOverflow("rows per chunk"))?;
            let mut row = 0_u64;
            let mut observation_buffer = Vec::new();
            while row < row_count {
                check_coarse_cancel(&mut interrupts)?;
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
                read_exact_at_into(
                    &mut self.reader,
                    chunk_offset,
                    chunk_length,
                    &mut self.scratch,
                    &mut observation_buffer,
                    "reading observation rows",
                )?;
                let staged = &observation_buffer;
                for local_row in 0..chunk_rows_usize {
                    check_frequent_cancel(&mut interrupts)?;
                    let row_at = local_row
                        .checked_mul(obs_length)
                        .ok_or(DtaError::ArithmeticOverflow("staged row offset"))?;
                    let output_row = usize::try_from(row)
                        .map_err(|_| DtaError::ArithmeticOverflow("output row"))?
                        .checked_add(local_row)
                        .ok_or(DtaError::ArithmeticOverflow("output row"))?;
                    for column in &plan.columns {
                        let variable = &self.metadata.variables[column.source_index as usize];
                        let width = column.byte_width;
                        let variable_at = column.byte_offset;
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
                            column.output_index,
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
        } else if !plan.columns.is_empty() {
            for row in 0..row_count {
                check_frequent_cancel(&mut interrupts)?;
                let output_row =
                    usize::try_from(row).map_err(|_| DtaError::ArithmeticOverflow("output row"))?;
                let source_row = row_start
                    .checked_add(row)
                    .ok_or(DtaError::ArithmeticOverflow("source row"))?;
                let row_offset = source_row
                    .checked_mul(self.metadata.obs_length)
                    .ok_or(DtaError::ArithmeticOverflow("row offset"))?;
                for column in &plan.columns {
                    let variable = &self.metadata.variables[column.source_index as usize];
                    let cell_offset = payload_start
                        .checked_add(row_offset)
                        .and_then(|value| value.checked_add(variable.byte_offset))
                        .ok_or(DtaError::ArithmeticOverflow("cell offset"))?;
                    let width = column.byte_width;
                    if matches!(variable.dta_type, DtaType::FixedString(_)) {
                        let mut coarse_interrupt = || interrupts.coarse();
                        let (value, _) = decode_range(
                            &mut self.reader,
                            cell_offset,
                            width,
                            self.text_encoding,
                            true,
                            &mut self.scratch,
                            &mut coarse_interrupt,
                            "reading fixed-string observation",
                        )?;
                        cell_decoder.sink.push_fixed_string(
                            column.output_index,
                            output_row,
                            &value,
                        )?;
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
                        column.output_index,
                        output_row,
                        &cell,
                        cell_offset,
                        &variable.dta_type,
                    )?;
                }
            }
        }
        {
            let mut coarse_interrupt = || interrupts.coarse();
            resolve_file_strls(
                &mut self.reader,
                &self.metadata,
                &mut self.scratch,
                &mut strl_pointers,
                &mut sink,
                &mut coarse_interrupt,
                self.text_encoding,
            )?;
        }
        check_coarse_cancel(&mut interrupts)?;
        if options.column_indices.is_some() {
            let mut coarse_interrupt = || interrupts.coarse();
            let selected = selected_value_label_names(&self.metadata, &indices);
            let value_label_indices =
                self.ensure_projected_value_labels(&selected, &mut coarse_interrupt)?;
            if S::TAKES_VALUE_LABEL_TABLES
                && self.projected_value_labels_should_move(&value_label_indices)
            {
                let tables = self.take_projected_value_label_tables(&value_label_indices)?;
                sink.finish_with_value_labels(
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Owned(tables),
                )
            } else {
                let tables = self.projected_value_label_tables(&value_label_indices)?;
                sink.finish_with_value_labels(
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Projected(&tables),
                )
            }
        } else {
            let mut coarse_interrupt = || interrupts.coarse();
            self.ensure_value_labels(&mut coarse_interrupt)?;
            if S::TAKES_VALUE_LABEL_TABLES && self.all_value_labels_should_move() {
                let tables = self.take_all_value_label_tables();
                sink.finish_with_value_labels(
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Owned(tables),
                )
            } else {
                let ValueLabelCache::Full(value_label_cache) = &self.value_labels else {
                    unreachable!("value-label cache was initialized")
                };
                sink.finish_with_value_labels(
                    &self.metadata,
                    row_start,
                    row_count,
                    ValueLabelTableView::Borrowed(&value_label_cache.tables),
                )
            }
        }
    }

    /// Return ownership of the underlying reader.
    pub fn into_inner(self) -> R {
        self.reader
    }

    fn ensure_value_labels<F>(&mut self, should_interrupt: &mut F) -> Result<(), DtaError>
    where
        F: FnMut() -> bool,
    {
        if matches!(self.value_labels, ValueLabelCache::Full(_)) {
            return Ok(());
        }
        check_cancel(should_interrupt)?;
        let tables = match &self.value_labels {
            ValueLabelCache::Indexed(cache) => {
                let mut missing = Vec::new();
                missing
                    .try_reserve_exact(cache.locations.len())
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label index allocation"))?;
                missing.extend(
                    (0..cache.locations.len()).filter(|index| !cache.tables.contains_key(index)),
                );
                let layout = cache.layout;
                for index in missing {
                    check_cancel(should_interrupt)?;
                    let ValueLabelCache::Indexed(cache) = &self.value_labels else {
                        unreachable!()
                    };
                    let table = read_indexed_value_label_table(
                        &mut self.reader,
                        &self.metadata,
                        &mut self.scratch,
                        should_interrupt,
                        self.text_encoding,
                        layout,
                        &cache.locations[index],
                    )?;
                    let ValueLabelCache::Indexed(cache) = &mut self.value_labels else {
                        unreachable!()
                    };
                    cache.tables.insert(index, table);
                }
                let ValueLabelCache::Indexed(mut cache) =
                    std::mem::replace(&mut self.value_labels, ValueLabelCache::Empty)
                else {
                    unreachable!()
                };
                let mut tables = Vec::new();
                tables
                    .try_reserve_exact(cache.locations.len())
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label table allocation"))?;
                for index in 0..cache.locations.len() {
                    tables.push(
                        cache
                            .tables
                            .remove(&index)
                            .expect("indexed value-label table was decoded"),
                    );
                }
                tables
            }
            ValueLabelCache::Empty => {
                read_value_labels_streaming(
                    &mut self.reader,
                    &self.metadata,
                    &mut self.scratch,
                    should_interrupt,
                    self.text_encoding,
                    ValueLabelStreamingMode::Full,
                )?
                .0
            }
            ValueLabelCache::Full(_) => unreachable!(),
        };
        check_cancel(should_interrupt)?;
        let indices_by_name = index_value_label_tables(&tables);
        self.value_labels = ValueLabelCache::Full(FullValueLabelCache {
            tables,
            indices_by_name,
        });
        Ok(())
    }

    fn ensure_projected_value_labels<F>(
        &mut self,
        selected: &HashSet<String>,
        should_interrupt: &mut F,
    ) -> Result<Vec<usize>, DtaError>
    where
        F: FnMut() -> bool,
    {
        match &self.value_labels {
            ValueLabelCache::Full(cache) => {
                return selected_value_label_location_indices(&cache.indices_by_name, selected);
            }
            ValueLabelCache::Indexed(cache) => {
                let indices =
                    selected_value_label_location_indices(&cache.indices_by_name, selected)?;
                self.populate_indexed_value_labels(&indices, should_interrupt)?;
                return Ok(indices);
            }
            ValueLabelCache::Empty => {}
        }
        check_cancel(should_interrupt)?;
        let mut locations = Vec::new();
        let mut indices_by_name = HashMap::new();
        let (tables, layout) = read_value_labels_streaming(
            &mut self.reader,
            &self.metadata,
            &mut self.scratch,
            should_interrupt,
            self.text_encoding,
            ValueLabelStreamingMode::Projected {
                selected,
                locations: &mut locations,
                indices_by_name: &mut indices_by_name,
            },
        )?;
        check_cancel(should_interrupt)?;
        let selected_indices = selected_value_label_location_indices(&indices_by_name, selected)?;
        let mut cached = HashMap::new();
        cached
            .try_reserve(tables.len())
            .map_err(|_| DtaError::ArithmeticOverflow("value-label cache allocation"))?;
        for (index, table) in selected_indices.iter().copied().zip(tables) {
            cached.insert(index, table);
        }
        self.value_labels = ValueLabelCache::Indexed(IndexedValueLabelCache {
            layout,
            locations,
            indices_by_name,
            tables: cached,
        });
        Ok(selected_indices)
    }

    fn projected_value_label_tables(
        &self,
        indices: &[usize],
    ) -> Result<Vec<&ValueLabelTable>, DtaError> {
        let mut tables = Vec::new();
        tables
            .try_reserve_exact(indices.len())
            .map_err(|_| DtaError::ArithmeticOverflow("projected value-label view allocation"))?;
        match &self.value_labels {
            ValueLabelCache::Full(cache) => {
                tables.extend(indices.iter().map(|&index| &cache.tables[index]));
            }
            ValueLabelCache::Indexed(cache) => tables.extend(
                indices
                    .iter()
                    .map(|index| cache.tables.get(index).expect("selected table was cached")),
            ),
            ValueLabelCache::Empty => unreachable!("value-label cache was initialized"),
        }
        Ok(tables)
    }

    fn projected_value_labels_should_move(&self, indices: &[usize]) -> bool {
        match &self.value_labels {
            ValueLabelCache::Full(cache) => indices
                .iter()
                .any(|&index| value_label_table_should_move(&cache.tables[index])),
            ValueLabelCache::Indexed(cache) => indices.iter().any(|index| {
                value_label_table_should_move(
                    cache
                        .tables
                        .get(index)
                        .expect("selected value-label table was cached"),
                )
            }),
            ValueLabelCache::Empty => unreachable!("value-label cache was initialized"),
        }
    }

    fn all_value_labels_should_move(&self) -> bool {
        let ValueLabelCache::Full(cache) = &self.value_labels else {
            unreachable!("full value-label cache was initialized")
        };
        let mut bytes = 0_usize;
        cache
            .tables
            .iter()
            .any(|table| accumulate_value_label_table_heap_bytes(table, &mut bytes, || {}))
    }

    fn take_all_value_label_tables(&mut self) -> Vec<ValueLabelTable> {
        let ValueLabelCache::Full(cache) =
            std::mem::replace(&mut self.value_labels, ValueLabelCache::Empty)
        else {
            unreachable!("full value-label cache was initialized")
        };
        cache.tables
    }

    fn take_projected_value_label_tables(
        &mut self,
        indices: &[usize],
    ) -> Result<Vec<ValueLabelTable>, DtaError> {
        take_projected_tables(&mut self.value_labels, indices)
    }

    fn populate_indexed_value_labels<F>(
        &mut self,
        selected_indices: &[usize],
        should_interrupt: &mut F,
    ) -> Result<(), DtaError>
    where
        F: FnMut() -> bool,
    {
        let ValueLabelCache::Indexed(cache) = &self.value_labels else {
            unreachable!("indexed value-label cache was initialized")
        };
        let mut missing = selected_indices.to_vec();
        missing.retain(|index| !cache.tables.contains_key(index));
        let layout = cache.layout;

        let mut decoded = Vec::new();
        decoded
            .try_reserve_exact(missing.len())
            .map_err(|_| DtaError::ArithmeticOverflow("value-label decode allocation"))?;
        for index in missing {
            check_cancel(should_interrupt)?;
            let ValueLabelCache::Indexed(cache) = &self.value_labels else {
                unreachable!("indexed value-label cache was initialized")
            };
            let table = read_indexed_value_label_table(
                &mut self.reader,
                &self.metadata,
                &mut self.scratch,
                should_interrupt,
                self.text_encoding,
                layout,
                &cache.locations[index],
            )?;
            decoded.push((index, table));
        }
        check_cancel(should_interrupt)?;

        let ValueLabelCache::Indexed(cache) = &mut self.value_labels else {
            unreachable!("indexed value-label cache was initialized")
        };
        for (index, table) in decoded {
            cache.tables.insert(index, table);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FileLayoutKind {
    Legacy,
    Modern,
}

fn inspect_file_layout<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
) -> Result<(FileLayoutKind, u64), DtaError> {
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
    let first = read_exact_at(reader, 0, 1, scratch, "reading signature")?;
    let kind = if matches!(first[0], 105 | 108 | 110 | 111 | 113..=115) {
        FileLayoutKind::Legacy
    } else {
        let signature_length = MODERN_SIGNATURE.len();
        if file_length < signature_length as u64
            || read_exact_at(reader, 0, signature_length, scratch, "reading signature")?
                != MODERN_SIGNATURE
        {
            return Err(DtaError::InvalidSignature);
        }
        FileLayoutKind::Modern
    };
    Ok((kind, file_length))
}

fn read_file_metadata<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<(DtaMetadata, u64), DtaError> {
    let (kind, file_length) = inspect_file_layout(reader, scratch)?;
    let metadata = match kind {
        FileLayoutKind::Legacy => read_legacy_metadata(reader, file_length, scratch, encoding)?,
        FileLayoutKind::Modern => read_modern_metadata(reader, file_length, scratch, encoding)?,
    };
    Ok((metadata, file_length))
}

fn read_file_schema_summary<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaSchemaSummary, DtaError> {
    let (kind, file_length) = inspect_file_layout(reader, scratch)?;
    match kind {
        FileLayoutKind::Legacy => {
            read_legacy_schema_summary(reader, file_length, scratch, encoding)
        }
        FileLayoutKind::Modern => {
            read_modern_schema_summary(reader, file_length, scratch, encoding)
        }
    }
}

fn check_cancel<F: FnMut() -> bool>(should_interrupt: &mut F) -> Result<(), DtaError> {
    if should_interrupt() {
        Err(DtaError::Cancelled)
    } else {
        Ok(())
    }
}

fn check_coarse_cancel<I: InterruptChecks>(interrupts: &mut I) -> Result<(), DtaError> {
    if interrupts.coarse() {
        Err(DtaError::Cancelled)
    } else {
        Ok(())
    }
}

fn check_frequent_cancel<I: InterruptChecks>(interrupts: &mut I) -> Result<(), DtaError> {
    if interrupts.frequent() {
        Err(DtaError::Cancelled)
    } else {
        Ok(())
    }
}

fn checked_add_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_add(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn observation_payload_start(metadata: &DtaMetadata) -> Result<u64, DtaError> {
    if metadata.format_version.is_modern() {
        checked_add_u64(metadata.section_offsets.data, 6, "data payload offset")
    } else {
        Ok(metadata.section_offsets.data)
    }
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
    let mut bytes = Vec::new();
    read_exact_at_into(reader, offset, length, scratch, &mut bytes, context)?;
    Ok(bytes)
}

fn read_exact_at_into<R: Read + Seek>(
    reader: &mut R,
    offset: u64,
    length: usize,
    scratch: &mut Scratch,
    bytes: &mut Vec<u8>,
    context: &'static str,
) -> Result<(), DtaError> {
    reader
        .seek(SeekFrom::Start(offset))
        .map_err(|error| DtaError::Io {
            context,
            offset,
            kind: error.kind(),
        })?;
    read_exact_current_into(reader, offset, length, scratch, bytes, context)
}

fn read_exact_current_into<R: Read>(
    reader: &mut R,
    offset: u64,
    length: usize,
    scratch: &mut Scratch,
    bytes: &mut Vec<u8>,
    context: &'static str,
) -> Result<(), DtaError> {
    scratch.record(length)?;
    if bytes.len() < length {
        bytes
            .try_reserve_exact(length - bytes.len())
            .map_err(|_| DtaError::ArithmeticOverflow("file read allocation"))?;
        bytes.resize(length, 0);
    } else {
        bytes.truncate(length);
    }
    let mut completed = 0_usize;
    while completed < length {
        let read_offset = offset
            .checked_add(
                u64::try_from(completed)
                    .map_err(|_| DtaError::ArithmeticOverflow("file read offset"))?,
            )
            .ok_or(DtaError::ArithmeticOverflow("file read offset"))?;
        let count = reader
            .read(&mut bytes[completed..length])
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
    Ok(())
}

/// Sequential, bounded look-ahead for metadata sections. It amortizes tiny
/// record fields into bounded block reads while retaining precise offsets
/// and allowing rejected payloads to be skipped without materialization.
struct BufferedSectionReader<'a, R> {
    reader: &'a mut R,
    scratch: &'a mut Scratch,
    buffer: Vec<u8>,
    buffer_start: u64,
    position: u64,
    end: u64,
}

impl<'a, R: Read + Seek> BufferedSectionReader<'a, R> {
    fn new(reader: &'a mut R, scratch: &'a mut Scratch, position: u64, end: u64) -> Self {
        Self {
            reader,
            scratch,
            buffer: Vec::new(),
            buffer_start: position,
            position,
            end,
        }
    }

    fn position(&self) -> u64 {
        self.position
    }

    fn available(&self) -> usize {
        let Some(relative) = self.position.checked_sub(self.buffer_start) else {
            return 0;
        };
        let Ok(relative) = usize::try_from(relative) else {
            return 0;
        };
        self.buffer.len().saturating_sub(relative)
    }

    fn refill(&mut self, context: &'static str) -> Result<(), DtaError> {
        let remaining =
            usize::try_from(self.end.saturating_sub(self.position)).unwrap_or(usize::MAX);
        let length = remaining
            .min(self.scratch.limit)
            .min(METADATA_SECTION_BUFFER_BYTES);
        if length == 0 {
            return Err(DtaError::Io {
                context,
                offset: self.position,
                kind: ErrorKind::UnexpectedEof,
            });
        }
        read_exact_at_into(
            self.reader,
            self.position,
            length,
            self.scratch,
            &mut self.buffer,
            context,
        )?;
        self.buffer_start = self.position;
        Ok(())
    }

    fn read_into(
        &mut self,
        length: usize,
        output: &mut Vec<u8>,
        context: &'static str,
    ) -> Result<(), DtaError> {
        self.scratch.record(length)?;
        output
            .try_reserve(length.saturating_sub(output.len()))
            .map_err(|_| DtaError::ArithmeticOverflow("metadata field allocation"))?;
        output.resize(length, 0);
        let mut completed = 0;
        while completed < length {
            if self.available() == 0 {
                self.refill(context)?;
            }
            let relative = usize::try_from(self.position - self.buffer_start)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata buffer offset"))?;
            let take = (length - completed).min(self.available());
            output[completed..completed + take]
                .copy_from_slice(&self.buffer[relative..relative + take]);
            self.position = checked_add_u64(
                self.position,
                u64::try_from(take)
                    .map_err(|_| DtaError::ArithmeticOverflow("metadata read length"))?,
                "metadata read length",
            )?;
            completed += take;
        }
        Ok(())
    }

    fn read_exact_into(
        &mut self,
        length: usize,
        output: &mut Vec<u8>,
        context: &'static str,
    ) -> Result<(), DtaError> {
        let target = checked_add_u64(
            self.position,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata read length"))?,
            "metadata read length",
        )?;
        if target > self.end {
            return Err(DtaError::Io {
                context,
                offset: self.position,
                kind: ErrorKind::UnexpectedEof,
            });
        }
        read_exact_at_into(
            self.reader,
            self.position,
            length,
            self.scratch,
            output,
            context,
        )?;
        self.position = target;
        self.buffer.clear();
        self.buffer_start = target;
        Ok(())
    }

    fn read_with_mode(
        &mut self,
        length: usize,
        output: &mut Vec<u8>,
        context: &'static str,
        read_ahead: bool,
    ) -> Result<(), DtaError> {
        if read_ahead {
            self.read_into(length, output, context)
        } else {
            self.read_exact_into(length, output, context)
        }
    }

    fn advance(&mut self, length: usize, context: &'static str) -> Result<(), DtaError> {
        let target = checked_add_u64(
            self.position,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata skip length"))?,
            "metadata skip length",
        )?;
        if target > self.end {
            return Err(DtaError::Truncated {
                context,
                offset: error_offset(self.position),
                needed: length,
                available: usize::try_from(self.end.saturating_sub(self.position))
                    .unwrap_or(usize::MAX),
            });
        }
        self.position = target;
        Ok(())
    }

    fn validate_field(&mut self, length: usize, context: &'static str) -> Result<(), DtaError> {
        self.consume_field(length, None, context).map(drop)
    }

    fn validate_buffered_field_at(
        &mut self,
        offset: u64,
        length: usize,
        context: &'static str,
    ) -> Result<(), DtaError> {
        validate_raw_value_length(length, error_offset(offset), context)?;
        if let Some(relative) = offset
            .checked_sub(self.buffer_start)
            .and_then(|relative| usize::try_from(relative).ok())
        {
            if let Some(bytes) = self.buffer.get(relative..relative.saturating_add(length)) {
                validate_raw_value_bytes(bytes, error_offset(offset), context)?;
                return Ok(());
            }
        }

        let end = checked_add_u64(
            offset,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata value length"))?,
            "metadata value length",
        )?;
        let mut value = BufferedSectionReader::new(self.reader, self.scratch, offset, end);
        value.validate_field(length, context)
    }

    fn consume_field(
        &mut self,
        length: usize,
        encoding: Option<TextEncoding>,
        context: &'static str,
    ) -> Result<String, DtaError> {
        let start = self.position;
        validate_raw_value_length(length, error_offset(start), context)?;
        let end = checked_add_u64(
            start,
            u64::try_from(length)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata value length"))?,
            "metadata value length",
        )?;
        if end > self.end {
            return Err(DtaError::Truncated {
                context,
                offset: error_offset(start),
                needed: length,
                available: usize::try_from(self.end.saturating_sub(start)).unwrap_or(usize::MAX),
            });
        }
        let mut decoder = encoding.map(TextEncoding::new_decoder);
        let mut output = String::new();
        let mut content_length = 0_usize;
        while self.position < end {
            if self.available() == 0 {
                self.refill(context)?;
            }
            let relative = usize::try_from(self.position - self.buffer_start)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata buffer offset"))?;
            let remaining = usize::try_from(end - self.position)
                .map_err(|_| DtaError::ArithmeticOverflow("metadata value length"))?;
            let take = remaining.min(self.available());
            let bytes = &self.buffer[relative..relative + take];
            let nul = bytes.iter().position(|byte| *byte == 0);
            let input = nul.map_or(bytes, |index| &bytes[..index]);
            content_length = content_length
                .checked_add(input.len())
                .ok_or(DtaError::ArithmeticOverflow("metadata value length"))?;
            if content_length > MAX_METADATA_VALUE_BYTES {
                return Err(DtaError::MetadataValueTooLong {
                    context,
                    offset: error_offset(start),
                    length: content_length,
                    limit: MAX_METADATA_VALUE_BYTES,
                });
            }
            let next = checked_add_u64(
                self.position,
                u64::try_from(take)
                    .map_err(|_| DtaError::ArithmeticOverflow("metadata value length"))?,
                "metadata value length",
            )?;
            let last = nul.is_some() || next == end;
            if let Some(decoder) = decoder.as_mut() {
                decode_into_string(decoder, input, last, &mut output)?;
            }
            self.position = next;
            if nul.is_some() {
                self.position = end;
                break;
            }
        }
        Ok(output)
    }
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
    let mut bytes = Vec::new();

    loop {
        check_cancel(should_interrupt)?;
        let remaining = length.saturating_sub(completed);
        let chunk_length = remaining.min(scratch.limit);
        if chunk_length == 0 {
            bytes.clear();
        } else {
            let chunk_offset = offset
                .checked_add(
                    u64::try_from(completed)
                        .map_err(|_| DtaError::ArithmeticOverflow("string read offset"))?,
                )
                .ok_or(DtaError::ArithmeticOverflow("string read offset"))?;
            read_exact_at_into(
                reader,
                chunk_offset,
                chunk_length,
                scratch,
                &mut bytes,
                context,
            )?;
        }
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
    requested_offsets: &mut [usize],
    requested_offsets_start: u64,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    context: &'static str,
) -> Result<String, DtaError> {
    let mut ordered = requested_offsets
        .iter()
        .copied()
        .enumerate()
        .map(|(index, offset)| (offset, index))
        .collect::<Vec<_>>();
    // Boundary failures track the lowest source entry explicitly, so an
    // unstable sort avoids another entry-sized merge-sort allocation.
    ordered.sort_unstable_by_key(|(offset, _)| *offset);
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
            let group_end = next_mapping
                + ordered[next_mapping..].partition_point(|(candidate, _)| *candidate == boundary);
            let input_end = boundary.saturating_sub(completed).min(bytes.len());
            let original_index = ordered[next_mapping..group_end]
                .iter()
                .map(|(_, original_index)| *original_index)
                .min()
                .expect("offset group is nonempty");
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
            for mapping in &mut ordered[next_mapping..group_end] {
                mapping.0 = output.len();
            }
            next_mapping = group_end;
            decoder = encoding.new_decoder();
        }
        let last = chunk_end == length;
        decode_into_string(&mut decoder, &bytes[input_start..], last, &mut output)?;
        completed = chunk_end;
        if last {
            if let Some((entry_index, boundary)) = first_invalid_boundary {
                return Err(DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: error_offset(
                        requested_offsets_start.saturating_add(
                            u64::try_from(entry_index)
                                .unwrap_or(u64::MAX)
                                .saturating_mul(4),
                        ),
                    ),
                    text_offset: i32::try_from(boundary).unwrap_or(i32::MAX),
                    text_length: length,
                });
            }
            output.shrink_to_fit();
            ordered.sort_unstable_by_key(|(_, original_index)| *original_index);
            for (requested_offset, (mapped_offset, _)) in requested_offsets.iter_mut().zip(ordered)
            {
                *requested_offset = mapped_offset;
            }
            return Ok(output);
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

fn read_fixed_text_fields<R: Read + Seek>(
    reader: &mut R,
    payload: u64,
    count: usize,
    width: usize,
    encoding: TextEncoding,
    scratch: &mut Scratch,
    context: &'static str,
) -> Result<Vec<String>, DtaError> {
    let fields_per_chunk = (scratch.limit / width).max(1);
    let mut values = Vec::new();
    values
        .try_reserve_exact(count)
        .map_err(|_| DtaError::ArithmeticOverflow("metadata text fields"))?;
    let mut first = 0_usize;
    while first < count {
        let field_count = (count - first).min(fields_per_chunk);
        let length = field_count
            .checked_mul(width)
            .ok_or(DtaError::ArithmeticOverflow("metadata text block"))?;
        let offset = payload
            .checked_add(
                u64::try_from(
                    first
                        .checked_mul(width)
                        .ok_or(DtaError::ArithmeticOverflow("metadata text offset"))?,
                )
                .map_err(|_| DtaError::ArithmeticOverflow("metadata text offset"))?,
            )
            .ok_or(DtaError::ArithmeticOverflow("metadata text offset"))?;
        let bytes = read_exact_at(reader, offset, length, scratch, context)?;
        for field in bytes.chunks_exact(width) {
            values.push(encoding.decode_cow(field_bytes(field)).into_owned());
        }
        first = first
            .checked_add(field_count)
            .ok_or(DtaError::ArithmeticOverflow("metadata field index"))?;
    }
    Ok(values)
}

fn read_modern_type_codes<R: Read + Seek>(
    reader: &mut R,
    payload: u64,
    count: usize,
    byte_order: ByteOrder,
    scratch: &mut Scratch,
) -> Result<Vec<u16>, DtaError> {
    let type_width = 2_usize;
    let fields_per_chunk = (scratch.limit / type_width).max(1);
    let mut values = Vec::new();
    values
        .try_reserve_exact(count)
        .map_err(|_| DtaError::ArithmeticOverflow("variable type codes"))?;
    let mut first = 0_usize;
    while first < count {
        let field_count = (count - first).min(fields_per_chunk);
        let length = field_count
            .checked_mul(type_width)
            .ok_or(DtaError::ArithmeticOverflow("variable type block"))?;
        let offset = payload
            .checked_add(
                u64::try_from(
                    first
                        .checked_mul(type_width)
                        .ok_or(DtaError::ArithmeticOverflow("variable type offset"))?,
                )
                .map_err(|_| DtaError::ArithmeticOverflow("variable type offset"))?,
            )
            .ok_or(DtaError::ArithmeticOverflow("variable type offset"))?;
        let bytes = read_exact_at(reader, offset, length, scratch, "reading variable types")?;
        for field in bytes.chunks_exact(type_width) {
            values.push(read_u16(field, 0, byte_order, "variable type")?);
        }
        first = first
            .checked_add(field_count)
            .ok_or(DtaError::ArithmeticOverflow("variable type index"))?;
    }
    Ok(values)
}

fn read_legacy_type_codes<R: Read + Seek>(
    reader: &mut R,
    payload: u64,
    count: usize,
    scratch: &mut Scratch,
) -> Result<Vec<u16>, DtaError> {
    let mut values = Vec::new();
    values
        .try_reserve_exact(count)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy variable type codes"))?;
    let mut raw = Vec::new();
    while values.len() < count {
        let chunk_count = (count - values.len()).min(scratch.limit);
        let offset = checked_add_u64(
            payload,
            u64::try_from(values.len())
                .map_err(|_| DtaError::ArithmeticOverflow("legacy variable type offset"))?,
            "legacy variable type offset",
        )?;
        read_exact_at_into(
            reader,
            offset,
            chunk_count,
            scratch,
            &mut raw,
            "reading legacy variable types",
        )?;
        values.extend(raw.iter().copied().map(u16::from));
    }
    Ok(values)
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

struct ModernCharacteristicScan {
    start: u64,
    end: u64,
    byte_order: ByteOrder,
    names_length: usize,
    adaptive_read_ahead: bool,
}

fn walk_modern_characteristic_records<R, F>(
    reader: &mut R,
    scratch: &mut Scratch,
    scan: ModernCharacteristicScan,
    mut visit: F,
) -> Result<(), DtaError>
where
    R: Read + Seek,
    F: FnMut(&mut BufferedSectionReader<'_, R>, u64, usize) -> Result<(), DtaError>,
{
    let mut section = BufferedSectionReader::new(reader, scratch, scan.start, scan.end);
    let mut record = Vec::new();
    let mut read_ahead = !scan.adaptive_read_ahead;
    loop {
        let record_offset = section.position();
        section.read_with_mode(4, &mut record, "reading characteristic tag", read_ahead)?;
        if record == b"</ch" {
            section.read_with_mode(
                b"aracteristics>".len(),
                &mut record,
                "reading </characteristics>",
                read_ahead,
            )?;
            if record != b"aracteristics>" {
                return Err(DtaError::UnexpectedTag {
                    expected: "</characteristics>",
                    offset: error_offset(record_offset),
                });
            }
            ensure_absolute("data", section.position(), scan.end)?;
            return Ok(());
        }
        if record != b"<ch>" {
            return Err(DtaError::UnexpectedTag {
                expected: "<ch> or </characteristics>",
                offset: error_offset(record_offset),
            });
        }
        section.read_with_mode(4, &mut record, "reading characteristic length", read_ahead)?;
        let payload_length = usize::try_from(read_u32(
            &record,
            0,
            scan.byte_order,
            "characteristic length",
        )?)
        .map_err(|_| DtaError::ArithmeticOverflow("characteristic length"))?;
        let payload_offset = section.position();
        if payload_length < scan.names_length {
            return Err(DtaError::Truncated {
                context: "characteristic names",
                offset: error_offset(payload_offset),
                needed: scan.names_length,
                available: payload_length,
            });
        }
        let close = checked_add_u64(
            payload_offset,
            u64::try_from(payload_length)
                .map_err(|_| DtaError::ArithmeticOverflow("characteristic payload length"))?,
            "characteristic payload",
        )?;
        let after_close = checked_add_u64(close, 5, "characteristic closing tag")?;
        if after_close > scan.end {
            return Err(DtaError::Truncated {
                context: "characteristic payload",
                offset: error_offset(payload_offset),
                needed: payload_length.saturating_add(5),
                available: usize::try_from(scan.end.saturating_sub(payload_offset))
                    .unwrap_or(usize::MAX),
            });
        }
        visit(&mut section, payload_offset, payload_length)?;
        debug_assert_eq!(section.position(), close);
        read_ahead = !scan.adaptive_read_ahead
            || payload_length < METADATA_SECTION_BUFFER_BYTES.saturating_div(2);
        section.read_with_mode(5, &mut record, "reading </ch>", read_ahead)?;
        if record != b"</ch>" {
            return Err(DtaError::UnexpectedTag {
                expected: "</ch>",
                offset: error_offset(close),
            });
        }
        debug_assert_eq!(section.position(), after_close);
    }
}

struct FileCharacteristicValue {
    value_offset: u64,
    value_length: usize,
    context: &'static str,
}

#[allow(clippy::too_many_arguments)]
fn plan_file_characteristic<R: Read + Seek>(
    plan: &mut CharacteristicPlan<FileCharacteristicValue>,
    section: &mut BufferedSectionReader<'_, R>,
    ordinal: usize,
    payload_length: usize,
    name_width: usize,
    encoding: TextEncoding,
    variable_indexes: &mut VariableTargetIndexes<'_>,
    names_context: &'static str,
    value_context: &'static str,
) -> Result<(), DtaError> {
    let names_length = name_width
        .checked_mul(2)
        .ok_or(DtaError::ArithmeticOverflow("characteristic names length"))?;
    let payload_offset = section.position();
    let value_offset = checked_add_u64(
        payload_offset,
        u64::try_from(names_length)
            .map_err(|_| DtaError::ArithmeticOverflow("characteristic names length"))?,
        "characteristic value offset",
    )?;
    let value_length = payload_length - names_length;
    let value_end = checked_add_u64(
        value_offset,
        u64::try_from(value_length)
            .map_err(|_| DtaError::ArithmeticOverflow("characteristic value length"))?,
        "characteristic value length",
    )?;

    if plan.has_deferred_error() {
        section.advance(payload_length, value_context)?;
        return Ok(());
    }

    let mut names = Vec::new();
    section.read_into(names_length, &mut names, names_context)?;
    let target = encoding.decode(field_bytes(&names[..name_width]));
    let name = encoding.decode(field_bytes(&names[name_width..]));
    let replaced = plan.push_record_replacing(
        ordinal,
        &target,
        name,
        error_offset(payload_offset.saturating_add(name_width as u64)),
        |target| variable_indexes.resolve(target),
        |value_use| match value_use {
            CharacteristicValueUse::Skip => {
                section.advance(value_length, value_context)?;
                Ok(None)
            }
            CharacteristicValueUse::Retain => {
                let validation = validate_raw_value_length(
                    value_length,
                    error_offset(value_offset),
                    value_context,
                );
                section.advance(value_length, value_context)?;
                validation?;
                Ok(Some(FileCharacteristicValue {
                    value_offset,
                    value_length,
                    context: value_context,
                }))
            }
            CharacteristicValueUse::Validate => {
                let validation = section.validate_field(value_length, value_context);
                if validation.is_err() {
                    section.position = value_end;
                }
                validation?;
                Ok(None)
            }
        },
    )?;
    if let Some((replaced_ordinal, replaced)) = replaced {
        if let Err(error) = section.validate_buffered_field_at(
            replaced.value_offset,
            replaced.value_length,
            replaced.context,
        ) {
            plan.defer_value_error(replaced_ordinal, error);
        }
    }
    debug_assert_eq!(section.position(), value_end);
    Ok(())
}

fn decode_file_characteristics<R: Read + Seek>(
    plan: CharacteristicPlan<FileCharacteristicValue>,
    reader: &mut R,
    encoding: TextEncoding,
    scratch: &mut Scratch,
) -> Result<DecodedCharacteristics, DtaError> {
    plan.decode(|record| {
        let (value, found_nul) = decode_range(
            reader,
            record.value_offset,
            record.value_length,
            encoding,
            true,
            scratch,
            &mut || false,
            record.context,
        )?;
        if record.value_length > MAX_METADATA_VALUE_BYTES && !found_nul {
            return Err(DtaError::MetadataValueTooLong {
                context: record.context,
                offset: error_offset(record.value_offset),
                length: record.value_length,
                limit: MAX_METADATA_VALUE_BYTES,
            });
        }
        Ok(value)
    })
}

fn scan_modern_characteristics<R: Read + Seek, F>(
    reader: &mut R,
    header: &FileModernHeaderMap,
    scratch: &mut Scratch,
    mut visit: F,
) -> Result<(), DtaError>
where
    F: FnMut(&mut BufferedSectionReader<'_, R>, usize, usize) -> Result<(), DtaError>,
{
    let width = if header.format_version == FormatVersion::V117 {
        33_usize
    } else {
        129_usize
    };
    let names_length = width
        .checked_mul(2)
        .ok_or(DtaError::ArithmeticOverflow("characteristic names length"))?;
    let close_offset = header
        .section_offsets
        .data
        .checked_sub(b"</characteristics>".len() as u64)
        .ok_or(DtaError::ArithmeticOverflow("characteristics closing tag"))?;
    let after_close = expect_file_tag(
        reader,
        close_offset,
        b"</characteristics>",
        "</characteristics>",
        scratch,
    )?;
    ensure_absolute("data", after_close, header.section_offsets.data)?;
    let cursor = expect_file_tag(
        reader,
        header.section_offsets.characteristics,
        b"<characteristics>",
        "<characteristics>",
        scratch,
    )?;
    let mut ordinal = 0_usize;
    walk_modern_characteristic_records(
        reader,
        scratch,
        ModernCharacteristicScan {
            start: cursor,
            end: header.section_offsets.data,
            byte_order: header.byte_order,
            names_length,
            adaptive_read_ahead: true,
        },
        |section, _, payload_length| {
            visit(section, ordinal, payload_length)?;
            ordinal = ordinal
                .checked_add(1)
                .ok_or(DtaError::ArithmeticOverflow("characteristic record count"))?;
            Ok(())
        },
    )
}

fn validate_modern_characteristic_framing<R: Read + Seek>(
    reader: &mut R,
    header: &FileModernHeaderMap,
    scratch: &mut Scratch,
) -> Result<(), DtaError> {
    scan_modern_characteristics(reader, header, scratch, |section, _, payload_length| {
        section.advance(payload_length, "characteristic payload")
    })
}

fn read_modern_characteristics<R: Read + Seek>(
    reader: &mut R,
    header: &FileModernHeaderMap,
    encoding: TextEncoding,
    scratch: &mut Scratch,
    variables: &[VariableInfo],
) -> Result<DecodedCharacteristics, DtaError> {
    let width = if header.format_version == FormatVersion::V117 {
        33_usize
    } else {
        129_usize
    };
    let mut plan = CharacteristicPlan::default();
    let mut variable_indexes = VariableTargetIndexes::new(variables);
    scan_modern_characteristics(
        reader,
        header,
        scratch,
        |section, ordinal, payload_length| {
            plan_file_characteristic(
                &mut plan,
                section,
                ordinal,
                payload_length,
                width,
                encoding,
                &mut variable_indexes,
                "reading characteristic names",
                "characteristic value",
            )
        },
    )?;
    drop(variable_indexes);
    decode_file_characteristics(plan, reader, encoding, scratch)
}

struct LegacyExpansionRecord {
    data_type: u8,
    payload_length: usize,
}

struct LegacyExpansionPlan {
    data_offset: u64,
}

fn read_legacy_expansion_record<R: Read + Seek>(
    section: &mut BufferedSectionReader<'_, R>,
    header: &mut Vec<u8>,
    byte_order: ByteOrder,
    layout: LegacyLayout,
    read_ahead: bool,
) -> Result<Option<LegacyExpansionRecord>, DtaError> {
    let header_offset = section.position();
    section.read_with_mode(
        layout.expansion_header_width(),
        header,
        "reading legacy expansion field",
        read_ahead,
    )?;
    let data_type = header[0];
    let length = if layout.expansion_length_width == 2 {
        i32::from(read_i16(
            header,
            1,
            byte_order,
            "legacy expansion-field length",
        )?)
    } else {
        read_i32(header, 1, byte_order, "legacy expansion-field length")?
    };
    if data_type == 0 && length == 0 {
        return Ok(None);
    }
    if length < 0 {
        return Err(DtaError::NegativeExpansionLength {
            value: length,
            offset: error_offset(header_offset.saturating_add(1)),
        });
    }
    if data_type == 0 {
        return Err(DtaError::InvalidExpansionTerminator {
            value: length,
            offset: error_offset(header_offset),
        });
    }
    let payload_offset = section.position();
    let payload_length = usize::try_from(length)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion length"))?;
    let payload_end = checked_add_u64(
        payload_offset,
        u64::try_from(payload_length)
            .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion length"))?,
        "legacy expansion payload",
    )?;
    if payload_end > section.end {
        return Err(DtaError::Truncated {
            context: "legacy expansion-field payload",
            offset: error_offset(payload_offset),
            needed: payload_length,
            available: usize::try_from(section.end.saturating_sub(payload_offset))
                .unwrap_or(usize::MAX),
        });
    }
    Ok(Some(LegacyExpansionRecord {
        data_type,
        payload_length,
    }))
}

fn walk_legacy_expansion_records<R: Read + Seek, F>(
    reader: &mut R,
    scratch: &mut Scratch,
    start: u64,
    file_length: u64,
    byte_order: ByteOrder,
    layout: LegacyLayout,
    mut visit: F,
) -> Result<LegacyExpansionPlan, DtaError>
where
    F: FnMut(
        &mut BufferedSectionReader<'_, R>,
        usize,
        LegacyExpansionRecord,
    ) -> Result<(), DtaError>,
{
    // Keep malformed unterminated streams bounded by locating the sentinel
    // before the collection pass allocates decoded values.
    let mut header = Vec::new();
    let mut section = BufferedSectionReader::new(reader, scratch, start, file_length);
    let mut read_ahead = false;
    let mut ordinal = 0_usize;
    loop {
        let Some(record) = read_legacy_expansion_record(
            &mut section,
            &mut header,
            byte_order,
            layout,
            read_ahead,
        )?
        else {
            return Ok(LegacyExpansionPlan {
                data_offset: section.position(),
            });
        };
        let payload_length = record.payload_length;
        visit(&mut section, ordinal, record)?;
        ordinal = ordinal.checked_add(1).ok_or(DtaError::ArithmeticOverflow(
            "legacy expansion record count",
        ))?;
        read_ahead = payload_length < METADATA_SECTION_BUFFER_BYTES.saturating_div(2);
    }
}

#[cfg(test)]
fn validate_legacy_expansion_framing<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
    start: u64,
    file_length: u64,
    byte_order: ByteOrder,
    layout: LegacyLayout,
) -> Result<LegacyExpansionPlan, DtaError> {
    walk_legacy_expansion_records(
        reader,
        scratch,
        start,
        file_length,
        byte_order,
        layout,
        |section, _, record| {
            section.advance(record.payload_length, "legacy expansion-field payload")
        },
    )
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
    let dataset_label = FileTextRange {
        offset: cursor,
        length: label_length,
    };
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

struct ModernSchemaCore {
    header: FileModernHeaderMap,
    encoding: TextEncoding,
    schema: ParsedSchema,
    formats: u64,
    value_label_names: u64,
    variable_labels: u64,
    widths: crate::metadata::FieldWidths,
}

fn read_modern_schema_core<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<ModernSchemaCore, DtaError> {
    let header = read_modern_header_map(reader, scratch)?;
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
    let type_codes = read_modern_type_codes(reader, types_start, nvar, header.byte_order, scratch)?;
    let names = read_fixed_text_fields(
        reader,
        varnames,
        nvar,
        widths.varname,
        encoding,
        scratch,
        "reading variable names",
    )?;
    let schema = build_parsed_schema(header.format_version, type_codes, names, |type_code| {
        resolve_type(type_code, header.format_version)
    })?;
    Ok(ModernSchemaCore {
        header,
        encoding,
        schema,
        formats,
        value_label_names,
        variable_labels,
        widths,
    })
}

fn read_modern_schema_summary<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaSchemaSummary, DtaError> {
    let core = read_modern_schema_core(reader, file_length, scratch, encoding)?;
    validate_modern_characteristic_framing(reader, &core.header, scratch)?;
    Ok(core.schema.into_summary())
}

fn read_modern_metadata<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    let core = read_modern_schema_core(reader, file_length, scratch, encoding)?;
    let ModernSchemaCore {
        header,
        encoding,
        schema,
        formats: formats_offset,
        value_label_names: value_label_names_offset,
        variable_labels: variable_labels_offset,
        widths,
    } = core;
    let mut never_cancel = || false;
    let dataset_label = decode_range(
        reader,
        header.dataset_label.offset,
        header.dataset_label.length,
        encoding,
        false,
        scratch,
        &mut never_cancel,
        "reading dataset label",
    )?
    .0;
    let formats = read_fixed_text_fields(
        reader,
        formats_offset,
        schema.variables.len(),
        widths.format,
        encoding,
        scratch,
        "reading variable formats",
    )?;
    let value_label_names = read_fixed_text_fields(
        reader,
        value_label_names_offset,
        schema.variables.len(),
        widths.value_label_name,
        encoding,
        scratch,
        "reading variable value-label names",
    )?;
    let labels = read_fixed_text_fields(
        reader,
        variable_labels_offset,
        schema.variables.len(),
        widths.variable_label,
        encoding,
        scratch,
        "reading variable labels",
    )?;
    let (mut variables, obs_length) = schema.into_variables(formats, value_label_names, labels)?;
    let mut notes = Vec::new();
    let mut characteristics = Vec::new();
    let collector = read_modern_characteristics(reader, &header, encoding, scratch, &variables)?;
    collector.finish(&mut notes, &mut characteristics, &mut variables);
    Ok(DtaMetadata {
        format_version: header.format_version,
        byte_order: header.byte_order,
        nvar: header.nvar,
        nobs: header.nobs,
        dataset_label,
        notes,
        characteristics,
        variables,
        section_offsets: header.section_offsets,
        obs_length,
    })
}

struct LegacySchemaCore {
    version: FormatVersion,
    layout: LegacyLayout,
    byte_order: ByteOrder,
    nvar: u32,
    nobs: u64,
    encoding: TextEncoding,
    schema: ParsedSchema,
    dataset_label: FileTextRange,
    variable_types: u64,
    varnames: u64,
    sortlist: u64,
    formats: u64,
    value_label_names: u64,
    variable_labels: u64,
    fixed_end: u64,
}

fn read_legacy_schema_core<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<LegacySchemaCore, DtaError> {
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

    let type_codes = read_legacy_type_codes(reader, variable_types, nvar_usize, scratch)?;
    let names = read_fixed_text_fields(
        reader,
        varnames,
        nvar_usize,
        layout.varname_width,
        encoding,
        scratch,
        "reading legacy variable names",
    )?;
    let schema = build_parsed_schema(version, type_codes, names, |code| {
        legacy_type(
            u8::try_from(code).map_err(|_| DtaError::UnknownTypeCode { code, version })?,
            version,
        )
    })?;

    Ok(LegacySchemaCore {
        version,
        layout,
        byte_order,
        nvar,
        nobs,
        encoding,
        schema,
        dataset_label: FileTextRange {
            offset: 10,
            length: layout.dataset_label_width,
        },
        variable_types,
        varnames,
        sortlist,
        formats,
        value_label_names,
        variable_labels,
        fixed_end: fixed_end_u64,
    })
}

fn validate_legacy_observation_extent(
    data_offset: u64,
    nobs: u64,
    obs_length: u64,
    file_length: u64,
) -> Result<u64, DtaError> {
    let observation_bytes = nobs
        .checked_mul(obs_length)
        .ok_or(DtaError::ArithmeticOverflow(
            "legacy observation data length",
        ))?;
    let value_labels =
        checked_add_u64(data_offset, observation_bytes, "legacy value-label offset")?;
    if value_labels > file_length {
        return Err(DtaError::Truncated {
            context: "legacy observation data",
            offset: error_offset(data_offset),
            needed: usize::try_from(observation_bytes).unwrap_or(usize::MAX),
            available: usize::try_from(file_length.saturating_sub(data_offset))
                .unwrap_or(usize::MAX),
        });
    }
    Ok(value_labels)
}

fn read_legacy_schema_summary<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaSchemaSummary, DtaError> {
    let core = read_legacy_schema_core(reader, file_length, scratch, encoding)?;
    let expansion = walk_legacy_expansion_records(
        reader,
        scratch,
        core.fixed_end,
        file_length,
        core.byte_order,
        core.layout,
        |section, _, record| {
            section.advance(record.payload_length, "legacy expansion-field payload")
        },
    )?;
    validate_legacy_observation_extent(
        expansion.data_offset,
        core.nobs,
        core.schema.obs_length,
        file_length,
    )?;
    Ok(core.schema.into_summary())
}

fn read_legacy_metadata<R: Read + Seek>(
    reader: &mut R,
    file_length: u64,
    scratch: &mut Scratch,
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    let core = read_legacy_schema_core(reader, file_length, scratch, encoding)?;
    let LegacySchemaCore {
        version,
        layout,
        byte_order,
        nvar,
        nobs,
        encoding,
        schema,
        dataset_label,
        variable_types,
        varnames,
        sortlist,
        formats: formats_offset,
        value_label_names: value_label_names_offset,
        variable_labels: variable_labels_offset,
        fixed_end,
    } = core;
    let mut never_cancel = || false;
    let dataset_label = decode_range(
        reader,
        dataset_label.offset,
        dataset_label.length,
        encoding,
        true,
        scratch,
        &mut never_cancel,
        "reading legacy dataset label",
    )?
    .0;
    let count = schema.variables.len();
    let formats = read_fixed_text_fields(
        reader,
        formats_offset,
        count,
        layout.format_width,
        encoding,
        scratch,
        "reading legacy display formats",
    )?;
    let value_label_names = read_fixed_text_fields(
        reader,
        value_label_names_offset,
        count,
        layout.value_label_name_width,
        encoding,
        scratch,
        "reading legacy value-label names",
    )?;
    let labels = read_fixed_text_fields(
        reader,
        variable_labels_offset,
        count,
        layout.variable_label_width,
        encoding,
        scratch,
        "reading legacy variable labels",
    )?;
    let (mut variables, obs_length) = schema.into_variables(formats, value_label_names, labels)?;
    let mut characteristic_plan = CharacteristicPlan::default();
    let mut variable_indexes = VariableTargetIndexes::new(&variables);
    let expansion_plan = walk_legacy_expansion_records(
        reader,
        scratch,
        fixed_end,
        file_length,
        byte_order,
        layout,
        |section, ordinal, record| {
            if record.data_type == 1 && record.payload_length >= 2 * layout.varname_width {
                plan_file_characteristic(
                    &mut characteristic_plan,
                    section,
                    ordinal,
                    record.payload_length,
                    layout.varname_width,
                    encoding,
                    &mut variable_indexes,
                    "reading legacy characteristic names",
                    "legacy characteristic value",
                )
            } else {
                section.advance(record.payload_length, "legacy expansion-field payload")
            }
        },
    )?;
    let cursor = expansion_plan.data_offset;
    drop(variable_indexes);
    let value_labels = validate_legacy_observation_extent(cursor, nobs, obs_length, file_length)?;
    let mut notes = Vec::new();
    let mut characteristics = Vec::new();
    let collector = decode_file_characteristics(characteristic_plan, reader, encoding, scratch)?;
    collector.finish(&mut notes, &mut characteristics, &mut variables);
    Ok(DtaMetadata {
        format_version: version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        notes,
        characteristics,
        variables,
        section_offsets: SectionOffsets {
            stata_data: 0,
            map: 0,
            variable_types,
            varnames,
            sortlist,
            formats: formats_offset,
            value_label_names: value_label_names_offset,
            variable_labels: variable_labels_offset,
            characteristics: fixed_end,
            data: cursor,
            strls: value_labels,
            value_labels,
            stata_data_close: file_length,
            end_of_file: file_length,
        },
        obs_length,
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

struct ValueLabelOffsetRead {
    start: u64,
    count: usize,
    text_start: u64,
    text_length: usize,
    byte_order: ByteOrder,
    encoding: TextEncoding,
}

fn read_value_label_offsets_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    options: ValueLabelOffsetRead,
) -> Result<Vec<usize>, DtaError> {
    let ValueLabelOffsetRead {
        start,
        count,
        text_start,
        text_length,
        byte_order,
        encoding,
    } = options;
    let mut output = Vec::new();
    output
        .try_reserve_exact(count)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label offset allocation"))?;
    let mut raw = Vec::new();
    let entries_per_chunk = (scratch.limit / 4).max(1);
    while output.len() < count {
        check_cancel(should_interrupt)?;
        let chunk_count = (count - output.len()).min(entries_per_chunk);
        let byte_offset = output
            .len()
            .checked_mul(4)
            .ok_or(DtaError::ArithmeticOverflow("value-label offset array"))?;
        let chunk_start = checked_add_u64(
            start,
            u64::try_from(byte_offset)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label offset array"))?,
            "value-label offset array",
        )?;
        read_exact_at_into(
            reader,
            chunk_start,
            chunk_count * 4,
            scratch,
            &mut raw,
            "reading value-label text offset",
        )?;
        for offset in (0..chunk_count * 4).step_by(4) {
            let entry_index = output.len();
            let text_offset =
                read_i32(&raw, offset, byte_order, "reading value-label text offset")?;
            let Some(text_offset_usize) = usize::try_from(text_offset)
                .ok()
                .filter(|offset| *offset < text_length)
            else {
                if encoding.is_utf8() {
                    if let Some(invalid) = first_invalid_utf8_file_offset(
                        reader,
                        scratch,
                        should_interrupt,
                        text_start,
                        text_length,
                        &output,
                    )? {
                        return Err(DtaError::InvalidValueLabelTextOffset {
                            entry_index: invalid.entry_index,
                            offset: error_offset(
                                start.saturating_add(
                                    u64::try_from(invalid.entry_index)
                                        .unwrap_or(u64::MAX)
                                        .saturating_mul(4),
                                ),
                            ),
                            text_offset: i32::try_from(invalid.boundary).unwrap_or(i32::MAX),
                            text_length,
                        });
                    }
                }
                return Err(DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: error_offset(chunk_start.saturating_add(offset as u64)),
                    text_offset,
                    text_length,
                });
            };
            output.push(text_offset_usize);
        }
    }
    Ok(output)
}

#[derive(Default)]
struct Utf8BoundaryPage {
    start: usize,
    bytes: Vec<u8>,
}

impl Utf8BoundaryPage {
    fn is_boundary<R: Read + Seek>(
        &mut self,
        reader: &mut R,
        scratch: &mut Scratch,
        text_start: u64,
        text_length: usize,
        boundary: usize,
        max_page_bytes: usize,
    ) -> Result<bool, DtaError> {
        if boundary == 0 || boundary >= text_length {
            return Ok(true);
        }
        let probe_start = boundary.saturating_sub(3);
        let probe_end = boundary.saturating_add(4).min(text_length);
        let cached_end = self.start.saturating_add(self.bytes.len());
        if self.bytes.is_empty() || probe_start < self.start || probe_end > cached_end {
            self.start = probe_start;
            let page_length = scratch.limit.min(max_page_bytes);
            let page_end = probe_start.saturating_add(page_length).min(text_length);
            read_exact_at_into(
                reader,
                checked_add_u64(
                    text_start,
                    u64::try_from(probe_start)
                        .map_err(|_| DtaError::ArithmeticOverflow("UTF-8 boundary probe"))?,
                    "UTF-8 boundary probe",
                )?,
                page_end - probe_start,
                scratch,
                &mut self.bytes,
                "reading value-label text",
            )?;
        }
        let local = boundary - self.start;
        Ok(is_utf8_boundary(&self.bytes, local))
    }
}

const VALUE_LABEL_BOUNDARY_BATCH_ENTRIES: usize = 4096;
const VALUE_LABEL_BOUNDARY_PAGE_BYTES: usize = 64 * 1024;
const VALUE_LABEL_BOUNDARY_PROBE_BYTES: usize = 7;
const VALUE_LABEL_PAGE_READ_AMPLIFICATION: usize = 16;

#[derive(Clone, Copy)]
struct IndexedTextOffset {
    entry_index: usize,
    boundary: usize,
}

fn adaptive_utf8_boundary_page_bytes(
    scratch_limit: usize,
    text_length: usize,
    offsets: &[IndexedTextOffset],
) -> usize {
    let full_page_bytes = scratch_limit.min(VALUE_LABEL_BOUNDARY_PAGE_BYTES);
    let mut staged_bytes = 0_usize;
    let mut page_start = 0_usize;
    let mut page_end = 0_usize;
    let mut has_page = false;
    for offset in offsets {
        if offset.boundary == 0 || offset.boundary >= text_length {
            continue;
        }
        let probe_start = offset.boundary.saturating_sub(3);
        let probe_end = offset.boundary.saturating_add(4).min(text_length);
        if !has_page || probe_start < page_start || probe_end > page_end {
            page_start = probe_start;
            page_end = probe_start.saturating_add(full_page_bytes).min(text_length);
            staged_bytes = staged_bytes.saturating_add(page_end - page_start);
            has_page = true;
        }
    }
    let probe_budget = offsets
        .len()
        .saturating_mul(VALUE_LABEL_BOUNDARY_PROBE_BYTES)
        .saturating_mul(VALUE_LABEL_PAGE_READ_AMPLIFICATION);
    if staged_bytes > probe_budget {
        VALUE_LABEL_BOUNDARY_PROBE_BYTES
    } else {
        full_page_bytes
    }
}

fn first_invalid_utf8_boundary_batch<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    text_start: u64,
    text_length: usize,
    offsets: &mut [IndexedTextOffset],
    page: &mut Utf8BoundaryPage,
) -> Result<Option<IndexedTextOffset>, DtaError> {
    offsets.sort_unstable_by_key(|offset| offset.boundary);
    let page_bytes = adaptive_utf8_boundary_page_bytes(scratch.limit, text_length, offsets);
    let mut first_invalid = None::<IndexedTextOffset>;
    for (position, &offset) in offsets.iter().enumerate() {
        if position % 1024 == 0 {
            check_cancel(should_interrupt)?;
        }
        if !page.is_boundary(
            reader,
            scratch,
            text_start,
            text_length,
            offset.boundary,
            page_bytes,
        )? && first_invalid.is_none_or(|first| offset.entry_index < first.entry_index)
        {
            first_invalid = Some(offset);
        }
    }
    Ok(first_invalid)
}

fn first_invalid_utf8_file_offset<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    text_start: u64,
    text_length: usize,
    offsets: &[usize],
) -> Result<Option<IndexedTextOffset>, DtaError> {
    let mut page = Utf8BoundaryPage::default();
    let mut batch = Vec::with_capacity(VALUE_LABEL_BOUNDARY_BATCH_ENTRIES);
    for (batch_index, boundaries) in offsets
        .chunks(VALUE_LABEL_BOUNDARY_BATCH_ENTRIES)
        .enumerate()
    {
        check_cancel(should_interrupt)?;
        batch.clear();
        let first_entry = batch_index.saturating_mul(VALUE_LABEL_BOUNDARY_BATCH_ENTRIES);
        batch.extend(
            boundaries
                .iter()
                .enumerate()
                .map(|(index, &boundary)| IndexedTextOffset {
                    entry_index: first_entry + index,
                    boundary,
                }),
        );
        if let Some(invalid) = first_invalid_utf8_boundary_batch(
            reader,
            scratch,
            should_interrupt,
            text_start,
            text_length,
            &mut batch,
            &mut page,
        )? {
            return Ok(Some(invalid));
        }
    }
    Ok(None)
}

struct UnselectedValueLabelValidation {
    offsets_start: u64,
    entry_count: usize,
    text_start: u64,
    text_length: usize,
    byte_order: ByteOrder,
    encoding: TextEncoding,
}

fn validate_unselected_value_label_table<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    options: UnselectedValueLabelValidation,
) -> Result<(), DtaError> {
    let UnselectedValueLabelValidation {
        offsets_start,
        entry_count,
        text_start,
        text_length,
        byte_order,
        encoding,
    } = options;
    if entry_count == 0 {
        return Ok(());
    }
    let mut raw = Vec::new();
    let entries_per_chunk = (scratch.limit / 4).max(1);
    let mut completed = 0_usize;
    let mut boundary_page = Utf8BoundaryPage::default();
    let mut boundary_batch = Vec::with_capacity(VALUE_LABEL_BOUNDARY_BATCH_ENTRIES);
    while completed < entry_count {
        check_cancel(should_interrupt)?;
        let chunk_count = (entry_count - completed).min(entries_per_chunk);
        let chunk_start = checked_add_u64(
            offsets_start,
            u64::try_from(completed.saturating_mul(4))
                .map_err(|_| DtaError::ArithmeticOverflow("value-label offset array"))?,
            "value-label offset array",
        )?;
        read_exact_at_into(
            reader,
            chunk_start,
            chunk_count * 4,
            scratch,
            &mut raw,
            "reading value-label text offset",
        )?;
        let mut chunk_entry = 0_usize;
        while chunk_entry < chunk_count {
            let batch_count = (chunk_count - chunk_entry).min(VALUE_LABEL_BOUNDARY_BATCH_ENTRIES);
            boundary_batch.clear();
            let mut range_error = None;
            for batch_entry in 0..batch_count {
                let entry_index = completed + chunk_entry + batch_entry;
                let offset = (chunk_entry + batch_entry) * 4;
                let text_offset =
                    read_i32(&raw, offset, byte_order, "reading value-label text offset")?;
                let Some(boundary) = usize::try_from(text_offset)
                    .ok()
                    .filter(|offset| *offset < text_length)
                else {
                    range_error = Some((entry_index, offset, text_offset));
                    break;
                };
                boundary_batch.push(IndexedTextOffset {
                    entry_index,
                    boundary,
                });
            }
            if encoding.is_utf8() {
                if let Some(invalid) = first_invalid_utf8_boundary_batch(
                    reader,
                    scratch,
                    should_interrupt,
                    text_start,
                    text_length,
                    &mut boundary_batch,
                    &mut boundary_page,
                )? {
                    return Err(DtaError::InvalidValueLabelTextOffset {
                        entry_index: invalid.entry_index,
                        offset: error_offset(
                            offsets_start.saturating_add(
                                u64::try_from(invalid.entry_index)
                                    .unwrap_or(u64::MAX)
                                    .saturating_mul(4),
                            ),
                        ),
                        text_offset: i32::try_from(invalid.boundary).unwrap_or(i32::MAX),
                        text_length,
                    });
                }
            }
            if let Some((entry_index, offset, text_offset)) = range_error {
                return Err(DtaError::InvalidValueLabelTextOffset {
                    entry_index,
                    offset: error_offset(chunk_start.saturating_add(offset as u64)),
                    text_offset,
                    text_length,
                });
            }
            chunk_entry += batch_count;
        }
        completed += chunk_count;
    }
    drop(boundary_page);

    let mut last_nul = None;
    let mut completed = 0_usize;
    while completed < text_length {
        check_cancel(should_interrupt)?;
        let chunk_length = (text_length - completed).min(scratch.limit);
        read_exact_at_into(
            reader,
            checked_add_u64(
                text_start,
                u64::try_from(completed)
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label text offset"))?,
                "value-label text offset",
            )?,
            chunk_length,
            scratch,
            &mut raw,
            "reading value-label text",
        )?;
        if let Some(position) = raw.iter().rposition(|byte| *byte == 0) {
            last_nul = Some(completed + position);
        }
        completed += chunk_length;
    }

    if last_nul == Some(text_length.saturating_sub(1)) {
        return Ok(());
    }
    let mut completed = 0_usize;
    while completed < entry_count {
        check_cancel(should_interrupt)?;
        let chunk_count = (entry_count - completed).min(entries_per_chunk);
        let chunk_start = checked_add_u64(
            offsets_start,
            u64::try_from(completed.saturating_mul(4))
                .map_err(|_| DtaError::ArithmeticOverflow("value-label offset array"))?,
            "value-label offset array",
        )?;
        read_exact_at_into(
            reader,
            chunk_start,
            chunk_count * 4,
            scratch,
            &mut raw,
            "reading value-label text offset",
        )?;
        for offset in (0..chunk_count * 4).step_by(4) {
            let text_offset = usize::try_from(read_i32(
                &raw,
                offset,
                byte_order,
                "reading value-label text offset",
            )?)
            .map_err(|_| DtaError::ArithmeticOverflow("validated value-label text offset"))?;
            if last_nul.is_none_or(|last_nul| text_offset > last_nul) {
                return Err(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: error_offset(
                        text_start.saturating_add(u64::try_from(text_offset).unwrap_or(u64::MAX)),
                    ),
                });
            }
        }
        completed += chunk_count;
    }
    Ok(())
}

fn nul_positions(text: &[u8]) -> Vec<usize> {
    text.iter()
        .enumerate()
        .filter_map(|(position, byte)| (*byte == 0).then_some(position))
        .collect()
}

fn first_nul_at_or_after(positions: &[usize], offset: usize) -> Option<usize> {
    positions
        .get(positions.partition_point(|&position| position < offset))
        .copied()
}

fn value_label_source_text_offset<R: Read + Seek>(
    reader: &mut R,
    scratch: &mut Scratch,
    offsets_start: u64,
    text_start: u64,
    entry_index: usize,
    byte_order: ByteOrder,
) -> Result<(i32, u64), DtaError> {
    let offset_position = checked_add_u64(
        offsets_start,
        u64::try_from(entry_index)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label entry offset"))?
            .checked_mul(4)
            .ok_or(DtaError::ArithmeticOverflow("value-label entry offset"))?,
        "value-label entry offset",
    )?;
    let text_offset = read_i32_at(
        reader,
        offset_position,
        byte_order,
        scratch,
        "reading value-label text offset",
    )?;
    let label_start = checked_add_u64(
        text_start,
        u64::try_from(text_offset)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label text offset"))?,
        "value-label text offset",
    )?;
    Ok((text_offset, label_start))
}

fn remaining_is_zero_padding<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    start: u64,
    end: u64,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    known_nonzero: &mut Option<u64>,
) -> Result<bool, DtaError> {
    const HEADER_PROBE_WIDTH: u64 = 12;

    if known_nonzero.is_some_and(|offset| (start..end).contains(&offset)) {
        return Ok(false);
    }
    let mut cursor = start;
    while cursor < end {
        check_cancel(should_interrupt)?;
        let remaining = end - cursor;
        let length = usize::try_from(remaining.min(if cursor == start {
            HEADER_PROBE_WIDTH
        } else {
            scratch.limit as u64
        }))
        .map_err(|_| DtaError::ArithmeticOverflow("value-label trailing bytes"))?;
        let bytes = read_exact_at(
            reader,
            cursor,
            length,
            scratch,
            "reading value-label trailing bytes",
        )?;
        if let Some(index) = bytes.iter().position(|byte| *byte != 0) {
            *known_nonzero = Some(checked_add_u64(
                cursor,
                u64::try_from(index)
                    .map_err(|_| DtaError::ArithmeticOverflow("value-label trailing bytes"))?,
                "value-label trailing bytes",
            )?);
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

fn has_legacy_offset_section_framing_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    start: u64,
    end: u64,
    byte_order: ByteOrder,
    name_width: usize,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
) -> Result<bool, DtaError> {
    let prefix_width = 4_usize
        .checked_add(name_width)
        .and_then(|value| value.checked_add(3))
        .ok_or(DtaError::ArithmeticOverflow("value-label table header"))?;
    let header_width = prefix_width
        .checked_add(8)
        .ok_or(DtaError::ArithmeticOverflow("value-label table header"))?;
    let mut cursor = start;
    let mut known_nonzero = None;
    while cursor < end {
        check_cancel(should_interrupt)?;
        let remaining = end - cursor;
        let probe_length = usize::try_from(remaining.min(header_width as u64))
            .map_err(|_| DtaError::ArithmeticOverflow("value-label section length"))?;
        let probe = read_exact_at(
            reader,
            cursor,
            probe_length,
            scratch,
            "probing legacy value-label section",
        )?;
        if probe.iter().all(|byte| *byte == 0) {
            return remaining_is_zero_padding(
                reader,
                cursor,
                end,
                scratch,
                should_interrupt,
                &mut known_nonzero,
            );
        }
        let section_length = usize::try_from(remaining)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label section length"))?;
        if !has_legacy_offset_table_framing(&probe, byte_order, section_length, name_width) {
            return Ok(false);
        }
        let declared = read_i32(&probe, 0, byte_order, "value-label table length")?;
        let declared = u64::try_from(declared)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label table length"))?;
        let next = checked_add_u64(
            cursor,
            u64::try_from(prefix_width)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label table header"))?,
            "value-label table header",
        )?;
        let next = checked_add_u64(next, declared, "value-label table")?;
        if next <= cursor || next > end {
            return Ok(false);
        }
        cursor = next;
    }
    Ok(true)
}

fn read_fixed8_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
    mut mode: ValueLabelStreamingMode<'_>,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    const NAME_WIDTH: usize = 9;
    const PADDING_WIDTH: usize = 1;
    const LABEL_WIDTH: usize = 8;

    let (mut cursor, section_end) = mode.section_range((
        metadata.section_offsets.value_labels,
        metadata.section_offsets.end_of_file,
    ));
    let section_scan = mode.scans_section();
    let mut tables = Vec::new();
    let mut known_nonzero = None;
    while cursor < section_end {
        check_cancel(should_interrupt)?;
        if section_scan
            && remaining_is_zero_padding(
                reader,
                cursor,
                section_end,
                scratch,
                should_interrupt,
                &mut known_nonzero,
            )?
        {
            cursor = section_end;
            break;
        }
        let table_start = cursor;
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
        let retain = mode.retains(&name);
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
        if retain {
            let mut raw = Vec::new();
            let mut values = Vec::new();
            values
                .try_reserve_exact(entry_count)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label value allocation"))?;
            let values_per_chunk = (scratch.limit / 2).max(1);
            while values.len() < entry_count {
                check_cancel(should_interrupt)?;
                let chunk_count = (entry_count - values.len()).min(values_per_chunk);
                let byte_offset = values
                    .len()
                    .checked_mul(2)
                    .ok_or(DtaError::ArithmeticOverflow("legacy value-label value"))?;
                read_exact_at_into(
                    reader,
                    checked_add_u64(
                        values_start,
                        u64::try_from(byte_offset).map_err(|_| {
                            DtaError::ArithmeticOverflow("legacy value-label value")
                        })?,
                        "legacy value-label value",
                    )?,
                    chunk_count * 2,
                    scratch,
                    &mut raw,
                    "reading legacy value-label value",
                )?;
                for offset in (0..chunk_count * 2).step_by(2) {
                    values.push(i32::from(read_i16(
                        &raw,
                        offset,
                        metadata.byte_order,
                        "legacy value-label value",
                    )?));
                }
            }

            let mut entries = Vec::new();
            entries
                .try_reserve_exact(entry_count)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label entry allocation"))?;
            let labels_per_chunk = (scratch.limit / LABEL_WIDTH).max(1);
            while entries.len() < entry_count {
                check_cancel(should_interrupt)?;
                let chunk_count = (entry_count - entries.len()).min(labels_per_chunk);
                let byte_offset = entries
                    .len()
                    .checked_mul(LABEL_WIDTH)
                    .ok_or(DtaError::ArithmeticOverflow("legacy value-label text"))?;
                read_exact_at_into(
                    reader,
                    checked_add_u64(
                        labels_start,
                        u64::try_from(byte_offset)
                            .map_err(|_| DtaError::ArithmeticOverflow("legacy value-label text"))?,
                        "legacy value-label text",
                    )?,
                    chunk_count * LABEL_WIDTH,
                    scratch,
                    &mut raw,
                    "reading legacy value-label text",
                )?;
                for offset in (0..chunk_count * LABEL_WIDTH).step_by(LABEL_WIDTH) {
                    let value = values[entries.len()];
                    entries.push(ValueLabelEntry {
                        value,
                        missing_tag: classify_long_missing_for_version(
                            value,
                            metadata.format_version,
                        ),
                        label: encoding.decode(field_bytes(&raw[offset..offset + LABEL_WIDTH])),
                    });
                }
            }
            tables.push(ValueLabelTable {
                name: name.clone(),
                entries,
            });
        }
        mode.record_location(&name, table_start, table_end);
        cursor = table_end;
    }
    ensure_absolute(
        if !section_scan {
            "value-label table"
        } else {
            "end_of_file"
        },
        cursor,
        section_end,
    )?;
    Ok(tables)
}

fn read_offset_value_labels_streaming<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
    legacy_name_width: usize,
    mut mode: ValueLabelStreamingMode<'_>,
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
    let (mut cursor, section_end) =
        mode.section_range((metadata.section_offsets.value_labels, section_end));
    let section_scan = mode.scans_section();
    if modern && section_scan {
        cursor = expect_file_tag(reader, cursor, b"<value_labels>", "<value_labels>", scratch)?;
    }
    let mut tables = Vec::new();
    let mut known_nonzero = None;

    while cursor < section_end {
        check_cancel(should_interrupt)?;
        if section_scan
            && !modern
            && remaining_is_zero_padding(
                reader,
                cursor,
                section_end,
                scratch,
                should_interrupt,
                &mut known_nonzero,
            )?
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
            if marker != b"<lbl>" && section_scan {
                cursor = expect_file_tag(
                    reader,
                    cursor,
                    b"</value_labels>",
                    "</value_labels>",
                    scratch,
                )?;
                break;
            }
            if marker != b"<lbl>" {
                return Err(DtaError::UnexpectedTag {
                    expected: "<lbl>",
                    offset: error_offset(cursor),
                });
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
        let retain = mode.retains(&name);
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
        let frame = frame_offset_value_label_payload(
            &payload_header,
            metadata.byte_order,
            error_offset(table_start),
            error_offset(payload_start),
            declared,
        )?;
        let entry_count = frame.entry_count;
        let text_length = frame.text_length;
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
        let entries = if retain {
            let mut decoded_offsets = read_value_label_offsets_streaming(
                reader,
                scratch,
                should_interrupt,
                ValueLabelOffsetRead {
                    start: offsets_start,
                    count: entry_count,
                    text_start,
                    text_length,
                    byte_order: metadata.byte_order,
                    encoding,
                },
            )?;
            let decoded_text = decode_range_with_offsets(
                reader,
                text_start,
                text_length,
                encoding,
                &mut decoded_offsets,
                offsets_start,
                scratch,
                should_interrupt,
                "reading value-label text",
            )?;
            let terminators = nul_positions(decoded_text.as_bytes());
            let mut entries = Vec::new();
            entries
                .try_reserve_exact(entry_count)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label entry allocation"))?;
            let mut raw_values = Vec::new();
            let entries_per_chunk = (scratch.limit / 4).max(1);
            while entries.len() < entry_count {
                check_cancel(should_interrupt)?;
                let chunk_count = (entry_count - entries.len()).min(entries_per_chunk);
                let byte_offset = entries
                    .len()
                    .checked_mul(4)
                    .ok_or(DtaError::ArithmeticOverflow("value-label value offset"))?;
                let chunk_start = checked_add_u64(
                    values_start,
                    u64::try_from(byte_offset)
                        .map_err(|_| DtaError::ArithmeticOverflow("value-label value offset"))?,
                    "value-label value offset",
                )?;
                read_exact_at_into(
                    reader,
                    chunk_start,
                    chunk_count * 4,
                    scratch,
                    &mut raw_values,
                    "reading value-label value",
                )?;
                for raw_offset in (0..chunk_count * 4).step_by(4) {
                    let entry_index = entries.len();
                    let value = read_i32(
                        &raw_values,
                        raw_offset,
                        metadata.byte_order,
                        "reading value-label value",
                    )?;
                    let decoded_offset = decoded_offsets[entry_index];
                    let Some(nul) = first_nul_at_or_after(&terminators, decoded_offset) else {
                        let (_, label_start) = value_label_source_text_offset(
                            reader,
                            scratch,
                            offsets_start,
                            text_start,
                            entry_index,
                            metadata.byte_order,
                        )?;
                        return Err(DtaError::MissingNulTerminator {
                            context: "value-label text",
                            offset: error_offset(label_start),
                        });
                    };
                    let Some(label) = decoded_text.get(decoded_offset..nul) else {
                        let (text_offset, label_start) = value_label_source_text_offset(
                            reader,
                            scratch,
                            offsets_start,
                            text_start,
                            entry_index,
                            metadata.byte_order,
                        )?;
                        return Err(DtaError::InvalidValueLabelTextOffset {
                            entry_index,
                            offset: error_offset(label_start),
                            text_offset,
                            text_length,
                        });
                    };
                    let mut label = label.to_owned();
                    label.shrink_to_fit();
                    entries.push(ValueLabelEntry {
                        value,
                        missing_tag: classify_long_missing_for_version(
                            value,
                            metadata.format_version,
                        ),
                        label,
                    });
                }
            }
            Some(entries)
        } else {
            validate_unselected_value_label_table(
                reader,
                scratch,
                should_interrupt,
                UnselectedValueLabelValidation {
                    offsets_start,
                    entry_count,
                    text_start,
                    text_length,
                    byte_order: metadata.byte_order,
                    encoding,
                },
            )?;
            None
        };
        cursor = table_end;
        if modern {
            cursor = expect_file_tag(reader, cursor, b"</lbl>", "</lbl>", scratch)?;
        }
        if let Some(entries) = entries {
            tables.push(ValueLabelTable {
                name: name.clone(),
                entries,
            });
        }
        mode.record_location(&name, table_start, cursor);
    }

    ensure_absolute(
        if !section_scan {
            "value-label table"
        } else if modern {
            "stata_data_close"
        } else {
            "end_of_file"
        },
        cursor,
        section_end,
    )?;
    if modern && section_scan {
        cursor = expect_file_tag(reader, cursor, b"</stata_dta>", "</stata_dta>", scratch)?;
        ensure_absolute("end_of_file", cursor, metadata.section_offsets.end_of_file)?;
    }
    Ok(tables)
}

fn select_legacy_value_label_layout<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
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
    let start = metadata.section_offsets.value_labels;
    let end = metadata.section_offsets.end_of_file;
    if metadata.format_version == FormatVersion::V108
        && has_legacy_offset_section_framing_streaming(
            reader,
            start,
            end,
            metadata.byte_order,
            9,
            scratch,
            should_interrupt,
        )?
    {
        return Ok((LegacyValueLabelLayout::OffsetTable, 9));
    }
    let long_framing = has_legacy_offset_section_framing_streaming(
        reader,
        start,
        end,
        metadata.byte_order,
        33,
        scratch,
        should_interrupt,
    )?;
    Ok(match metadata.format_version {
        FormatVersion::V105 if long_framing => (LegacyValueLabelLayout::OffsetTable, 33),
        FormatVersion::V105 => (LegacyValueLabelLayout::Fixed8, 9),
        FormatVersion::V108 if long_framing => (LegacyValueLabelLayout::OffsetTable, 33),
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
    mode: ValueLabelStreamingMode<'_>,
) -> Result<(Vec<ValueLabelTable>, IndexedValueLabelLayout), DtaError> {
    let layout = if metadata.format_version.is_modern() {
        IndexedValueLabelLayout::OffsetTable {
            legacy_name_width: 0,
        }
    } else {
        let (layout, table_name_width) =
            select_legacy_value_label_layout(reader, metadata, scratch, should_interrupt)?;
        match layout {
            LegacyValueLabelLayout::Fixed8 => IndexedValueLabelLayout::Fixed8,
            LegacyValueLabelLayout::OffsetTable => IndexedValueLabelLayout::OffsetTable {
                legacy_name_width: table_name_width,
            },
        }
    };
    let tables = match layout {
        IndexedValueLabelLayout::Fixed8 => read_fixed8_value_labels_streaming(
            reader,
            metadata,
            scratch,
            should_interrupt,
            encoding,
            mode,
        ),
        IndexedValueLabelLayout::OffsetTable { legacy_name_width } => {
            read_offset_value_labels_streaming(
                reader,
                metadata,
                scratch,
                should_interrupt,
                encoding,
                legacy_name_width,
                mode,
            )
        }
    }?;
    Ok((tables, layout))
}

fn read_indexed_value_label_table<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    should_interrupt: &mut F,
    encoding: TextEncoding,
    layout: IndexedValueLabelLayout,
    location: &ValueLabelLocation,
) -> Result<ValueLabelTable, DtaError> {
    let range = (location.start, location.end);
    let mut tables = match layout {
        IndexedValueLabelLayout::Fixed8 => read_fixed8_value_labels_streaming(
            reader,
            metadata,
            scratch,
            should_interrupt,
            encoding,
            ValueLabelStreamingMode::Indexed { range },
        )?,
        IndexedValueLabelLayout::OffsetTable { legacy_name_width } => {
            read_offset_value_labels_streaming(
                reader,
                metadata,
                scratch,
                should_interrupt,
                encoding,
                legacy_name_width,
                ValueLabelStreamingMode::Indexed { range },
            )?
        }
    };
    if tables.len() != 1 || tables[0].name != location.name.as_ref() {
        return Err(DtaError::Output(
            "indexed value-label table no longer matches its source".to_owned(),
        ));
    }
    Ok(tables.pop().expect("one indexed table was decoded"))
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
    let (variable, observation) = crate::strl::read_pointer_parts(bytes, 0, metadata)?;
    if variable == 0 && observation == 0 {
        return Ok(None);
    }
    let key = FileGsoKey {
        variable,
        observation,
    };
    crate::strl::validate_key(
        metadata,
        key.variable,
        key.observation,
        error_offset(offset),
        true,
    )?;
    Ok(Some(key))
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
            let field = field_bytes(cell);
            if self.sink.try_push_fixed_string_bytes(
                output_column,
                output_row,
                field,
                self.text_encoding,
            )? {
                return Ok(());
            }
            let value = self.text_encoding.decode_cow(field);
            return self
                .sink
                .push_fixed_string(output_column, output_row, &value);
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

    let entries = index_file_strls(reader, metadata, scratch, &requested, should_interrupt)?;
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

fn index_file_strls<R: Read + Seek, F: FnMut() -> bool>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    requested: &HashSet<FileGsoKey>,
    should_interrupt: &mut F,
) -> Result<HashMap<FileGsoKey, FileGsoEntry>, DtaError> {
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
        crate::strl::validate_key(
            metadata,
            key.variable,
            key.observation,
            error_offset(cursor),
            false,
        )?;
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
    Ok(entries)
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
        materialize_file_strl_pointers(
            reader,
            scratch,
            entries,
            column_pointers,
            &mut decoded,
            &mut pointer_count,
            should_interrupt,
            encoding,
            |row_index, value| sink.push_strl(column_index, row_index, value),
        )?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn materialize_file_strl_pointers<
    R: Read + Seek,
    F: FnMut() -> bool,
    P: FnMut(usize, &str) -> Result<(), DtaError>,
>(
    reader: &mut R,
    scratch: &mut Scratch,
    entries: &HashMap<FileGsoKey, FileGsoEntry>,
    pointers: &[Option<FileGsoKey>],
    decoded: &mut HashMap<FileGsoKey, String>,
    pointer_count: &mut usize,
    should_interrupt: &mut F,
    encoding: TextEncoding,
    mut push: P,
) -> Result<(), DtaError> {
    for (row_index, pointer) in pointers.iter().copied().enumerate() {
        if pointer_count.is_multiple_of(STRL_CANCEL_CHECK_INTERVAL) {
            check_cancel(should_interrupt)?;
        }
        *pointer_count = pointer_count
            .checked_add(1)
            .ok_or(DtaError::ArithmeticOverflow("strL pointer count"))?;
        let Some(key) = pointer else {
            push(row_index, "")?;
            continue;
        };
        if let Some(value) = decoded.get(&key) {
            push(row_index, value)?;
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
        push(row_index, &value)?;
        decoded.insert(key, value);
    }
    Ok(())
}

fn resolve_parallel_file_strls<R: Read + Seek, F: FnMut() -> bool, C: DtaColumnSink>(
    reader: &mut R,
    metadata: &DtaMetadata,
    scratch: &mut Scratch,
    columns: &mut [ParallelColumn<C>],
    should_interrupt: &mut F,
    encoding: TextEncoding,
) -> Result<(), DtaError> {
    if !columns.iter().any(|column| column.strl_pointers.is_some()) {
        return Ok(());
    }
    let requested = columns
        .iter()
        .filter_map(|column| column.strl_pointers.as_ref())
        .flat_map(|column| column.iter().flatten().copied())
        .collect::<HashSet<_>>();
    let entries = index_file_strls(reader, metadata, scratch, &requested, should_interrupt)?;

    let mut decoded = HashMap::<FileGsoKey, String>::new();
    let mut pointer_count = 0_usize;
    for column in columns {
        let Some(pointers) = column.strl_pointers.as_ref() else {
            continue;
        };
        let sink = &mut column.sink;
        materialize_file_strl_pointers(
            reader,
            scratch,
            &entries,
            pointers,
            &mut decoded,
            &mut pointer_count,
            should_interrupt,
            encoding,
            |row_index, value| sink.push_strl(row_index, value),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::StataCharacteristic;
    use std::io::{Cursor, Result as IoResult};

    struct CountingReader {
        inner: Cursor<Vec<u8>>,
        bytes_read: usize,
        read_calls: usize,
        reads: Vec<(u64, usize)>,
    }

    impl CountingReader {
        fn new(bytes: Vec<u8>) -> Self {
            Self {
                inner: Cursor::new(bytes),
                bytes_read: 0,
                read_calls: 0,
                reads: Vec::new(),
            }
        }
    }

    impl Read for CountingReader {
        fn read(&mut self, output: &mut [u8]) -> IoResult<usize> {
            let offset = self.inner.position();
            let count = self.inner.read(output)?;
            self.bytes_read += count;
            self.read_calls += 1;
            self.reads.push((offset, count));
            Ok(count)
        }
    }

    fn ranges_overlap(left: (u64, usize), right: (u64, usize)) -> bool {
        let left_end = left.0.saturating_add(left.1 as u64);
        let right_end = right.0.saturating_add(right.1 as u64);
        left.0 < right_end && right.0 < left_end
    }

    #[test]
    fn schema_summary_reads_only_modern_type_codes_and_names() {
        let bytes = include_bytes!("../../../inst/extdata/auto_v118.dta").to_vec();
        let mut header_reader = Cursor::new(bytes.clone());
        let header = read_modern_header_map(&mut header_reader, &mut Scratch::new(1024)).unwrap();
        let count = header.nvar as usize;
        let widths = field_widths(header.format_version);
        let skipped = [
            (header.dataset_label.offset, header.dataset_label.length),
            (
                header.section_offsets.formats + b"<formats>".len() as u64,
                count * widths.format,
            ),
            (
                header.section_offsets.value_label_names + b"<value_label_names>".len() as u64,
                count * widths.value_label_name,
            ),
            (
                header.section_offsets.variable_labels + b"<variable_labels>".len() as u64,
                count * widths.variable_label,
            ),
        ];
        let mut reader = CountingReader::new(bytes);
        let summary =
            read_file_schema_summary(&mut reader, &mut Scratch::new(1024), TextEncoding::Auto)
                .unwrap();
        assert_eq!(summary.variables.len(), count);
        for read in &reader.reads {
            assert!(
                skipped
                    .iter()
                    .all(|&payload| !ranges_overlap(*read, payload)),
                "schema preflight read skipped metadata payload {read:?}"
            );
        }
    }

    #[test]
    fn schema_summary_reads_only_legacy_type_codes_and_names() {
        let bytes = include_bytes!("../../../inst/extdata/all_types_v115.dta").to_vec();
        let layout = LegacyLayout::for_version(FormatVersion::V115);
        let header = &bytes[..layout.header_size];
        let byte_order = if header[1] == 1 {
            ByteOrder::Msf
        } else {
            ByteOrder::Lsf
        };
        let count = usize::from(read_u16(header, 4, byte_order, "test variable count").unwrap());
        let fixed = legacy_fixed_offsets(count, FormatVersion::V115).unwrap();
        let skipped = [
            (fixed.formats as u64, count * layout.format_width),
            (
                fixed.value_label_names as u64,
                count * layout.value_label_name_width,
            ),
            (
                fixed.variable_labels as u64,
                count * layout.variable_label_width,
            ),
        ];
        let mut reader = CountingReader::new(bytes);
        let summary =
            read_file_schema_summary(&mut reader, &mut Scratch::new(1024), TextEncoding::Auto)
                .unwrap();
        assert_eq!(summary.variables.len(), count);
        for read in &reader.reads {
            assert!(
                skipped
                    .iter()
                    .all(|&payload| !ranges_overlap(*read, payload)),
                "schema preflight read skipped legacy metadata payload {read:?}"
            );
        }
    }

    #[test]
    fn schema_summary_validates_modern_framing_before_type_codes() {
        let mut bytes = include_bytes!("../../../inst/extdata/auto_v118.dta").to_vec();
        let header =
            read_modern_header_map(&mut Cursor::new(bytes.clone()), &mut Scratch::new(1024))
                .unwrap();
        let type_code = header.section_offsets.variable_types as usize + b"<variable_types>".len();
        bytes[type_code..type_code + 2].copy_from_slice(&0_u16.to_le_bytes());
        let formats_close = header.section_offsets.value_label_names as usize - b"</formats>".len();
        bytes[formats_close] = b'!';
        assert!(matches!(
            read_file_schema_summary(
                &mut Cursor::new(bytes),
                &mut Scratch::new(1024),
                TextEncoding::Auto,
            ),
            Err(DtaError::UnexpectedTag {
                expected: "formats",
                ..
            })
        ));
    }

    #[test]
    fn schema_summary_preserves_legacy_structural_error_precedence() {
        let original = include_bytes!("../../../inst/extdata/all_types_v115.dta").to_vec();
        let byte_order = if original[1] == 1 {
            ByteOrder::Msf
        } else {
            ByteOrder::Lsf
        };
        let count = usize::from(read_u16(&original, 4, byte_order, "test variable count").unwrap());
        let fixed = legacy_fixed_offsets(count, FormatVersion::V115).unwrap();

        let mut truncated = original.clone();
        truncated[fixed.variable_types] = 0;
        truncated.truncate(fixed.end - 1);
        assert!(matches!(
            read_file_schema_summary(
                &mut Cursor::new(truncated),
                &mut Scratch::new(1024),
                TextEncoding::Auto,
            ),
            Err(DtaError::Truncated {
                context: "legacy fixed metadata sections",
                ..
            })
        ));

        let mut invalid_type = original;
        invalid_type[fixed.variable_types] = 0;
        invalid_type.truncate(fixed.end);
        assert!(matches!(
            read_file_schema_summary(
                &mut Cursor::new(invalid_type),
                &mut Scratch::new(1024),
                TextEncoding::Auto,
            ),
            Err(DtaError::UnknownTypeCode {
                code: 0,
                version: FormatVersion::V115,
            })
        ));
    }

    #[test]
    fn parsed_schema_scales_to_release_119_variable_counts() {
        let count = 120_000;
        let names = (0..count).map(|index| format!("v{index}")).collect();
        let schema = build_parsed_schema(FormatVersion::V119, vec![65526; count], names, |code| {
            resolve_type(code, FormatVersion::V119)
        })
        .unwrap();
        assert_eq!(schema.variables.len(), count);
        assert_eq!(schema.obs_length, count as u64 * 8);
        assert_eq!(
            schema.into_summary().variables.last().unwrap().name,
            "v119999"
        );
    }

    #[test]
    fn value_label_move_threshold_stops_visiting_entries() {
        let table = ValueLabelTable {
            name: String::new(),
            entries: (0..100_000)
                .map(|index| ValueLabelEntry {
                    value: index,
                    missing_tag: None,
                    label: "x".repeat(1024),
                })
                .collect(),
        };
        let mut visited = 0;
        assert!(accumulate_value_label_table_heap_bytes(
            &table,
            &mut 0,
            || visited += 1,
        ));
        assert!(visited < 100, "visited {visited} entries");

        let mut total = 0;
        let small_tables = (0..100_000).map(|index| ValueLabelTable {
            name: format!("t{index}"),
            entries: vec![ValueLabelEntry {
                value: index,
                missing_tag: None,
                label: "x".repeat(1024),
            }],
        });
        let mut visited_tables = 0;
        assert!(
            small_tables
                .take_while(|table| {
                    visited_tables += 1;
                    !accumulate_value_label_table_heap_bytes(table, &mut total, || {})
                })
                .count()
                < 100
        );
        assert!(visited_tables < 100, "visited {visited_tables} tables");
    }

    impl Seek for CountingReader {
        fn seek(&mut self, position: SeekFrom) -> IoResult<u64> {
            self.inner.seek(position)
        }
    }

    fn unterminated_characteristic_record(width: usize, byte_order: ByteOrder) -> Vec<u8> {
        let value_length = crate::stata_metadata::MAX_METADATA_VALUE_BYTES + 2;
        let payload_length = width * 2 + value_length;
        let mut bytes = b"<characteristics><ch>".to_vec();
        let length = u32::try_from(payload_length).expect("test payload fits u32");
        let encoded_length = match byte_order {
            ByteOrder::Lsf => length.to_le_bytes(),
            ByteOrder::Msf => length.to_be_bytes(),
        };
        bytes.extend_from_slice(&encoded_length);
        let mut target = vec![0; width];
        target[..4].copy_from_slice(b"_dta");
        bytes.extend_from_slice(&target);
        let mut name = vec![0; width];
        name[..6].copy_from_slice(b"source");
        bytes.extend_from_slice(&name);
        bytes.extend(std::iter::repeat_n(b'x', value_length));
        bytes.extend_from_slice(b"</ch>");
        bytes
    }

    #[test]
    fn file_metadata_checks_modern_characteristic_terminator_before_value_decode() {
        let bytes = unterminated_characteristic_record(129, ByteOrder::Lsf);
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };
        assert!(matches!(
            read_modern_characteristics(
                &mut Cursor::new(bytes),
                &header,
                TextEncoding::Utf8,
                &mut Scratch::new(1024),
                &[],
            ),
            Err(DtaError::UnexpectedTag {
                expected: "</characteristics>",
                ..
            })
        ));
    }

    #[test]
    fn file_metadata_rejects_forged_modern_terminator_before_value_decode() {
        let width = 129;
        let mut bytes = unterminated_characteristic_record(width, ByteOrder::Lsf);
        let forged_length = width * 2 + b"</characteristics>".len();
        bytes.extend_from_slice(b"<ch>");
        bytes.extend_from_slice(&(forged_length as u32).to_le_bytes());
        bytes.extend(std::iter::repeat_n(0, width * 2));
        bytes.extend_from_slice(b"</characteristics>");
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };
        assert!(matches!(
            read_modern_characteristics(
                &mut Cursor::new(bytes),
                &header,
                TextEncoding::Utf8,
                &mut Scratch::new(1024),
                &[],
            ),
            Err(DtaError::Truncated {
                context: "characteristic payload",
                ..
            })
        ));
    }

    #[test]
    fn schema_preflight_frames_but_does_not_materialize_characteristic_payloads() {
        let width = 129_usize;
        let value_length = 32 * 1024;
        let payload_length = width * 2 + value_length;
        let mut bytes = b"<characteristics><ch>".to_vec();
        bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
        let mut target = vec![0; width];
        target[..4].copy_from_slice(b"_dta");
        bytes.extend_from_slice(&target);
        let mut name = vec![0; width];
        name[..6].copy_from_slice(b"source");
        bytes.extend_from_slice(&name);
        bytes.extend(std::iter::repeat_n(b'x', value_length - 1));
        bytes.push(0);
        bytes.extend_from_slice(b"</ch></characteristics>");
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };

        let mut preflight = CountingReader::new(bytes.clone());
        validate_modern_characteristic_framing(&mut preflight, &header, &mut Scratch::new(1024))
            .unwrap();
        let mut full = CountingReader::new(bytes);
        read_modern_characteristics(
            &mut full,
            &header,
            TextEncoding::Utf8,
            &mut Scratch::new(1024),
            &[],
        )
        .unwrap();
        assert!(
            preflight.bytes_read * 8 < full.bytes_read,
            "preflight read {} bytes; full metadata read {}",
            preflight.bytes_read,
            full.bytes_read
        );
    }

    #[test]
    fn file_metadata_frames_legacy_expansions_without_decoding_values() {
        let layout = LegacyLayout::for_version(FormatVersion::V115);
        let modern = unterminated_characteristic_record(layout.varname_width, ByteOrder::Lsf);
        let names_start = b"<characteristics><ch>".len() + 4;
        let payload = &modern[names_start..modern.len() - b"</ch>".len()];
        let mut bytes = vec![1];
        bytes.extend_from_slice(&(payload.len() as i32).to_le_bytes());
        bytes.extend_from_slice(payload);
        let length = bytes.len() as u64;
        assert!(matches!(
            validate_legacy_expansion_framing(
                &mut Cursor::new(bytes),
                &mut Scratch::new(1024),
                0,
                length,
                ByteOrder::Lsf,
                layout,
            ),
            Err(DtaError::Io {
                context: "reading legacy expansion field",
                kind: ErrorKind::UnexpectedEof,
                ..
            })
        ));
    }

    #[test]
    fn legacy_framing_reads_only_headers_around_large_payloads() {
        let layout = LegacyLayout::for_version(FormatVersion::V115);
        let payload_length = METADATA_SECTION_BUFFER_BYTES + 1024;
        let mut bytes = Vec::new();
        for _ in 0..8 {
            bytes.push(2);
            bytes.extend_from_slice(&(payload_length as i32).to_le_bytes());
            bytes.extend(std::iter::repeat_n(0, payload_length));
        }
        bytes.extend_from_slice(&[0; 5]);
        let file_length = bytes.len() as u64;
        let mut reader = CountingReader::new(bytes);
        validate_legacy_expansion_framing(
            &mut reader,
            &mut Scratch::new(1024 * 1024),
            0,
            file_length,
            ByteOrder::Lsf,
            layout,
        )
        .expect("large payload framing");
        assert_eq!(reader.bytes_read, 45);
    }

    #[test]
    fn legacy_framing_reads_dense_small_headers_in_blocks() {
        let layout = LegacyLayout::for_version(FormatVersion::V115);
        let mut bytes = Vec::new();
        for _ in 0..10_000 {
            bytes.extend_from_slice(&[2, 0, 0, 0, 0]);
        }
        bytes.extend_from_slice(&[0; 5]);
        let file_length = bytes.len() as u64;
        let mut reader = CountingReader::new(bytes);
        validate_legacy_expansion_framing(
            &mut reader,
            &mut Scratch::new(1024 * 1024),
            0,
            file_length,
            ByteOrder::Lsf,
            layout,
        )
        .expect("dense expansion framing");
        assert!(reader.read_calls <= 3, "{} reads", reader.read_calls);
    }

    #[test]
    fn repeated_sparse_value_label_selections_use_the_name_index() {
        let locations = (0..10_000)
            .map(|index| ValueLabelLocation {
                name: Arc::from(if index == 7 || index == 9_997 {
                    "selected".to_owned()
                } else {
                    format!("unused_{index}")
                }),
                start: index as u64,
                end: index as u64 + 1,
            })
            .collect::<Vec<_>>();
        let indices_by_name = index_value_label_locations(&locations);
        let cache = IndexedValueLabelCache {
            layout: IndexedValueLabelLayout::Fixed8,
            locations,
            indices_by_name,
            tables: HashMap::new(),
        };
        let selected = HashSet::from(["selected".to_owned()]);

        for _ in 0..100 {
            assert_eq!(
                selected_value_label_location_indices(&cache.indices_by_name, &selected).unwrap(),
                [7, 9_997]
            );
        }
    }

    fn kernel_metadata(byte_order: ByteOrder) -> DtaMetadata {
        DtaMetadata {
            format_version: FormatVersion::V119,
            byte_order,
            nvar: 0,
            nobs: 0,
            dataset_label: String::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            variables: Vec::new(),
            section_offsets: SectionOffsets::from_array([0; 14]),
            obs_length: 0,
        }
    }

    fn kernel_column(
        kind: ObservationKind,
        byte_offset: usize,
        byte_width: usize,
    ) -> ParallelColumn<ColumnBuilder> {
        let sink = match kind {
            ObservationKind::Byte => ColumnBuilder::Byte {
                index: 0,
                values: Vec::new(),
                missing_tags: Vec::new(),
            },
            ObservationKind::Int => ColumnBuilder::Int {
                index: 0,
                values: Vec::new(),
                missing_tags: Vec::new(),
            },
            ObservationKind::Long => ColumnBuilder::Long {
                index: 0,
                values: Vec::new(),
                missing_tags: Vec::new(),
            },
            ObservationKind::Float => ColumnBuilder::Float {
                index: 0,
                values: Vec::new(),
                missing_tags: Vec::new(),
            },
            ObservationKind::Double => ColumnBuilder::Double {
                index: 0,
                values: Vec::new(),
                missing_tags: Vec::new(),
            },
            ObservationKind::FixedString => ColumnBuilder::FixedString {
                index: 0,
                values: Vec::new(),
            },
            ObservationKind::StrL => ColumnBuilder::StrL {
                index: 0,
                values: Vec::new(),
            },
        };
        ParallelColumn {
            plan: ObservationColumnPlan {
                output_index: 0,
                source_index: 0,
                byte_offset,
                byte_width,
                kind,
            },
            sink,
            strl_pointers: matches!(kind, ObservationKind::StrL).then(Vec::new),
        }
    }

    #[test]
    fn column_kernels_decode_big_endian_wide_numeric_values() {
        let mut bytes = Vec::new();
        for (long, float, double) in [(-2_i32, 1.5_f32, -3.25_f64), (42, -0.5, 9.75)] {
            bytes.extend_from_slice(&long.to_be_bytes());
            bytes.extend_from_slice(&float.to_bits().to_be_bytes());
            bytes.extend_from_slice(&double.to_bits().to_be_bytes());
        }
        let mut columns = vec![
            kernel_column(ObservationKind::Long, 0, 4),
            kernel_column(ObservationKind::Float, 4, 4),
            kernel_column(ObservationKind::Double, 8, 8),
        ];
        let block = ObservationBlock {
            bytes,
            source_offset: 0,
            output_row_start: 0,
            row_count: 2,
        };
        decode_worker_block(
            &mut columns,
            &block,
            16,
            &kernel_metadata(ByteOrder::Msf),
            TextEncoding::Utf8,
            None,
        )
        .unwrap();

        let ColumnBuilder::Long { values, .. } = &columns[0].sink else {
            unreachable!()
        };
        assert_eq!(values, &[-2, 42]);
        let ColumnBuilder::Float { values, .. } = &columns[1].sink else {
            unreachable!()
        };
        assert_eq!(values, &[1.5, -0.5]);
        let ColumnBuilder::Double { values, .. } = &columns[2].sink else {
            unreachable!()
        };
        assert_eq!(values, &[-3.25, 9.75]);
    }

    #[test]
    fn column_kernel_collects_v119_strl_pointers_in_both_byte_orders() {
        for (byte_order, pointer) in [
            (ByteOrder::Lsf, [1, 0, 0, 42, 0, 0, 0, 0]),
            (ByteOrder::Msf, [0, 0, 1, 0, 0, 0, 0, 42]),
        ] {
            let mut metadata = kernel_metadata(byte_order);
            metadata.format_version = FormatVersion::V119;
            metadata.nvar = 1;
            metadata.nobs = 42;
            metadata.obs_length = 8;
            metadata.variables = vec![VariableInfo {
                name: "text".to_owned(),
                dta_type: DtaType::StrL,
                type_code: 32_768,
                format: "%9s".to_owned(),
                label: String::new(),
                value_label_name: String::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                byte_width: 8,
                byte_offset: 0,
            }];
            let mut bytes = Vec::from(pointer);
            bytes.extend_from_slice(&[0; 8]);
            let mut columns = vec![kernel_column(ObservationKind::StrL, 0, 8)];
            let block = ObservationBlock {
                bytes,
                source_offset: 512,
                output_row_start: 0,
                row_count: 2,
            };

            decode_worker_block(&mut columns, &block, 8, &metadata, TextEncoding::Utf8, None)
                .unwrap();

            assert_eq!(
                columns[0].strl_pointers.as_deref(),
                Some(
                    [
                        Some(FileGsoKey {
                            variable: 1,
                            observation: 42,
                        }),
                        None,
                    ]
                    .as_slice()
                )
            );
        }
    }

    #[test]
    fn column_kernel_range_proof_rejects_truncation_and_output_overflow() {
        let metadata = kernel_metadata(ByteOrder::Lsf);
        let mut truncated = vec![kernel_column(ObservationKind::Double, 1, 8)];
        let block = ObservationBlock {
            bytes: vec![0; 17],
            source_offset: 0,
            output_row_start: 0,
            row_count: 2,
        };
        assert!(matches!(
            decode_worker_block(
                &mut truncated,
                &block,
                9,
                &metadata,
                TextEncoding::Utf8,
                None,
            ),
            Err(DtaError::Truncated { .. })
        ));

        let mut overflowing = vec![kernel_column(ObservationKind::Byte, 0, 1)];
        let block = ObservationBlock {
            bytes: vec![0; 2],
            source_offset: 0,
            output_row_start: usize::MAX,
            row_count: 2,
        };
        assert_eq!(
            decode_worker_block(
                &mut overflowing,
                &block,
                1,
                &metadata,
                TextEncoding::Utf8,
                None,
            ),
            Err(DtaError::ArithmeticOverflow("parallel output row"))
        );
    }

    #[test]
    fn synchronous_column_kernel_polls_between_long_row_runs() {
        let row_count = COLUMNAR_CANCEL_CHECK_INTERVAL * 3;
        let mut columns = vec![kernel_column(ObservationKind::Byte, 0, 1)];
        let block = ObservationBlock {
            bytes: vec![1; row_count],
            source_offset: 0,
            output_row_start: 0,
            row_count,
        };
        let mut checks = 0;
        let mut interrupt = || {
            checks += 1;
            checks >= 2
        };
        assert_eq!(
            decode_worker_block(
                &mut columns,
                &block,
                1,
                &kernel_metadata(ByteOrder::Lsf),
                TextEncoding::Utf8,
                Some(&mut interrupt),
            ),
            Err(DtaError::Cancelled)
        );
        let ColumnBuilder::Byte { values, .. } = &columns[0].sink else {
            unreachable!()
        };
        assert_eq!(values.len(), COLUMNAR_CANCEL_CHECK_INTERVAL);
    }

    #[test]
    fn automatic_parallelism_accepts_large_byte_or_cell_workloads() {
        assert!(!automatic_parallel_workload(
            MIN_PARALLEL_DATA_BYTES - 1,
            MIN_PARALLEL_CELLS - 1,
        ));
        assert!(automatic_parallel_workload(
            MIN_PARALLEL_DATA_BYTES,
            MIN_PARALLEL_CELLS - 1,
        ));
        assert!(automatic_parallel_workload(
            MIN_PARALLEL_DATA_BYTES - 1,
            MIN_PARALLEL_CELLS,
        ));

        let narrow_projection = ObservationPlan {
            row_width: 4096,
            columns: vec![
                ObservationColumnPlan {
                    output_index: 0,
                    source_index: 0,
                    byte_offset: 0,
                    byte_width: 8,
                    kind: ObservationKind::Double,
                },
                ObservationColumnPlan {
                    output_index: 1,
                    source_index: 1,
                    byte_offset: 4088,
                    byte_width: 8,
                    kind: ObservationKind::Double,
                },
            ],
        };
        let rows = 100_000;
        let selected_bytes = narrow_projection.selected_data_bytes(rows);
        assert_eq!(selected_bytes, 1_600_000);
        assert!(!automatic_parallel_workload(selected_bytes, rows * 2));
    }

    #[test]
    fn short_strl_pointer_cells_return_a_truncation_error() {
        let metadata = DtaMetadata {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 1,
            nobs: 1,
            dataset_label: String::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            variables: vec![VariableInfo {
                name: "text".to_owned(),
                dta_type: DtaType::StrL,
                type_code: 32_768,
                format: "%9s".to_owned(),
                label: String::new(),
                value_label_name: String::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
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
    fn owning_sink_moves_large_projected_tables_without_cloning_their_text() {
        let label = "x".repeat(VALUE_LABEL_MOVE_THRESHOLD_BYTES);
        let label_pointer = label.as_ptr();
        let tables = vec![ValueLabelTable {
            name: "large".to_owned(),
            entries: vec![ValueLabelEntry {
                value: 1,
                missing_tag: None,
                label,
            }],
        }];
        let mut cache = ValueLabelCache::Full(FullValueLabelCache {
            indices_by_name: index_value_label_tables(&tables),
            tables,
        });

        let moved = take_projected_tables(&mut cache, &[0]).unwrap();
        assert_eq!(moved[0].entries[0].label.as_ptr(), label_pointer);
        assert!(matches!(cache, ValueLabelCache::Empty));
    }

    #[test]
    fn characteristic_plan_retains_only_accepted_record_descriptors() {
        let width = 129_usize;
        let mut bytes = b"<characteristics>".to_vec();
        for index in 0..2_048 {
            let name = if index == 2_047 {
                "source"
            } else {
                "_lang_list"
            };
            let payload_length = 2 * width + 2;
            bytes.extend_from_slice(b"<ch>");
            bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
            let mut target = vec![0; width];
            target[..4].copy_from_slice(b"_dta");
            bytes.extend_from_slice(&target);
            let mut encoded_name = vec![0; width];
            encoded_name[..name.len()].copy_from_slice(name.as_bytes());
            bytes.extend_from_slice(&encoded_name);
            bytes.extend_from_slice(b"x\0");
            bytes.extend_from_slice(b"</ch>");
        }
        bytes.extend_from_slice(b"</characteristics>");
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };
        let mut plan = CharacteristicPlan::default();
        let mut variable_indexes = VariableTargetIndexes::new(&[]);
        scan_modern_characteristics(
            &mut Cursor::new(bytes),
            &header,
            &mut Scratch::new(1024),
            |section, ordinal, payload_length| {
                plan_file_characteristic(
                    &mut plan,
                    section,
                    ordinal,
                    payload_length,
                    width,
                    TextEncoding::Utf8,
                    &mut variable_indexes,
                    "reading characteristic names",
                    "characteristic value",
                )
            },
        )
        .unwrap();
        assert_eq!(plan.retained_len(), 1);
        assert!(!plan.has_deferred_error());
    }

    #[test]
    fn streaming_modern_characteristics_validate_and_compact_duplicates() {
        const DUPLICATES: usize = 10_000;
        let width = 129_usize;
        let mut bytes = b"<characteristics>".to_vec();
        for ordinal in 0..DUPLICATES {
            let value = format!("{ordinal}\0");
            let payload_length = 2 * width + value.len();
            bytes.extend_from_slice(b"<ch>");
            bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
            let mut names = vec![0; 2 * width];
            names[..4].copy_from_slice(b"_dta");
            names[width..width + 6].copy_from_slice(b"source");
            bytes.extend_from_slice(&names);
            bytes.extend_from_slice(value.as_bytes());
            bytes.extend_from_slice(b"</ch>");
        }
        bytes.extend_from_slice(b"</characteristics>");
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };
        let mut reader = Cursor::new(bytes);
        let mut scratch = Scratch::new(1024);
        let mut plan = CharacteristicPlan::default();
        let mut variable_indexes = VariableTargetIndexes::new(&[]);
        scan_modern_characteristics(
            &mut reader,
            &header,
            &mut scratch,
            |section, ordinal, payload_length| {
                plan_file_characteristic(
                    &mut plan,
                    section,
                    ordinal,
                    payload_length,
                    width,
                    TextEncoding::Utf8,
                    &mut variable_indexes,
                    "reading characteristic names",
                    "characteristic value",
                )
            },
        )
        .unwrap();
        assert_eq!(plan.retained_len(), 1);
        assert!(!plan.has_deferred_error());
        drop(variable_indexes);

        let collector =
            decode_file_characteristics(plan, &mut reader, TextEncoding::Utf8, &mut scratch)
                .unwrap();
        let mut characteristics = Vec::new();
        collector.finish(&mut Vec::new(), &mut characteristics, &mut []);
        assert_eq!(
            characteristics,
            vec![StataCharacteristic {
                name: "source".into(),
                value: (DUPLICATES - 1).to_string(),
            }]
        );
    }

    #[test]
    fn streaming_modern_characteristics_validate_superseded_duplicate_values() {
        let width = 129_usize;
        let invalid_value = vec![b'x'; MAX_METADATA_VALUE_BYTES + 1];
        let mut bytes = b"<characteristics>".to_vec();
        for value in [invalid_value.as_slice(), b"replacement\0".as_slice()] {
            let payload_length = 2 * width + value.len();
            bytes.extend_from_slice(b"<ch>");
            bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
            let mut names = vec![0; 2 * width];
            names[..4].copy_from_slice(b"_dta");
            names[width..width + 6].copy_from_slice(b"source");
            bytes.extend_from_slice(&names);
            bytes.extend_from_slice(value);
            bytes.extend_from_slice(b"</ch>");
        }
        bytes.extend_from_slice(b"</characteristics>");
        let header = FileModernHeaderMap {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: FileTextRange {
                offset: 0,
                length: 0,
            },
            section_offsets: SectionOffsets {
                characteristics: 0,
                data: bytes.len() as u64,
                ..SectionOffsets::default()
            },
        };
        let mut plan = CharacteristicPlan::default();
        let mut variable_indexes = VariableTargetIndexes::new(&[]);
        scan_modern_characteristics(
            &mut Cursor::new(bytes),
            &header,
            &mut Scratch::new(1024),
            |section, ordinal, payload_length| {
                plan_file_characteristic(
                    &mut plan,
                    section,
                    ordinal,
                    payload_length,
                    width,
                    TextEncoding::Utf8,
                    &mut variable_indexes,
                    "reading characteristic names",
                    "characteristic value",
                )
            },
        )
        .unwrap();
        assert_eq!(plan.retained_len(), 1);
        assert!(plan.has_deferred_error());
        assert!(matches!(
            plan.decode(|_| Ok(String::new())),
            Err(DtaError::MetadataValueTooLong { .. })
        ));
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
