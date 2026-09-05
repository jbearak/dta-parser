import * as fs from 'node:fs';
import { ArrowReader, abortArrowRead } from './arrow-reader';
import { safeSize } from './arrow-ipc';
import type { ArrowCell, ArrowDictionary, ArrowMetadata, ArrowOpenOptions, ArrowReadOptions, ArrowRow, ArrowVariable } from './arrow-types';

const yieldToEventLoop = (): Promise<void> => new Promise(resolve => setImmediate(resolve));

/** Seekable Arrow reader. Holds one file descriptor until close(), even after path replacement. */
export class ArrowFile {
    private closed = false;
    private constructor(private readonly fd: number, private readonly reader: ArrowReader) {}
    static async open(path: string, options: ArrowOpenOptions = {}): Promise<ArrowFile> {
        const fd = fs.openSync(path, 'r');
        try {
            const size = fs.fstatSync(fd).size;
            const reader = new ArrowReader({ size, read(offset, length) {
                safeSize(offset, 'Arrow read offset'); safeSize(length, 'Arrow read length');
                if (offset > size - length) throw new Error('Unexpected EOF reading Arrow file');
                const result = Buffer.allocUnsafe(length);
                let total = 0;
                while (total < length) {
                    const count = fs.readSync(fd, result, total, length - total, offset + total);
                    if (!count) throw new Error('Unexpected EOF reading Arrow file');
                    total += count;
                }
                return result;
            } }, options);
            return new ArrowFile(fd, reader);
        } catch (error) { fs.closeSync(fd); throw error; }
    }
    private ensureOpen(): void { if (this.closed) throw new Error('Arrow file is closed'); }
    get nobs(): number { return this.reader.nobs; }
    get nvar(): number { return this.reader.nvar; }
    get metadata(): ArrowMetadata { this.ensureOpen(); return this.reader.metadata; }
    get variables(): ArrowVariable[] { this.ensureOpen(); return this.reader.variables; }
    get dictionaries(): Map<number, ArrowDictionary> { this.ensureOpen(); return this.reader.dictionaries; }
    get_dictionary(index: number): ArrowDictionary | undefined { this.ensureOpen(); return this.reader.get_dictionary(index); }
    async read_rows(start: number, count: number, col_start = 0, col_end = this.nvar, options: ArrowReadOptions = {}): Promise<ArrowRow[]> {
        this.ensureOpen(); abortArrowRead(options.signal);
        const columns = this.reader.rowColumns(col_start, col_end), window = this.reader.window(start, count);
        const rows: ArrowRow[] = [];
        await yieldToEventLoop();
        this.ensureOpen(); abortArrowRead(options.signal);
        for (const chunk of this.reader.chunks(columns, start, count, options)) {
            this.ensureOpen(); abortArrowRead(options.signal);
            const length = columns.length ? chunk.get(columns[0])!.length : 0;
            for (let i = 0; i < length; i++) rows.push(columns.map(index => chunk.get(index)![i]));
            await yieldToEventLoop();
            this.ensureOpen(); abortArrowRead(options.signal);
        }
        if (!columns.length) return Array.from({ length: window.count }, () => []);
        return rows;
    }
    async read_columns(indices: number[], options: ArrowReadOptions = {}): Promise<Map<number, ArrowCell[]>> {
        this.ensureOpen(); abortArrowRead(options.signal);
        const columns = this.reader.normalizeColumns(indices), result = new Map(columns.map(index => [index, [] as ArrowCell[]]));
        await yieldToEventLoop();
        this.ensureOpen(); abortArrowRead(options.signal);
        for (const chunk of this.reader.chunks(columns, 0, this.nobs, options)) {
            this.ensureOpen(); abortArrowRead(options.signal);
            for (const index of columns) for (const cell of chunk.get(index)!) result.get(index)!.push(cell);
            await yieldToEventLoop();
            this.ensureOpen(); abortArrowRead(options.signal);
        }
        return result;
    }
    close(): void {
        if (!this.closed) { this.closed = true; fs.closeSync(this.fd); }
    }
}
