import { type ArrowSource } from './arrow-ipc';
import type { ArrowCell, ArrowDictionary, ArrowMetadata, ArrowOpenOptions, ArrowReadOptions, ArrowRow, ArrowVariable } from './arrow-types';
export declare function abortArrowRead(signal?: AbortSignal): void;
/** Shared synchronous byte reader; the Node adapter yields between decoded chunks. */
export declare class ArrowReader {
    private readonly source;
    private readonly footer;
    private readonly applyProfile;
    private readonly verify;
    private readonly maxBytes;
    private readonly maxRows?;
    private readonly dictionaryCache;
    private readonly profileVersion?;
    constructor(source: ArrowSource, options?: ArrowOpenOptions);
    get nobs(): number;
    get nvar(): number;
    private allIndices;
    private selectionProfile;
    /** Accessing complete metadata consumes every profile field document. */
    get metadata(): ArrowMetadata;
    get variables(): ArrowVariable[];
    normalizeColumns(indices: readonly number[]): number[];
    rowColumns(start?: number, end?: number): number[];
    window(start: number, count: number): {
        start: number;
        count: number;
    };
    private loadArray;
    private dictionary;
    get_dictionary(index: number): ArrowDictionary | undefined;
    get dictionaries(): Map<number, ArrowDictionary>;
    chunks(indices: number[], start: number, count: number, options?: ArrowReadOptions): Generator<Map<number, ArrowCell[]>>;
}
/** Synchronous reader for complete Arrow IPC file bytes, including compressed files. */
export declare class ArrowBuffer {
    private readonly reader;
    private constructor();
    static open(buffer: ArrayBuffer | Uint8Array, options?: ArrowOpenOptions): ArrowBuffer;
    get nobs(): number;
    get nvar(): number;
    get metadata(): ArrowMetadata;
    get variables(): ArrowVariable[];
    get dictionaries(): Map<number, ArrowDictionary>;
    get_dictionary(index: number): ArrowDictionary | undefined;
    read_rows(start: number, count: number, col_start?: number, col_end?: number, options?: ArrowReadOptions): ArrowRow[];
    read_columns(indices: number[], options?: ArrowReadOptions): Map<number, ArrowCell[]>;
}
//# sourceMappingURL=arrow-reader.d.ts.map