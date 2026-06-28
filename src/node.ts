// -----------------------------------------------------------
// DtaFile — public API for reading .dta files
//
// Combines header parsing, data reading, strL resolution,
// and value label parsing into a single high-level class.
//
// Usage:
//   const file = await DtaFile.open('auto.dta');
//   console.log(file.nobs, file.nvar);
//   const rows = await file.read_rows(0, 100);
//   file.close();
// -----------------------------------------------------------

import * as fs from 'fs';
import { parse_metadata } from './header';
import {
    parse_legacy_metadata,
    legacy_metadata_buffer_size,
} from './legacy-header';
import {
    read_rows_from_data_buffer,
    read_columns_from_data_buffer,
} from './data-reader';
import {
    build_gso_index,
    decode_gso_entry,
    read_strl_pointer,
    type GsoEntry,
} from './strl-reader';
import { parse_value_labels } from './value-labels';
import type {
    DtaMetadata,
    LegacyFormatVersion,
    VariableInfo,
    Row,
    RowCell,
} from './types';
import { is_legacy_format } from './types';

// -----------------------------------------------------------
// Constants
// -----------------------------------------------------------
const INITIAL_METADATA_READ_SIZE = 64 * 1024;
const MAX_READ_RETRIES = 2;
const DATA_TAG_LENGTH = '<data>'.length;

// Default rows per chunk for the cancellable read path. Bounds the
// synchronous work between event-loop yields so an abort posted while
// a large column is being read can be observed promptly.
const DEFAULT_CHUNK_ROWS = 65536;

/** Options for {@link DtaFile.read_rows}. */
export interface ReadRowsOptions {
    /**
     * When provided, the read is performed in chunks that yield to the
     * event loop between them, and is abandoned with an `AbortError` as
     * soon as the signal fires. Without a signal, the read is a single
     * synchronous pass (the original fast path).
     */
    signal?: AbortSignal;
    /** Rows per chunk on the cancellable path (default 65536). */
    chunk_rows?: number;
}

/** Options for {@link DtaFile.read_columns}. */
export interface ReadColumnsOptions {
    /**
     * When provided, aborting the signal rejects with an `AbortError`
     * between observation chunks.
     */
    signal?: AbortSignal;
    /** Rows per chunk (default 65536). */
    chunk_rows?: number;
}

function throw_if_aborted(signal: AbortSignal): void {
    if (signal.aborted) {
        throw new DOMException(
            'The read was aborted', 'AbortError'
        );
    }
}

function yield_to_event_loop(): Promise<void> {
    return new Promise(resolve => setImmediate(resolve));
}

function normalise_chunk_rows(
    requested_chunk_rows: number | undefined
): number {
    return typeof requested_chunk_rows === 'number'
        && Number.isInteger(requested_chunk_rows)
        && requested_chunk_rows >= 1
        ? requested_chunk_rows
        : DEFAULT_CHUNK_ROWS;
}

function normalise_column_indices(
    col_indices: number[],
    nvar: number
): number[] {
    const the_seen = new Set<number>();
    const the_columns: number[] = [];

    for (const my_col of col_indices) {
        if (!Number.isInteger(my_col)) {
            throw new Error(
                `Column index ${my_col} must be an integer`
            );
        }
        if (my_col < 0 || my_col >= nvar) {
            throw new Error(
                `Column index ${my_col} is out of bounds ` +
                `for ${nvar} columns`
            );
        }
        if (!the_seen.has(my_col)) {
            the_seen.add(my_col);
            the_columns.push(my_col);
        }
    }

    return the_columns;
}

// -----------------------------------------------------------
// DtaFile class
// -----------------------------------------------------------

