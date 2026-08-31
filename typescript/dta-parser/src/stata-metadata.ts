import type { StataCharacteristic, StataNote, VariableInfo } from './types';

export interface StataMetadataTarget {
    notes?: StataNote[] | string[];
    characteristics?: StataCharacteristic[];
}

const NOTE_NAME = /^note([0-9]+)$/;
const MAX_STATA_METADATA_VALUE_BYTES = 67_784;
const MAX_DECODED_STATA_METADATA_VALUE_BYTES = 203_352;
const TEXT_ENCODER = new TextEncoder();

const LAZY_NOTES = new WeakMap<object, StataNote[] | string[]>();
const LAZY_CHARACTERISTICS = new WeakMap<object, StataCharacteristic[]>();

/** Whether this lazy target has allocated its notes array. */
export function isStataNotesMaterialized(target: object): boolean {
    return LAZY_NOTES.has(target);
}

/** Whether this lazy target has allocated its characteristics array. */
export function isStataCharacteristicsMaterialized(target: object): boolean {
    return LAZY_CHARACTERISTICS.has(target);
}

function lazyNotes(this: object): StataNote[] | string[] {
    let notes = LAZY_NOTES.get(this);
    if (notes === undefined) {
        notes = [];
        LAZY_NOTES.set(this, notes);
    }
    return notes;
}

function setLazyNotes(this: object, notes: StataNote[] | string[]): void {
    LAZY_NOTES.set(this, notes);
}

function lazyCharacteristics(this: object): StataCharacteristic[] {
    let characteristics = LAZY_CHARACTERISTICS.get(this);
    if (characteristics === undefined) {
        characteristics = [];
        LAZY_CHARACTERISTICS.set(this, characteristics);
    }
    return characteristics;
}

function setLazyCharacteristics(
    this: object, characteristics: StataCharacteristic[]
): void {
    LAZY_CHARACTERISTICS.set(this, characteristics);
}

/** Add canonical metadata arrays without allocating them until first access. */
export function withLazyStataMetadata<T extends object>(
    target: T
): T & { notes: StataNote[]; characteristics: StataCharacteristic[] } {
    Object.defineProperties(target, {
        notes: {
            configurable: true,
            enumerable: true,
            get: lazyNotes,
            set: setLazyNotes,
        },
        characteristics: {
            configurable: true,
            enumerable: true,
            get: lazyCharacteristics,
            set: setLazyCharacteristics,
        },
    });
    return target as T & {
        notes: StataNote[];
        characteristics: StataCharacteristic[];
    };
}

function noteNumber(name: string): number | null {
    const match = NOTE_NAME.exec(name);
    if (match === null) return null;
    const number = Number(match[1]);
    return Number.isInteger(number)
        && number >= 1
        && number <= 9999
        && match[1] === String(number)
        ? number : null;
}

function reservedCharacteristicName(name: string): boolean {
    return NOTE_NAME.test(name)
        || name === '_lang_list'
        || name === '_lang_c'
        || name === 'fralias_from'
        || name === 'fralias_varname'
        || name.startsWith('_lang_v_')
        || name.startsWith('_lang_l_');
}

function validCharacteristicNameShape(name: string): boolean {
    return /^[_\p{L}][_\p{L}\p{N}]*$/u.test(name)
        && codePointLengthAtMost(name, 32)
        && utf8LengthAtMost(name, 128);
}

export interface AcceptedStataCharacteristic {
    scopeIndex: number;
    name: string;
    noteNumber: number | null;
}

function mutableNotes(target: StataMetadataTarget): StataNote[] {
    const current = target.notes;
    if (current === undefined) {
        const notes: StataNote[] = [];
        target.notes = notes;
        return notes;
    }
    if (!Array.isArray(current)) {
        throw new Error('Malformed Stata note metadata');
    }
    if (current.length > 0 && current.every(note => typeof note === 'string')) {
        if (current.length > 9999) {
            throw new Error('Malformed Stata note metadata');
        }
        const notes = (current as string[]).map((text, index) => {
            validExistingMetadataValue(text, 'note');
            return { number: index + 1, text };
        });
        target.notes = notes;
        return notes;
    }
    const numbers = new Set<number>();
    for (const note of current) {
        if (typeof note !== 'object' || note === null) {
            throw new Error('Malformed Stata note metadata');
        }
        const { number, text } = note as StataNote;
        if (!Number.isInteger(number) || number < 1 || number > 9999
            || numbers.has(number)) {
            throw new Error('Malformed Stata note metadata');
        }
        validExistingMetadataValue(text, 'note');
        numbers.add(number);
    }
    return current as StataNote[];
}

