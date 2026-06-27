import { describe, it, expect, afterEach } from 'bun:test';
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

const FIXTURE_DIR = path.join(
    __dirname, '..', 'fixtures', 'dta'
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
    });
});