export class DtaFile {
    private _fd: number | null;
    private readonly _metadata: DtaMetadata;
    // strL (GSO) state, populated lazily by `_ensure_gso()` the first
    // time an strL cell is actually resolved. Files without strL columns,
    // and reads that never touch an strL column, never read or retain the
    // section. Once loaded, the section bytes stay resident so each cell
    // resolves with an in-memory slice + decode rather than a per-cell
    // disk read. `_gso_base` is the section's file offset, used to map an
    // entry's absolute offset into `_gso_section`.
    private _gso_index: Map<string, GsoEntry>;
    private _gso_section: Uint8Array | null;
    private _gso_base: number;
    private _gso_loaded: boolean;
    private _value_label_tables: Map<
        string,
        Map<number, string>
    >;
    private _closed: boolean;

    // Precomputed: column indices of strL variables
    private readonly _strl_col_indices: number[];
    // Same set, for O(1) membership tests in per-column reads
    private readonly _strl_col_set: ReadonlySet<number>;

    private constructor(
        fd: number,
        metadata: DtaMetadata,
        value_label_tables: Map<
            string,
            Map<number, string>
        >
    ) {
        this._fd = fd;
        this._metadata = metadata;
        this._gso_index = new Map();
        this._gso_section = null;
        this._gso_base = 0;
        this._gso_loaded = false;
        this._value_label_tables = value_label_tables;
        this._closed = false;

        // Pre-scan for strL column indices
        const the_indices: number[] = [];
        for (
            let i = 0;
            i < metadata.variables.length;
            i++
        ) {
            if (metadata.variables[i].type === 'strL') {
                the_indices.push(i);
            }
        }
        this._strl_col_indices = the_indices;
        this._strl_col_set = new Set(the_indices);
    }

    /**
     * Open a .dta file and parse all metadata.
     *
     * Keeps the file descriptor open for fd-backed random
     * access. Only metadata and sidecar sections are loaded
     * into memory; observation rows are read on demand.
     */
    static async open(file_path: string): Promise<DtaFile> {
        const my_fd = fs.openSync(file_path, 'r');

        try {
            const my_file_size =
                fs.fstatSync(my_fd).size;
            const my_metadata = detect_and_parse_metadata(
                my_fd, my_file_size
            );

            const my_labels = read_value_labels(
                my_fd, my_metadata
            );

            return new DtaFile(
                my_fd,
                my_metadata,
                my_labels
            );
        } catch (my_err) {
            fs.closeSync(my_fd);
            throw my_err;
        }
    }

    // -------------------------------------------------------
    // Public accessors
    // -------------------------------------------------------

    /** Number of observations (rows). */
    get nobs(): number {
        return this._metadata.nobs;
    }

    /** Number of variables (columns). */
    get nvar(): number {
        return this._metadata.nvar;
    }

    /** Variable metadata array. */
    get variables(): VariableInfo[] {
        return this._metadata.variables;
    }

    /** Dataset label string. */
    get dataset_label(): string {
        return this._metadata.dataset_label;
    }

    /** Value label tables (table_name -> value -> label). */
    get value_label_tables(): Map<
        string,
        Map<number, string>
    > {
        return this._value_label_tables;
    }

    // -------------------------------------------------------
    // Data reading
    // -------------------------------------------------------

