import { FlatBuffer } from './arrow-flatbuffer';
import { decodeArrowBuffer } from './arrow-codecs';
import type { ArrowType, ArrowVariable } from './arrow-types';

export interface ArrowSource {
    readonly size: number;
    read(offset: number, length: number): Uint8Array;
}
export interface IpcField extends ArrowVariable {
    bufferIndex: number;
    dictionaryId?: bigint;
}
export interface IpcBlock { offset: number; metadataLength: number; bodyLength: number; }
export interface IpcBatch {
    block: IpcBlock;
    rows: number;
    nodes: Array<{ length: number; nullCount: number }>;
    buffers: Array<{ offset: number; length: number }>;
    compression?: 0 | 1;
    dictionaryId?: bigint;
    delta?: boolean;
}
export interface IpcFooter {
    fields: IpcField[];
    batches: IpcBatch[];
    dictionaries: IpcBatch[];
    metadata: Map<string, string>;
    customMetadata: Map<string, string>;
    rows: number;
}
const MAX_METADATA = 64 * 1024 * 1024;
const decoder = new TextDecoder();
export function safeSize(value: number, name: string): number {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${name} must be a non-negative safe integer`);
    return value;
}
function intType(fb: FlatBuffer, table: number): ArrowType {
    const width = fb.scalar(table, 0, 'i32');
    if (![8, 16, 32, 64].includes(width)) throw new Error('Unsupported Arrow integer width');
    return `${fb.boolean(table, 1) ? '' : 'u'}int${width}` as ArrowType;
}
function parseField(fb: FlatBuffer, table: number, bufferIndex: number): IpcField {
    const name = fb.string(table, 0, true)!;
    const kind = fb.scalar(table, 2, 'u8');
    const detail = fb.child(table, 3, true)!;
    let type: ArrowType;
    let unit: IpcField['unit'];
    let timezone: string | undefined;
    switch (kind) {
        case 2: type = intType(fb, detail); break;
        case 3: {
            const precision = fb.scalar(detail, 0, 'i16');
            if (precision !== 1 && precision !== 2) throw new Error('Unsupported Arrow float precision');
            type = precision === 1 ? 'float32' : 'float64'; break;
        }
        case 5: type = 'utf8'; break;
        case 6: type = 'bool'; break;
        case 8:
            if (fb.scalar(detail, 0, 'i16', 1) !== 0) throw new Error('Unsupported Arrow date unit');
            type = 'date32'; unit = 'day'; break;
        case 10: case 18: {
            const timeUnit = fb.scalar(detail, 0, 'i16', kind === 18 ? 1 : 0);
            if (timeUnit < 0 || timeUnit > 3) throw new Error('Unsupported Arrow time unit');
            unit = (['second', 'millisecond', 'microsecond', 'nanosecond'] as const)[timeUnit];
            type = kind === 10 ? 'timestamp' : 'duration';
            if (kind === 10) timezone = fb.string(detail, 1);
            break;
        }
        case 20: type = 'large-utf8'; break;
        default: throw new Error(`Unsupported Arrow field type ${kind} on ${name}`);
    }
    if (fb.tables(table, 5).length) throw new Error('Unsupported Arrow nested field');
    const field: IpcField = { name, type, nullable: fb.boolean(table, 1), unit, timezone,
        custom_metadata: fb.metadata(table, 6), bufferIndex };
    const dictionary = fb.child(table, 4);
    if (dictionary !== undefined) {
        if (type !== 'utf8' && type !== 'large-utf8') throw new Error('Unsupported Arrow dictionary value type');
        const indexType = fb.child(dictionary, 1);
        const key = indexType === undefined ? 'int32' : intType(fb, indexType);
        if (!['int8', 'int16', 'int32', 'int64'].includes(key)) throw new Error('Unsupported Arrow dictionary key type');
        if (fb.scalar(dictionary, 3, 'i16') !== 0) throw new Error('Unsupported Arrow dictionary kind');
        const id = fb.field(dictionary, 0, 8);
        field.dictionaryId = id === undefined ? 0n : fb.i64(id);
        field.dictionaryKeyType = key as IpcField['dictionaryKeyType'];
        field.dictionaryValueType = type;
        field.dictionaryOrdered = fb.boolean(dictionary, 2);
        field.type = 'dictionary';
    }
    return field;
}
export function bufferCount(field: Pick<IpcField, 'type'>): number {
    return field.type === 'utf8' || field.type === 'large-utf8' ? 3 : 2;
}
export function physicalWidth(type: ArrowType): number {
    if (type === 'date32') return 4;
    if (type === 'timestamp' || type === 'duration') return 8;
    const match = /^(?:u?int|float)(8|16|32|64)$/.exec(type);
    if (!match) throw new Error(`Arrow type ${type} has no fixed byte width`);
    return Number(match[1]) / 8;
}
function readBatch(source: ArrowSource, block: IpcBlock, dictionary: boolean): IpcBatch {
    const raw = new FlatBuffer(source.read(block.offset, block.metadataLength));
    const continuation = raw.u32(0) === 0xffffffff;
    const prefix = continuation ? 8 : 4;
    const length = raw.i32(continuation ? 4 : 0);
    if (length <= 0 || length > block.metadataLength - prefix) throw new Error('Invalid Arrow message length');
    const fb = new FlatBuffer(raw.bytes.subarray(prefix, prefix + length));
    const message = fb.root();
    const version = fb.scalar(message, 0, 'i16');
    if (version !== 3 && version !== 4) throw new Error('Unsupported Arrow IPC metadata version');
    if (fb.scalar(message, 1, 'u8') !== (dictionary ? 2 : 3)) throw new Error('Invalid Arrow block message type');
    const bodyLength = fb.field(message, 3, 8);
    if ((bodyLength === undefined ? 0 : fb.size(bodyLength)) !== block.bodyLength) throw new Error('Invalid Arrow body length');
    let table = fb.child(message, 2, true)!;
    let dictionaryId: bigint | undefined;
    let delta: boolean | undefined;
    if (dictionary) {
        const id = fb.field(table, 0, 8);
        dictionaryId = id === undefined ? 0n : fb.i64(id);
        delta = fb.boolean(table, 2);
        table = fb.child(table, 1, true)!;
    }
    const rowsPosition = fb.field(table, 0, 8);
    const rows = rowsPosition === undefined ? 0 : fb.size(rowsPosition);
    const nodesVector = fb.vector(table, 1, 16);
    const nodes = Array.from({ length: nodesVector.length }, (_, i) => {
        const p = nodesVector.start + 16 * i;
        const length = fb.size(p), nullCount = fb.size(p + 8);
        if (length !== rows || nullCount > length) throw new Error('Invalid Arrow field node length or null count');
        return { length, nullCount };
    });
    const buffersVector = fb.vector(table, 2, 16);
    let previousEnd = 0;
    const buffers = Array.from({ length: buffersVector.length }, (_, i) => {
        const p = buffersVector.start + 16 * i;
        const offset = fb.size(p), length = fb.size(p + 8);
        if (offset < previousEnd || offset > block.bodyLength - length) throw new Error('Invalid Arrow buffer extent');
        previousEnd = offset + length;
        return { offset, length };
    });
    let compression: 0 | 1 | undefined;
    const compressionTable = fb.child(table, 3);
    if (compressionTable !== undefined) {
        const codec = fb.scalar(compressionTable, 0, 'u8');
        if ((codec !== 0 && codec !== 1) || fb.scalar(compressionTable, 1, 'u8') !== 0) {
            throw new Error('Unsupported Arrow body compression');
        }
        compression = codec;
    }
    if (fb.vector(table, 4, 8).length) throw new Error('Unsupported Arrow variadic buffers');
    return { block, rows, nodes, buffers, compression, dictionaryId, delta };
}

export function readFooter(source: ArrowSource): IpcFooter {
    safeSize(source.size, 'Arrow file size');
    if (source.size < 18 || decoder.decode(source.read(0, 6)) !== 'ARROW1') throw new Error('Not an Arrow IPC file');
    const tail = source.read(source.size - 10, 10);
    if (decoder.decode(tail.subarray(4)) !== 'ARROW1') throw new Error('Invalid Arrow file footer magic');
    const footerLength = new DataView(tail.buffer, tail.byteOffset, tail.byteLength).getUint32(0, true);
    if (!footerLength || footerLength > MAX_METADATA || footerLength > source.size - 18) throw new Error('Invalid Arrow footer length');
    const footerStart = source.size - 10 - footerLength;
    const fb = new FlatBuffer(source.read(footerStart, footerLength));
    const footer = fb.root();
    const version = fb.scalar(footer, 0, 'i16');
    if (version !== 3 && version !== 4) throw new Error('Unsupported Arrow IPC metadata version');
    const schema = fb.child(footer, 1, true)!;
    if (fb.scalar(schema, 0, 'i16') !== 0) throw new Error('Unsupported Arrow big-endian schema');
    let bufferIndex = 0;
    const fields = fb.tables(schema, 1).map(table => {
        const field = parseField(fb, table, bufferIndex);
        bufferIndex += bufferCount(field);
        return field;
    });
    const features = fb.vector(schema, 3, 8);
    for (let i = 0; i < features.length; i++) {
        const feature = fb.i64(features.start + i * 8);
        if (feature !== 0n && feature !== 1n && feature !== 2n) throw new Error('Unsupported Arrow schema feature');
    }
    const allBlocks: IpcBlock[] = [];
    const blocks = (index: number): IpcBlock[] => {
        const vector = fb.vector(footer, index, 24);
        return Array.from({ length: vector.length }, (_, i) => {
            const p = vector.start + i * 24;
            const block = { offset: fb.size(p), metadataLength: fb.i32(p + 8), bodyLength: fb.size(p + 16) };
            if (block.metadataLength < 4 || block.metadataLength > MAX_METADATA || block.offset < 8
                || block.offset > footerStart - block.metadataLength - block.bodyLength) throw new Error('Invalid Arrow block extent');
            allBlocks.push(block);
            return block;
        });
    };
    const dictionaryBlocks = blocks(2), recordBlocks = blocks(3);
    allBlocks.sort((a, b) => a.offset - b.offset);
    for (let i = 1; i < allBlocks.length; i++) {
        const last = allBlocks[i - 1];
        if (allBlocks[i].offset < last.offset + last.metadataLength + last.bodyLength) throw new Error('Invalid Arrow overlapping blocks');
    }
    const batches = recordBlocks.map(block => readBatch(source, block, false));
    const dictionaries = dictionaryBlocks.map(block => readBatch(source, block, true));
    for (const batch of batches) {
        if (batch.nodes.length !== fields.length || batch.buffers.length !== bufferIndex) throw new Error('Invalid Arrow batch layout');
        fields.forEach((field, i) => {
            if (!field.nullable && batch.nodes[i].nullCount !== 0) throw new Error('Invalid Arrow nulls in non-nullable field');
        });
    }
    let rows = 0;
    for (const batch of batches) rows = safeSize(rows + batch.rows, 'Arrow row count');
    return { fields, batches, dictionaries, rows, metadata: fb.metadata(schema, 2), customMetadata: fb.metadata(footer, 4) };
}

export function readIpcBuffer(source: ArrowSource, batch: IpcBatch, index: number, maxBytes: number, expectedLength: number): Uint8Array {
    safeSize(expectedLength, 'Arrow logical buffer length');
    if (expectedLength > maxBytes) throw new Error('Arrow decoded buffer exceeds max_buffer_bytes');
    const entry = batch.buffers[index];
    if (!entry) throw new Error('Invalid Arrow missing buffer');
    if (entry.length > maxBytes) throw new Error('Arrow stored buffer exceeds max_buffer_bytes');
    if (batch.compression === undefined && entry.length !== expectedLength) throw new Error('Invalid Arrow buffer length does not match field layout');
    if (!entry.length && !expectedLength) return new Uint8Array();
    const raw = source.read(batch.block.offset + batch.block.metadataLength + entry.offset, entry.length);
    if (batch.compression === undefined) return raw;
    if (raw.length < 8) throw new Error('Invalid Arrow compressed buffer prefix');
    const expected = new DataView(raw.buffer, raw.byteOffset, raw.byteLength).getBigInt64(0, true);
    if (expected === -1n) {
        if (raw.length - 8 !== expectedLength) throw new Error('Invalid Arrow uncompressed buffer length');
        return raw.subarray(8);
    }
    if (expected < 0n || expected > BigInt(maxBytes)) throw new Error('Arrow decoded buffer exceeds max_buffer_bytes');
    if (expected !== BigInt(expectedLength)) throw new Error('Invalid Arrow declared decompressed buffer length');
    return decodeArrowBuffer(batch.compression, raw.subarray(8), Number(expected));
}
