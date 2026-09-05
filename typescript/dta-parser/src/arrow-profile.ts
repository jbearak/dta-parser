import type { FormatVersion, MissingType, MissingValue, StataCharacteristic, StataNote } from './types';
import { byte_missing_offset, int_missing_offset, long_missing_offset, float_missing_offset,
    classify_raw_double_missing_at, make_missing_value, missing_value_from_offset } from './missing-values';
import { listStataCharacteristics, listStataNotes } from './stata-metadata';

export const ARROW_PROFILE_VERSION = '0';
export const ARROW_PROFILE_VERSION_KEY = 'dtatools:profile-version';
export const ARROW_DATASET_KEY = 'dtatools:dataset';
export const ARROW_FIELD_KEY = 'dtatools:field';
export const ARROW_CHECKSUMS_KEY = 'dtatools:checksums';

export interface ArrowValueLabelEntry { value?: number; tag?: MissingType; label: string }
export interface DatasetDocument {
    version: number;
    output_container?: string;
    label: string;
    notes: StataNote[];
    characteristics: StataCharacteristic[];
    value_labels: Record<string, ArrowValueLabelEntry[]>;
}
export type StataStorage = 'byte' | 'int' | 'long' | 'float' | 'double';
export interface ArrowRSemantics { class: string; ordered?: boolean; tz?: string; units?: string }
export interface ArrowFieldDocument {
    version: number;
    label: string;
    format: string;
    notes: StataNote[];
    characteristics: StataCharacteristic[];
    storage?: StataStorage;
    string_storage?: string;
    value_labels?: string;
    missing?: 'sentinel' | 'payload';
    missing_release?: FormatVersion;
    r?: ArrowRSemantics;
}
export interface ProfileFieldDescriptor {
    name: string;
    type: string;
    nullable: boolean;
    dictionaryKeyType?: string;
    dictionaryValueType?: string;
}
export interface BatchChecksums { columns: string[][] }
export interface ChecksumsDocument {
    version: number;
    algorithm: string;
    batches: BatchChecksums[];
    dictionaries: Record<string, string[]>;
}

function malformed(detail: string): never {
    throw new Error(`Malformed Arrow profile: ${detail}`);
}
export function validateProfileVersion(version: string): void {
    if (version !== ARROW_PROFILE_VERSION) throw new Error(`Unsupported Arrow profile version ${version}`);
}

/** JSON.parse accepts duplicate keys. Profile documents require unique decoded keys. */
export function parseProfileJson(json: string): unknown {
    let cursor = 0;
    const whitespace = (): void => { while (/[\t\n\r ]/.test(json[cursor] ?? '') && cursor < json.length) cursor++; };
    const string = (): string => {
        const start = cursor++;
        while (cursor < json.length) {
            const character = json[cursor++];
            if (character === '\\') cursor++;
            else if (character === '"') {
                let decoded: string;
                try { decoded = JSON.parse(json.slice(start, cursor)) as string; }
                catch { return malformed('invalid JSON string'); }
                // JSON.parse retains lone UTF-16 surrogates; Rust JSON strings
                // require Unicode scalar values, including in object keys.
                for (let index = 0; index < decoded.length; index++) {
                    const code = decoded.charCodeAt(index);
                    if (code >= 0xd800 && code <= 0xdbff) {
                        const low = decoded.charCodeAt(++index);
                        if (!(low >= 0xdc00 && low <= 0xdfff)) malformed('unpaired JSON surrogate');
                    } else if (code >= 0xdc00 && code <= 0xdfff) {
                        malformed('unpaired JSON surrogate');
                    }
                }
                return decoded;
            }
        }
        return malformed('unterminated JSON string');
    };
    const value = (depth: number): unknown => {
        if (depth > 128) malformed('JSON nesting exceeds the profile limit');
        whitespace();
        if (json[cursor] === '"') return string();
        if (json[cursor] === '{') {
            cursor++;
            const object: Record<string, unknown> = Object.create(null);
            whitespace();
            if (json[cursor] === '}') { cursor++; return object; }
            while (cursor < json.length) {
                whitespace();
                if (json[cursor] !== '"') malformed('expected JSON object key');
                const key = string();
                if (Object.hasOwn(object, key)) malformed(`duplicate JSON key ${key}`);
                whitespace();
                if (json[cursor++] !== ':') malformed('expected JSON colon');
                object[key] = value(depth + 1);
                whitespace();
                const delimiter = json[cursor++];
                if (delimiter === '}') return object;
                if (delimiter !== ',') malformed('expected JSON object delimiter');
            }
            return malformed('unterminated JSON object');
        }
        if (json[cursor] === '[') {
            cursor++;
            const array: unknown[] = [];
            whitespace();
            if (json[cursor] === ']') { cursor++; return array; }
            while (cursor < json.length) {
                array.push(value(depth + 1));
                whitespace();
                const delimiter = json[cursor++];
                if (delimiter === ']') return array;
                if (delimiter !== ',') malformed('expected JSON array delimiter');
            }
            return malformed('unterminated JSON array');
        }
        const start = cursor;
        while (cursor < json.length && !/[\s,\]}]/.test(json[cursor])) cursor++;
        try { return JSON.parse(json.slice(start, cursor)); }
        catch { return malformed('invalid JSON value'); }
    };
    const result = value(0);
    whitespace();
    if (cursor !== json.length) malformed('trailing JSON content');
    return result;
}

