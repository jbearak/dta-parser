import {
    afterEach,
    describe,
    expect,
    it,
    spyOn,
} from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';
import { DtaFile } from '../../src/node';
import type { RowCell } from '../../src/types';

const FIXTURE_DIR = path.join(
    __dirname, '..', 'fixtures', 'dta'
);

let my_file: DtaFile | null = null;

afterEach(() => {
    my_file?.close();
    my_file = null;
});

async function read_single_column(
    file: DtaFile,
    col_index: number,
    chunk_rows = 3
): Promise<RowCell[]> {
    const my_controller = new AbortController();
    const the_rows = await file.read_rows(
        0,
        file.nobs,
        col_index,
        col_index + 1,
        { signal: my_controller.signal, chunk_rows }
    );
    return the_rows.map(my_row => my_row[0]);
}

async function expect_columns_equal_read_rows(
    file: DtaFile,
    col_indices: number[],
    chunk_rows = 4
): Promise<void> {
    const the_columns = await file.read_columns(
        col_indices,
        { chunk_rows }
    );
    const the_distinct = [...new Set(col_indices)];
    expect(the_columns.size).toBe(the_distinct.length);

    for (const my_col of the_distinct) {
        const the_expected = await read_single_column(
            file,
            my_col,
            chunk_rows
        );
        expect(the_columns.get(my_col)).toEqual(the_expected);
    }
}

describe('DtaFile.read_columns', () => {
    it('returns an empty map for an empty request', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );

        const the_columns = await my_file.read_columns([]);

        expect(the_columns).toBeInstanceOf(Map);
        expect(the_columns.size).toBe(0);
    });

    it('matches read_rows for distinct non-contiguous columns', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );

        await expect_columns_equal_read_rows(
            my_file,
            [10, 1, 3, 0]
        );
    });

    it('deduplicates requested columns', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );

        await expect_columns_equal_read_rows(
            my_file,
            [3, 1, 3, 10, 1]
        );
    });

    it('preserves missing-value classification', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'missing_values.dta')
        );

        await expect_columns_equal_read_rows(my_file, [0, 1]);
    });

    it('preserves value-label raw codes', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'value_labels.dta')
        );

        await expect_columns_equal_read_rows(my_file, [0, 1]);
    });

    it('resolves strL columns across chunk boundaries', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'all_types.dta')
        );
        const my_strl_idx = my_file.variables.findIndex(
            my_var => my_var.type === 'strL'
        );
        expect(my_strl_idx).toBeGreaterThanOrEqual(0);

        await expect_columns_equal_read_rows(
            my_file,
            [my_strl_idx, 0, 2],
            2
        );
    });

    it('loads the strL section lazily and only once', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'all_types.dta')
        );
        const my_strl_idx = my_file.variables.findIndex(
            my_var => my_var.type === 'strL'
        );
        expect(my_strl_idx).toBeGreaterThanOrEqual(0);

        const my_original = fs.readSync;
        function count_reads(
            fn: () => Promise<unknown>
        ): Promise<number> {
            let n = 0;
            const my_spy = spyOn(fs, 'readSync');
            my_spy.mockImplementation((...args) => {
                n++;
                return (my_original as Function)(...args);
            });
            return fn()
                .then(() => n)
                .finally(() => my_spy.mockRestore());
        }

        // Numeric columns must not touch the GSO section at all.
        const my_numeric_reads = await count_reads(() =>
            my_file!.read_columns([0, 1, 2])
        );
        // The first strL read loads the section exactly once on top of
        // the data-chunk reads — not once per row (would be nobs+1).
        const my_first_strl_reads = await count_reads(() =>
            my_file!.read_columns([my_strl_idx])
        );
        // A second strL read reuses the cached section: no extra reads
        // beyond the data chunk(s).
        const my_second_strl_reads = await count_reads(() =>
            my_file!.read_columns([my_strl_idx])
        );

        expect(my_first_strl_reads).toBe(my_numeric_reads + 1);
        expect(my_second_strl_reads).toBe(my_numeric_reads);
    });

    it('rejects out-of-bounds column indices', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );

        await expect(
            my_file.read_columns([-1])
        ).rejects.toThrow(/column index -1.*out of bounds/i);
        await expect(
            my_file.read_columns([my_file.nvar])
        ).rejects.toThrow(/out of bounds/i);
        await expect(
            my_file.read_columns([1.5])
        ).rejects.toThrow(/integer/i);
    });

    it('rejects with AbortError when pre-aborted', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );
        const my_controller = new AbortController();
        my_controller.abort();

        let my_error: unknown = null;
        try {
            await my_file.read_columns(
                [0, 1],
                { signal: my_controller.signal, chunk_rows: 2 }
            );
        } catch (err) {
            my_error = err;
        }

        expect(my_error).toBeInstanceOf(Error);
        expect((my_error as Error).name).toBe('AbortError');
    });

    it('rejects with AbortError when aborted mid-read', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );
        const my_controller = new AbortController();

        const my_promise = my_file.read_columns(
            [0, 1, 2],
            { signal: my_controller.signal, chunk_rows: 1 }
        );
        setImmediate(() => my_controller.abort());

        let my_error: unknown = null;
        try {
            await my_promise;
        } catch (err) {
            my_error = err;
        }

        expect(my_error).toBeInstanceOf(Error);
        expect((my_error as Error).name).toBe('AbortError');
    });

    it('chunks even without a signal so data reads stay bounded', async () => {
        my_file = await DtaFile.open(
            path.join(FIXTURE_DIR, 'auto_v118.dta')
        );
        const my_chunk_rows = 5;
        const my_obs_width = my_file.variables.reduce(
            (sum, my_var) => sum + my_var.byte_width,
            0
        );
        const the_read_lengths: number[] = [];
        const my_original = fs.readSync;
        const my_spy = spyOn(fs, 'readSync');
        my_spy.mockImplementation(
            (fd, buffer, offset, length, position) => {
                the_read_lengths.push(length);
                return my_original(
                    fd,
                    buffer,
                    offset,
                    length,
                    position
                );
            }
        );

        try {
            await my_file.read_columns(
                [1, 10],
                { chunk_rows: my_chunk_rows }
            );
        } finally {
            my_spy.mockRestore();
        }

        expect(the_read_lengths.length).toBeGreaterThan(1);
        expect(
            Math.max(...the_read_lengths)
        ).toBeLessThanOrEqual(my_chunk_rows * my_obs_width);
    });
});
