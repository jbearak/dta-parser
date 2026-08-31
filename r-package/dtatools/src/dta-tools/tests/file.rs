mod support;

use std::cell::RefCell;
use std::fs;
use std::io::{Cursor, Read, Result as IoResult, Seek, SeekFrom};
use std::rc::Rc;
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc,
};
use support::{fixture, parser_data_dir};

use dta_tools::{
    read_dta, read_dta_with_options, ColumnValues, DtaColumnSink, DtaError, DtaFile, DtaMetadata,
    DtaType, FileOptions, MissingTag, ParallelDtaSink, ReadOptions, ValueLabelTable,
};

#[derive(Default)]
struct Trace {
    reads: Vec<(u64, usize)>,
    seeks: Vec<u64>,
    max_request: usize,
}

struct TracedReader {
    inner: Cursor<Vec<u8>>,
    trace: Rc<RefCell<Trace>>,
}

impl TracedReader {
    fn new(bytes: Vec<u8>) -> (Self, Rc<RefCell<Trace>>) {
        let trace = Rc::new(RefCell::new(Trace::default()));
        (
            Self {
                inner: Cursor::new(bytes),
                trace: Rc::clone(&trace),
            },
            trace,
        )
    }
}

impl Read for TracedReader {
    fn read(&mut self, buffer: &mut [u8]) -> IoResult<usize> {
        let offset = self.inner.position();
        let read = self.inner.read(buffer)?;
        let mut trace = self.trace.borrow_mut();
        trace.max_request = trace.max_request.max(buffer.len());
        trace.reads.push((offset, read));
        Ok(read)
    }
}

impl Seek for TracedReader {
    fn seek(&mut self, position: SeekFrom) -> IoResult<u64> {
        let offset = self.inner.seek(position)?;
        self.trace.borrow_mut().seeks.push(offset);
        Ok(offset)
    }
}

fn options(row_start: u64, row_count: Option<u64>, columns: Vec<u32>) -> ReadOptions {
    ReadOptions {
        row_start,
        row_count,
        column_indices: Some(columns),
    }
}

struct ProbeColumn {
    panic_on_push: bool,
    started: Arc<AtomicBool>,
    pushes: Arc<AtomicUsize>,
}

impl ProbeColumn {
    fn push(&self) -> Result<(), DtaError> {
        if self.panic_on_push {
            panic!("intentional column-sink panic");
        }
        self.pushes.fetch_add(1, Ordering::SeqCst);
        self.started.store(true, Ordering::SeqCst);
        Ok(())
    }
}

impl DtaColumnSink for ProbeColumn {
    fn push_byte(
        &mut self,
        _row: usize,
        _value: i8,
        _missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.push()
    }

    fn push_int(
        &mut self,
        _row: usize,
        _value: i16,
        _missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.push()
    }

    fn push_long(
        &mut self,
        _row: usize,
        _value: i32,
        _missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.push()
    }

    fn push_float(
        &mut self,
        _row: usize,
        _value: f32,
        _missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.push()
    }

    fn push_double(
        &mut self,
        _row: usize,
        _value: f64,
        _missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.push()
    }

    fn push_fixed_string(&mut self, _row: usize, _value: &str) -> Result<(), DtaError> {
        self.push()
    }

    fn push_strl(&mut self, _row: usize, _value: &str) -> Result<(), DtaError> {
        self.push()
    }
}

struct ProbeSink {
    columns: Vec<ProbeColumn>,
}

impl ProbeSink {
    fn new(
        column_count: usize,
        panic_on_push: bool,
        started: Arc<AtomicBool>,
        pushes: Arc<AtomicUsize>,
    ) -> Self {
        let columns = (0..column_count)
            .map(|_| ProbeColumn {
                panic_on_push,
                started: Arc::clone(&started),
                pushes: Arc::clone(&pushes),
            })
            .collect();
        Self { columns }
    }
}

impl ParallelDtaSink for ProbeSink {
    type Output = ();
    type Column = ProbeColumn;
    type State = ();

    fn split(self) -> (Self::State, Vec<Self::Column>) {
        ((), self.columns)
    }

    fn finish_parallel(
        _state: Self::State,
        _columns: Vec<Self::Column>,
        _metadata: DtaMetadata,
        _row_start: u64,
        _row_count: u64,
        _value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        Ok(())
    }
}

fn first_non_strl_columns(file: &DtaFile<Cursor<Vec<u8>>>, count: usize) -> Vec<u32> {
    file.metadata()
        .variables
        .iter()
        .enumerate()
        .filter(|(_, variable)| variable.dta_type != DtaType::StrL)
        .take(count)
        .map(|(index, _)| u32::try_from(index).unwrap())
        .collect()
}

fn file_and_slice_error(bytes: Vec<u8>) -> DtaError {
    let slice_error = read_dta(&bytes).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    let file_error = file
        .read_with_options(&options(0, Some(0), vec![]))
        .unwrap_err();
    assert_eq!(file_error, slice_error);
    slice_error
}

fn add_v118_map_offset(bytes: &mut [u8], map_start: usize, index: usize, delta: u64) {
    let entry = map_start + b"<map>".len() + index * 8;
    let value = u64::from_le_bytes(bytes[entry..entry + 8].try_into().unwrap());
    bytes[entry..entry + 8].copy_from_slice(&(value + delta).to_le_bytes());
}

fn large_first_gso(mut bytes: Vec<u8>, extra: usize) -> (Vec<u8>, u64) {
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let first_gso = metadata.section_offsets.strls as usize + b"<strls>".len();
    let old_length =
        u32::from_le_bytes(bytes[first_gso + 16..first_gso + 20].try_into().unwrap()) as usize;
    let content_start = first_gso + 20;
    bytes.splice(
        content_start + old_length - 1..content_start + old_length - 1,
        vec![b'x'; extra],
    );
    bytes[first_gso + 16..first_gso + 20]
        .copy_from_slice(&u32::try_from(old_length + extra).unwrap().to_le_bytes());
    let delta = extra as u64;
    let map_start = metadata.section_offsets.map as usize;
    for index in 11..=13 {
        add_v118_map_offset(&mut bytes, map_start, index, delta);
    }
    (bytes, content_start as u64)
}