    /**
     * Read observation rows, resolving strL pointers.
     *
     * @param start - First row index (0-based)
     * @param count - Number of rows to read
     * @param col_start - First column (inclusive, optional)
     * @param col_end - Last column (exclusive, optional)
     * @param options - Cancellation options (see {@link ReadRowsOptions}).
     *   When `options.signal` is provided, the read is chunked and
     *   yields between chunks so the abort can be observed; it rejects
     *   with an `AbortError` if the signal fires. Without a signal the
     *   read is a single synchronous pass identical to prior behavior.
     */
    async read_rows(
        start: number,
        count: number,
        col_start?: number,
        col_end?: number,
        options?: ReadRowsOptions
    ): Promise<Row[]> {
        if (this._closed || this._fd === null) return [];

        const my_actual_count = Math.min(
            count,
            this._metadata.nobs - start
        );
        if (
            this._metadata.nobs === 0
            || start >= this._metadata.nobs
            || my_actual_count <= 0
        ) {
            return [];
        }

        // Fast path: no signal → single synchronous read,
        // byte-identical to the original implementation.
        if (!options?.signal) {
            return this._read_rows_range(
                start, my_actual_count, col_start, col_end
            );
        }

        // Cancellable path: read in chunks, yielding to the event
        // loop between them so a queued abort is observed promptly.
        const my_signal = options.signal;
        // Use the default for any non-positive-integer chunk size (0,
        // negative, NaN, fractional); each would stall or corrupt the
        // chunk loop.
        const my_chunk_rows = normalise_chunk_rows(
            options.chunk_rows
        );
        throw_if_aborted(my_signal);

        const the_rows: Row[] = [];
        let my_read = 0;
        while (my_read < my_actual_count) {
            // Yield before every chunk after the first, then check the
            // signal, so an abort delivered during the yield is caught
            // before the next (potentially long) synchronous read.
            if (my_read > 0) {
                await yield_to_event_loop();
                throw_if_aborted(my_signal);
            }
            // A close during the yield must not surface a partial
            // column; matching the "closed returns []" contract keeps
            // a truncated read from masquerading as success.
            if (this._closed || this._fd === null) return [];

            const my_chunk_count = Math.min(
                my_chunk_rows, my_actual_count - my_read
            );
            const my_chunk = this._read_rows_range(
                start + my_read,
                my_chunk_count,
                col_start,
                col_end
            );
            for (const my_row of my_chunk) {
                the_rows.push(my_row);
            }
            my_read += my_chunk_count;
        }

        throw_if_aborted(my_signal);
        return the_rows;
    }

    /**
     * Read multiple columns in a single pass over the data section,
     * parsing only the requested columns.
     *
     * @param col_indices - Distinct or repeated 0-based column indices.
     *   Repeats are deduplicated, and the returned map is keyed by the
     *   requested absolute column indices.
     * @param options - Chunking and cancellation options.
     * @returns A map keyed by the requested distinct column indices, each
     *   mapping to that column's value for every observation. A closed
     *   file (at entry or closed mid-read) yields an empty map with NO
     *   keys — deliberately distinct from the keyed-but-empty map returned
     *   for an empty request or a zero-row dataset. Callers must treat a
     *   missing key as "not read" (e.g. fall back to reading that column
     *   directly) rather than assuming every requested key is present.
     */
    async read_columns(
        col_indices: number[],
        options?: ReadColumnsOptions
    ): Promise<Map<number, RowCell[]>> {
        // Closed/unopened: empty map with no keys. Intentionally distinct
        // from the keyed-but-empty map returned below for a zero-row
        // dataset — a missing key signals "not read" so callers can fall
        // back, instead of mistaking absence for a genuinely empty column.
        if (this._closed || this._fd === null) {
            return new Map();
        }

        const the_columns = normalise_column_indices(
            col_indices,
            this._metadata.nvar
        );
        const the_values = new Map<number, RowCell[]>();
        for (const my_col of the_columns) {
            the_values.set(my_col, []);
        }

        if (
            the_columns.length === 0
            || this._metadata.nobs === 0
        ) {
            return the_values;
        }

        const my_signal = options?.signal;
        if (my_signal) {
            throw_if_aborted(my_signal);
        }

        const my_chunk_rows = normalise_chunk_rows(
            options?.chunk_rows
        );
        let my_read = 0;
        while (my_read < this._metadata.nobs) {
            if (my_read > 0) {
                await yield_to_event_loop();
                if (my_signal) {
                    throw_if_aborted(my_signal);
                }
            }
            // A close during the yield must not surface a partial result;
            // returning a keyless map keeps a truncated read from
            // masquerading as complete data, matching read_rows' "closed
            // returns []" contract (see the @returns note above).
            if (this._closed || this._fd === null) {
                return new Map();
            }

            const my_chunk_count = Math.min(
                my_chunk_rows,
                this._metadata.nobs - my_read
            );
            const my_chunk_start = my_read;
            const my_data_buffer = read_data_rows(
                this._fd,
                this._metadata,
                my_chunk_start,
                my_chunk_count
            );

            // One pass decodes every requested column straight into its
            // flat array (strL cells land as placeholders)...
            read_columns_from_data_buffer(
                my_data_buffer,
                this._metadata,
                my_chunk_count,
                the_columns,
                the_values
            );

            // ...then resolve the placeholders for any strL columns.
            for (const my_col of the_columns) {
                if (this._strl_col_set.has(my_col)) {
                    this._resolve_strl_column(
                        the_values.get(my_col)!,
                        my_chunk_start,
                        my_data_buffer,
                        my_col,
                        my_chunk_count
                    );
                }
            }

            my_read += my_chunk_count;
        }

        if (my_signal) {
            throw_if_aborted(my_signal);
        }
        return the_values;
    }