function object(raw: unknown, keys?: readonly string[]): Record<string, unknown> {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) malformed('expected an object');
    const result = raw as Record<string, unknown>;
    if (keys) for (const key of Object.keys(result)) {
        if (!keys.includes(key)) malformed(`unknown field ${key}`);
    }
    return result;
}
function text(raw: unknown, context: string): string {
    if (typeof raw !== 'string') malformed(`${context} must be a string`);
    return raw;
}
function optionalText(raw: unknown, context: string): string | undefined {
    return raw === undefined || raw === null ? undefined : text(raw, context);
}
function array(raw: unknown, context: string): unknown[] {
    if (!Array.isArray(raw)) malformed(`${context} must be an array`);
    return raw;
}
function version(raw: unknown, context: string): number {
    if (raw !== 0) malformed(`${context} document version ${String(raw)}`);
    return 0;
}
function metadata(raw: Record<string, unknown>): { notes: StataNote[]; characteristics: StataCharacteristic[] } {
    const notes = array(raw.notes === undefined ? [] : raw.notes, 'notes');
    if (notes.length > 9999) malformed('notes may contain at most 9,999 entries');
    let previous = 0;
    const normalized = notes.map((entry, index) => {
        const note = typeof entry === 'string' ? { number: index + 1, text: entry }
            : object(entry, ['number', 'text']);
        if (typeof note.number !== 'number' || !Number.isInteger(note.number)
            || note.number <= previous || note.number > 9999) {
            malformed('notes require unique ascending numbers from 1 through 9999');
        }
        previous = note.number;
        return { number: note.number, text: text(note.text, 'note text') };
    });
    const characteristics = array(raw.characteristics === undefined ? [] : raw.characteristics, 'characteristics').map(entry => {
        const characteristic = object(entry, ['name', 'value']);
        return { name: text(characteristic.name, 'characteristic name'), value: text(characteristic.value, 'characteristic value') };
    });
    try {
        return { notes: listStataNotes({ notes: normalized }), characteristics: listStataCharacteristics({ characteristics }) };
    } catch (error) {
        return malformed(error instanceof Error ? error.message : 'invalid Stata metadata');
    }
}

/** Validate all registry entries, retaining only requested tables on a projection. */
export function validateDatasetDocument(raw: unknown, selectedValueLabels?: ReadonlySet<string>): DatasetDocument {
    const document = object(raw === undefined ? { version: 0 } : raw,
        ['version', 'output_container', 'label', 'notes', 'characteristics', 'value_labels']);
    const output_container = optionalText(document.output_container, 'output_container');
    if (output_container !== undefined && (!output_container || output_container.trim() !== output_container)) {
        malformed('output_container must be a nonempty name without surrounding whitespace');
    }
    const registry = object(document.value_labels ?? {});
    const names = Object.keys(registry);
    if (names.length > 120_000) malformed('value-label registry may contain at most 120,000 tables');
    const value_labels: Record<string, ArrowValueLabelEntry[]> = Object.create(null);
    for (const name of names) {
        const entries = array(registry[name], 'value-label table').map(rawEntry => {
            const entry = object(rawEntry, ['value', 'tag', 'label']);
            const value = entry.value ?? undefined;
            const tag = entry.tag ?? undefined;
            if ((value === undefined) === (tag === undefined)) malformed('value-label entry must contain exactly one of value or tag');
            if (value !== undefined && (typeof value !== 'number' || !Number.isInteger(value)
                || value < -2147483648 || value > 2147483647)) malformed('value-label value must be an int32');
            if (tag !== undefined && (typeof tag !== 'string' || !/^\.[a-z]$/.test(tag))) {
                malformed('value-label tag must be extended missing .a through .z');
            }
            return { ...(value !== undefined ? { value: value as number } : { tag: tag as MissingType }), label: text(entry.label, 'value-label label') };
        });
        if (selectedValueLabels === undefined || selectedValueLabels.has(name)) value_labels[name] = entries;
    }
    return { version: version(document.version, 'dataset'), ...(output_container !== undefined ? { output_container } : {}),
        label: document.label === undefined ? '' : text(document.label, 'label'), ...metadata(document), value_labels };
}

