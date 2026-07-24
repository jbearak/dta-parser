// Regenerate the Rust observation conformance oracle from the maintained
// TypeScript decoder. Run from the repository root with:
//
//   bun rust/dta-parser/tests/support/generate-modern-canonical.ts

// The checked-in JSON intentionally contains every supported (non-strL) cell
// in every modern shared fixture. Rust tests consume it without invoking Bun.

import { readFileSync, writeFileSync } from 'node:fs';
import * as path from 'node:path';

import { read_rows_from_buffer } from '../../../../src/data-reader';
import { parse_metadata } from '../../../../src/header';
import { is_missing_value_object } from '../../../../src/missing-values';

const FIXTURES = [
    'all_types.dta',
    'all_types_v117.dta',
    'all_types_v118.dta',
    'auto_v117.dta',
    'auto_v118.dta',
    'auto_v119.dta',
    'empty.dta',
    'empty_v118.dta',
    'missing_values.dta',
    'missing_values_v118.dta',
    'strl_test.dta',
    'strl_test_v118.dta',
    'value_labels.dta',
    'value_labels_v117.dta',
    'value_labels_v118.dta',
    'wide.dta',
    'wide_v118.dta',
] as const;

const fixture_dir = path.resolve('tests/fixtures/dta');
const fixtures: Record<string, unknown> = {};

for (const fixture_name of FIXTURES) {
    const node_buffer = readFileSync(
        path.join(fixture_dir, fixture_name)
    );
    const buffer = node_buffer.buffer.slice(
        node_buffer.byteOffset,
        node_buffer.byteOffset + node_buffer.byteLength
    );
    const metadata = parse_metadata(buffer);
    const rows = read_rows_from_buffer(
        buffer,
        metadata,
        0,
        metadata.nobs
    );
    const columns = metadata.variables.flatMap(
        (variable, variable_index) => {
            if (variable.type === 'strL') return [];
            return [{
                variable_index,
                name: variable.name,
                storage_type: variable.type,
                cells: rows.map(row => {
                    const cell = row[variable_index];
                    return is_missing_value_object(cell)
                        ? { missing: cell.missing_type }
                        : cell;
                }),
            }];
        }
    );
    fixtures[fixture_name] = {
        format_version: metadata.format_version,
        row_count: metadata.nobs,
        columns,
    };
}

const output = {
    schema_version: 1,
    source: 'TypeScript read_rows_from_buffer; values mirror haven-derived shared fixture expectations',
    fixtures,
};
const output_path = path.resolve(
    'rust/dta-parser/tests/data/modern-canonical.json'
);
writeFileSync(output_path, `${JSON.stringify(output, null, 2)}\n`);