    /**
     * Read a contiguous row range in a single synchronous pass and
     * resolve any strL columns in range. Shared by both the fast path
     * and each chunk of the cancellable path. Callers must ensure the
     * file is open (`_fd !== null`).
     */
    private _read_rows_range(
        start: number,
        count: number,
        col_start?: number,
        col_end?: number
    ): Row[] {
        const my_data_buffer = read_data_rows(
            this._fd!,
            this._metadata,
            start,
            count
        );
        const the_rows = read_rows_from_data_buffer(
            my_data_buffer,
            this._metadata,
            start,
            count,
            col_start,
            col_end
        );

        // Resolve strL placeholders if any strL columns
        // fall within the requested column range
        if (this._strl_col_indices.length > 0) {
            this._resolve_strls(
                the_rows,
                my_data_buffer,
                col_start ?? 0,
                col_end ?? this._metadata.nvar
            );
        }

        return the_rows;
    }

    // -------------------------------------------------------
    // Resource management
    // -------------------------------------------------------

    /**
     * Release the open file handle and internal caches.
     * After close, read_rows returns empty arrays.
     */
    close(): void {
        if (this._fd !== null) {
            fs.closeSync(this._fd);
            this._fd = null;
        }
        this._closed = true;
        this._gso_index = new Map();
        this._gso_section = null;
        this._value_label_tables = new Map();
    }

    // -------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------

    /**
     * Lazily read and index the strL (GSO) section on first use. Called
     * only from the strL resolution paths, so a file whose strL columns
     * are never read pays nothing: the section is neither read nor
     * retained. The whole section is read once (a single sequential
     * read) and kept resident so subsequent cells resolve from memory.
     */
    private _ensure_gso(): void {
        if (this._gso_loaded) return;

        if (
            this._fd === null
            || this._strl_col_indices.length === 0
        ) {
            // Nothing to load; this outcome is stable across retries.
            this._gso_loaded = true;
            return;
        }

        const my_start =
            this._metadata.section_offsets.strls;
        const my_length =
            this._metadata.section_offsets.value_labels
            - my_start;
        if (my_length <= 0) {
            this._gso_loaded = true;
            return;
        }

        // Mark loaded only after the read and index succeed: if either
        // throws (truncated file, >32-bit obs count) the error must
        // propagate and a later retry must be free to try again, rather
        // than be short-circuited into resolving strL cells to ''.
        const my_buffer = read_range(
            this._fd, my_start, my_length
        );
        this._gso_index = build_gso_index(
            my_buffer, this._metadata, my_start
        );
        this._gso_section = new Uint8Array(my_buffer);
        this._gso_base = my_start;
        this._gso_loaded = true;
    }

