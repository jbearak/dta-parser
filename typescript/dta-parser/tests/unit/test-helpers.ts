import { spyOn } from 'bun:test';
import * as fs from 'fs';
import type { DtaFile } from '../../src/node';

export async function with_temporary_nobs<T>(
    file: DtaFile,
    nobs: number,
    fn: () => Promise<T>
): Promise<T> {
    const my_metadata = (
        file as unknown as {
            _metadata: { nobs: number };
        }
    )._metadata;
    const my_original_nobs = my_metadata.nobs;

    try {
        my_metadata.nobs = nobs;
        return await fn();
    } finally {
        my_metadata.nobs = my_original_nobs;
    }
}

export async function capture_read_lengths(
    fn: () => Promise<unknown>
): Promise<number[]> {
    const my_spy = spyOn(fs, 'readSync');
    try {
        await fn();
        return my_spy.mock.calls.map(
            my_call => my_call[3] as number
        );
    } finally {
        my_spy.mockRestore();
    }
}
