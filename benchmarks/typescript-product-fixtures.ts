import { parse_metadata } from '../typescript/dta-parser/src/header';
import { build_gso_index } from '../typescript/dta-parser/src/strl-reader';
import type { DtaMetadata } from '../typescript/dta-parser/src/types';

const MAP_TAG_LENGTH = '<map>'.length;
const DATA_TAG_LENGTH = '<data>'.length;
const DATA_CLOSE_TAG = '</data>';
const STRLS_TAG_LENGTH = '<strls>'.length;
const STRLS_CLOSE_TAG = '</strls>';
const VALUE_LABELS_TAG_LENGTH = '<value_labels>'.length;
const VALUE_LABELS_CLOSE_TAG = '</value_labels>';
const LBL_OPEN_TAG = '<lbl>';
const LBL_CLOSE_TAG = '</lbl>';
const MODERN_LABEL_NAME_WIDTH = 129;
const LABEL_PADDING_BYTES = 3;
const GSO_FIXED_BYTES = 3 + 4 + 8 + 1 + 4;
const ASCII_ENCODER = new TextEncoder();

function assert_product_fixture_format(metadata: DtaMetadata): void {
    if (
        metadata.format_version !== 118
        && metadata.format_version !== 119
    ) {
        throw new Error(
            'Product benchmark fixtures require DTA format 118 or 119'
        );
    }
}

function assert_positive_integer(value: number, name: string): void {
    if (!Number.isSafeInteger(value) || value < 1) {
        throw new RangeError(`${name} must be a positive integer`);
    }
}

function ascii_matches_at(
    bytes: Uint8Array,
    offset: number,
    expected: string
): boolean {
    if (offset < 0 || offset + expected.length > bytes.length) {
        return false;
    }
    for (let i = 0; i < expected.length; i++) {
        if (bytes[offset + i] !== expected.charCodeAt(i)) {
            return false;
        }
    }
    return true;
}

function assert_ascii_at(
    bytes: Uint8Array,
    offset: number,
    expected: string
): void {
    if (!ascii_matches_at(bytes, offset, expected)) {
        throw new Error(`Expected ${expected} at byte offset ${offset}`);
    }
}

function find_ascii(
    bytes: Uint8Array,
    expected: string,
    end: number = bytes.length
): number {
    const my_limit = Math.min(end, bytes.length) - expected.length;
    for (let i = 0; i <= my_limit; i++) {
        if (ascii_matches_at(bytes, i, expected)) return i;
    }
    return -1;
}

function checked_output_length(input_length: number, delta: number): number {
    const my_length = input_length + delta;
    if (!Number.isSafeInteger(my_length) || my_length < 0) {
        throw new RangeError('Generated benchmark fixture is too large');
    }
    return my_length;
}

function shift_map_offsets(
    bytes: Uint8Array,
    metadata: DtaMetadata,
    first_shifted_entry: number,
    delta: number
): void {
    if (delta === 0) return;

    const my_view = new DataView(bytes.buffer);
    const my_little_endian = metadata.byte_order === 'LSF';
    const my_map_start = metadata.section_offsets.map + MAP_TAG_LENGTH;
    for (let i = first_shifted_entry; i < 14; i++) {
        const my_offset = my_map_start + i * 8;
        const my_old_value = my_view.getBigUint64(
            my_offset, my_little_endian
        );
        const my_new_value = my_old_value + BigInt(delta);
        if (my_new_value < 0n) {
            throw new RangeError('Generated section offset is negative');
        }
        my_view.setBigUint64(
            my_offset, my_new_value, my_little_endian
        );
    }
}

