import { canonicalBufferHashes } from './arrow-checksum';
import { bufferCount, physicalWidth, readFooter, readIpcBuffer, safeSize,
    type ArrowSource, type IpcBatch, type IpcField, type IpcFooter } from './arrow-ipc';
import { ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY, ARROW_FIELD_KEY, ARROW_PROFILE_VERSION_KEY,
    classifyProfileMissing, parseProfileJson, validateChecksumsDocument, validateDatasetDocument,
    validateFieldDocument, validateProfileVersion, validateValueLabelReference,
    type ArrowFieldDocument, type ChecksumsDocument, type DatasetDocument } from './arrow-profile';
import type { ArrowCell, ArrowDictionary, ArrowMetadata, ArrowOpenOptions, ArrowReadOptions,
    ArrowRow, ArrowType, ArrowVariable } from './arrow-types';

interface DecodedArray {
    length: number;
    type: ArrowType;
    validity?: Uint8Array;
    buffers: Uint8Array[];
    cell(index: number, profile?: ArrowFieldDocument): ArrowCell;
}
interface SelectionProfile {
    fields: Map<number, ArrowFieldDocument>;
    dataset?: DatasetDocument;
    checksums?: ChecksumsDocument;
}
const textDecoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
function bit(bytes: Uint8Array, index: number): boolean { return (bytes[index >> 3] & (1 << (index & 7))) !== 0; }
export function abortArrowRead(signal?: AbortSignal): void {
    if (signal?.aborted) throw new DOMException('The Arrow read was aborted', 'AbortError');
}
function clone<T>(value: T): T { return structuredClone(value); }
function verifyHashes(actual: string[], expected: string[] | undefined, field: string): void {
    if (!expected || expected.length !== actual.length) throw new Error(`Malformed Arrow profile: missing buffer checksums for ${field}`);
    if (expected.some(hash => !/^[0-9a-fA-F]{16}$/.test(hash))) throw new Error('Malformed Arrow profile: invalid checksum');
    if (actual.some((hash, i) => hash !== expected[i].toLowerCase())) throw new Error(`Arrow checksum mismatch for ${field}`);
}
function hashes(array: DecodedArray, field: IpcField): string[] {
    return canonicalBufferHashes({ type: array.type, length: array.length,
        validity: array.validity, buffers: array.buffers, dictionaryKeyType: field.dictionaryKeyType });
}

