import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

import { parse_metadata } from '../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../typescript/dta-parser/src/legacy-header';
import { read_rows_from_buffer } from '../typescript/dta-parser/src/data-reader';
import { parse_value_labels } from '../typescript/dta-parser/src/value-labels';
import { DtaFile } from '../typescript/dta-parser/src/node';
import { build_gso_index, resolve_strl } from '../typescript/dta-parser/src/strl-reader';
import { is_missing_value_object } from '../typescript/dta-parser/src/missing-values';
import { is_legacy_format, type DtaMetadata, type FormatVersion, type RowCell } from '../typescript/dta-parser/src/types';

type FixtureCase = { name: string; sha256: string };
type Manifest = {
    schema_version: number;
    identity: {
        canonical_oracle: string;
        canonical_sha256: string;
        fixture_count: number;
        case_count: number;
        fixture_oracle_gate: { binary: string; test: string };
    };
    fixture_cases: FixtureCase[];
    deterministic_cases: Array<{
        name: string;
        kind: string;
        coverage: string;
        gate: { binary: string; test: string };
    }>;
};

const root = path.resolve(import.meta.dir, '..');
const fixtureDir = path.join(root, 'tests/fixtures/dta');
const manifest = JSON.parse(
    readFileSync(path.join(root, 'conformance/cases.json'), 'utf8')
) as Manifest;
const canonicalBytes = readFileSync(
    path.join(root, manifest.identity.canonical_oracle)
);
type OracleCell = number | string | { missing: string };
type OracleFixture = {
    sha256: string;
    metadata: DtaMetadata;
    columns: Array<{ variable_index: number; name: string; storage_type: string; cells: OracleCell[] }>;
    value_label_tables: Array<{ name: string; entries: Array<{ value: number; label: string }> }>;
};
const canonical = JSON.parse(canonicalBytes.toString('utf8')) as {
    schema_version: number;
    fixtures: Record<string, OracleFixture>;
};

function invariant(condition: unknown, message: string): asserts condition {
    if (!condition) throw new Error(`conformance: ${message}`);
}