function write_nobs(
    bytes: Uint8Array,
    metadata: DtaMetadata,
    target_rows: number
): void {
    const my_n_tag = find_ascii(
        bytes, '<N>', metadata.section_offsets.map
    );
    if (my_n_tag === -1) {
        throw new Error('Missing <N> tag in benchmark fixture');
    }

    const my_view = new DataView(bytes.buffer);
    const my_little_endian = metadata.byte_order === 'LSF';
    const my_value_offset = my_n_tag + '<N>'.length;
    if (metadata.format_version === 118) {
        if (target_rows > 0xffff_ffff) {
            throw new RangeError('DTA 118 observation count exceeds uint32');
        }
        my_view.setUint32(
            my_value_offset, target_rows, my_little_endian
        );
    } else {
        my_view.setBigUint64(
            my_value_offset, BigInt(target_rows), my_little_endian
        );
    }
}

/** Copy a Node/Bun byte view into an exact, standalone ArrayBuffer. */
export function exact_array_buffer(bytes: Uint8Array): ArrayBuffer {
    const my_copy = new Uint8Array(bytes.byteLength);
    my_copy.set(bytes);
    return my_copy.buffer;
}

/**
 * Repeat the observations in a modern fixture until it contains target_rows.
 * Metadata and all post-data section offsets are updated in the returned file.
 */
export function scale_modern_rows(
    buffer: ArrayBuffer,
    target_rows: number
): ArrayBuffer {
    assert_positive_integer(target_rows, 'target_rows');
    const my_metadata = parse_metadata(buffer);
    assert_product_fixture_format(my_metadata);
    if (my_metadata.nobs < 1 || my_metadata.obs_length < 1) {
        throw new Error('Source fixture must contain at least one observation');
    }

    const my_source = new Uint8Array(buffer);
    const my_data_start =
        my_metadata.section_offsets.data + DATA_TAG_LENGTH;
    const my_source_data_length =
        my_metadata.nobs * my_metadata.obs_length;
    const my_source_data_end = my_data_start + my_source_data_length;
    assert_ascii_at(my_source, my_source_data_end, DATA_CLOSE_TAG);

    const my_target_data_length = target_rows * my_metadata.obs_length;
    if (!Number.isSafeInteger(my_target_data_length)) {
        throw new RangeError('Generated data section is too large');
    }
    const my_delta = my_target_data_length - my_source_data_length;
    const my_output = new Uint8Array(
        checked_output_length(my_source.length, my_delta)
    );
    my_output.set(my_source.subarray(0, my_data_start), 0);

    let my_written = 0;
    while (my_written < my_target_data_length) {
        const my_copy_length = Math.min(
            my_source_data_length,
            my_target_data_length - my_written
        );
        my_output.set(
            my_source.subarray(
                my_data_start,
                my_data_start + my_copy_length
            ),
            my_data_start + my_written
        );
        my_written += my_copy_length;
    }
    my_output.set(
        my_source.subarray(my_source_data_end),
        my_data_start + my_target_data_length
    );

    write_nobs(my_output, my_metadata, target_rows);
    shift_map_offsets(my_output, my_metadata, 10, my_delta);
    return my_output.buffer;
}

interface LabelBlock {
    offset: number;
    length: number;
}

function modern_label_blocks(
    bytes: Uint8Array,
    metadata: DtaMetadata,
    entries_start: number,
    entries_end: number
): LabelBlock[] {
    const my_view = new DataView(bytes.buffer);
    const my_little_endian = metadata.byte_order === 'LSF';
    const the_blocks: LabelBlock[] = [];
    let my_position = entries_start;

    while (my_position < entries_end) {
        assert_ascii_at(bytes, my_position, LBL_OPEN_TAG);
        const my_table_length = my_view.getInt32(
            my_position + LBL_OPEN_TAG.length,
            my_little_endian
        );
        if (my_table_length < 0) {
            throw new Error('Negative value-label table length');
        }
        const my_block_length =
            LBL_OPEN_TAG.length
            + 4
            + MODERN_LABEL_NAME_WIDTH
            + LABEL_PADDING_BYTES
            + my_table_length
            + LBL_CLOSE_TAG.length;
        const my_block_end = my_position + my_block_length;
        if (my_block_end > entries_end) {
            throw new Error('Value-label table exceeds section bounds');
        }
        assert_ascii_at(
            bytes,
            my_block_end - LBL_CLOSE_TAG.length,
            LBL_CLOSE_TAG
        );
        the_blocks.push({
            offset: my_position,
            length: my_block_length,
        });
        my_position = my_block_end;
    }

    if (my_position !== entries_end || the_blocks.length === 0) {
        throw new Error('Source fixture has no complete value-label tables');
    }
    return the_blocks;
}

