import { execFileSync } from 'node:child_process';
import {
    closeSync,
    mkdtempSync,
    mkdirSync,
    openSync,
    readFileSync,
    readSync,
    readdirSync,
    rmSync,
    statSync,
    writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DtaFile } from '../../src/node';
import { parse_metadata } from '../../src/header';
import { read_rows_from_data_buffer } from '../../src/data-reader';
import { parse_value_labels } from '../../src/value-labels';
import { is_missing_value_object } from '../../src/missing-values';
import { is_legacy_format, type RowCell } from '../../src/types';

type JsonValue = null | boolean | number | string
    | JsonValue[] | { [key: string]: JsonValue };

interface Options {
    correctness: boolean;
    benchmark: boolean;
    rows: number;
    warmup: number;
    iterations: number;
    json?: string;
}

interface TimingDataset {
    file: string;
    nvar: number;
    full: number[];
    selected: number[];
    selected_indices: number[];
    decomposition?: Record<string, number[]>;
}

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '../..');
const FIXTURE_DIR = path.join(ROOT_DIR, 'tests/fixtures/dta');

function parse_positive(value: string | undefined, flag: string): number {
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 1) {
        throw new Error(`${flag} requires a positive integer`);
    }
    return parsed;
}

function parse_options(argv: string[]): Options {
    const options: Options = {
        correctness: true,
        benchmark: true,
        rows: 100_000,
        warmup: 2,
        iterations: 5,
    };
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === '--correctness-only') options.benchmark = false;
        else if (argument === '--benchmark-only') options.correctness = false;
        else if (argument === '--rows') {
            options.rows = parse_positive(argv[++index], argument);
        } else if (argument === '--warmup') {
            options.warmup = parse_positive(argv[++index], argument);
        } else if (argument === '--iterations') {
            options.iterations = parse_positive(argv[++index], argument);
        } else if (argument === '--json') {
            options.json = argv[++index];
            if (!options.json) throw new Error('--json requires a path');
        } else if (argument === '--help') {
            console.log(`Usage: bun run benchmarks/dta-vs-haven/run.ts [options]

  --correctness-only  compare checked-in fixtures without timing
  --benchmark-only    run generated performance workloads only
  --rows N            rows per generated dataset (default: 100000)
  --warmup N          untimed reads per implementation (default: 2)
  --iterations N      timed reads per implementation (default: 5)
  --json PATH         also write machine-readable results`);
            process.exit(0);
        } else {
            throw new Error(`unknown argument: ${argument}`);
        }
    }
    return options;
}

function run_r(arguments_: string[]): void {
    execFileSync('Rscript', arguments_, { stdio: 'inherit' });
}