fn large_first_value_label(mut bytes: Vec<u8>, extra: usize) -> (Vec<u8>, u64) {
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let map_start = metadata.section_offsets.map as usize;
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let length_offset = table_start + b"<lbl>".len();
    let payload_start = length_offset + 4 + 129 + 3;
    let entry_count =
        u32::from_le_bytes(bytes[payload_start..payload_start + 4].try_into().unwrap()) as usize;
    let text_length = u32::from_le_bytes(
        bytes[payload_start + 4..payload_start + 8]
            .try_into()
            .unwrap(),
    ) as usize;
    let offsets_start = payload_start + 8;
    let values_start = offsets_start + entry_count * 4;
    let text_start = values_start + entry_count * 4;
    let first_offset =
        u32::from_le_bytes(bytes[offsets_start..offsets_start + 4].try_into().unwrap()) as usize;
    let first_nul = bytes[text_start + first_offset..text_start + text_length]
        .iter()
        .position(|byte| *byte == 0)
        .unwrap()
        + text_start
        + first_offset;
    bytes.splice(first_nul..first_nul, vec![b'x'; extra]);

    for index in 1..entry_count {
        let offset = offsets_start + index * 4;
        let value = u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap());
        bytes[offset..offset + 4]
            .copy_from_slice(&(value + u32::try_from(extra).unwrap()).to_le_bytes());
    }
    let declared = u32::from_le_bytes(bytes[length_offset..length_offset + 4].try_into().unwrap());
    bytes[length_offset..length_offset + 4]
        .copy_from_slice(&(declared + u32::try_from(extra).unwrap()).to_le_bytes());
    bytes[payload_start + 4..payload_start + 8].copy_from_slice(
        &(u32::try_from(text_length).unwrap() + u32::try_from(extra).unwrap()).to_le_bytes(),
    );
    let delta = extra as u64;
    for index in 12..=13 {
        add_v118_map_offset(&mut bytes, map_start, index, delta);
    }
    (bytes, (text_start + first_offset) as u64)
}

fn modern_value_label_ranges(bytes: &[u8], metadata: &DtaMetadata) -> Vec<(String, u64, u64)> {
    let name_width = match metadata.format_version {
        dta_tools::FormatVersion::V117 => 33,
        dta_tools::FormatVersion::V118 | dta_tools::FormatVersion::V119 => 129,
        _ => panic!("modern fixture expected"),
    };
    let mut cursor = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let mut ranges = Vec::new();
    while bytes[cursor..].starts_with(b"<lbl>") {
        let start = cursor;
        let length_start = start + b"<lbl>".len();
        let declared =
            u32::from_le_bytes(bytes[length_start..length_start + 4].try_into().unwrap()) as usize;
        let name_start = length_start + 4;
        let name_end = bytes[name_start..name_start + name_width]
            .iter()
            .position(|byte| *byte == 0)
            .unwrap();
        let name = String::from_utf8(bytes[name_start..name_start + name_end].to_vec()).unwrap();
        cursor = name_start + name_width + 3 + declared + b"</lbl>".len();
        ranges.push((name, start as u64, cursor as u64));
    }
    ranges
}

fn modern_value_label_value_ranges(
    bytes: &[u8],
    metadata: &DtaMetadata,
) -> Vec<(String, u64, u64)> {
    let name_width = match metadata.format_version {
        dta_tools::FormatVersion::V117 => 33,
        dta_tools::FormatVersion::V118 | dta_tools::FormatVersion::V119 => 129,
        _ => panic!("modern fixture expected"),
    };
    modern_value_label_ranges(bytes, metadata)
        .into_iter()
        .map(|(name, start, _)| {
            let payload_start = start as usize + b"<lbl>".len() + 4 + name_width + 3;
            let entry_count =
                u32::from_le_bytes(bytes[payload_start..payload_start + 4].try_into().unwrap())
                    as usize;
            let values_start = payload_start + 8 + entry_count * 4;
            (
                name,
                values_start as u64,
                (values_start + entry_count * 4) as u64,
            )
        })
        .collect()
}

fn many_short_first_value_labels(mut bytes: Vec<u8>, count: usize) -> Vec<u8> {
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let map_start = metadata.section_offsets.map as usize;
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let length_offset = table_start + b"<lbl>".len();
    let payload_start = length_offset + 4 + 129 + 3;
    let old_length =
        u32::from_le_bytes(bytes[length_offset..length_offset + 4].try_into().unwrap()) as usize;
    let text_length = count * 2;
    let mut payload = Vec::with_capacity(8 + count * 8 + text_length);
    payload.extend_from_slice(&i32::try_from(count).unwrap().to_le_bytes());
    payload.extend_from_slice(&i32::try_from(text_length).unwrap().to_le_bytes());
    for index in 0..count {
        payload.extend_from_slice(&i32::try_from(index * 2).unwrap().to_le_bytes());
    }
    for index in 0..count {
        payload.extend_from_slice(&i32::try_from(index).unwrap().to_le_bytes());
    }
    for _ in 0..count {
        payload.extend_from_slice(b"x\0");
    }
    assert!(payload.len() > old_length);
    let extra = payload.len() - old_length;
    bytes.splice(payload_start..payload_start + old_length, payload);
    bytes[length_offset..length_offset + 4]
        .copy_from_slice(&u32::try_from(old_length + extra).unwrap().to_le_bytes());
    for index in 12..=13 {
        add_v118_map_offset(&mut bytes, map_start, index, extra as u64);
    }
    bytes
}

