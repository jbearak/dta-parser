// Regenerate the checked Rust/TypeScript compatibility oracle. Run from the
// repository root with:
//
//   bun r-package/dtatools/src/dta-tools/tests/support/generate-modern-canonical.ts
//
// Every checked-in .dta fixture is included. The Node-backed TypeScript path
// resolves strLs and legacy files exactly as production consumers do.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { parse_metadata } from '../../../../../../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../../../../../../typescript/dta-parser/src/legacy-header';
import { is_missing_value_object } from '../../../../../../typescript/dta-parser/src/missing-values';
import { DtaFile } from '../../../../../../typescript/dta-parser/src/node';
import {
    is_legacy_format,
    type FormatVersion,
} from '../../../../../../typescript/dta-parser/src/types';

const script_dir = path.dirname(fileURLToPath(import.meta.url));
const repository_root = path.resolve(script_dir, '../../../../../..');
const fixture_dir = path.join(repository_root, 'tests/fixtures/dta');
const fixture_names = readdirSync(fixture_dir)
    .filter(name => name.endsWith('.dta'))
    .sort();
const fixtures: Record<string, unknown> = {};

for (const fixture_name of fixture_names) {
    const fixture_path = path.join(fixture_dir, fixture_name);
    const node_buffer = readFileSync(fixture_path);
    const buffer = node_buffer.buffer.slice(
        node_buffer.byteOffset,
        node_buffer.byteOffset + node_buffer.byteLength
    );
    const version = node_buffer[0] as FormatVersion;
    const metadata = is_legacy_format(version)
        ? parse_legacy_metadata(buffer, node_buffer.length)
        : parse_metadata(buffer);
    const file = await DtaFile.open(fixture_path);
    try {
        const rows = await file.read_rows(0, metadata.nobs);
        const columns = metadata.variables.map(
            (variable, variable_index) => ({
                variable_index,
                name: variable.name,
                storage_type: variable.type,
                cells: rows.map(row => {
                    const cell = row[variable_index];
                    return is_missing_value_object(cell)
                        ? { missing: cell.missing_type }
                        : cell;
                }),
            })
        );
        const value_label_tables = Array.from(
            file.value_label_tables,
            ([name, entries]) => ({
                name,
                entries: Array.from(
                    entries,
                    ([value, label]) => ({ value, label })
                ),
            })
        );
        fixtures[fixture_name] = {
            sha256: createHash('sha256')
                .update(node_buffer)
                .digest('hex'),
            metadata: {
                format_version: metadata.format_version,
                byte_order: metadata.byte_order,
                nvar: metadata.nvar,
                nobs: metadata.nobs,
                dataset_label: metadata.dataset_label,
                obs_length: metadata.obs_length,
                section_offsets: metadata.section_offsets,
                variables: metadata.variables,
            },
            columns,
            value_label_tables,
        };
    } finally {
        file.close();
    }
}

const output = {
    schema_version: 2,
    source: 'Production TypeScript DtaFile plus parse_metadata/parse_legacy_metadata; fixture values and missing tags retain the shared haven-derived expectations',
    fixtures,
};
const output_path = path.join(
    repository_root,
    'r-package/dtatools/src/dta-tools/tests/data/modern-canonical.json'
);
writeFileSync(output_path, `${JSON.stringify(output, null, 2)}\n`);