/** Compare every recorded field while allowing newly exposed metadata fields. */
function exact_recorded_fields(actual: unknown, expected: unknown, context: string): void {
    if (Array.isArray(expected)) {
        invariant(Array.isArray(actual) && actual.length === expected.length, `${context} array length`);
        expected.forEach((value, index) => exact_recorded_fields(actual[index], value, `${context}[${index}]`));
    } else if (expected !== null && typeof expected === 'object') {
        invariant(actual !== null && typeof actual === 'object', `${context} object`);
        for (const [key, value] of Object.entries(expected)) {
            exact_recorded_fields((actual as Record<string, unknown>)[key], value, `${context}.${key}`);
        }
    } else {
        invariant(Object.is(actual, expected), `${context}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }
}

let verifiedCells = 0;
function compare_cell(actual: RowCell, expected: OracleCell, storage: string, context: string): void {
    const normalized = is_missing_value_object(actual) ? { missing: actual.missing_type } : actual;
    if ((storage === 'float' || storage === 'double')
        && typeof normalized === 'number' && typeof expected === 'number') {
        invariant(Object.is(normalized, expected)
            || Number.isFinite(normalized) && Number.isFinite(expected)
            && Math.abs(normalized - expected) <= 1e-7 * Math.max(1, Math.abs(expected)),
        `${context}: numeric value differs from oracle`);
    } else {
        exact_recorded_fields(normalized, expected, context);
    }
    verifiedCells++;
}

invariant(manifest.schema_version === 1, 'unsupported manifest schema');
invariant(canonical.schema_version === 2, 'unsupported canonical schema');
invariant(
    createHash('sha256').update(canonicalBytes).digest('hex')
        === manifest.identity.canonical_sha256,
    'canonical oracle identity changed; regenerate intentionally'
);
invariant(
    manifest.fixture_cases.length === manifest.identity.fixture_count,
    'fixture count does not match manifest identity'
);
invariant(
    manifest.fixture_cases.length + manifest.deterministic_cases.length
        === manifest.identity.case_count,
    'total case count does not match manifest identity'
);
invariant(manifest.identity.case_count === 32, 'case inventory must remain 32');
invariant(
    manifest.identity.fixture_oracle_gate.binary.length > 0
        && manifest.identity.fixture_oracle_gate.test.length > 0,
    'fixture canonical-oracle gate identity is missing'
);
const declaredGates = new Set<string>();
for (const item of manifest.deterministic_cases) {
    invariant(item.kind.length > 0, `${item.name} has no kind`);
    invariant(item.coverage.length > 0, `${item.name} has no coverage statement`);
    invariant(item.gate.binary.length > 0, `${item.name} has no gate binary`);
    invariant(item.gate.test.length > 0, `${item.name} has no gate test`);
    const identity = `${item.gate.binary}::${item.gate.test}`;
    invariant(!declaredGates.has(identity), `${item.name} reuses gate ${identity}`);
    declaredGates.add(identity);
}
const fixtureOracleIdentity = `${manifest.identity.fixture_oracle_gate.binary}::${manifest.identity.fixture_oracle_gate.test}`;
invariant(
    !declaredGates.has(fixtureOracleIdentity),
    `fixture canonical-oracle gate must be separate from the ${manifest.deterministic_cases.length} deterministic cases`
);

const diskNames = readdirSync(fixtureDir)
    .filter(name => name.endsWith('.dta'))
    .sort();
const manifestNames = manifest.fixture_cases.map(item => item.name).sort();
invariant(
    JSON.stringify(diskNames) === JSON.stringify(manifestNames),
    'disk fixture inventory differs from the checked manifest'
);
invariant(
    JSON.stringify(Object.keys(canonical.fixtures).sort())
        === JSON.stringify(manifestNames),
    'canonical fixture inventory differs from the checked manifest'
);

for (const item of manifest.fixture_cases) {
    const bytes = readFileSync(path.join(fixtureDir, item.name));
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    invariant(sha256 === item.sha256, `${item.name} hash differs from manifest`);
    invariant(
        canonical.fixtures[item.name]?.sha256 === item.sha256,
        `${item.name} hash differs from canonical oracle`
    );

    const arrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
    );
    const metadata = is_legacy_format(bytes[0] as FormatVersion)
        ? parse_legacy_metadata(arrayBuffer, bytes.length)
        : parse_metadata(arrayBuffer);
    const oracle = canonical.fixtures[item.name];
    exact_recorded_fields(metadata, oracle.metadata, `${item.name} buffer metadata`);
    invariant(oracle.columns.length === metadata.nvar, `${item.name} oracle column count`);
    const bufferRows = read_rows_from_buffer(arrayBuffer, metadata, 0, metadata.nobs);
    const strlColumns = metadata.variables.flatMap((variable, index) => variable.type === 'strL' ? [index] : []);
    if (strlColumns.length > 0) {
        const gso = build_gso_index(arrayBuffer, metadata);
        for (let row = 0; row < metadata.nobs; row++) {
            for (const column of strlColumns) {
                bufferRows[row][column] = resolve_strl(arrayBuffer, metadata, gso,
                    metadata.section_offsets.data + '<data>'.length
                    + row * metadata.obs_length + metadata.variables[column].byte_offset);
            }
        }
    }
    const bufferLabels = parse_value_labels(arrayBuffer, metadata);
    exact_recorded_fields(Array.from(bufferLabels, ([name, entries]) => ({
        name, entries: Array.from(entries, ([value, label]) => ({ value, label })),
    })), oracle.value_label_tables, `${item.name} buffer value labels`);
    const file = await DtaFile.open(path.join(fixtureDir, item.name));
    try {
        exact_recorded_fields(file.metadata, oracle.metadata, `${item.name} Node metadata`);
        // The frozen oracle predates numbered notes and characteristics. Check
        // those against the independent buffer path without assuming absence.
        exact_recorded_fields(file.metadata, metadata, `${item.name} complete Node/buffer metadata`);
        exact_recorded_fields(Array.from(file.value_label_tables, ([name, entries]) => ({
            name, entries: Array.from(entries, ([value, label]) => ({ value, label })),
        })), oracle.value_label_tables, `${item.name} Node value labels`);
        const allRows = await file.read_rows(0, metadata.nobs);
        const allColumns = await file.read_columns(metadata.variables.map((_, index) => index), { chunk_rows: 3 });
        invariant(allRows.length === metadata.nobs && bufferRows.length === metadata.nobs,
            `${item.name} full row counts`);
        for (const column of oracle.columns) {
            const index = column.variable_index;
            invariant(metadata.variables[index]?.name === column.name
                && metadata.variables[index]?.type === column.storage_type, `${item.name} oracle column identity`);
            invariant(column.cells.length === metadata.nobs && allColumns.get(index)?.length === metadata.nobs,
                `${item.name} full column counts`);
            for (let row = 0; row < metadata.nobs; row++) {
                const context = `${item.name}[${row},${index}]`;
                compare_cell(allRows[row][index], column.cells[row], column.storage_type, `${context} Node row`);
                compare_cell(allColumns.get(index)![row], column.cells[row], column.storage_type, `${context} Node column`);
                compare_cell(bufferRows[row][index], column.cells[row], column.storage_type, `${context} buffer row`);
            }
        }
        invariant(file.nvar === metadata.nvar, `${item.name} nvar mismatch`);
        invariant(file.nobs === metadata.nobs, `${item.name} nobs mismatch`);
        invariant(
            JSON.stringify(file.variables) === JSON.stringify(metadata.variables),
            `${item.name} variable metadata mismatch`
        );
        const start = Math.min(1, metadata.nobs);
        const count = Math.min(2, Math.max(0, metadata.nobs - start));
        const projected = metadata.nvar === 0
            ? []
            : [metadata.nvar - 1, 0];
        const rows = await file.read_rows(start, count);
        const columns = await file.read_columns(projected, { chunk_rows: 64 });
        invariant(rows.length === count, `${item.name} row-window mismatch`);
        for (const index of projected) {
            invariant(
                columns.get(index)?.slice(start, start + count).length === count,
                `${item.name} projected row-window mismatch`
            );
            const projectedRows = await file.read_rows(start, count, index, index + 1);
            const column = oracle.columns[index];
            for (let row = 0; row < count; row++) {
                compare_cell(rows[row][index], column.cells[start + row], column.storage_type, `${item.name} window`);
                compare_cell(columns.get(index)![start + row], column.cells[start + row], column.storage_type,
                    `${item.name} projected column`);
                compare_cell(projectedRows[row][0], column.cells[start + row], column.storage_type,
                    `${item.name} projected row`);
            }
        }
    } finally {
        file.close();
    }
}

function must_reject(operation: () => unknown, context: string): void {
    let rejected = false;
    try { operation(); } catch { rejected = true; }
    invariant(rejected, `${context} was accepted`);
}

// Execute TypeScript rejection checks too; validating the native gate names
// alone does not prove agreement on malformed input.
const malformedBase = new Uint8Array(readFileSync(path.join(fixtureDir, 'auto_v118.dta')));
for (const tag of ['<stata_dta>', '</K>', '</N>', '</map>', '</variable_types>', '</sortlist>']) {
    const bytes = malformedBase.slice();
    const offset = Buffer.from(bytes).indexOf(tag);
    invariant(offset >= 0, `malformed source lacks ${tag}`);
    bytes[offset] = 88;
    must_reject(() => parse_metadata(bytes.buffer), `TypeScript invalid ${tag}`);
}
for (const tag of ['<data>', '</data>', '<strls>', '</strls>']) {
    const bytes = malformedBase.slice();
    const metadata = parse_metadata(bytes.buffer);
    const offset = Buffer.from(bytes).indexOf(tag);
    invariant(offset >= 0, `malformed source lacks ${tag}`);
    bytes[offset] = 88;
    must_reject(() => read_rows_from_buffer(bytes.buffer, metadata, 0, 1), `TypeScript invalid ${tag}`);
}
for (const tag of ['<value_labels>', '<lbl>', '</lbl>', '</value_labels>', '</stata_dta>']) {
    const bytes = malformedBase.slice();
    const metadata = parse_metadata(bytes.buffer);
    const offset = Buffer.from(bytes).indexOf(tag, metadata.section_offsets.value_labels);
    invariant(offset >= 0, `malformed source lacks ${tag}`);
    bytes[offset] = 88;
    must_reject(() => parse_value_labels(bytes.buffer, metadata), `TypeScript invalid ${tag}`);
}
{
    const bytes = new Uint8Array(readFileSync(path.join(fixtureDir, 'strl_test_v118.dta')));
    const metadata = parse_metadata(bytes.buffer);
    const index = build_gso_index(bytes.buffer, metadata);
    const variable = metadata.variables.find(variable => variable.type === 'strL')!;
    const pointer = metadata.section_offsets.data + '<data>'.length + variable.byte_offset;
    // Keep a structurally valid key but remove its object from the index.
    index.clear();
    must_reject(() => resolve_strl(bytes.buffer, metadata, index, pointer), 'TypeScript dangling strL pointer');
}

function replaceFirstByte(
    bytes: Uint8Array,
    needle: string,
    replacement: number
): void {
    const encoded = new TextEncoder().encode(needle);
    for (let i = 0; i <= bytes.length - encoded.length; i++) {
        let matches = true;
        for (let j = 0; j < encoded.length; j++) {
            if (bytes[i + j] !== encoded[j]) {
                matches = false;
                break;
            }
        }
        if (matches) {
            bytes[i] = replacement;
            return;
        }
    }
    throw new Error(`conformance: fixture does not contain ${needle}`);
}

function encodingSurfaces(
    bytes: Uint8Array,
    encoding?: 'utf-8' | 'windows-1252' | 'iso-8859-1'
): string[] {
    const buffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
    ) as ArrayBuffer;
    const metadata = parse_metadata(
        buffer, encoding === undefined ? {} : { encoding }
    );
    const rows = read_rows_from_buffer(buffer, metadata, 0, 1);
    const labels = parse_value_labels(buffer, metadata);
    return [
        metadata.dataset_label,
        metadata.variables[0].label,
        rows[0][0] as string,
        labels.get('origin')?.get(0) ?? '',
    ];
}

const encodingFixture = new Uint8Array(readFileSync(
    path.join(fixtureDir, 'auto_v117.dta')
));
replaceFirstByte(encodingFixture, '1978 automobile data', 0x80);
replaceFirstByte(encodingFixture, 'Make and model', 0x80);
replaceFirstByte(encodingFixture, 'AMC Concord', 0x80);
replaceFirstByte(encodingFixture, 'Domestic', 0x80);
invariant(
    encodingSurfaces(encodingFixture).every(
        value => value.startsWith('\u20ac')
    ),
    'release 117 automatic text encoding differs from Rust Windows-1252 policy'
);
invariant(
    encodingSurfaces(encodingFixture, 'utf-8').every(
        value => value.startsWith('\ufffd')
    ),
    'release 117 explicit UTF-8 differs from Rust replacement policy'
);
invariant(
    encodingSurfaces(encodingFixture, 'iso-8859-1').every(
        value => value.startsWith('\u0080')
    ),
    'explicit ISO-8859-1 must remain distinct from Windows-1252'
);

process.stdout.write(
    `TypeScript fixture conformance: PASS (${manifest.fixture_cases.length} `
        + `immutable fixtures, ${verifiedCells} decoded cell comparisons); ${manifest.deterministic_cases.length} `
        + 'deterministic native gate identities validated '
        + '(execution follows in scripts/conformance.sh)\n'
);