fn alternating_short_first_value_labels(bytes: Vec<u8>, count: usize) -> Vec<u8> {
    let mut bytes = many_short_first_value_labels(bytes, count);
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let offsets_start = payload_start + 8;
    let text_length = i32::from_le_bytes(
        bytes[payload_start + 4..payload_start + 8]
            .try_into()
            .unwrap(),
    );
    let low = 2_i32;
    let high = text_length - 2;
    for index in 0..count {
        let offset = offsets_start + index * 4;
        let boundary = if index.is_multiple_of(2) { low } else { high };
        bytes[offset..offset + 4].copy_from_slice(&boundary.to_le_bytes());
    }
    bytes
}

fn widely_spaced_first_value_labels(mut bytes: Vec<u8>) -> (Vec<u8>, usize) {
    const ENTRY_COUNT: usize = 65_536;
    const TEXT_PAGE_BYTES: usize = 64 * 1024;
    const TEXT_PAGE_COUNT: usize = 1024;
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let map_start = metadata.section_offsets.map as usize;
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let length_offset = table_start + b"<lbl>".len();
    let payload_start = length_offset + 4 + 129 + 3;
    let old_length =
        u32::from_le_bytes(bytes[length_offset..length_offset + 4].try_into().unwrap()) as usize;
    let text_length = TEXT_PAGE_BYTES * TEXT_PAGE_COUNT;
    let mut payload = Vec::with_capacity(8 + ENTRY_COUNT * 8 + text_length);
    payload.extend_from_slice(&i32::try_from(ENTRY_COUNT).unwrap().to_le_bytes());
    payload.extend_from_slice(&i32::try_from(text_length).unwrap().to_le_bytes());
    for index in 0..ENTRY_COUNT {
        let page = index % TEXT_PAGE_COUNT;
        let boundary = page * TEXT_PAGE_BYTES + 2;
        payload.extend_from_slice(&i32::try_from(boundary).unwrap().to_le_bytes());
    }
    payload.resize(8 + ENTRY_COUNT * 8 + text_length, 0);
    let new_length = payload.len();
    bytes.splice(payload_start..payload_start + old_length, payload);
    bytes[length_offset..length_offset + 4]
        .copy_from_slice(&u32::try_from(new_length).unwrap().to_le_bytes());
    let extra = u64::try_from(new_length - old_length).unwrap();
    for index in 12..=13 {
        add_v118_map_offset(&mut bytes, map_start, index, extra);
    }
    (bytes, text_length)
}

fn wide_empty_fixed_strings(mut bytes: Vec<u8>) -> (Vec<u8>, u32) {
    const WIDE: usize = 2045;
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let variable_index = metadata
        .variables
        .iter()
        .position(|variable| matches!(variable.dta_type, DtaType::FixedString(_)))
        .unwrap();
    let variable = &metadata.variables[variable_index];
    let old_width = variable.byte_width as usize;
    assert!(old_width < WIDE);
    let extra_per_row = WIDE - old_width;
    let payload_start = metadata.section_offsets.data as usize + b"<data>".len();
    for row in (0..metadata.nobs as usize).rev() {
        let cell_start =
            payload_start + row * metadata.obs_length as usize + variable.byte_offset as usize;
        bytes[cell_start..cell_start + old_width].fill(0);
        bytes.splice(
            cell_start + old_width..cell_start + old_width,
            vec![0; extra_per_row],
        );
    }
    let type_offset = metadata.section_offsets.variable_types as usize
        + b"<variable_types>".len()
        + variable_index * 2;
    bytes[type_offset..type_offset + 2].copy_from_slice(&(WIDE as u16).to_le_bytes());
    let total_extra = u64::try_from(extra_per_row).unwrap() * metadata.nobs;
    let map_start = metadata.section_offsets.map as usize;
    for index in 10..=13 {
        add_v118_map_offset(&mut bytes, map_start, index, total_extra);
    }
    (bytes, variable_index as u32)
}

fn overlong_first_gso(mut bytes: Vec<u8>) -> Vec<u8> {
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let first_gso = metadata.section_offsets.strls as usize + b"<strls>".len();
    let content_start = first_gso + 20;
    let gso_end = metadata.section_offsets.value_labels as usize - b"</strls>".len();
    let overlong = u32::try_from(gso_end - content_start + 1).unwrap();
    bytes[first_gso + 16..first_gso + 20].copy_from_slice(&overlong.to_le_bytes());
    bytes
}

fn beyond_eof_first_gso(mut bytes: Vec<u8>) -> Vec<u8> {
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let first_gso = metadata.section_offsets.strls as usize + b"<strls>".len();
    bytes[first_gso + 16..first_gso + 20].copy_from_slice(&u32::MAX.to_le_bytes());
    bytes
}

#[test]
fn file_reads_match_slice_for_modern_strl_and_legacy_projections() {
    for (name, read_options) in [
        ("auto_v118.dta", options(5, Some(4), vec![11, 0, 3])),
        ("all_types_v118.dta", options(1, Some(3), vec![7, 0, 6])),
        ("all_types_v117.dta", options(1, Some(3), vec![7, 0, 6])),
        ("all_types_v115.dta", options(1, Some(3), vec![6, 0, 4])),
        ("value_labels_v115.dta", options(0, Some(4), vec![2, 0])),
    ] {
        let bytes = fixture(name);
        let expected = read_dta_with_options(&bytes, &read_options).unwrap();
        let mut file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
        let actual = file.read_with_options(&read_options).unwrap();
        assert_eq!(actual, expected, "{name}");
        if name == "auto_v118.dta" {
            assert_eq!(
                actual
                    .metadata
                    .notes
                    .iter()
                    .map(|note| note.text.as_str())
                    .collect::<Vec<_>>(),
                ["From Consumer Reports with permission"]
            );
        }
    }
}