/** Shared synchronous byte reader; the Node adapter yields between decoded chunks. */
export class ArrowReader {
    private readonly footer: IpcFooter;
    private readonly applyProfile: boolean;
    private readonly verify: boolean;
    private readonly maxBytes: number;
    private readonly maxRows?: number;
    private readonly dictionaryCache = new Map<bigint, DecodedArray>();
    private readonly profileVersion?: string;
    constructor(private readonly source: ArrowSource, options: ArrowOpenOptions = {}) {
        for (const key of ['profile', 'verify'] as const) {
            if (options[key] !== undefined && typeof options[key] !== 'boolean') throw new Error(`${key} must be a boolean`);
        }
        this.maxBytes = safeSize(options.max_buffer_bytes ?? 256 * 1024 * 1024, 'max_buffer_bytes');
        if (!this.maxBytes) throw new Error('max_buffer_bytes must be positive');
        this.maxRows = options.max_output_rows === undefined ? undefined : safeSize(options.max_output_rows, 'max_output_rows');
        this.applyProfile = options.profile !== false;
        this.verify = options.verify !== false && this.applyProfile;
        this.footer = readFooter(source);
        if (this.applyProfile) {
            this.profileVersion = this.footer.metadata.get(ARROW_PROFILE_VERSION_KEY);
            if (this.profileVersion !== undefined) validateProfileVersion(this.profileVersion);
        }
    }
    get nobs(): number { return this.footer.rows; }
    get nvar(): number { return this.footer.fields.length; }
    private allIndices(): number[] { return this.footer.fields.map((_, i) => i); }
    private selectionProfile(indices: number[]): SelectionProfile {
        const result: SelectionProfile = { fields: new Map() };
        if (this.profileVersion === undefined) return result;
        const references = new Set<string>();
        for (const index of indices) {
            const field = this.footer.fields[index];
            const raw = field.custom_metadata.get(ARROW_FIELD_KEY);
            if (raw === undefined) continue;
            const document = validateFieldDocument(parseProfileJson(raw), field);
            result.fields.set(index, document);
            if (document.value_labels !== undefined) references.add(document.value_labels);
        }
        const datasetRaw = this.footer.metadata.get(ARROW_DATASET_KEY);
        result.dataset = validateDatasetDocument(datasetRaw === undefined ? undefined : parseProfileJson(datasetRaw),
            indices.length === this.nvar ? undefined : references);
        for (const [index, document] of result.fields) validateValueLabelReference(this.footer.fields[index], document, result.dataset);
        if (this.verify) {
            const raw = this.footer.customMetadata.get(ARROW_CHECKSUMS_KEY);
            if (raw === undefined) throw new Error('Malformed Arrow profile: missing checksums document');
            result.checksums = validateChecksumsDocument(parseProfileJson(raw));
            if (result.checksums.batches.length !== this.footer.batches.length) throw new Error('Malformed Arrow profile: checksum batch count mismatch');
        }
        return result;
    }
    /** Accessing complete metadata consumes every profile field document. */
    get metadata(): ArrowMetadata {
        const profile = this.selectionProfile(this.allIndices());
        const variables: ArrowVariable[] = this.footer.fields.map((field, index) => {
            const { bufferIndex: _, dictionaryId: __, ...variable } = field;
            const copy = clone(variable);
            if (profile.fields.has(index)) copy.profile = clone(profile.fields.get(index)!);
            if (field.type === 'date32') copy.epoch = '1970-01-01';
            if (field.type === 'timestamp') copy.epoch = field.timezone ? '1970-01-01T00:00:00Z' : '1970-01-01T00:00:00';
            const semantics = copy.profile?.r;
            if (semantics?.class === 'Date') copy.temporal_semantics = { unit: 'days', epoch: '1970-01-01' };
            if (semantics?.class === 'POSIXct') copy.temporal_semantics = { unit: 'secs', epoch: '1970-01-01T00:00:00Z', timezone: semantics.tz };
            if (semantics?.class === 'difftime') copy.temporal_semantics = { unit: semantics.units ?? 'secs' };
            if (!this.applyProfile) copy.custom_metadata.delete(ARROW_FIELD_KEY);
            return copy;
        });
        const custom_metadata = new Map(this.footer.metadata), footer_metadata = new Map(this.footer.customMetadata);
        if (!this.applyProfile) {
            custom_metadata.delete(ARROW_PROFILE_VERSION_KEY);
            custom_metadata.delete(ARROW_DATASET_KEY);
            footer_metadata.delete(ARROW_CHECKSUMS_KEY);
        }
        return { nobs: this.nobs, nvar: this.nvar, profile_version: this.profileVersion,
            dataset: clone(profile.dataset), variables, custom_metadata, footer_metadata };
    }
    get variables(): ArrowVariable[] { return this.metadata.variables; }
    normalizeColumns(indices: readonly number[]): number[] {
        const output: number[] = [], seen = new Set<number>();
        for (const index of indices) {
            safeSize(index, 'Arrow column index');
            if (index >= this.nvar) throw new Error(`Arrow column index ${index} is out of bounds`);
            if (!seen.has(index)) { seen.add(index); output.push(index); }
        }
        return output;
    }
    rowColumns(start = 0, end = this.nvar): number[] {
        safeSize(start, 'col_start'); safeSize(end, 'col_end');
        if (start > end || end > this.nvar) throw new Error('Arrow column range is out of bounds');
        return Array.from({ length: end - start }, (_, i) => start + i);
    }
    window(start: number, count: number): { start: number; count: number } {
        safeSize(start, 'Arrow row start'); safeSize(count, 'Arrow row count');
        const actual = Math.min(count, Math.max(0, this.nobs - start));
        if (this.maxRows !== undefined && actual > this.maxRows) throw new Error('Arrow selection exceeds max_output_rows');
        if (actual > 0xffffffff) throw new Error('Arrow selection exceeds JavaScript array capacity');
        return { start: Math.min(start, this.nobs), count: actual };
    }
    private loadArray(batch: IpcBatch, field: IpcField, nodeIndex: number): DecodedArray {
        const node = batch.nodes[nodeIndex];
        if (!node || batch.buffers.length < field.bufferIndex + bufferCount(field)) throw new Error('Invalid Arrow array layout');
        const read = (index: number, expected: number): Uint8Array => readIpcBuffer(this.source, batch, field.bufferIndex + index, this.maxBytes, expected);
        const validity = node.nullCount ? read(0, Math.ceil(node.length / 8)) : undefined;
        if (validity && validity.length < Math.ceil(node.length / 8)) throw new Error('Invalid Arrow validity bitmap length');
        if (validity) {
            let count = 0;
            for (let i = 0; i < node.length; i++) if (!bit(validity, i)) count++;
            if (count !== node.nullCount) throw new Error('Invalid Arrow validity bitmap null count');
        }
        const type = field.type;
        const stringWidth = type === 'utf8' ? 4 : type === 'large-utf8' ? 8 : 0;
        const firstLength = stringWidth ? (node.length + 1) * stringWidth : type === 'bool'
            ? Math.ceil(node.length / 8) : node.length * physicalWidth(type === 'dictionary' ? field.dictionaryKeyType! : type);
        const buffers = [read(1, firstLength)];
        if (stringWidth) {
            const offsets = new DataView(buffers[0].buffer, buffers[0].byteOffset, buffers[0].byteLength);
            const last = stringWidth === 4 ? BigInt(offsets.getInt32(node.length * 4, true)) : offsets.getBigInt64(node.length * 8, true);
            if (last < 0n || last > BigInt(this.maxBytes)) throw new Error('Invalid Arrow string data length exceeds max_buffer_bytes');
            buffers.push(read(2, Number(last)));
        }
        const data = buffers[0];
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
        let value: (index: number, profile?: ArrowFieldDocument) => ArrowCell;
        if (type === 'utf8' || type === 'large-utf8') {
            const width = type === 'utf8' ? 4 : 8;
            if (data.length < (node.length + 1) * width) throw new Error('Invalid Arrow string offsets length');
            const stringData = buffers[1];
            const offset = (i: number): number => {
                const position = width === 4 ? BigInt(view.getInt32(i * width, true)) : view.getBigInt64(i * width, true);
                if (position < 0n || position > BigInt(stringData.length)) throw new Error('Invalid Arrow string offset');
                return Number(position);
            };
            let previous = offset(0);
            for (let i = 1; i <= node.length; i++) {
                const current = offset(i);
                if (current < previous) throw new Error('Invalid Arrow decreasing string offsets');
                // Validate every string, even outside the requested row window.
                textDecoder.decode(stringData.subarray(previous, current));
                previous = current;
            }
            value = i => textDecoder.decode(stringData.subarray(offset(i), offset(i + 1)));
        } else if (type === 'bool') {
            if (data.length < Math.ceil(node.length / 8)) throw new Error('Invalid Arrow boolean buffer length');
            value = i => bit(data, i);
        } else {
            const physical = type === 'dictionary' ? field.dictionaryKeyType! : type;
            const width = physicalWidth(physical);
            if (data.length < node.length * width) throw new Error('Invalid Arrow value buffer length');
            const getters: Partial<Record<ArrowType, (p: number) => number | bigint>> = {
                int8: p => view.getInt8(p), uint8: p => view.getUint8(p),
                int16: p => view.getInt16(p, true), uint16: p => view.getUint16(p, true),
                int32: p => view.getInt32(p, true), uint32: p => view.getUint32(p, true),
                int64: p => view.getBigInt64(p, true), uint64: p => view.getBigUint64(p, true),
                float32: p => view.getFloat32(p, true), float64: p => view.getFloat64(p, true),
                date32: p => view.getInt32(p, true), timestamp: p => view.getBigInt64(p, true), duration: p => view.getBigInt64(p, true),
            };
            value = (i, profile) => {
                const p = i * width;
                if (profile) {
                    const missing = classifyProfileMissing(data, p, profile);
                    if (missing) return missing;
                }
                return getters[physical]!(p);
            };
        }
        return { type, length: node.length, validity, buffers,
            cell: (i, profile) => validity && !bit(validity, i) ? null : value(i, profile) };
    }
    private dictionary(field: IpcField): DecodedArray {
        const id = field.dictionaryId!;
        const cached = this.dictionaryCache.get(id);
        if (cached) return cached;
        const sourceFields = this.footer.fields.filter(other => other.dictionaryId === id);
        if (sourceFields.some(other => other.dictionaryValueType !== field.dictionaryValueType)) throw new Error('Invalid Arrow dictionary has conflicting value types');
        const chunks: DecodedArray[] = [];
        for (const batch of this.footer.dictionaries) {
            if (batch.dictionaryId !== id) continue;
            if (batch.nodes.length !== 1 || batch.buffers.length !== 3) throw new Error('Invalid Arrow dictionary batch layout');
            if (batch.delta && !chunks.length) throw new Error('Invalid Arrow delta dictionary has no preceding dictionary');
            if (!batch.delta) chunks.length = 0;
            chunks.push(this.loadArray(batch, { ...field, type: field.dictionaryValueType!, bufferIndex: 0 }, 0));
        }
        if (!chunks.length) throw new Error(`Invalid Arrow missing dictionary ${id}`);
        let result: DecodedArray;
        if (chunks.length === 1) result = chunks[0];
        else {
            // Arrow file dictionaries use the complete dictionary after all deltas.
            const length = chunks.reduce((sum, chunk) => safeSize(sum + chunk.length, 'Arrow dictionary length'), 0);
            const width = field.dictionaryValueType === 'utf8' ? 4 : 8;
            const bytes = chunks.reduce((sum, chunk) => sum + chunk.buffers[1].length, 0);
            if (bytes > this.maxBytes || (length + 1) * width > this.maxBytes) throw new Error('Arrow dictionary exceeds max_buffer_bytes');
            const offsets = new Uint8Array((length + 1) * width), strings = new Uint8Array(bytes), validity = new Uint8Array(Math.ceil(length / 8));
            const offsetView = new DataView(offsets.buffer);
            const levels: Array<string | null> = [];
            const encoder = new TextEncoder();
            let position = 0, nulls = false;
            for (const chunk of chunks) for (let i = 0; i < chunk.length; i++) {
                const cell = chunk.cell(i) as string | null, index = levels.length;
                levels.push(cell);
                if (cell !== null) { validity[index >> 3] |= 1 << (index & 7); const encoded = encoder.encode(cell); strings.set(encoded, position); position += encoded.length; }
                else nulls = true;
                if (width === 4) offsetView.setInt32((index + 1) * width, position, true);
                else offsetView.setBigInt64((index + 1) * width, BigInt(position), true);
            }
            result = { type: field.dictionaryValueType!, length, validity: nulls ? validity : undefined,
                buffers: [offsets, strings.subarray(0, position)], cell: i => levels[i] };
        }
        this.dictionaryCache.set(id, result);
        return result;
    }
    get_dictionary(index: number): ArrowDictionary | undefined {
        this.normalizeColumns([index]);
        const field = this.footer.fields[index];
        if (field.dictionaryId === undefined) return undefined;
        const profile = this.selectionProfile([index]);
        const array = this.dictionary(field);
        if (profile.checksums) verifyHashes(hashes(array, field), profile.checksums.dictionaries[String(index)], field.name);
        if (array.length > 0xffffffff) throw new Error('Arrow dictionary exceeds JavaScript array capacity');
        return { ordered: profile.fields.get(index)?.r?.ordered ?? field.dictionaryOrdered ?? false,
            levels: Array.from({ length: array.length }, (_, i) => array.cell(i) as string | null) };
    }
    get dictionaries(): Map<number, ArrowDictionary> {
        const result = new Map<number, ArrowDictionary>();
        for (const index of this.allIndices()) {
            const dictionary = this.get_dictionary(index);
            if (dictionary) result.set(index, dictionary);
        }
        return result;
    }
    *chunks(indices: number[], start: number, count: number, options: ArrowReadOptions = {}): Generator<Map<number, ArrowCell[]>> {
        abortArrowRead(options.signal);
        const selected = this.normalizeColumns(indices), window = this.window(start, count);
        const chunkRows = safeSize(options.chunk_rows ?? 65536, 'chunk_rows');
        if (!chunkRows) throw new Error('chunk_rows must be positive');
        const profile = this.selectionProfile(selected);
        const dictionaries = new Map<number, DecodedArray>();
        for (const index of selected) {
            abortArrowRead(options.signal);
            const field = this.footer.fields[index];
            if (field.dictionaryId !== undefined) {
                const dictionary = this.dictionary(field);
                if (profile.checksums) verifyHashes(hashes(dictionary, field), profile.checksums.dictionaries[String(index)], field.name);
                dictionaries.set(index, dictionary);
            }
        }
        let batchStart = 0;
        for (let batchIndex = 0; batchIndex < this.footer.batches.length; batchIndex++) {
            const batch = this.footer.batches[batchIndex];
            const first = Math.max(window.start - batchStart, 0);
            const last = Math.min(window.start + window.count - batchStart, batch.rows);
            batchStart += batch.rows;
            if (first >= last) continue;
            const arrays = new Map<number, DecodedArray>();
            for (const index of selected) {
                abortArrowRead(options.signal);
                const field = this.footer.fields[index];
                const array = this.loadArray(batch, field, index);
                if (profile.checksums) verifyHashes(hashes(array, field), profile.checksums.batches[batchIndex]?.columns[index], `${field.name}, batch ${batchIndex}`);
                const dictionary = dictionaries.get(index);
                if (dictionary) for (let row = 0; row < array.length; row++) {
                    const code = array.cell(row);
                    if (code !== null && (BigInt(code as number | bigint) < 0n || BigInt(code as number | bigint) >= BigInt(dictionary.length))) throw new Error('Invalid Arrow dictionary index');
                }
                arrays.set(index, array);
            }
            for (let offset = first; offset < last; offset += chunkRows) {
                abortArrowRead(options.signal);
                const length = Math.min(last - offset, chunkRows), result = new Map<number, ArrowCell[]>();
                for (const index of selected) result.set(index, Array.from({ length }, (_, i) => arrays.get(index)!.cell(offset + i, profile.fields.get(index))));
                yield result;
            }
        }
    }
}

