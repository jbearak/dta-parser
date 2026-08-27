import {
    mkdtempSync,
    readFileSync,
    rmSync,
    writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

import { read_rows_from_buffer } from '../typescript/dta-parser/src/data-reader';
import { parse_metadata } from '../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../typescript/dta-parser/src/legacy-header';
import { DtaFile } from '../typescript/dta-parser/src/node';
import {
    build_gso_index,
    resolve_strl,
} from '../typescript/dta-parser/src/strl-reader';
import type { DtaMetadata } from '../typescript/dta-parser/src/types';
import { parse_value_labels } from '../typescript/dta-parser/src/value-labels';
import { parse_benchmark_iterations } from './config';
import {
    deterministic_sparse_rows,
    exact_array_buffer,
    expand_modern_strls,
    repeat_modern_value_labels,
    scale_modern_rows,
} from './typescript-product-fixtures';

const fixture_dir = path.resolve(import.meta.dir, '../tests/fixtures/dta');
const iterations = parse_benchmark_iterations(
    process.env.DTA_BENCH_ITERATIONS
);
const SIGHT_ROWS = 100_000;
const SIGHT_VIEWPORT_ROWS = 200;
const TABLE_VIEWER_WIDE_ROWS = 1_000;
const TABLE_VIEWER_PAGE_ROWS = 100;
const TABLE_VIEWER_SCAN_CHUNK_ROWS = 128;
const LARGE_LABEL_REPETITIONS = 2_048;
const LARGE_STRL_ENTRIES = 4_096;
const LARGE_STRL_PAYLOAD_BYTES = 256;
const DATA_TAG_LENGTH = '<data>'.length;
let result_sink = 0;

function consume_result(result: unknown): void {
    if (Array.isArray(result)) {
        result_sink = (result_sink + result.length) | 0;
    } else if (result instanceof Map) {
        result_sink = (result_sink + result.size) | 0;
    } else if (result instanceof Uint8Array) {
        result_sink = (result_sink + result.byteLength) | 0;
    } else if (typeof result === 'string') {
        result_sink = (result_sink + result.length) | 0;
    } else if (typeof result === 'number') {
        result_sink = (result_sink + result) | 0;
    }
}

async function measure(
    operation: () => unknown | Promise<unknown>
): Promise<number> {
    const my_start = performance.now();
    for (let i = 0; i < iterations; i++) {
        consume_result(await operation());
    }
    return (performance.now() - my_start) / iterations;
}

async function measure_with_setup<T>(
    setup: () => T | Promise<T>,
    operation: (resource: T) => unknown | Promise<unknown>,
    teardown: (resource: T) => void | Promise<void>
): Promise<number> {
    let my_elapsed = 0;
    for (let i = 0; i < iterations; i++) {
        const my_resource = await setup();
        try {
            const my_start = performance.now();
            consume_result(await operation(my_resource));
            my_elapsed += performance.now() - my_start;
        } finally {
            await teardown(my_resource);
        }
    }
    return my_elapsed / iterations;
}

function emit_report(
    case_name: string,
    phase: string,
    input_bytes: number,
    mean: number
): void {
    console.log(
        `${case_name}\t${phase}\t${input_bytes}`
        + `\t${iterations}\t${mean.toFixed(6)}`
    );
}

async function report(
    case_name: string,
    phase: string,
    input_bytes: number,
    operation: () => unknown | Promise<unknown>
): Promise<void> {
    emit_report(
        case_name,
        phase,
        input_bytes,
        await measure(operation)
    );
}

function fixture_buffer(name: string): ArrayBuffer {
    return exact_array_buffer(
        readFileSync(path.join(fixture_dir, name))
    );
}

async function read_indexed_file_rows(
    file: DtaFile,
    row_indices: number[]
): Promise<number> {
    let my_rows_read = 0;
    for (let i = 0; i < row_indices.length;) {
        const my_start = row_indices[i];
        let my_count = 1;
        while (
            i + my_count < row_indices.length
            && row_indices[i + my_count] === my_start + my_count
        ) {
            my_count++;
        }
        my_rows_read += (
            await file.read_rows(my_start, my_count)
        ).length;
        i += my_count;
    }
    return my_rows_read;
}

function read_sparse_buffer_projection(
    buffer: ArrayBuffer,
    metadata: DtaMetadata,
    row_indices: number[],
    column_indices: number[]
): number {
    let my_cells_read = 0;
    for (const my_row of row_indices) {
        for (const my_column of column_indices) {
            const my_rows = read_rows_from_buffer(
                buffer,
                metadata,
                my_row,
                1,
                my_column,
                my_column + 1
            );
            my_cells_read += my_rows[0]?.length ?? 0;
        }
    }
    return my_cells_read;
}

function scan_buffer_column(
    buffer: ArrayBuffer,
    metadata: DtaMetadata,
    column: number
): number {
    let my_rows_read = 0;
    for (
        let my_start = 0;
        my_start < metadata.nobs;
        my_start += TABLE_VIEWER_SCAN_CHUNK_ROWS
    ) {
        const my_count = Math.min(
            TABLE_VIEWER_SCAN_CHUNK_ROWS,
            metadata.nobs - my_start
        );
        my_rows_read += read_rows_from_buffer(
            buffer,
            metadata,
            my_start,
            my_count,
            column,
            column + 1
        ).length;
    }
    return my_rows_read;
}

console.log('case\tphase\tinput_bytes\titerations\tmean_ms');

for (const [my_case_name, my_fixture_name] of [
    ['modern-all-types', 'all_types_v118.dta'],
    ['wide', 'wide_v118.dta'],
    ['strl', 'strl_test_v118.dta'],
    ['legacy', 'all_types_v115.dta'],
] as const) {
    const my_fixture_path = path.join(fixture_dir, my_fixture_name);
    const my_bytes = readFileSync(my_fixture_path);
    const my_array_buffer = exact_array_buffer(my_bytes);
    const my_is_legacy = my_bytes[0] >= 113 && my_bytes[0] <= 115;
    const my_metadata = my_is_legacy
        ? parse_legacy_metadata(my_array_buffer, my_bytes.length)
        : parse_metadata(my_array_buffer);

    await report(
        my_case_name,
        'file-io',
        my_bytes.length,
        () => readFileSync(my_fixture_path)
    );
    await report(
        my_case_name,
        'metadata',
        my_bytes.length,
        () => my_is_legacy
            ? parse_legacy_metadata(my_array_buffer, my_bytes.length)
            : parse_metadata(my_array_buffer)
    );
    await report(
        my_case_name,
        'buffer-full-decode',
        my_bytes.length,
        () => read_rows_from_buffer(
            my_array_buffer,
            my_metadata,
            0,
            my_metadata.nobs
        )
    );

    const my_file = await DtaFile.open(my_fixture_path);
    try {
        await report(
            my_case_name,
            'node-file-projected-window',
            my_bytes.length,
            () => my_file.read_rows(
                1,
                16,
                0,
                Math.min(2, my_metadata.nvar)
            )
        );
    } finally {
        my_file.close();
    }
}

const my_sight_buffer = scale_modern_rows(
    fixture_buffer('auto_v118.dta'),
    SIGHT_ROWS
);
const my_sight_metadata = parse_metadata(my_sight_buffer);
const the_sight_sorted_rows = deterministic_sparse_rows(
    SIGHT_ROWS,
    SIGHT_VIEWPORT_ROWS
);
const my_table_viewer_wide_buffer = scale_modern_rows(
    fixture_buffer('wide_v118.dta'),
    TABLE_VIEWER_WIDE_ROWS
);
const my_table_viewer_wide_metadata = parse_metadata(
    my_table_viewer_wide_buffer
);
const the_table_viewer_sparse_rows = deterministic_sparse_rows(
    TABLE_VIEWER_WIDE_ROWS,
    TABLE_VIEWER_PAGE_ROWS,
    0x7ab1_e001
);
const my_large_labels_buffer = repeat_modern_value_labels(
    fixture_buffer('value_labels_v118.dta'),
    LARGE_LABEL_REPETITIONS
);
const my_large_labels_metadata = parse_metadata(my_large_labels_buffer);
const my_large_strl_buffer = expand_modern_strls(
    scale_modern_rows(
        fixture_buffer('strl_test_v118.dta'),
        LARGE_STRL_ENTRIES
    ),
    LARGE_STRL_ENTRIES,
    LARGE_STRL_PAYLOAD_BYTES
);
const my_large_strl_metadata = parse_metadata(my_large_strl_buffer);
const my_strl_column = my_large_strl_metadata.variables.findIndex(
    my_variable => my_variable.type === 'strL'
);
if (my_strl_column === -1) {
    throw new Error('Generated strL fixture has no strL column');
}
const my_strl_pointer_offset =
    my_large_strl_metadata.section_offsets.data
    + DATA_TAG_LENGTH
    + my_large_strl_metadata.variables[my_strl_column].byte_offset;

const my_temp_dir = mkdtempSync(
    path.join(tmpdir(), 'dta-parser-typescript-benchmark-')
);
const my_sight_path = path.join(my_temp_dir, 'sight-100k.dta');
const my_strl_path = path.join(my_temp_dir, 'sight-large-strl.dta');
writeFileSync(my_sight_path, new Uint8Array(my_sight_buffer));
writeFileSync(my_strl_path, new Uint8Array(my_large_strl_buffer));

try {
    const my_sight_file = await DtaFile.open(my_sight_path);
    try {
        await report(
            'sight',
            'viewport-200-natural-file',
            my_sight_buffer.byteLength,
            () => my_sight_file.read_rows(0, SIGHT_VIEWPORT_ROWS)
        );
        await report(
            'sight',
            'viewport-200-sorted-sparse-file',
            my_sight_buffer.byteLength,
            () => read_indexed_file_rows(
                my_sight_file, the_sight_sorted_rows
            )
        );
        await report(
            'sight',
            'restore-three-sort-filter-columns-file',
            my_sight_buffer.byteLength,
            () => my_sight_file.read_columns([1, 4, 10])
        );
    } finally {
        my_sight_file.close();
    }

    emit_report(
        'sight',
        'first-strl-touch-file',
        my_large_strl_buffer.byteLength,
        await measure_with_setup(
            () => DtaFile.open(my_strl_path),
            my_file => my_file.read_rows(
                0, 1, my_strl_column, my_strl_column + 1
            ),
            my_file => my_file.close()
        )
    );

    await report(
        'table-viewer',
        'page-100-wide-buffer',
        my_table_viewer_wide_buffer.byteLength,
        () => read_rows_from_buffer(
            my_table_viewer_wide_buffer,
            my_table_viewer_wide_metadata,
            0,
            TABLE_VIEWER_PAGE_ROWS
        )
    );
    await report(
        'table-viewer',
        'sparse-indexed-three-columns-buffer',
        my_table_viewer_wide_buffer.byteLength,
        () => read_sparse_buffer_projection(
            my_table_viewer_wide_buffer,
            my_table_viewer_wide_metadata,
            the_table_viewer_sparse_rows,
            [0, 59, 119]
        )
    );
    await report(
        'table-viewer',
        'selected-column-analysis-buffer',
        my_sight_buffer.byteLength,
        () => scan_buffer_column(
            my_sight_buffer, my_sight_metadata, 1
        )
    );
    await report(
        'table-viewer',
        'large-value-labels-buffer',
        my_large_labels_buffer.byteLength,
        () => parse_value_labels(
            my_large_labels_buffer, my_large_labels_metadata
        )
    );
    await report(
        'table-viewer',
        'large-strl-first-touch-buffer',
        my_large_strl_buffer.byteLength,
        () => {
            const my_index = build_gso_index(
                my_large_strl_buffer, my_large_strl_metadata
            );
            return resolve_strl(
                my_large_strl_buffer,
                my_large_strl_metadata,
                my_index,
                my_strl_pointer_offset
            );
        }
    );
} finally {
    rmSync(my_temp_dir, { recursive: true, force: true });
}

// Keep the observable sink live without adding non-TSV benchmark output.
if (result_sink === Number.MIN_SAFE_INTEGER) process.exitCode = 1;