#[test]
fn modern_characteristic_lengths_cannot_cross_the_data_section() {
    let mut bytes = fixture("auto_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let length = metadata.section_offsets.characteristics as usize + b"<characteristics><ch>".len();
    bytes[length..length + 4].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(matches!(
        DtaFile::from_reader(Cursor::new(bytes)),
        Err(DtaError::Truncated {
            context: "characteristic payload",
            ..
        })
    ));
}

#[test]
fn bounds_each_read_and_avoids_unselected_rows_and_gso_payloads() {
    let bytes = fixture("strl_test_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    trace.borrow_mut().reads.clear();
    let data = file
        .read_with_options(&options(2, Some(1), vec![1]))
        .unwrap();
    assert_eq!(data.row_start, 2);
    assert_eq!(data.row_count, 1);
    let trace = trace.borrow();
    assert!(trace.max_request <= 1024);
    assert!(file.max_scratch_bytes_used() <= 1024);

    let data_payload = metadata.section_offsets.data + 6;
    let selected = data_payload + 2 * metadata.obs_length + metadata.variables[1].byte_offset;
    assert!(trace.reads.iter().any(|(offset, length)| {
        *offset <= selected && offset.saturating_add(*length as u64) >= selected + 4
    }));
    let gso_payload_start = metadata.section_offsets.strls + 7;
    let gso_payload_end = metadata.section_offsets.value_labels - 8;
    assert!(!trace.reads.iter().any(|(offset, length)| {
        let end = offset.saturating_add(*length as u64);
        *offset < gso_payload_end && end > gso_payload_start
    }));
}

#[test]
fn stages_bounded_wide_rows_for_dense_and_sparse_projections() {
    let bytes = fixture("wide_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    assert!(metadata.obs_length <= 1024);
    let dense = (0..metadata.nvar).collect::<Vec<_>>();
    let sparse = vec![metadata.nvar - 1, 0, metadata.nvar / 2];
    let rows_per_chunk = 1024_u64 / metadata.obs_length;
    let expected_chunks = metadata.nobs.div_ceil(rows_per_chunk) as usize;
    let payload_start = metadata.section_offsets.data + b"<data>".len() as u64;
    let payload_end = payload_start + metadata.nobs * metadata.obs_length;

    for columns in [dense, sparse] {
        let read_options = options(0, None, columns);
        let expected = read_dta_with_options(&bytes, &read_options).unwrap();
        let (reader, trace) = TracedReader::new(bytes.clone());
        let mut file = DtaFile::from_reader_with_options(
            reader,
            FileOptions {
                max_buffer_bytes: 1024,
            },
        )
        .unwrap();
        {
            let mut trace = trace.borrow_mut();
            trace.reads.clear();
            trace.seeks.clear();
            trace.max_request = 0;
        }
        let actual = file.read_with_options(&read_options).unwrap();
        assert_eq!(actual, expected);

        let trace = trace.borrow();
        let observation_reads = trace
            .reads
            .iter()
            .filter(|(offset, length)| {
                *offset < payload_end && offset.saturating_add(*length as u64) > payload_start
            })
            .collect::<Vec<_>>();
        let observation_seeks = trace
            .seeks
            .iter()
            .filter(|offset| **offset >= payload_start && **offset < payload_end)
            .count();
        assert_eq!(observation_reads.len(), expected_chunks);
        assert_eq!(observation_seeks, expected_chunks);
        assert!(observation_reads.iter().all(|(_, length)| *length <= 1024));
        assert!(trace.max_request <= 1024);
        drop(trace);
        assert!(file.max_scratch_bytes_used() <= 1024);
    }
}

#[test]
fn parallel_vectors_match_serial_across_supported_releases_and_strls() {
    for name in [
        "synthetic-v105.dta",
        "synthetic-v108.dta",
        "synthetic-v110.dta",
        "synthetic-v111.dta",
        "all_types_v115.dta",
        "all_types_v117.dta",
        "all_types_v118.dta",
    ] {
        let bytes = if name.starts_with("synthetic-") {
            fs::read(parser_data_dir().join(name)).unwrap()
        } else {
            fixture(name)
        };
        let metadata = dta_tools::parse_metadata(&bytes).unwrap();
        let columns = metadata
            .variables
            .iter()
            .enumerate()
            .filter(|(_, variable)| variable.dta_type != DtaType::StrL)
            .map(|(index, _)| u32::try_from(index).unwrap())
            .collect::<Vec<_>>();
        assert!(columns.len() >= 2, "{name}");
        let read_options = options(0, None, columns.clone());

        let mut serial_file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
        let serial = serial_file.read_with_options(&read_options).unwrap();
        let mut parallel_file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
        let parallel = parallel_file
            .read_with_parallel_interrupt(&read_options, 2, || false)
            .unwrap();
        assert_eq!(parallel, serial, "{name}");

        let single_options = options(0, None, vec![columns[0]]);
        let mut single_serial_file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
        let single_serial = single_serial_file
            .read_with_options(&single_options)
            .unwrap();
        let mut single_column_file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
        assert!(single_column_file
            .supports_columnar_sink(&single_options)
            .unwrap());
        let single_column = single_column_file
            .read_with_parallel_interrupt(&single_options, 1, || false)
            .unwrap();
        assert_eq!(single_column, single_serial, "single column: {name}");

        let expected_threads = std::thread::available_parallelism()
            .map_or(1, usize::from)
            .min(4)
            .min(read_options.column_indices.as_ref().unwrap().len())
            .max(1);
        assert_eq!(
            parallel_file
                .parallel_thread_count(&read_options, 4)
                .unwrap(),
            expected_threads,
            "{name}"
        );
    }

    for name in ["all_types_v117.dta", "strl_test_v118.dta"] {
        let strl = fixture(name);
        let mut serial_file = DtaFile::from_reader(Cursor::new(strl.clone())).unwrap();
        let serial = serial_file.read().unwrap();
        let mut strl_file = DtaFile::from_reader(Cursor::new(strl)).unwrap();
        let parallel = strl_file
            .read_with_parallel_interrupt(&ReadOptions::default(), 4, || false)
            .unwrap();
        assert_eq!(parallel, serial, "{name}");
        let expected_threads = std::thread::available_parallelism()
            .map_or(1, usize::from)
            .min(4)
            .min(strl_file.metadata().variables.len())
            .max(1);
        assert_eq!(
            strl_file
                .parallel_thread_count(&ReadOptions::default(), 4)
                .unwrap(),
            expected_threads,
            "{name}"
        );
        assert!(
            strl_file
                .supports_columnar_sink(&ReadOptions::default())
                .unwrap(),
            "{name}"
        );
    }
}

#[test]
fn parallel_sink_panics_are_returned_as_errors() {
    let mut file = DtaFile::from_reader(Cursor::new(fixture("auto_v118.dta"))).unwrap();
    let columns = first_non_strl_columns(&file, 2);
    assert_eq!(columns.len(), 2);
    let started = Arc::new(AtomicBool::new(false));
    let pushes = Arc::new(AtomicUsize::new(0));

    let result = file.read_with_parallel_sink_and_interrupt(
        &options(0, None, columns),
        2,
        {
            let started = Arc::clone(&started);
            let pushes = Arc::clone(&pushes);
            move |_metadata, _row_start, _row_count, indices| {
                Ok(ProbeSink::new(
                    indices.len(),
                    true,
                    Arc::clone(&started),
                    Arc::clone(&pushes),
                ))
            }
        },
        || false,
    );

    assert_eq!(
        result,
        Err(DtaError::Output(
            "parallel decoder worker panicked".to_owned()
        ))
    );
}

#[test]
fn pipelined_cancellation_does_not_dispatch_the_ready_block() {
    let buffer_limit = 1024;
    let mut file = DtaFile::from_reader_with_options(
        Cursor::new(fixture("auto_v118.dta")),
        FileOptions {
            max_buffer_bytes: buffer_limit,
        },
    )
    .unwrap();
    let columns = first_non_strl_columns(&file, 2);
    assert_eq!(columns.len(), 2);
    let rows_per_block =
        buffer_limit / usize::try_from(file.metadata().obs_length).expect("row width fits usize");
    assert!(rows_per_block > 0);
    assert!(usize::try_from(file.metadata().nobs).unwrap() > rows_per_block);
    let started = Arc::new(AtomicBool::new(false));
    let pushes = Arc::new(AtomicUsize::new(0));

    let result = file.read_with_parallel_sink_and_interrupt(
        &options(0, None, columns),
        2,
        {
            let started = Arc::clone(&started);
            let pushes = Arc::clone(&pushes);
            move |_metadata, _row_start, _row_count, indices| {
                Ok(ProbeSink::new(
                    indices.len(),
                    false,
                    Arc::clone(&started),
                    Arc::clone(&pushes),
                ))
            }
        },
        {
            let started = Arc::clone(&started);
            move || started.load(Ordering::SeqCst)
        },
    );

    assert_eq!(result, Err(DtaError::Cancelled));
    assert_eq!(pushes.load(Ordering::SeqCst), rows_per_block * 2);
}

#[test]
fn file_and_slice_reject_invalid_signatures_identically() {
    for bytes in [b"xot a dta".as_slice(), b"<stata_dat>".as_slice()] {
        assert_eq!(
            dta_tools::parse_metadata(bytes),
            Err(DtaError::InvalidSignature)
        );
        assert!(matches!(
            DtaFile::from_reader(Cursor::new(bytes.to_vec())),
            Err(DtaError::InvalidSignature)
        ));
    }
}

#[test]
fn file_and_slice_report_the_same_overlong_gso_error() {
    let bytes = overlong_first_gso(fixture("strl_test_v118.dta"));
    let slice_error = read_dta(&bytes).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let file_error = file
        .read_with_options(&options(0, Some(1), vec![0]))
        .unwrap_err();
    assert_eq!(file_error, slice_error);
    let mut parallel_file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    let parallel_error = parallel_file
        .read_with_parallel_interrupt(&options(0, Some(1), vec![0]), 1, || false)
        .unwrap_err();
    assert_eq!(parallel_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::Truncated {
            context: "GSO content",
            ..
        }
    ));
}

#[test]
fn file_and_slice_report_the_same_beyond_eof_gso_error() {
    let bytes = beyond_eof_first_gso(fixture("strl_test_v118.dta"));
    let slice_error = read_dta(&bytes).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let file_error = file
        .read_with_options(&options(0, Some(1), vec![0]))
        .unwrap_err();
    assert_eq!(file_error, slice_error);
    let mut parallel_file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    let parallel_error = parallel_file
        .read_with_parallel_interrupt(&options(0, Some(1), vec![0]), 1, || false)
        .unwrap_err();
    assert_eq!(parallel_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::Truncated {
            context: "GSO content",
            needed,
            ..
        } if needed == u32::MAX as usize
    ));
}

#[test]
fn file_and_slice_report_identical_value_label_structure_errors() {
    let original = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&original).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let length_offset = table_start + b"<lbl>".len();
    let payload_start = length_offset + 4 + 129 + 3;

    let mut wrong_length = original.clone();
    wrong_length[length_offset..length_offset + 4].copy_from_slice(&70_i32.to_le_bytes());
    assert_eq!(
        file_and_slice_error(wrong_length),
        DtaError::InvalidValueLabelLength {
            offset: table_start,
            declared: 70,
            expected: 69,
        }
    );

    let entry_count = u32::from_le_bytes(
        original[payload_start..payload_start + 4]
            .try_into()
            .unwrap(),
    ) as usize;
    let values_start = payload_start + 8 + entry_count * 4;
    let mut unsorted = original;
    let first_value = unsorted[values_start..values_start + 4].to_vec();
    unsorted[values_start + 4..values_start + 8].copy_from_slice(&first_value);
    let slice = read_dta(&unsorted).unwrap();
    let mut file = DtaFile::from_reader(Cursor::new(unsorted)).unwrap();
    assert_eq!(file.value_label_tables().unwrap(), slice.value_label_tables);
    assert_eq!(slice.value_label_tables[0].entries[0].value, 1);
    assert_eq!(slice.value_label_tables[0].entries[1].value, 1);
}

