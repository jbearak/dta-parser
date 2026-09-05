import type { ArrowCell, ArrowDictionary, ArrowMetadata, ArrowOpenOptions, ArrowReadOptions, ArrowRow, ArrowVariable } from './arrow-types';
/** Seekable Arrow reader. Holds one file descriptor until close(), even after path replacement. */
export declare class ArrowFile {
    private readonly fd;
    private readonly reader;
    private closed;
    private constructor();
    static open(path: string, options?: ArrowOpenOptions): Promise<ArrowFile>;
    private ensureOpen;
    get nobs(): number;
    get nvar(): number;
    get metadata(): ArrowMetadata;
    get variables(): ArrowVariable[];
    get dictionaries(): Map<number, ArrowDictionary>;
    get_dictionary(index: number): ArrowDictionary | undefined;
    read_rows(start: number, count: number, col_start?: number, col_end?: number, options?: ArrowReadOptions): Promise<ArrowRow[]>;
    read_columns(indices: number[], options?: ArrowReadOptions): Promise<Map<number, ArrowCell[]>>;
    close(): void;
}
//# sourceMappingURL=arrow-node.d.ts.map