function mutableCharacteristics(
    target: StataMetadataTarget
): StataCharacteristic[] {
    if (target.characteristics === undefined) {
        target.characteristics = [];
    }
    if (!Array.isArray(target.characteristics)) {
        throw new Error('Malformed Stata characteristic metadata');
    }
    const names = new Set<string>();
    for (const characteristic of target.characteristics) {
        if (typeof characteristic !== 'object' || characteristic === null) {
            throw new Error('Malformed Stata characteristic metadata');
        }
        const { name, value } = characteristic as StataCharacteristic;
        if (typeof name !== 'string'
            || !validCharacteristicNameShape(name)
            || reservedCharacteristicName(name)
            || names.has(name)) {
            throw new Error('Malformed Stata characteristic metadata');
        }
        validExistingMetadataValue(value, 'characteristic');
        names.add(name);
    }
    return target.characteristics;
}

/** Incrementally folds raw characteristic records into canonical metadata. */
export class StataMetadataCollector {
    private readonly dataset: StataMetadataTarget;
    private readonly variables: VariableInfo[];
    private targetIndexes: Map<string, number> | undefined;
    private uniqueNoteScopes: Uint8Array | undefined;
    private uniqueCharacteristicScopes: Uint8Array | undefined;

    constructor(dataset: StataMetadataTarget, variables: VariableInfo[]) {
        this.dataset = dataset;
        this.variables = variables;
    }

    /** Variable-name lookup entries still retained by this collector. */
    get retainedTargetIndexCount(): number {
        return this.targetIndexes?.size ?? 0;
    }

    private targetIndex(target: string): number | undefined {
        if (target === '_dta') return 0;
        if (this.targetIndexes === undefined) {
            this.targetIndexes = new Map<string, number>();
            this.variables.forEach((variable, index) => {
                this.targetIndexes!.set(variable.name, index + 1);
            });
        }
        return this.targetIndexes.get(target);
    }

    private scope(scopeIndex: number): StataMetadataTarget {
        return scopeIndex === 0
            ? this.dataset
            : this.variables[scopeIndex - 1];
    }

    private uniqueNotes(scopeIndex: number): StataNote[] {
        let scopes = this.uniqueNoteScopes;
        if (scopes === undefined) {
            scopes = new Uint8Array(this.variables.length + 1);
            this.uniqueNoteScopes = scopes;
        }
        const scope = this.scope(scopeIndex);
        if (scopes[scopeIndex] === 0) {
            const values = mutableNotes(scope);
            scopes[scopeIndex] = 1;
            return values;
        }
        return scope.notes as StataNote[];
    }

    private uniqueCharacteristics(scopeIndex: number): StataCharacteristic[] {
        let scopes = this.uniqueCharacteristicScopes;
        if (scopes === undefined) {
            scopes = new Uint8Array(this.variables.length + 1);
            this.uniqueCharacteristicScopes = scopes;
        }
        const scope = this.scope(scopeIndex);
        if (scopes[scopeIndex] === 0) {
            const values = mutableCharacteristics(scope);
            scopes[scopeIndex] = 1;
            return values;
        }
        return scope.characteristics as StataCharacteristic[];
    }

    accept(
        target: string, name: string
    ): AcceptedStataCharacteristic | null {
        if (!validCharacteristicNameShape(name)) {
            throw new Error('Invalid on-disk Stata characteristic name');
        }
        const number = noteNumber(name);
        if (number === null && reservedCharacteristicName(name)) return null;
        const scopeIndex = this.targetIndex(target);
        if (scopeIndex === undefined) return null;
        return { scopeIndex, name, noteNumber: number };
    }

    /** Materialize a record from a plan that already resolved duplicates. */
    pushAcceptedUniqueLazy(
        accepted: AcceptedStataCharacteristic,
        value: () => string
    ): void {
        // Target resolution ended during framing. Release the wide-schema
        // lookup before value decoding begins.
        this.targetIndexes = undefined;
        const decoded = value();
        validExistingMetadataValue(
            decoded,
            accepted.noteNumber === null ? 'characteristic' : 'note'
        );
        if (accepted.noteNumber !== null) {
            this.uniqueNotes(accepted.scopeIndex).push({
                number: accepted.noteNumber,
                text: decoded,
            });
        } else {
            this.uniqueCharacteristics(accepted.scopeIndex).push({
                name: accepted.name,
                value: decoded,
            });
        }
    }

    finish(): void {
        const uniqueNoteScopes = this.uniqueNoteScopes;
        if (uniqueNoteScopes !== undefined) {
            for (let scopeIndex = 0;
                scopeIndex < uniqueNoteScopes.length;
                scopeIndex++) {
                if (uniqueNoteScopes[scopeIndex] !== 0) {
                    (this.scope(scopeIndex).notes as StataNote[]).sort(
                        (left, right) => left.number - right.number
                    );
                }
            }
        }
        this.targetIndexes = undefined;
        this.uniqueNoteScopes = undefined;
        this.uniqueCharacteristicScopes = undefined;
    }
}

function validNoteNumber(number: number): void {
    if (!Number.isInteger(number) || number < 1 || number > 9999) {
        throw new Error('A note number must be an integer from 1 through 9999');
    }
}