#[test]
fn file_and_slice_match_for_mid_codepoint_and_malformed_utf8_label_offsets() {
    let original = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&original).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let entry_count = u32::from_le_bytes(
        original[payload_start..payload_start + 4]
            .try_into()
            .unwrap(),
    ) as usize;
    let offsets_start = payload_start + 8;
    let text_start = offsets_start + entry_count * 8;

    let mut mid_codepoint = original.clone();
    mid_codepoint[text_start..text_start + 3].copy_from_slice(&[0xc3, 0xa9, 0]);
    for entry_index in [0, 2] {
        let offset_position = offsets_start + entry_index * 4;
        mid_codepoint[offset_position..offset_position + 4].copy_from_slice(&1_i32.to_le_bytes());
    }
    assert_eq!(
        file_and_slice_error(mid_codepoint),
        DtaError::InvalidValueLabelTextOffset {
            entry_index: 0,
            offset: offsets_start,
            text_offset: 1,
            text_length: 29,
        }
    );

    let mut malformed = original;
    malformed[text_start..text_start + 3].copy_from_slice(&[0xc3, 0xff, 0]);
    malformed[offsets_start..offsets_start + 4].copy_from_slice(&1_i32.to_le_bytes());
    let expected = read_dta(&malformed).unwrap();
    assert_eq!(expected.value_label_tables[0].entries[0].label, "�");
    let mut file = DtaFile::from_reader(Cursor::new(malformed)).unwrap();
    assert_eq!(file.read().unwrap(), expected);
}

