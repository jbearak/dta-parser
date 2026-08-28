import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import {
    deterministic_sparse_rows,
    exact_array_buffer,
    expand_modern_strls,
    repeat_modern_value_labels,
    scale_modern_rows,
} from '../../benchmarks/typescript-product-fixtures';
import { read_rows_from_buffer } from '../../typescript/dta-tools/src/data-reader';
import { parse_metadata } from '../../typescript/dta-tools/src/header';
import {
    build_gso_index,
    decode_gso_entry,
} from '../../typescript/dta-tools/src/strl-reader';
import { parse_value_labels } from '../../typescript/dta-tools/src/value-labels';

const fixture_dir = path.resolve(import.meta.dir, '../fixtures/dta');

function fixture_buffer(name: string): ArrayBuffer {
    return exact_array_buffer(readFileSync(path.join(fixture_dir, name)));
}

describe('TypeScript product benchmark fixtures', () => {
    it('scales observations while preserving rows and section offsets', () => {
        const my_source = fixture_buffer('auto_v118.dta');
        const my_source_metadata = parse_metadata(my_source);
        const my_scaled = scale_modern_rows(my_source, 173);
        const my_scaled_metadata = parse_metadata(my_scaled);
        const my_source_rows = read_rows_from_buffer(
            my_source,
            my_source_metadata,
            0,
            my_source_metadata.nobs
        );
        const my_scaled_rows = read_rows_from_buffer(
            my_scaled,
            my_scaled_metadata,
            0,
            my_scaled_metadata.nobs
        );
        const my_expected_delta =
            (173 - my_source_metadata.nobs)
            * my_source_metadata.obs_length;

        expect(my_scaled_metadata.nobs).toBe(173);
        expect(my_scaled_rows[0]).toEqual(my_source_rows[0]);
        expect(my_scaled_rows[74]).toEqual(my_source_rows[0]);
        expect(my_scaled_rows[172]).toEqual(
            my_source_rows[172 % my_source_metadata.nobs]
        );
        expect(
            my_scaled_metadata.section_offsets.strls
            - my_source_metadata.section_offsets.strls
        ).toBe(my_expected_delta);
        expect(my_scaled_metadata.section_offsets.end_of_file).toBe(
            my_scaled.byteLength
        );
        expect(parse_value_labels(my_scaled, my_scaled_metadata)).toEqual(
            parse_value_labels(my_source, my_source_metadata)
        );
    });

    it('creates distinct copies of modern value-label tables', () => {
        const my_source = fixture_buffer('value_labels_v118.dta');
        const my_source_metadata = parse_metadata(my_source);
        const my_source_labels = parse_value_labels(
            my_source, my_source_metadata
        );
        const my_expanded = repeat_modern_value_labels(my_source, 4);
        const my_expanded_metadata = parse_metadata(my_expanded);
        const my_expanded_labels = parse_value_labels(
            my_expanded, my_expanded_metadata
        );

        expect(my_source_labels.size).toBe(3);
        expect(my_expanded_labels.size).toBe(12);
        for (const my_name of my_source_labels.keys()) {
            expect(my_expanded_labels.get(my_name)).toEqual(
                my_source_labels.get(my_name)
            );
        }
        expect(my_expanded_labels.has('bench_1_0')).toBe(true);
        expect(my_expanded_labels.has('bench_3_2')).toBe(true);
        expect(my_expanded_metadata.section_offsets.end_of_file).toBe(
            my_expanded.byteLength
        );
    });

    it('creates a large valid GSO index with deterministic payloads', () => {
        const my_source = fixture_buffer('strl_test_v118.dta');
        const my_scaled = scale_modern_rows(my_source, 10);
        const my_expanded = expand_modern_strls(my_scaled, 10, 32);
        const my_metadata = parse_metadata(my_expanded);
        const my_index = build_gso_index(my_expanded, my_metadata);
        const my_generated_entry = my_index.get('1:10');

        expect(my_metadata.nobs).toBe(10);
        expect(my_index.size).toBe(10);
        expect(my_generated_entry).toBeDefined();
        expect(decode_gso_entry(
            new Uint8Array(my_expanded),
            my_generated_entry!
        )).toStartWith('bench-1-10');
        expect(my_metadata.section_offsets.end_of_file).toBe(
            my_expanded.byteLength
        );
    });

    it('generates stable, unique sparse row requests', () => {
        const the_rows = deterministic_sparse_rows(100_000, 200);

        expect(the_rows).toEqual(
            deterministic_sparse_rows(100_000, 200)
        );
        expect(new Set(the_rows).size).toBe(200);
        expect(the_rows.every(my_row =>
            my_row >= 0 && my_row < 100_000
        )).toBe(true);
        expect(the_rows).not.toEqual(
            [...the_rows].sort((my_left, my_right) => my_left - my_right)
        );
    });
});