/** Repeat a fixture's value-label tables, assigning unique names to copies. */
export function repeat_modern_value_labels(
    buffer: ArrayBuffer,
    repetitions: number
): ArrayBuffer {
    assert_positive_integer(repetitions, 'repetitions');
    const my_metadata = parse_metadata(buffer);
    assert_product_fixture_format(my_metadata);
    const my_source = new Uint8Array(buffer);
    const my_entries_start =
        my_metadata.section_offsets.value_labels
        + VALUE_LABELS_TAG_LENGTH;
    const my_entries_end =
        my_metadata.section_offsets.stata_data_close
        - VALUE_LABELS_CLOSE_TAG.length;
    assert_ascii_at(
        my_source, my_entries_end, VALUE_LABELS_CLOSE_TAG
    );
    const the_blocks = modern_label_blocks(
        my_source, my_metadata, my_entries_start, my_entries_end
    );
    const my_entries_length = my_entries_end - my_entries_start;
    const my_delta = my_entries_length * (repetitions - 1);
    const my_output = new Uint8Array(
        checked_output_length(my_source.length, my_delta)
    );

    my_output.set(my_source.subarray(0, my_entries_end), 0);
    let my_output_position = my_entries_end;
    for (let my_copy = 1; my_copy < repetitions; my_copy++) {
        for (let my_entry = 0; my_entry < the_blocks.length; my_entry++) {
            const my_block = the_blocks[my_entry];
            my_output.set(
                my_source.subarray(
                    my_block.offset,
                    my_block.offset + my_block.length
                ),
                my_output_position
            );
            const my_name_start =
                my_output_position + LBL_OPEN_TAG.length + 4;
            my_output.fill(
                0,
                my_name_start,
                my_name_start + MODERN_LABEL_NAME_WIDTH
            );
            const my_name = ASCII_ENCODER.encode(
                `bench_${my_copy}_${my_entry}`
            );
            if (my_name.length >= MODERN_LABEL_NAME_WIDTH) {
                throw new Error('Generated value-label name is too long');
            }
            my_output.set(my_name, my_name_start);
            my_output_position += my_block.length;
        }
    }
    my_output.set(
        my_source.subarray(my_entries_end),
        my_output_position
    );

    shift_map_offsets(my_output, my_metadata, 12, my_delta);
    return my_output.buffer;
}

/**
 * Append deterministic ASCII GSO records until the strLs section contains
 * target_entries. The source must have enough observations and strL columns
 * to provide unique (variable, observation) keys.
 */