#[test]
fn labels_are_lazy_and_cancellation_never_returns_partial_data() {
    let bytes = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    assert!(!trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset >= metadata.section_offsets.data));
    assert!(!trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset >= metadata.section_offsets.value_labels));
    assert_eq!(file.value_label_tables().unwrap().len(), 3);

    let before = trace.borrow().reads.len();
    assert_eq!(
        file.read_with_interrupt(&ReadOptions::default(), || true),
        Err(DtaError::Cancelled)
    );
    assert_eq!(trace.borrow().reads.len(), before);

    let mut checks = 0;
    let result = file.read_with_interrupt(&ReadOptions::default(), || {
        checks += 1;
        checks > 8
    });
    assert_eq!(result, Err(DtaError::Cancelled));
}

#[test]
fn projected_reads_clone_only_selected_value_label_tables() {
    let bytes = fixture("value_labels_v118.dta");
    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let projected = file.read_with_options(&options(0, None, vec![1])).unwrap();
    assert_eq!(projected.value_label_tables.len(), 1);
    assert_eq!(projected.value_label_tables[0].name, "rep_lbl");

    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let parallel = file
        .read_with_parallel_interrupt(&options(0, None, vec![1]), 1, || false)
        .unwrap();
    assert_eq!(parallel.value_label_tables.len(), 1);
    assert_eq!(parallel.value_label_tables[0].name, "rep_lbl");

    let (reader, trace) = TracedReader::new(bytes.clone());
    let mut file = DtaFile::from_reader(reader).unwrap();
    file.read_with_options(&options(0, None, vec![1])).unwrap();
    let reads_after_projection = trace.borrow().reads.len();
    assert_eq!(file.value_label_tables().unwrap().len(), 3);
    assert!(
        trace.borrow().reads.len() > reads_after_projection,
        "a projected read must not retain the complete registry cache"
    );

    let mut file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    let empty = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(empty.value_label_tables.is_empty());
}

#[test]
fn projected_cache_does_not_retain_unreferenced_registry_locations() {
    let mut bytes = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let names_start =
        metadata.section_offsets.value_label_names as usize + b"<value_label_names>".len();
    let names_end = names_start + metadata.variables.len() * 129;
    bytes[names_start..names_end].fill(0);
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    assert!(metadata
        .variables
        .iter()
        .all(|variable| variable.value_label_name.is_empty()));

    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader(reader).unwrap();
    let projected = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(projected.value_label_tables.is_empty());

    trace.borrow_mut().reads.clear();
    assert_eq!(file.value_label_tables().unwrap().len(), 3);
    assert!(trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset == metadata.section_offsets.value_labels));
}

#[test]
fn repeated_projections_reuse_the_validated_value_label_index() {
    let bytes = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let ranges = modern_value_label_ranges(&bytes, &metadata);
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader(reader).unwrap();

    let first = file.read_with_options(&options(0, None, vec![1])).unwrap();
    assert_eq!(first.value_label_tables[0].name, "rep_lbl");

    trace.borrow_mut().reads.clear();
    let second = file.read_with_options(&options(0, None, vec![2])).unwrap();
    assert_eq!(second.value_label_tables[0].name, "region_lbl");
    let (_, selected_start, selected_end) = ranges
        .iter()
        .find(|(name, _, _)| name == "region_lbl")
        .unwrap();
    let label_reads = trace
        .borrow()
        .reads
        .iter()
        .copied()
        .filter(|(offset, _)| *offset >= metadata.section_offsets.value_labels)
        .collect::<Vec<_>>();
    assert!(!label_reads.is_empty());
    assert!(label_reads.iter().all(|(offset, length)| {
        *offset >= *selected_start && *offset + *length as u64 <= *selected_end
    }));

    trace.borrow_mut().reads.clear();
    file.read_with_options(&options(0, None, vec![2])).unwrap();
    assert!(!trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset >= metadata.section_offsets.value_labels));
}

#[test]
fn unselected_value_label_validation_skips_value_arrays() {
    let bytes = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let value_ranges = modern_value_label_value_ranges(&bytes, &metadata);
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader(reader).unwrap();
    trace.borrow_mut().reads.clear();

    let projected = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(projected.value_label_tables.is_empty());
    for (name, start, end) in value_ranges {
        assert!(
            !trace.borrow().reads.iter().any(|(offset, length)| {
                *offset < end && offset.saturating_add(*length as u64) > start
            }),
            "unselected table `{name}` read its value array"
        );
    }
}

