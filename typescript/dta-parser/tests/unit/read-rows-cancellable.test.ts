import {
    describe,
    it,
    expect,
    afterEach,
    spyOn,
} from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';
import { DtaFile } from '../../src/node';

// -----------------------------------------------------------
// read_rows cancellable / chunked path
//
// When called with options.signal, read_rows reads the
// requested range in chunks, yielding to the event loop
// between chunks so a queued abort can be observed, and
// throwing an AbortError when the signal fires. Without a
// signal it must behave exactly as the single-shot path.
// -----------------------------------------------------------

const FIXTURE_DIR = path.resolve(
    __dirname, '../../../../tests/fixtures/dta'
);

let my_file: DtaFile | null = null;

afterEach(() => {
    my_file?.close();
    my_file = null;
});

describe('read_rows (cancellable)', () => {

    // ----- equivalence with the single-shot path -----

    describe('chunk equivalence', () => {
        it('chunked read equals single-shot read (full)', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_single = await my_file.read_rows(0, 74);
            const my_controller = new AbortController();
            const the_chunked = await my_file.read_rows(
                0, 74, undefined, undefined,
                { signal: my_controller.signal, chunk_rows: 7 }
            );
            expect(the_chunked).toEqual(the_single);
        });

        it('chunked read equals single-shot with col subrange', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_single = await my_file.read_rows(
                0, 74, 1, 4
            );
            const my_controller = new AbortController();
            const the_chunked = await my_file.read_rows(
                0, 74, 1, 4,
                { signal: my_controller.signal, chunk_rows: 5 }
            );
            expect(the_chunked).toEqual(the_single);
        });

        it('returns [] for an empty projection across chunks', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );

            for (const [my_col_start, my_col_end] of [
                [4, 4],
                [my_file.nvar + 1, my_file.nvar + 2],
            ]) {
                const the_rows = await my_file.read_rows(
                    0,
                    my_file.nobs,
                    my_col_start,
                    my_col_end,
                    { chunk_rows: 1 }
                );
                expect(the_rows).toEqual([]);
                expect(the_rows.length).toBe(0);
                expect(JSON.stringify(the_rows)).toBe('[]');
            }
        });

        it('returns [] for a negative start across chunks', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_controller = new AbortController();

            for (const my_options of [
                { chunk_rows: 1 },
                {
                    signal: my_controller.signal,
                    chunk_rows: 1,
                },
            ]) {
                expect(
                    await my_file.read_rows(
                        -1,
                        3,
                        undefined,
                        undefined,
                        my_options
                    )
                ).toEqual([]);
            }
        });

        it('does not let a signal change NaN range errors', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_controller = new AbortController();

            for (const [my_start, my_count] of [
                [0, NaN],
                [NaN, 1],
            ]) {
                for (const my_options of [
                    undefined,
                    {
                        signal: my_controller.signal,
                        chunk_rows: 1,
                    },
                ]) {
                    await expect(
                        my_file.read_rows(
                            my_start,
                            my_count,
                            undefined,
                            undefined,
                            my_options
                        )
                    ).rejects.toBeInstanceOf(RangeError);
                }
            }
        });

        it('chunked read resolves strL across chunk boundary', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'all_types.dta')
            );
            const the_single = await my_file.read_rows(0, 5);
            const my_controller = new AbortController();
            const the_chunked = await my_file.read_rows(
                0, 5, undefined, undefined,
                { signal: my_controller.signal, chunk_rows: 2 }
            );
            expect(the_chunked).toEqual(the_single);
        });

        it('clamps a negative projection before resolving strL', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'all_types.dta')
            );
            const my_strl_idx = my_file.variables.findIndex(
                my_var => my_var.type === 'strL'
            );
            const the_expected = await my_file.read_rows(
                0,
                my_file.nobs,
                0,
                my_strl_idx + 1
            );

            for (const my_options of [
                undefined,
                { chunk_rows: 2 },
            ]) {
                expect(
                    await my_file.read_rows(
                        0,
                        my_file.nobs,
                        -1,
                        my_strl_idx + 1,
                        my_options
                    )
                ).toEqual(the_expected);
            }
        });

        it('falls back to the default for invalid chunk_rows', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_single = await my_file.read_rows(0, 74);
            const my_controller = new AbortController();
            for (const my_bad of [0, -5, NaN, 2.5]) {
                const the_chunked = await my_file.read_rows(
                    0, 74, undefined, undefined,
                    { signal: my_controller.signal, chunk_rows: my_bad }
                );
                expect(the_chunked).toEqual(the_single);
            }
        });

        it('chunk_rows larger than count reads in one go', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_single = await my_file.read_rows(0, 74);
            const my_controller = new AbortController();
            const the_chunked = await my_file.read_rows(
                0, 74, undefined, undefined,
                { signal: my_controller.signal, chunk_rows: 10000 }
            );
            expect(the_chunked).toEqual(the_single);
        });
    });

    // ----- abort -----

    describe('abort', () => {
        it('rejects with AbortError when pre-aborted', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_controller = new AbortController();
            my_controller.abort();

            let my_error: unknown = null;
            try {
                await my_file.read_rows(
                    0, 74, undefined, undefined,
                    { signal: my_controller.signal, chunk_rows: 7 }
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

            const my_promise = my_file.read_rows(
                0, 74, undefined, undefined,
                { signal: my_controller.signal, chunk_rows: 1 }
            );
            // Abort after the first inter-chunk yield.
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

        it('does not preallocate the full result before the first yield', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_metadata = (
                my_file as unknown as {
                    _metadata: { nobs: number };
                }
            )._metadata;
            const my_original_nobs = my_metadata.nobs;
            const my_controller = new AbortController();
            setImmediate(() => my_controller.abort());

            let my_error: unknown = null;
            try {
                my_metadata.nobs = 0x1_0000_0000;
                await my_file.read_rows(
                    0,
                    my_metadata.nobs,
                    undefined,
                    undefined,
                    {
                        signal: my_controller.signal,
                        chunk_rows: 1,
                    }
                );
            } catch (err) {
                my_error = err;
            } finally {
                my_metadata.nobs = my_original_nobs;
            }

            expect(my_error).toBeInstanceOf(Error);
            expect((my_error as Error).name).toBe('AbortError');
        });
    });

    // ----- closed mid-read -----

    describe('closed mid-read', () => {
        it('returns [] (never a partial column) if closed between chunks', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_controller = new AbortController();

            const my_promise = my_file.read_rows(
                0, 74, undefined, undefined,
                { signal: my_controller.signal, chunk_rows: 1 }
            );
            // Close after the first inter-chunk yield.
            setImmediate(() => my_file?.close());

            const the_rows = await my_promise;
            expect(the_rows).toEqual([]);
            my_file = null; // already closed
        });
    });

    // ----- signal-less path unchanged -----

    describe('no signal', () => {
        it('behaves like the single-shot path when options omitted', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const the_a = await my_file.read_rows(0, 74);
            const the_b = await my_file.read_rows(
                0, 74, undefined, undefined, {}
            );
            expect(the_b).toEqual(the_a);
        });

        it('honors chunk_rows to bound observation reads', async () => {
            my_file = await DtaFile.open(
                path.join(FIXTURE_DIR, 'auto_v118.dta')
            );
            const my_chunk_rows = 5;
            const my_row_width = my_file.variables.reduce(
                (sum, variable) => sum + variable.byte_width,
                0
            );
            const the_read_lengths: number[] = [];
            const my_original = fs.readSync;
            const my_spy = spyOn(fs, 'readSync');
            my_spy.mockImplementation(
                (fd, buffer, offset, length, position) => {
                    the_read_lengths.push(length);
                    return my_original(
                        fd, buffer, offset, length, position
                    );
                }
            );

            try {
                const the_rows = await my_file.read_rows(
                    0,
                    my_file.nobs,
                    undefined,
                    undefined,
                    { chunk_rows: my_chunk_rows }
                );
                expect(the_rows.length).toBe(my_file.nobs);
            } finally {
                my_spy.mockRestore();
            }

            expect(the_read_lengths.length).toBeGreaterThan(1);
            expect(Math.max(...the_read_lengths)).toBeLessThanOrEqual(
                my_chunk_rows * my_row_width
            );
        });
    });
});
