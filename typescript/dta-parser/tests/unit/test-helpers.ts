import { spyOn } from 'bun:test';
import * as fs from 'fs';
import type { DtaFile } from '../../src/node';

export async function with_temporary_nobs<T>(
    file: DtaFile,
    nobs: number,
    fn: () => Promise<T>
): Promise<T> {
    const internal = (
        file as unknown as {
            _read_plan: { readonly nobs: number };
        }
    );
    const original = internal._read_plan;

    try {
        internal._read_plan = { ...original, nobs };
        return await fn();
    } finally {
        internal._read_plan = original;
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