/** Synchronous reader for complete Arrow IPC file bytes, including compressed files. */
export class ArrowBuffer {
    private constructor(private readonly reader: ArrowReader) {}
    static open(buffer: ArrayBuffer | Uint8Array, options: ArrowOpenOptions = {}): ArrowBuffer {
        const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
        const source: ArrowSource = { size: bytes.byteLength, read(offset, length) {
            safeSize(offset, 'Arrow read offset'); safeSize(length, 'Arrow read length');
            if (offset > bytes.length - length) throw new Error('Unexpected EOF reading Arrow buffer');
            return bytes.subarray(offset, offset + length);
        } };
        return new ArrowBuffer(new ArrowReader(source, options));
    }
    get nobs(): number { return this.reader.nobs; }
    get nvar(): number { return this.reader.nvar; }
    get metadata(): ArrowMetadata { return this.reader.metadata; }
    get variables(): ArrowVariable[] { return this.reader.variables; }
    get dictionaries(): Map<number, ArrowDictionary> { return this.reader.dictionaries; }
    get_dictionary(index: number): ArrowDictionary | undefined { return this.reader.get_dictionary(index); }
    read_rows(start: number, count: number, col_start = 0, col_end = this.nvar, options: ArrowReadOptions = {}): ArrowRow[] {
        const columns = this.reader.rowColumns(col_start, col_end), window = this.reader.window(start, count);
        const rows: ArrowRow[] = [];
        for (const chunk of this.reader.chunks(columns, start, count, options)) {
            const length = columns.length ? chunk.get(columns[0])!.length : 0;
            for (let i = 0; i < length; i++) rows.push(columns.map(index => chunk.get(index)![i]));
        }
        if (!columns.length) return Array.from({ length: window.count }, () => []);
        return rows;
    }
    read_columns(indices: number[], options: ArrowReadOptions = {}): Map<number, ArrowCell[]> {
        const columns = this.reader.normalizeColumns(indices), result = new Map(columns.map(index => [index, [] as ArrowCell[]]));
        for (const chunk of this.reader.chunks(columns, 0, this.nobs, options)) {
            for (const index of columns) for (const cell of chunk.get(index)!) result.get(index)!.push(cell);
        }
        return result;
    }
}