const STORAGE_TYPES = { byte: 'int8', int: 'int16', long: 'int32', float: 'float32', double: 'float64' } as const;
const DOUBLE_TYPES = ['float32', 'float64', 'int64', 'uint16', 'uint32', 'uint64'];

export function validateFieldDocument(raw: unknown, field: ProfileFieldDescriptor): ArrowFieldDocument {
    const source = object(raw, ['version', 'label', 'format', 'notes', 'characteristics', 'storage',
        'string_storage', 'value_labels', 'missing', 'missing_release', 'r']);
    const fail = (message: string): never => malformed(`field ${field.name} ${message}`);
    const storage = optionalText(source.storage, 'storage');
    if (storage !== undefined && !Object.hasOwn(STORAGE_TYPES, storage)) fail('declares invalid Stata storage');
    const missing = optionalText(source.missing, 'missing');
    if (missing !== undefined && missing !== 'sentinel' && missing !== 'payload') fail('declares invalid missing encoding');
    const missing_release = source.missing_release ?? undefined;
    if (missing_release !== undefined && ![105, 108, 110, 111, 113, 114, 115, 117, 118, 119].includes(missing_release as number)) {
        fail('declares invalid missing_release');
    }
    let r: ArrowRSemantics | undefined;
    if (source.r !== undefined && source.r !== null) {
        const semantics = object(source.r, ['class', 'ordered', 'tz', 'units']);
        if (semantics.ordered !== undefined && semantics.ordered !== null && typeof semantics.ordered !== 'boolean') fail('r.ordered must be boolean');
        r = { class: text(semantics.class, 'r.class'),
            ...(semantics.ordered != null ? { ordered: semantics.ordered as boolean } : {}),
            ...(semantics.tz != null ? { tz: text(semantics.tz, 'r.tz') } : {}),
            ...(semantics.units != null ? { units: text(semantics.units, 'r.units') } : {}) };
    }
    const document: ArrowFieldDocument = {
        version: version(source.version, 'field'), label: source.label === undefined ? '' : text(source.label, 'label'),
        format: source.format === undefined ? '' : text(source.format, 'format'), ...metadata(source),
        ...(storage !== undefined ? { storage: storage as StataStorage } : {}),
        ...(missing !== undefined ? { missing: missing as 'sentinel' | 'payload' } : {}),
        ...(missing_release !== undefined ? { missing_release: missing_release as FormatVersion } : {}),
        ...(r !== undefined ? { r } : {}),
    };
    const stringStorage = optionalText(source.string_storage, 'string_storage');
    const valueLabels = optionalText(source.value_labels, 'value_labels');
    if (stringStorage !== undefined) {
        document.string_storage = stringStorage;
        if (stringStorage !== 'strL' && (!/^str[1-9][0-9]*$/.test(stringStorage) || Number(stringStorage.slice(3)) > 2045)) fail('declares invalid string storage');
        if (storage !== undefined || field.type !== 'utf8') fail('declares string storage incompatible with Arrow type');
    }
    if (valueLabels !== undefined) document.value_labels = valueLabels;
    if (storage !== undefined) {
        if (field.type !== STORAGE_TYPES[storage as StataStorage]) fail('declares Stata storage incompatible with Arrow type');
        if (missing !== (storage === 'float' || storage === 'double' ? 'payload' : 'sentinel')) fail('declares missing encoding incompatible with Stata storage');
        if (missing_release !== undefined && storage === 'double') fail('declares source missing release for double storage');
        if (field.nullable) fail('declares raw Stata missing storage on a nullable field');
        if (r && (r.class !== 'stata_numeric' || r.ordered !== undefined || r.tz !== undefined || r.units !== undefined)) fail('declares R semantics incompatible with Stata storage');
        return document;
    }
    if (missing_release !== undefined) fail('declares source missing release without Stata storage');
    if (missing === 'sentinel') fail('declares sentinel encoding without Stata storage');
    if (missing === 'payload' && (field.type !== 'float64' || field.nullable
        || !r || !['double', 'haven_labelled', 'Date', 'POSIXct', 'difftime'].includes(r.class))) fail('declares incompatible payload missing semantics');
    if (r) {
        const compatible: Record<string, boolean> = {
            logical: field.type === 'bool', integer: ['int8', 'int16', 'int32', 'uint8'].includes(field.type),
            double: DOUBLE_TYPES.includes(field.type), character: ['utf8', 'large-utf8'].includes(field.type),
            factor: field.type === 'dictionary' && field.dictionaryKeyType === 'int32' && ['utf8', 'large-utf8'].includes(field.dictionaryValueType ?? ''),
            raw: field.type === 'uint8', Date: ['date32', 'float64'].includes(field.type),
            POSIXct: ['timestamp', 'float64'].includes(field.type), difftime: ['duration', 'float64'].includes(field.type),
            haven_labelled: field.type === 'float64',
        };
        if (!Object.hasOwn(compatible, r.class) || !compatible[r.class]) fail(`declares unsupported or incompatible R class ${r.class}`);
        if (r.ordered !== undefined && r.class !== 'factor') fail('declares r.ordered without factor semantics');
        if (r.tz !== undefined && r.class !== 'POSIXct') fail('declares r.tz without POSIXct semantics');
        if (r.units !== undefined && (r.class !== 'difftime' || !['secs', 'mins', 'hours', 'days', 'weeks'].includes(r.units))) fail('declares unsupported difftime units');
    }
    if (valueLabels !== undefined && ![...DOUBLE_TYPES, 'date32', 'timestamp', 'duration'].includes(field.type)) fail('declares value labels incompatible with Arrow type');
    return document;
}

