/** Bounds-checked access to the flat, supported Arrow IPC metadata tables. */
export declare class FlatBuffer {
    readonly bytes: Uint8Array;
    readonly view: DataView;
    private readonly decoder;
    constructor(bytes: Uint8Array);
    range(position: number, length: number): number;
    u8(p: number): number;
    i16(p: number): number;
    u16(p: number): number;
    i32(p: number): number;
    u32(p: number): number;
    i64(p: number): bigint;
    size(p: number): number;
    indirect(p: number): number;
    root(): number;
    field(table: number, index: number, width?: number): number | undefined;
    scalar(table: number, index: number, kind: 'u8' | 'i16' | 'i32', fallback?: number): number;
    boolean(table: number, index: number): boolean;
    child(table: number, index: number, required?: boolean): number | undefined;
    vector(table: number, index: number, width: number): {
        start: number;
        length: number;
    };
    tables(table: number, index: number): number[];
    string(table: number, index: number, required?: boolean): string | undefined;
    metadata(table: number, index: number): Map<string, string>;
}
//# sourceMappingURL=arrow-flatbuffer.d.ts.map