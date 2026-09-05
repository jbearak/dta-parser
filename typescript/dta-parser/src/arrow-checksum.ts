/** Canonical logical Arrow buffer checksums, matching the Rust profile. */
const MASK = 0xffffffffffffffffn;
const P1 = 11400714785074694791n;
const P2 = 14029467366897019727n;
const P3 = 1609587929392839161n;
const P4 = 9650029242287828579n;
const P5 = 2870177450012600261n;
const rotate = (value: bigint, count: bigint): bigint =>
    ((value << count) | (value >> (64n - count))) & MASK;
const round = (acc: bigint, value: bigint): bigint =>
    (rotate((acc + value * P2) & MASK, 31n) * P1) & MASK;

/** xxHash64 with the profile's fixed zero seed. */
export function xxh64(bytes: Uint8Array): bigint {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let cursor = 0;
    let hash: bigint;
    if (bytes.length >= 32) {
        let a = (P1 + P2) & MASK;
        let b = P2;
        let c = 0n;
        let d = (-P1) & MASK;
        do {
            a = round(a, view.getBigUint64(cursor, true));
            b = round(b, view.getBigUint64(cursor + 8, true));
            c = round(c, view.getBigUint64(cursor + 16, true));
            d = round(d, view.getBigUint64(cursor + 24, true));
            cursor += 32;
        } while (cursor <= bytes.length - 32);
        hash = (rotate(a, 1n) + rotate(b, 7n) + rotate(c, 12n) + rotate(d, 18n)) & MASK;
        for (const lane of [a, b, c, d]) {
            hash = ((hash ^ round(0n, lane)) * P1 + P4) & MASK;
        }
    } else {
        hash = P5;
    }
    hash = (hash + BigInt(bytes.length)) & MASK;
    while (cursor + 8 <= bytes.length) {
        hash ^= round(0n, view.getBigUint64(cursor, true));
        hash = (rotate(hash, 27n) * P1 + P4) & MASK;
        cursor += 8;
    }
    if (cursor + 4 <= bytes.length) {
        hash ^= (BigInt(view.getUint32(cursor, true)) * P1) & MASK;
        hash = (rotate(hash, 23n) * P2 + P3) & MASK;
        cursor += 4;
    }
    while (cursor < bytes.length) {
        hash ^= (BigInt(bytes[cursor++]) * P5) & MASK;
        hash = (rotate(hash, 11n) * P1) & MASK;
    }
    hash ^= hash >> 33n;
    hash = (hash * P2) & MASK;
    hash ^= hash >> 29n;
    hash = (hash * P3) & MASK;
    return (hash ^ (hash >> 32n)) & MASK;
}

export interface CanonicalArrowBuffers {
    type: string;
    length: number;
    offset?: number;
    /** Omit when the logical array has no null bitmap. */
    validity?: Uint8Array;
    validityOffset?: number;
    /** Data buffers, excluding validity. */
    buffers: readonly Uint8Array[];
    dictionaryKeyType?: string;
}

function integer(value: number): void {
    if (!Number.isSafeInteger(value) || value < 0) {
        throw new Error('Invalid Arrow checksum offset or length');
    }
}

function slice(bytes: Uint8Array | undefined, start: number, length: number): Uint8Array {
    integer(start);
    integer(length);
    if (!bytes || start > bytes.length || length > bytes.length - start) {
        throw new Error('Arrow checksum buffer is too short');
    }
    return bytes.subarray(start, start + length);
}

function bitmap(bytes: Uint8Array, offset: number, length: number): Uint8Array {
    integer(offset);
    if (offset % 8 !== 0) throw new Error('Bitmap checksum requires a byte-aligned offset');
    const result = slice(bytes, offset / 8, Math.ceil(length / 8));
    if (length % 8 === 0) return result;
    const masked = result.slice();
    masked[masked.length - 1] &= (1 << (length % 8)) - 1;
    return masked;
}

/** Dictionary arrays hash keys here; hash their shared values separately. */
export function canonicalBufferHashes(array: CanonicalArrowBuffers): string[] {
    integer(array.length);
    const offset = array.offset ?? 0;
    integer(offset);
    const result: string[] = [];
    const hash = (bytes: Uint8Array): void => {
        result.push(xxh64(bytes).toString(16).padStart(16, '0'));
    };
    if (array.validity !== undefined) {
        hash(bitmap(array.validity, array.validityOffset ?? offset, array.length));
    }
    if (array.type === 'bool') {
        hash(bitmap(slice(array.buffers[0], 0, array.buffers[0]?.length ?? 0), offset, array.length));
    } else if (array.type === 'utf8' || array.type === 'large-utf8') {
        const width = array.type === 'utf8' ? 4 : 8;
        const raw = slice(array.buffers[0], offset * width, (array.length + 1) * width);
        const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
        const read = (index: number): bigint => width === 4
            ? BigInt(view.getInt32(index * width, true))
            : view.getBigInt64(index * width, true);
        const first = read(0);
        let previous = first;
        const rebased = new Uint8Array(raw.length);
        const output = new DataView(rebased.buffer);
        for (let index = 0; index <= array.length; index++) {
            const value = read(index);
            if (value < 0n || value < previous || value > BigInt(Number.MAX_SAFE_INTEGER)) {
                throw new Error('Invalid Arrow string checksum offsets');
            }
            const relative = value - first;
            if (width === 4) output.setInt32(index * width, Number(relative), true);
            else output.setBigInt64(index * width, relative, true);
            previous = value;
        }
        hash(first === 0n ? raw : rebased);
        hash(slice(array.buffers[1], Number(first), Number(previous - first)));
    } else {
        const widths: Record<string, number> = {
            int8: 1, uint8: 1, int16: 2, uint16: 2,
            int32: 4, uint32: 4, float32: 4, date32: 4,
            int64: 8, uint64: 8, float64: 8, date64: 8, timestamp: 8, duration: 8,
        };
        const type = array.type === 'dictionary' ? array.dictionaryKeyType ?? '' : array.type;
        const width = Object.hasOwn(widths, type) ? widths[type] : undefined;
        if (!width) throw new Error(`Cannot checksum unsupported Arrow type ${array.type}`);
        hash(slice(array.buffers[0], offset * width, array.length * width));
    }
    return result;
}