    /**
     * Post-process rows to resolve strL placeholders.
     *
     * For each strL column in the requested range, decode the pointer
     * from the row buffer and resolve the GSO payload from the
     * in-memory strL section (no per-cell disk reads).
     */
    private _resolve_strls(
        the_rows: Row[],
        data_buffer: ArrayBuffer,
        col_start: number,
        col_end: number
    ): void {
        if (this._fd === null) return;

        // Only touch the GSO section if a strL column actually falls in
        // the requested range — reading non-strL columns of a file that
        // merely contains strLs must not load it.
        const my_has_strl_in_range =
            this._strl_col_indices.some(
                my_col =>
                    my_col >= col_start && my_col < col_end
            );
        if (!my_has_strl_in_range) return;
        this._ensure_gso();

        const my_view = new DataView(data_buffer);

        for (const my_abs_col of this._strl_col_indices) {
            // Skip columns outside the requested range
            if (
                my_abs_col < col_start
                || my_abs_col >= col_end
            ) {
                continue;
            }

            // Column index within the row array
            const my_row_col = my_abs_col - col_start;
            const my_var = this._metadata
                .variables[my_abs_col];

            for (let i = 0; i < the_rows.length; i++) {
                const my_pointer_offset =
                    i * this._metadata.obs_length
                    + my_var.byte_offset;
                the_rows[i][my_row_col] =
                    this._resolve_strl_at(
                        my_view, my_pointer_offset
                    );
            }
        }
    }

    /**
     * Resolve the strL placeholders of one column, in place, into a
     * flat column array. Used by the single-pass read_columns path,
     * where `read_columns_from_data_buffer` first fills the column
     * with placeholders. `base_index` is where this chunk's values
     * begin in `col_values`.
     */
    private _resolve_strl_column(
        col_values: RowCell[],
        base_index: number,
        data_buffer: ArrayBuffer,
        abs_col: number,
        count: number
    ): void {
        this._ensure_gso();
        const my_view = new DataView(data_buffer);
        const my_var = this._metadata.variables[abs_col];
        for (let i = 0; i < count; i++) {
            const my_pointer_offset =
                i * this._metadata.obs_length
                + my_var.byte_offset;
            col_values[base_index + i] =
                this._resolve_strl_at(
                    my_view, my_pointer_offset
                );
        }
    }

    /**
     * Resolve a single strL pointer at `pointer_offset` within the
     * chunk's data buffer to its string value, reading the GSO payload
     * from the in-memory strL section. Returns '' for a null pointer
     * or an unresolvable/absent entry.
     */
    private _resolve_strl_at(
        view: DataView,
        pointer_offset: number
    ): string {
        const my_pointer = read_strl_pointer(
            view, this._metadata, pointer_offset
        );
        if (!my_pointer) return '';

        const my_entry = this._gso_index.get(
            my_pointer.v + ':' + my_pointer.o
        );
        if (!my_entry || this._gso_section === null) {
            return '';
        }

        return decode_gso_entry(this._gso_section, {
            ...my_entry,
            content_offset:
                my_entry.content_offset - this._gso_base,
        });
    }
}

// -----------------------------------------------------------
// Format detection and metadata dispatch
// -----------------------------------------------------------

// Legacy format version bytes
const LEGACY_VERSION_BYTES = new Set([113, 114, 115]);

// Minimum .dta file must have at least the version byte
const MIN_LEGACY_HEADER = 109;

function detect_and_parse_metadata(
    fd: number,
    file_size: number
): DtaMetadata {
    // Peek at the first byte to determine format family
    if (file_size < 1) {
        throw new Error(
            'Not a valid .dta file: file is empty'
        );
    }
    const my_probe = read_range(fd, 0, 1);
    const my_first_byte = new Uint8Array(my_probe)[0];

    if (LEGACY_VERSION_BYTES.has(my_first_byte)) {
        return read_legacy_metadata(fd, file_size);
    }

    return read_modern_metadata(fd, file_size);
}

function read_legacy_metadata(
    fd: number,
    file_size: number
): DtaMetadata {
    if (file_size < MIN_LEGACY_HEADER) {
        throw new Error(
            'Not a valid .dta file: too small for ' +
            'legacy header'
        );
    }

    // Read the fixed header to get nvar and format version
    const my_header = read_range(
        fd, 0, Math.min(file_size, MIN_LEGACY_HEADER)
    );
    const my_header_bytes = new Uint8Array(my_header);
    const my_version =
        my_header_bytes[0] as LegacyFormatVersion;
    const my_byte_order_code = my_header_bytes[1];
    const my_little_endian = my_byte_order_code === 2;
    const my_header_view = new DataView(my_header);
    const my_nvar = my_header_view.getUint16(
        4, my_little_endian
    );

    // Compute exact buffer size needed for all metadata
    const my_needed = legacy_metadata_buffer_size(
        my_nvar, my_version
    );
    const my_read_size = Math.min(file_size, my_needed);
    const my_buffer = read_range(fd, 0, my_read_size);

    return parse_legacy_metadata(my_buffer, file_size);
}