#[test]
fn projected_slice_and_file_validate_unselected_utf8_label_offsets() {
    let mut bytes = fixture("value_labels_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let entry_count =
        u32::from_le_bytes(bytes[payload_start..payload_start + 4].try_into().unwrap()) as usize;
    let offsets_start = payload_start + 8;
    let text_start = offsets_start + entry_count * 8;
    bytes[text_start..text_start + 3].copy_from_slice(&[0xc3, 0xa9, 0]);
    bytes[offsets_start..offsets_start + 4].copy_from_slice(&1_i32.to_le_bytes());
    let read_options = options(0, None, vec![2]);

    let slice_error = read_dta_with_options(&bytes, &read_options).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let file_error = file.read_with_options(&read_options).unwrap_err();
    assert_eq!(file_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::InvalidValueLabelTextOffset { entry_index: 0, .. }
    ));

    assert!(entry_count >= 2);
    let text_length = i32::from_le_bytes(
        bytes[payload_start + 4..payload_start + 8]
            .try_into()
            .unwrap(),
    );
    bytes[offsets_start + 4..offsets_start + 8].copy_from_slice(&text_length.to_le_bytes());
    let slice_error = read_dta_with_options(&bytes, &read_options).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes.clone())).unwrap();
    let file_error = file.read_with_options(&read_options).unwrap_err();
    assert_eq!(file_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::InvalidValueLabelTextOffset { entry_index: 0, .. }
    ));
    let slice_error = read_dta(&bytes).unwrap_err();
    let mut file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    let file_error = file.read().unwrap_err();
    assert_eq!(file_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::InvalidValueLabelTextOffset { entry_index: 0, .. }
    ));
}

#[test]
fn large_unselected_value_label_offsets_use_bounded_staging() {
    let bytes = many_short_first_value_labels(fixture("value_labels_v118.dta"), 100_000);
    let slice = read_dta_with_options(&bytes, &options(0, None, Vec::new())).unwrap();
    assert!(slice.value_label_tables.is_empty());
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    let projected = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(projected.value_label_tables.is_empty());
    assert!(file.max_scratch_bytes_used() <= 1024);
    assert!(trace.borrow().max_request <= 1024);
}

#[test]
fn unordered_unselected_value_label_offsets_use_bounded_file_io() {
    let bytes = alternating_short_first_value_labels(fixture("value_labels_v118.dta"), 100_000);
    let file_length = bytes.len();
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    {
        let mut trace = trace.borrow_mut();
        trace.reads.clear();
        trace.seeks.clear();
    }
    let projected = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(projected.value_label_tables.is_empty());
    let trace = trace.borrow();
    let total_read = trace.reads.iter().map(|(_, length)| *length).sum::<usize>();
    assert!(total_read < file_length * 5, "read {total_read} bytes");
    assert!(
        trace.seeks.len() < 5_000,
        "issued {} seeks",
        trace.seeks.len()
    );
}

#[test]
fn widely_spaced_offset_batches_bound_repeated_page_reads() {
    let (bytes, text_length) = widely_spaced_first_value_labels(fixture("value_labels_v118.dta"));
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader(reader).unwrap();
    {
        let mut trace = trace.borrow_mut();
        trace.reads.clear();
        trace.seeks.clear();
    }
    let projected = file
        .read_with_options(&options(0, None, Vec::new()))
        .unwrap();
    assert!(projected.value_label_tables.is_empty());
    let trace = trace.borrow();
    let total_read = trace.reads.iter().map(|(_, length)| *length).sum::<usize>();
    assert!(
        total_read < text_length * 3,
        "read {total_read} bytes while validating {text_length} text bytes"
    );
    assert!(
        trace.seeks.len() < 25_000,
        "issued {} seeks",
        trace.seeks.len()
    );
}

#[test]
fn late_invalid_value_label_offset_batches_prior_utf8_validation() {
    let count = 100_000;
    let mut bytes = alternating_short_first_value_labels(fixture("value_labels_v118.dta"), count);
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let offsets_start = payload_start + 8;
    let text_length = i32::from_le_bytes(
        bytes[payload_start + 4..payload_start + 8]
            .try_into()
            .unwrap(),
    );
    let final_offset = offsets_start + (count - 1) * 4;
    bytes[final_offset..final_offset + 4].copy_from_slice(&text_length.to_le_bytes());
    let slice_error = read_dta(&bytes).unwrap_err();

    let file_length = bytes.len();
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    {
        let mut trace = trace.borrow_mut();
        trace.reads.clear();
        trace.seeks.clear();
    }
    let file_error = file.read().unwrap_err();
    assert_eq!(file_error, slice_error);
    assert!(matches!(
        file_error,
        DtaError::InvalidValueLabelTextOffset { entry_index, .. }
            if entry_index == count - 1
    ));
    let trace = trace.borrow();
    let total_read = trace.reads.iter().map(|(_, length)| *length).sum::<usize>();
    assert!(total_read < file_length * 5, "read {total_read} bytes");
    assert!(
        trace.seeks.len() < 5_000,
        "issued {} seeks",
        trace.seeks.len()
    );
}

#[test]
fn split_interrupt_callbacks_keep_row_polling_separate() {
    let mut file = DtaFile::from_reader(Cursor::new(fixture("auto_v118.dta"))).unwrap();
    let mut coarse_checks = 0_usize;
    let mut frequent_checks = 0_usize;
    let result = file.read_with_interrupts(
        &ReadOptions::default(),
        || {
            coarse_checks += 1;
            false
        },
        || {
            frequent_checks += 1;
            true
        },
    );
    assert_eq!(result, Err(DtaError::Cancelled));
    assert!(coarse_checks >= 2);
    assert_eq!(frequent_checks, 1);
}