function r_json(mode: string, arguments_: string[]): any {
    const directory = mkdtempSync(path.join(tmpdir(), 'dta-haven-r-'));
    const output = path.join(directory, 'result.json');
    try {
        run_r([path.join(SCRIPT_DIR, 'haven.R'), mode, output, ...arguments_]);
        return JSON.parse(readFileSync(output, 'utf8'));
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
}

function canonical_cell(cell: RowCell): JsonValue {
    return is_missing_value_object(cell)
        ? { missing: cell.missing_type }
        : cell;
}

async function snapshot_file(file_path: string): Promise<JsonValue> {
    const file = await DtaFile.open(file_path);
    try {
        const rows = await file.read_rows(0, file.nobs);
        return {
            file: path.basename(file_path),
            dataset_label: file.dataset_label,
            nrow: file.nobs,
            ncol: file.nvar,
            variables: file.variables.map(variable => {
                const table = file.value_label_tables.get(
                    variable.value_label_name
                );
                return {
                    name: variable.name,
                    label: variable.label,
                    format: variable.format,
                    labels: table
                        ? [...table].map(([value, label]) => ({
                            value: canonical_cell(value), label,
                        }))
                        : [],
                };
            }),
            rows: rows.map(row => row.map(canonical_cell)),
        };
    } finally {
        file.close();
    }
}

function compare_values(
    actual: any,
    expected: any,
    location: string,
    failures: string[],
): void {
    if (typeof actual === 'number' && typeof expected === 'number') {
        const scale = Math.max(1, Math.abs(actual), Math.abs(expected));
        if (Math.abs(actual - expected) > 1e-7 * scale) {
            failures.push(`${location}: ${actual} !== ${expected}`);
        }
        return;
    }
    if (Array.isArray(actual) && Array.isArray(expected)) {
        if (actual.length !== expected.length) {
            failures.push(
                `${location}: length ${actual.length} !== ${expected.length}`
            );
            return;
        }
        for (let index = 0; index < actual.length; index++) {
            compare_values(
                actual[index], expected[index],
                `${location}[${index}]`, failures
            );
        }
        return;
    }
    if (actual && expected
        && typeof actual === 'object' && typeof expected === 'object') {
        const keys = new Set([
            ...Object.keys(actual), ...Object.keys(expected),
        ]);
        for (const key of keys) {
            compare_values(
                actual[key], expected[key],
                `${location}.${key}`, failures
            );
        }
        return;
    }
    if (actual !== expected) {
        failures.push(
            `${location}: ${JSON.stringify(actual)} !== `
            + JSON.stringify(expected)
        );
    }
}

async function run_correctness(): Promise<any> {
    const files = readdirSync(FIXTURE_DIR)
        .filter(file => file.endsWith('.dta'))
        .sort()
        .map(file => path.join(FIXTURE_DIR, file));
    const haven = r_json('snapshot', files);
    const parser = [];
    for (const file of files) parser.push(await snapshot_file(file));
    const failures: string[] = [];
    compare_values(
        parser, haven.datasets, 'datasets', failures
    );
    if (failures.length > 0) {
        const shown = failures.slice(0, 20).join('\n');
        throw new Error(
            `reproducibility comparison failed (${failures.length} `
            + `differences):\n${shown}`
        );
    }
    console.log(
        `Correctness: PASS — ${files.length} files match haven `
        + `(tolerance 1e-7).`
    );
    return {
        status: 'pass', files: files.length,
        tolerance: 1e-7,
        haven_version: haven.haven_version,
        r_version: haven.r_version,
    };
}

async function elapsed_samples(
    read_once: () => Promise<number>,
    warmup: number,
    iterations: number,
): Promise<number[]> {
    for (let index = 0; index < warmup; index++) await read_once();
    const samples: number[] = [];
    for (let index = 0; index < iterations; index++) {
        const start = performance.now();
        await read_once();
        samples.push(performance.now() - start);
    }
    return samples;
}

async function benchmark_file(
    file_path: string,
    selected_indices: number[],
    options: Options,
): Promise<TimingDataset> {
    const full_read = async (): Promise<number> => {
        const file = await DtaFile.open(file_path);
        try {
            const rows = await file.read_rows(0, file.nobs);
            return rows.length;
        } finally {
            file.close();
        }
    };
    const selected_read = async (): Promise<number> => {
        const file = await DtaFile.open(file_path);
        try {
            const columns = await file.read_columns(selected_indices);
            return Array.from(columns.values()).reduce(
                (total, column) => total + column.length,
                columns.size,
            );
        } finally {
            file.close();
        }
    };
    const file_bytes = readFileSync(file_path);
    const file_buffer = file_bytes.buffer.slice(
        file_bytes.byteOffset,
        file_bytes.byteOffset + file_bytes.byteLength,
    ) as ArrayBuffer;
    const metadata = parse_metadata(file_buffer);
    const data_tag_length = is_legacy_format(metadata.format_version)
        ? 0 : '<data>'.length;
    const data_start = metadata.section_offsets.data + data_tag_length;
    const data_length = metadata.nobs * metadata.obs_length;
    const data_buffer = file_buffer.slice(
        data_start, data_start + data_length
    );
    const descriptor = openSync(file_path, 'r');
    const open_only = async (): Promise<number> => {
        const file = await DtaFile.open(file_path);
        try {
            return file.nobs + file.nvar;
        } finally {
            file.close();
        }
    };
    const observation_read = async (): Promise<number> => {
        const buffer = Buffer.allocUnsafe(data_length);
        let total = 0;
        while (total < data_length) {
            const count = readSync(
                descriptor, buffer, total,
                data_length - total, data_start + total,
            );
            if (count === 0) throw new Error('unexpected EOF');
            total += count;
        }
        return total;
    };
    const decode_preloaded = async (): Promise<number> => {
        const rows = read_rows_from_data_buffer(
            data_buffer, metadata, 0, metadata.nobs
        );
        return rows.length;
    };
    const metadata_preloaded = async (): Promise<number> => {
        const parsed = parse_metadata(file_buffer);
        return parsed.nobs + parsed.nvar;
    };
    const labels_preloaded = async (): Promise<number> => {
        return parse_value_labels(file_buffer, metadata).size;
    };
    let synthetic_rows_sink: unknown;
    const synthetic_row_shape = async (): Promise<number> => {
        const rows = Array.from(
            { length: metadata.nobs },
            () => new Array(metadata.nvar),
        );
        synthetic_rows_sink = rows;
        return (synthetic_rows_sink as unknown[]).length;
    };
    try {
        const full = await elapsed_samples(
            full_read, options.warmup, options.iterations
        );
        const selected = await elapsed_samples(
            selected_read, options.warmup, options.iterations
        );
        return {
            file: path.basename(file_path),
            nvar: metadata.nvar,
            full,
            selected,
            selected_indices,
            decomposition: {
                end_to_end_file: full,
                open_metadata_labels: await elapsed_samples(
                    open_only, options.warmup, options.iterations
                ),
                observation_read: await elapsed_samples(
                    observation_read, options.warmup, options.iterations
                ),
                decode_preloaded: await elapsed_samples(
                    decode_preloaded, options.warmup, options.iterations
                ),
                metadata_parse_preloaded: await elapsed_samples(
                    metadata_preloaded, options.warmup, options.iterations
                ),
                labels_parse_preloaded: await elapsed_samples(
                    labels_preloaded, options.warmup, options.iterations
                ),
                synthetic_row_shape: await elapsed_samples(
                    synthetic_row_shape, options.warmup, options.iterations
                ),
            },
        };
    } finally {
        closeSync(descriptor);
    }
}

function median(values: number[]): number {
    const sorted = [...values].sort((left, right) => left - right);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
}

async function run_benchmark(options: Options): Promise<any> {
    const directory = mkdtempSync(path.join(tmpdir(), 'dta-benchmark-'));
    try {
        run_r([
            path.join(SCRIPT_DIR, 'generate.R'),
            directory, String(options.rows),
        ]);
        const files = ['numeric-v118.dta', 'mixed-v118.dta']
            .map(file => path.join(directory, file));
        const haven = r_json('benchmark', [
            String(options.warmup), String(options.iterations), ...files,
        ]);
        const parser: TimingDataset[] = [];
        for (const dataset of haven.datasets as TimingDataset[]) {
            parser.push(await benchmark_file(
                path.join(directory, dataset.file),
                dataset.selected_indices,
                options,
            ));
        }
        console.log('\nPerformance (median milliseconds; lower is better)');
        console.log('dataset\tread\tdta-parser\thaven\tdta-parser throughput');
        const comparisons = [];
        const attribution = [];
        for (let index = 0; index < parser.length; index++) {
            const file_size = statSync(files[index]).size;
            for (const read of ['full', 'selected'] as const) {
                const dta_ms = median(parser[index][read]);
                const haven_ms = median(haven.datasets[index][read]);
                const relative = haven_ms / dta_ms;
                console.log(
                    `${parser[index].file}\t${read}\t${dta_ms.toFixed(1)}`
                    + `\t${haven_ms.toFixed(1)}\t${relative.toFixed(2)}x`
                );
                comparisons.push({
                    file: parser[index].file,
                    bytes: file_size,
                    read,
                    dta_parser_ms: parser[index][read],
                    haven_ms: haven.datasets[index][read],
                    dta_parser_median_ms: dta_ms,
                    haven_median_ms: haven_ms,
                    dta_parser_throughput_relative_to_haven: relative,
                });
            }

            const dta_stages = parser[index].decomposition!;
            const haven_stages = (
                haven.datasets[index].decomposition
            ) as Record<string, number[]>;
            const dta_total = median(dta_stages.end_to_end_file);
            const dta_open = median(dta_stages.open_metadata_labels);
            const dta_read = median(dta_stages.observation_read);
            const dta_decode = median(dta_stages.decode_preloaded);
            const dta_residual = dta_total
                - dta_open - dta_read - dta_decode;
            const haven_total = median(haven_stages.end_to_end_file);
            const haven_native = median(haven_stages.native_file);
            const haven_metadata = median(
                haven_stages.native_metadata_file
            );
            const haven_native_data_output = haven_native - haven_metadata;
            const haven_wrapper = haven_total - haven_native;
            const decoded_cells = options.rows * parser[index].nvar;
            const percent = (value: number, total: number): number =>
                total === 0 ? 0 : value / total * 100;

            console.log(`\nAttribution: ${parser[index].file}`);
            console.log('implementation\tfactor\tmedian ms\t% of end-to-end');
            for (const [implementation, factor, milliseconds, total] of [
                ['dta-parser', 'open + metadata + labels', dta_open, dta_total],
                ['dta-parser', 'observation-section read', dta_read, dta_total],
                ['dta-parser', 'decode + JS result allocation', dta_decode, dta_total],
                ['dta-parser', 'composition/noise residual', dta_residual, dta_total],
                ['haven', 'native metadata/setup', haven_metadata, haven_total],
                ['haven', 'native data + decode + R result',
                    haven_native_data_output, haven_total],
                ['haven', 'R wrapper/datasource residual', haven_wrapper, haven_total],
            ] as Array<[string, string, number, number]>) {
                console.log(
                    `${implementation}\t${factor}\t${milliseconds.toFixed(2)}`
                    + `\t${percent(milliseconds, total).toFixed(1)}%`
                );
            }
            console.log('diagnostic\tmedian ms');
            console.log(`decoded cells\t${decoded_cells}`);
            console.log(
                `dta decode + result ns/cell\t${(
                    dta_decode * 1e6 / decoded_cells
                ).toFixed(2)}`
            );
            console.log(
                `haven native data + decode + result ns/cell\t${(
                    haven_native_data_output * 1e6 / decoded_cells
                ).toFixed(2)}`
            );
            console.log(
                `dta metadata parse, preloaded\t${median(
                    dta_stages.metadata_parse_preloaded
                ).toFixed(2)}`
            );
            console.log(
                `dta value-label parse, preloaded\t${median(
                    dta_stages.labels_parse_preloaded
                ).toFixed(2)}`
            );
            console.log(
                `dta empty row-container allocation lower bound\t${median(
                    dta_stages.synthetic_row_shape
                ).toFixed(2)}`
            );
            console.log(
                `haven raw file read only\t${median(
                    haven_stages.raw_file_read
                ).toFixed(2)}`
            );
            console.log(
                `haven native parse from preloaded raw\t${median(
                    haven_stages.native_preloaded_raw
                ).toFixed(2)}`
            );
            console.log(
                `haven empty typed-result allocation lower bound\t${median(
                    haven_stages.synthetic_result_shape
                ).toFixed(2)}`
            );

            attribution.push({
                file: parser[index].file,
                decoded_cells,
                dta_parser: {
                    end_to_end_ms: dta_total,
                    open_metadata_labels_ms: dta_open,
                    observation_read_ms: dta_read,
                    decode_and_result_ms: dta_decode,
                    composition_residual_ms: dta_residual,
                    metadata_parse_preloaded_ms: median(
                        dta_stages.metadata_parse_preloaded
                    ),
                    labels_parse_preloaded_ms: median(
                        dta_stages.labels_parse_preloaded
                    ),
                    empty_row_container_allocation_lower_bound_ms: median(
                        dta_stages.synthetic_row_shape
                    ),
                    raw_samples: dta_stages,
                },
                haven: {
                    end_to_end_ms: haven_total,
                    native_file_ms: haven_native,
                    native_metadata_setup_ms: haven_metadata,
                    native_data_decode_result_ms: haven_native_data_output,
                    r_wrapper_datasource_residual_ms: haven_wrapper,
                    raw_file_read_ms: median(haven_stages.raw_file_read),
                    native_preloaded_raw_ms: median(
                        haven_stages.native_preloaded_raw
                    ),
                    empty_typed_result_allocation_lower_bound_ms: median(
                        haven_stages.synthetic_result_shape
                    ),
                    raw_samples: haven_stages,
                },
            });
        }
        return {
            rows: options.rows,
            warmup: options.warmup,
            iterations: options.iterations,
            haven_version: haven.haven_version,
            r_version: haven.r_version,
            comparisons,
            attribution,
        };
    } finally {
        rmSync(directory, { recursive: true, force: true });
    }
}

const options = parse_options(process.argv.slice(2));
const result: any = {
    generated_at: new Date().toISOString(),
    environment: {
        platform: `${os.platform()} ${os.release()} ${os.arch()}`,
        cpu: os.cpus()[0]?.model ?? 'unknown',
        bun: Bun.version,
    },
};
if (options.benchmark) result.performance = await run_benchmark(options);
if (options.correctness) result.correctness = await run_correctness();
if (options.json) {
    const output = path.resolve(options.json);
    mkdirSync(path.dirname(output), { recursive: true });
    writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
    console.log(`\nWrote ${output}`);
}