export function validateValueLabelReference(field: ProfileFieldDescriptor, document: ArrowFieldDocument, dataset: DatasetDocument): void {
    if (document.value_labels !== undefined && !Object.hasOwn(dataset.value_labels, document.value_labels)) {
        malformed(`field ${field.name} refers to missing value-label table ${document.value_labels}`);
    }
}

export function validateChecksumsDocument(raw: unknown): ChecksumsDocument {
    const document = object(raw, ['version', 'algorithm', 'batches', 'dictionaries']);
    if (document.algorithm !== 'xxh64') malformed('unknown checksum algorithm');
    const hashes = (rawHashes: unknown): string[] => array(rawHashes, 'checksums').map(hash => text(hash, 'checksum'));
    const batches = array(document.batches, 'checksum batches').map(rawBatch => {
        const batch = object(rawBatch, ['columns']);
        return { columns: array(batch.columns, 'checksum columns').map(hashes) };
    });
    const dictionaries: Record<string, string[]> = Object.create(null);
    const registry = object(document.dictionaries === undefined ? {} : document.dictionaries);
    for (const name of Object.keys(registry)) dictionaries[name] = hashes(registry[name]);
    return { version: version(document.version, 'checksums'), algorithm: 'xxh64', batches, dictionaries };
}

/** Inspect stored bits before converting floats to JavaScript numbers. */
export function classifyProfileMissing(bytes: Uint8Array, offset: number, document: ArrowFieldDocument): MissingValue | null {
    if (document.missing === undefined) return null;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const modern = (document.missing_release ?? 118) >= 113;
    let code = -1;
    switch (document.storage) {
        case 'byte': code = byte_missing_offset(view.getInt8(offset), modern); break;
        case 'int': code = int_missing_offset(view.getInt16(offset, true), modern); break;
        case 'long': code = long_missing_offset(view.getInt32(offset, true), modern); break;
        case 'float': code = float_missing_offset(view.getUint32(offset, true), modern); break;
        case 'double': {
            const tag = classify_raw_double_missing_at(view, offset, true);
            return tag === null ? null : make_missing_value(tag);
        }
        default: {
            // R NA and haven tags tolerate the sign and quiet-NaN bits.
            const bits = view.getBigUint64(offset, true);
            const ignored = 0x800800ff00000000n;
            const mask = 0xffffffffffffffffn ^ ignored;
            if ((bits & mask) !== (0x7ff00000000007a2n & mask)) return null;
            const tag = Number((bits >> 32n) & 255n);
            code = tag === 0 ? 0 : tag >= 97 && tag <= 122 ? tag - 96 : -1;
        }
    }
    return code < 0 ? null : missing_value_from_offset(code);
}