function codePointLengthAtMost(value: string, limit: number): boolean {
    let count = 0;
    for (const _character of value) {
        count++;
        if (count > limit) return false;
    }
    return true;
}

function utf8LengthAtMost(value: string, limit: number): boolean {
    const output = new Uint8Array(Math.min(limit + 1, value.length * 3));
    const encoded = TEXT_ENCODER.encodeInto(value, output);
    return encoded.read === value.length && encoded.written <= limit;
}

function validCharacteristicName(name: string): void {
    if (!validCharacteristicNameShape(name) || reservedCharacteristicName(name)) {
        throw new Error('Invalid or reserved Stata characteristic name');
    }
}

/** Return the canonical content end within a bounded raw metadata value. */
export function stataMetadataValueEnd(
    bytes: Uint8Array, start: number, length: number
): number {
    if (length > MAX_STATA_METADATA_VALUE_BYTES + 1) {
        throw new Error('Characteristic value exceeds the 67,784-byte limit');
    }
    const limit = start + length;
    let end = start;
    while (end < limit && bytes[end] !== 0) end++;
    if (end - start > MAX_STATA_METADATA_VALUE_BYTES) {
        throw new Error('Characteristic value exceeds the 67,784-byte limit');
    }
    return end;
}

function validMetadataValue(value: string): void {
    if (typeof value !== 'string'
        || value.includes('\0')
        || !utf8LengthAtMost(value, MAX_STATA_METADATA_VALUE_BYTES)) {
        throw new Error('Invalid or over-limit Stata metadata value');
    }
}

function validExistingMetadataValue(
    value: unknown, kind: 'note' | 'characteristic'
): asserts value is string {
    if (typeof value !== 'string'
        || value.includes('\0')
        || !codePointLengthAtMost(
            value, MAX_STATA_METADATA_VALUE_BYTES
        )
        || !utf8LengthAtMost(
            value, MAX_DECODED_STATA_METADATA_VALUE_BYTES
        )) {
        throw new Error(`Malformed Stata ${kind} metadata`);
    }
}

export function listStataNotes(target: StataMetadataTarget): StataNote[] {
    return mutableNotes(target).map(note => ({ ...note }));
}

export function getStataNote(
    target: StataMetadataTarget, number: number
): string | undefined {
    validNoteNumber(number);
    return mutableNotes(target).find(note => note.number === number)?.text;
}

export function setStataNote(
    target: StataMetadataTarget, number: number, text: string
): void {
    validNoteNumber(number);
    validMetadataValue(text);
    const notes = mutableNotes(target);
    const existing = notes.find(note => note.number === number);
    if (existing === undefined) notes.push({ number, text });
    else existing.text = text;
    notes.sort((left, right) => left.number - right.number);
}

export function addStataNote(target: StataMetadataTarget, text: string): number {
    const notes = mutableNotes(target);
    const number = notes.length === 0
        ? 1 : Math.max(...notes.map(note => note.number)) + 1;
    validNoteNumber(number);
    setStataNote(target, number, text);
    return number;
}

export function dropStataNotes(
    target: StataMetadataTarget, numbers?: readonly number[]
): void {
    mutableNotes(target);
    if (numbers === undefined) {
        target.notes = [];
        return;
    }
    numbers.forEach(validNoteNumber);
    const dropped = new Set(numbers);
    target.notes = mutableNotes(target).filter(
        note => !dropped.has(note.number)
    );
}

export function renumberStataNotes(
    target: StataMetadataTarget, start = 1
): void {
    validNoteNumber(start);
    const notes = mutableNotes(target);
    if (notes.length > 0 && start + notes.length - 1 > 9999) {
        throw new Error('Renumbered notes would exceed note number 9999');
    }
    notes
        .sort((left, right) => left.number - right.number)
        .forEach((note, index) => { note.number = start + index; });
}

export function listStataCharacteristics(
    target: StataMetadataTarget
): StataCharacteristic[] {
    return mutableCharacteristics(target).map(
        characteristic => ({ ...characteristic })
    );
}

export function getStataCharacteristic(
    target: StataMetadataTarget, name: string
): string | undefined {
    validCharacteristicName(name);
    return mutableCharacteristics(target)
        .find(item => item.name === name)?.value;
}

export function setStataCharacteristic(
    target: StataMetadataTarget, name: string, value: string
): void {
    validCharacteristicName(name);
    validMetadataValue(value);
    const characteristics = mutableCharacteristics(target);
    const existing = characteristics.find(item => item.name === name);
    if (existing === undefined) characteristics.push({ name, value });
    else existing.value = value;
}

export function dropStataCharacteristics(
    target: StataMetadataTarget, names?: readonly string[]
): void {
    mutableCharacteristics(target);
    if (names === undefined) {
        target.characteristics = [];
        return;
    }
    names.forEach(validCharacteristicName);
    const dropped = new Set(names);
    target.characteristics = mutableCharacteristics(target).filter(
        characteristic => !dropped.has(characteristic.name)
    );
}