function read_modern_metadata(
    fd: number,
    file_size: number
): DtaMetadata {
    let my_read_size = Math.min(
        file_size,
        INITIAL_METADATA_READ_SIZE
    );
    let my_last_error: unknown = null;

    while (my_read_size <= file_size) {
        const my_buffer = read_range(
            fd,
            0,
            my_read_size
        );

        try {
            return parse_metadata(my_buffer);
        } catch (my_err) {
            my_last_error = my_err;
            if (
                my_err instanceof Error
                && my_err.message.includes(
                    'unrecognized format signature'
                )
            ) {
                throw new Error(
                    'Unsupported .dta format: only ' +
                    'Stata 8+ files (formats 113-115 ' +
                    'and 117-119) are supported'
                );
            }
            if (my_read_size === file_size) {
                break;
            }
            my_read_size = Math.min(
                file_size,
                my_read_size * 2
            );
        }
    }

    throw my_last_error;
}

function read_value_labels(
    fd: number,
    metadata: DtaMetadata
): Map<string, Map<number, string>> {
    const my_section_start =
        metadata.section_offsets.value_labels;
    const my_section_length =
        metadata.section_offsets.end_of_file
        - metadata.section_offsets.value_labels;
    if (my_section_length <= 0) {
        return new Map();
    }

    const my_buffer = read_range(
        fd,
        my_section_start,
        my_section_length
    );
    return parse_value_labels(
        my_buffer,
        metadata,
        my_section_start
    );
}

function read_data_rows(
    fd: number,
    metadata: DtaMetadata,
    start: number,
    count: number
): ArrayBuffer {
    const my_tag_length = is_legacy_format(
        metadata.format_version
    ) ? 0 : DATA_TAG_LENGTH;
    const my_offset =
        metadata.section_offsets.data
        + my_tag_length
        + start * metadata.obs_length;
    const my_length = count * metadata.obs_length;

    return read_range(fd, my_offset, my_length);
}

function read_range(
    fd: number,
    offset: number,
    length: number
): ArrayBuffer {
    const my_buffer = Buffer.allocUnsafe(length);
    let my_total_read = 0;
    let my_attempts = 0;

    while (my_total_read < length) {
        const my_bytes_read = fs.readSync(
            fd,
            my_buffer,
            my_total_read,
            length - my_total_read,
            offset + my_total_read
        );

        if (my_bytes_read === 0) {
            my_attempts++;
            if (my_attempts > MAX_READ_RETRIES) {
                throw new Error(
                    `Unexpected EOF while reading ${length} bytes ` +
                    `at offset ${offset}`
                );
            }
            continue;
        }

        my_total_read += my_bytes_read;
    }

    return my_buffer.buffer.slice(
        my_buffer.byteOffset,
        my_buffer.byteOffset + my_total_read
    ) as ArrayBuffer;
}

// -----------------------------------------------------------
// Barrel exports
// -----------------------------------------------------------

export type {
    VariableInfo,
    Row,
    RowCell,
    MissingType,
    MissingValue,
    DtaMetadata,
    DtaType,
    FormatVersion,
    LegacyFormatVersion,
    SectionOffsets,
} from './types';
export { is_legacy_format } from './types';
export { apply_display_format } from './display-format';
export {
    classify_missing_value,
    classify_raw_float_missing,
    classify_raw_double_missing_at,
    is_missing_value,
    is_missing_value_object,
    make_missing_value,
    missing_type_to_label_key,
    STATA_MISSING_B,
} from './missing-values';