export function expand_modern_strls(
    buffer: ArrayBuffer,
    target_entries: number,
    payload_bytes: number
): ArrayBuffer {
    assert_positive_integer(target_entries, 'target_entries');
    assert_positive_integer(payload_bytes, 'payload_bytes');
    const my_metadata = parse_metadata(buffer);
    assert_product_fixture_format(my_metadata);
    const my_source = new Uint8Array(buffer);
    const my_entries_start =
        my_metadata.section_offsets.strls + STRLS_TAG_LENGTH;
    const my_entries_end =
        my_metadata.section_offsets.value_labels - STRLS_CLOSE_TAG.length;
    assert_ascii_at(my_source, my_entries_end, STRLS_CLOSE_TAG);
    if (my_entries_end < my_entries_start) {
        throw new Error('Invalid strLs section bounds');
    }

    const my_index = build_gso_index(buffer, my_metadata);
    if (target_entries < my_index.size) {
        throw new RangeError(
            'target_entries cannot be smaller than the source GSO index'
        );
    }
    const the_strl_variables = my_metadata.variables
        .map((my_variable, my_index) => ({
            index: my_index + 1,
            is_strl: my_variable.type === 'strL',
        }))
        .filter(my_variable => my_variable.is_strl)
        .map(my_variable => my_variable.index);
    if (the_strl_variables.length === 0) {
        throw new Error('Source fixture has no strL variables');
    }
    if (
        target_entries
        > the_strl_variables.length * my_metadata.nobs
    ) {
        throw new RangeError(
            'target_entries exceeds available unique strL keys'
        );
    }

    const my_new_entry_count = target_entries - my_index.size;
    const my_record_length = GSO_FIXED_BYTES + payload_bytes;
    const my_delta = my_new_entry_count * my_record_length;
    const my_output = new Uint8Array(
        checked_output_length(my_source.length, my_delta)
    );
    my_output.set(my_source.subarray(0, my_entries_end), 0);
    const my_view = new DataView(my_output.buffer);
    const my_little_endian = my_metadata.byte_order === 'LSF';
    let my_output_position = my_entries_end;
    let my_generated = 0;

    for (const my_variable of the_strl_variables) {
        for (
            let my_observation = 1;
            my_observation <= my_metadata.nobs;
            my_observation++
        ) {
            if (my_generated === my_new_entry_count) break;
            const my_key = `${my_variable}:${my_observation}`;
            if (my_index.has(my_key)) continue;

            my_output.set(
                [0x47, 0x53, 0x4f],
                my_output_position
            );
            my_output_position += 3;
            my_view.setUint32(
                my_output_position,
                my_variable,
                my_little_endian
            );
            my_output_position += 4;
            my_view.setBigUint64(
                my_output_position,
                BigInt(my_observation),
                my_little_endian
            );
            my_output_position += 8;
            my_output[my_output_position] = 130;
            my_output_position += 1;
            my_view.setUint32(
                my_output_position,
                payload_bytes,
                my_little_endian
            );
            my_output_position += 4;

            const my_content_start = my_output_position;
            my_output.fill(
                0x78,
                my_content_start,
                my_content_start + payload_bytes - 1
            );
            const my_prefix = ASCII_ENCODER.encode(
                `bench-${my_variable}-${my_observation}`
            );
            my_output.set(
                my_prefix.subarray(0, payload_bytes - 1),
                my_content_start
            );
            my_output[my_content_start + payload_bytes - 1] = 0;
            my_output_position += payload_bytes;
            my_generated++;
        }
        if (my_generated === my_new_entry_count) break;
    }
    if (my_generated !== my_new_entry_count) {
        throw new Error('Could not generate the requested GSO entries');
    }

    my_output.set(
        my_source.subarray(my_entries_end),
        my_output_position
    );
    shift_map_offsets(my_output, my_metadata, 11, my_delta);
    return my_output.buffer;
}

/** Return stable, unique row indices in intentionally non-sequential order. */
export function deterministic_sparse_rows(
    row_count: number,
    count: number,
    seed: number = 0x5eed_1234
): number[] {
    assert_positive_integer(row_count, 'row_count');
    assert_positive_integer(count, 'count');
    if (count > row_count) {
        throw new RangeError('count cannot exceed row_count');
    }

    const the_rows: number[] = [];
    const the_seen = new Set<number>();
    let my_state = seed >>> 0;
    while (the_rows.length < count) {
        my_state = (
            Math.imul(my_state, 1_664_525) + 1_013_904_223
        ) >>> 0;
        const my_row = my_state % row_count;
        if (!the_seen.has(my_row)) {
            the_seen.add(my_row);
            the_rows.push(my_row);
        }
    }
    return the_rows;
}