#[test]
fn cancels_between_large_gso_chunks_without_returning_partial_data() {
    let (bytes, content_start) = large_first_gso(fixture("strl_test_v118.dta"), 4096);
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    trace.borrow_mut().reads.clear();
    let result = file.read_with_interrupts(
        &options(0, Some(1), vec![0]),
        || {
            trace
                .borrow()
                .reads
                .iter()
                .any(|(offset, length)| *offset == content_start && *length == 1024)
        },
        || false,
    );
    assert_eq!(result, Err(DtaError::Cancelled));
    assert!(!trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset == content_start + 1024));
    assert!(file.max_scratch_bytes_used() <= 1024);
}

#[test]
fn cancels_between_large_label_chunks_and_leaves_cache_uninitialized() {
    let (bytes, label_start) = large_first_value_label(fixture("value_labels_v118.dta"), 4096);
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    trace.borrow_mut().reads.clear();
    let result = file.read_with_interrupts(
        &options(0, Some(0), vec![]),
        || {
            trace
                .borrow()
                .reads
                .iter()
                .any(|(offset, length)| *offset == label_start && *length == 1024)
        },
        || false,
    );
    assert_eq!(result, Err(DtaError::Cancelled));
    assert!(!trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, _)| *offset == label_start + 1024));

    trace.borrow_mut().reads.clear();
    assert_eq!(file.value_label_tables().unwrap().len(), 3);
    assert!(trace
        .borrow()
        .reads
        .iter()
        .any(|(offset, length)| *offset == label_start && *length == 1024));
    assert!(file.max_scratch_bytes_used() <= 1024);
}

#[test]
fn shared_gso_references_are_decoded_once_with_projection() {
    let mut bytes = fixture("strl_test_v118.dta");
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let payload = metadata.section_offsets.data as usize + b"<data>".len();
    let first_pointer = payload + metadata.variables[0].byte_offset as usize;
    let repeated_pointer =
        payload + 4 * metadata.obs_length as usize + metadata.variables[0].byte_offset as usize;
    let pointer = bytes[first_pointer..first_pointer + 8].to_vec();
    bytes[repeated_pointer..repeated_pointer + 8].copy_from_slice(&pointer);
    let expected = read_dta_with_options(&bytes, &options(0, None, vec![0])).unwrap();
    let first_gso = metadata.section_offsets.strls as usize + b"<strls>".len();
    let content_start = (first_gso + 20) as u64;
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader(reader).unwrap();
    trace.borrow_mut().reads.clear();
    let actual = file.read_with_options(&options(0, None, vec![0])).unwrap();
    assert_eq!(actual, expected);
    assert_eq!(
        trace
            .borrow()
            .reads
            .iter()
            .filter(|(offset, _)| *offset == content_start)
            .count(),
        1
    );
}

#[test]
fn retained_string_capacity_tracks_useful_text_not_source_ranges() {
    let bytes = many_short_first_value_labels(fixture("value_labels_v118.dta"), 256);
    let mut labels_file = DtaFile::from_reader_with_options(
        Cursor::new(bytes),
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    let first_table = &labels_file.value_label_tables().unwrap()[0];
    assert_eq!(first_table.entries.len(), 256);
    let useful_label_bytes = first_table
        .entries
        .iter()
        .map(|entry| entry.label.len())
        .sum::<usize>();
    let retained_label_bytes = first_table
        .entries
        .iter()
        .map(|entry| entry.label.capacity())
        .sum::<usize>();
    assert!(retained_label_bytes <= useful_label_bytes * 4 + 256 * 8);
    assert!(labels_file.max_scratch_bytes_used() <= 1024);

    let (bytes, variable_index) = wide_empty_fixed_strings(fixture("all_types_v118.dta"));
    let read_options = options(0, None, vec![variable_index]);
    let expected = read_dta_with_options(&bytes, &read_options).unwrap();
    let mut strings_file = DtaFile::from_reader_with_options(
        Cursor::new(bytes),
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    let data = strings_file.read_with_options(&read_options).unwrap();
    assert_eq!(data, expected);
    let ColumnValues::FixedString { values } = &data.columns[0].values else {
        panic!("expected a fixed-string column");
    };
    assert!(values.iter().all(String::is_empty));
    assert!(values.iter().map(String::capacity).sum::<usize>() <= values.len() * 8);
    assert!(strings_file.max_scratch_bytes_used() <= 1024);
}

#[test]
fn value_label_text_block_is_streamed_once_in_bounded_reads() {
    let bytes = many_short_first_value_labels(fixture("value_labels_v118.dta"), 256);
    let metadata = dta_tools::parse_metadata(&bytes).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let entry_count =
        u32::from_le_bytes(bytes[payload_start..payload_start + 4].try_into().unwrap()) as usize;
    let text_length = u32::from_le_bytes(
        bytes[payload_start + 4..payload_start + 8]
            .try_into()
            .unwrap(),
    ) as usize;
    let text_start = (payload_start + 8 + entry_count * 8) as u64;
    let text_end = text_start + text_length as u64;
    let (reader, trace) = TracedReader::new(bytes);
    let mut file = DtaFile::from_reader_with_options(
        reader,
        FileOptions {
            max_buffer_bytes: 1024,
        },
    )
    .unwrap();
    trace.borrow_mut().reads.clear();

    assert_eq!(file.value_label_tables().unwrap()[0].entries.len(), 256);
    let text_reads = trace
        .borrow()
        .reads
        .iter()
        .copied()
        .filter(|(offset, _)| *offset >= text_start && *offset < text_end)
        .collect::<Vec<_>>();
    assert_eq!(text_reads, vec![(text_start, text_length)]);
    assert!(file.max_scratch_bytes_used() <= 1024);
}

#[test]
fn rejects_zero_buffer_limit() {
    assert!(matches!(
        DtaFile::from_reader_with_options(
            Cursor::new(fixture("empty_v118.dta")),
            FileOptions {
                max_buffer_bytes: 0
            }
        ),
        Err(DtaError::InvalidBufferSize)
    ));
}
