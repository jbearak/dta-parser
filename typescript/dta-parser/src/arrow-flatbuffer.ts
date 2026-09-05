/** Bounds-checked access to the flat, supported Arrow IPC metadata tables. */
export class FlatBuffer {
    readonly view: DataView;
    private readonly decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
    constructor(readonly bytes: Uint8Array) {
        this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    }
    range(position: number, length: number): number {
        if (!Number.isSafeInteger(position) || !Number.isSafeInteger(length)
            || position < 0 || length < 0 || position > this.bytes.length - length) {
            throw new Error('Invalid Arrow IPC metadata: offset outside buffer');
        }
        return position;
    }
    u8(p: number): number { return this.view.getUint8(this.range(p, 1)); }
    i16(p: number): number { return this.view.getInt16(this.range(p, 2), true); }
    u16(p: number): number { return this.view.getUint16(this.range(p, 2), true); }
    i32(p: number): number { return this.view.getInt32(this.range(p, 4), true); }
    u32(p: number): number { return this.view.getUint32(this.range(p, 4), true); }
    i64(p: number): bigint { return this.view.getBigInt64(this.range(p, 8), true); }
    size(p: number): number {
        const value = this.i64(p);
        if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) {
            throw new Error('Invalid Arrow IPC metadata: size is not a safe integer');
        }
        return Number(value);
    }
    indirect(p: number): number {
        const offset = this.u32(p);
        if (offset < 4) throw new Error('Invalid Arrow IPC metadata: invalid relative offset');
        return this.range(p + offset, 4);
    }
    root(): number { return this.indirect(0); }
    field(table: number, index: number, width = 4): number | undefined {
        const vtable = table - this.i32(table);
        const length = this.u16(vtable);
        const objectLength = this.u16(vtable + 2);
        if (length < 4 || length % 2 || objectLength < 4) {
            throw new Error('Invalid Arrow IPC metadata: invalid table length');
        }
        this.range(vtable, length);
        this.range(table, objectLength);
        if (4 + index * 2 >= length) return undefined;
        const offset = this.u16(vtable + 4 + index * 2);
        if (!offset) return undefined;
        if (offset < 4 || offset + width > objectLength) {
            throw new Error('Invalid Arrow IPC metadata: field outside table');
        }
        return table + offset;
    }
    scalar(table: number, index: number, kind: 'u8' | 'i16' | 'i32', fallback = 0): number {
        const position = this.field(table, index, kind === 'u8' ? 1 : kind === 'i16' ? 2 : 4);
        return position === undefined ? fallback : this[kind](position);
    }
    boolean(table: number, index: number): boolean {
        const value = this.scalar(table, index, 'u8');
        if (value > 1) throw new Error('Invalid Arrow IPC metadata: invalid boolean');
        return value === 1;
    }
    child(table: number, index: number, required = false): number | undefined {
        const position = this.field(table, index);
        if (position !== undefined) return this.indirect(position);
        if (required) throw new Error('Invalid Arrow IPC metadata: missing required table');
        return undefined;
    }
    vector(table: number, index: number, width: number): { start: number; length: number } {
        const position = this.child(table, index);
        if (position === undefined) return { start: 0, length: 0 };
        const length = this.u32(position);
        const start = position + 4;
        this.range(start, length * width);
        return { start, length };
    }
    tables(table: number, index: number): number[] {
        const { start, length } = this.vector(table, index, 4);
        return Array.from({ length }, (_, i) => this.indirect(start + 4 * i));
    }
    string(table: number, index: number, required = false): string | undefined {
        const position = this.child(table, index, required);
        if (position === undefined) return undefined;
        const length = this.u32(position);
        this.range(position + 4, length + 1);
        if (this.u8(position + 4 + length) !== 0) {
            throw new Error('Invalid Arrow IPC metadata: unterminated string');
        }
        return this.decoder.decode(this.bytes.subarray(position + 4, position + 4 + length));
    }
    metadata(table: number, index: number): Map<string, string> {
        const result = new Map<string, string>();
        for (const entry of this.tables(table, index)) {
            const key = this.string(entry, 0, true)!;
            const value = this.string(entry, 1) ?? '';
            if (result.has(key)) throw new Error(`Invalid Arrow IPC metadata: duplicate key ${key}`);
            result.set(key, value);
        }
        return result;
    }
}
