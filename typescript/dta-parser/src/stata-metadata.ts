import type { StataCharacteristic, StataNote, VariableInfo } from './types';

export interface StataMetadataTarget {
    notes: StataNote[];
    characteristics: StataCharacteristic[];
}

export interface StataCharacteristicRecord {
    target: string;
    name: string;
    value: string;
}

const NOTE_NAME = /^note([0-9]+)$/;
export const MAX_STATA_METADATA_VALUE_BYTES = 67_784;

function noteNumber(name: string): number | null {
    const match = NOTE_NAME.exec(name);
    if (match === null) return null;
    const number = Number(match[1]);
    return Number.isInteger(number) && number >= 1 && number <= 9999
        ? number : null;
}

function reservedCharacteristicName(name: string): boolean {
    return NOTE_NAME.test(name) || name === '_lang_list' || name === '_lang_c';
}

interface ScopeIndexes {
    notes: Map<number, number>;
    characteristics: Map<string, number>;
}

/** Incrementally folds raw characteristic records into canonical metadata. */
export class StataMetadataCollector {
    private readonly scopes: StataMetadataTarget[];
    private readonly targetIndexes: Map<string, number>;
    private readonly indexes: ScopeIndexes[];

    constructor(dataset: StataMetadataTarget, variables: VariableInfo[]) {
        this.scopes = [dataset, ...variables];
        this.targetIndexes = new Map<string, number>([['_dta', 0]]);
        variables.forEach((variable, index) => {
            this.targetIndexes.set(variable.name, index + 1);
        });
        this.indexes = this.scopes.map(scope => ({
            notes: new Map(
                scope.notes.map((note, index) => [note.number, index])
            ),
            characteristics: new Map(
                scope.characteristics.map((item, index) => [item.name, index])
            ),
        }));
    }

    accepts(target: string, name: string): boolean {
        return this.targetIndexes.has(target)
            && (noteNumber(name) !== null || !reservedCharacteristicName(name));
    }

    push(record: StataCharacteristicRecord): void {
        const scopeIndex = this.targetIndexes.get(record.target);
        if (scopeIndex === undefined || !this.accepts(record.target, record.name)) return;
        const scope = this.scopes[scopeIndex];
        const indexes = this.indexes[scopeIndex];
        const number = noteNumber(record.name);
        if (number !== null) {
            const existing = indexes.notes.get(number);
            if (existing === undefined) {
                indexes.notes.set(number, scope.notes.length);
                scope.notes.push({ number, text: record.value });
            } else {
                scope.notes[existing].text = record.value;
            }
            return;
        }
        const existing = indexes.characteristics.get(record.name);
        if (existing === undefined) {
            indexes.characteristics.set(record.name, scope.characteristics.length);
            scope.characteristics.push({ name: record.name, value: record.value });
        } else {
            scope.characteristics[existing].value = record.value;
        }
    }

    finish(): void {
        for (const scope of this.scopes) {
            scope.notes.sort((left, right) => left.number - right.number);
        }
    }
}

export function applyCharacteristicRecords(
    records: StataCharacteristicRecord[],
    dataset: StataMetadataTarget,
    variables: VariableInfo[]
): void {
    const collector = new StataMetadataCollector(dataset, variables);
    records.forEach(record => collector.push(record));
    collector.finish();
}

function validNoteNumber(number: number): void {
    if (!Number.isInteger(number) || number < 1 || number > 9999) {
        throw new Error('A note number must be an integer from 1 through 9999');
    }
}

function validCharacteristicName(name: string): void {
    if (!/^[_\p{L}][_\p{L}\p{N}]*$/u.test(name)
        || [...name].length > 32
        || new TextEncoder().encode(name).length > 128
        || reservedCharacteristicName(name)) {
        throw new Error('Invalid or reserved Stata characteristic name');
    }
}

function validMetadataValue(value: string): void {
    if (typeof value !== 'string'
        || value.includes('\0')
        || new TextEncoder().encode(value).length > MAX_STATA_METADATA_VALUE_BYTES) {
        throw new Error('Invalid or over-limit Stata metadata value');
    }
}

export function listStataNotes(target: StataMetadataTarget): StataNote[] {
    return target.notes.map(note => ({ ...note }));
}

export function getStataNote(
    target: StataMetadataTarget, number: number
): string | undefined {
    validNoteNumber(number);
    return target.notes.find(note => note.number === number)?.text;
}

export function setStataNote(
    target: StataMetadataTarget, number: number, text: string
): void {
    validNoteNumber(number);
    validMetadataValue(text);
    const existing = target.notes.find(note => note.number === number);
    if (existing === undefined) target.notes.push({ number, text });
    else existing.text = text;
    target.notes.sort((left, right) => left.number - right.number);
}

export function addStataNote(target: StataMetadataTarget, text: string): number {
    const number = target.notes.length === 0
        ? 1 : Math.max(...target.notes.map(note => note.number)) + 1;
    validNoteNumber(number);
    setStataNote(target, number, text);
    return number;
}

export function dropStataNotes(
    target: StataMetadataTarget, numbers?: readonly number[]
): void {
    if (numbers === undefined) {
        target.notes = [];
        return;
    }
    numbers.forEach(validNoteNumber);
    const dropped = new Set(numbers);
    target.notes = target.notes.filter(note => !dropped.has(note.number));
}

export function renumberStataNotes(
    target: StataMetadataTarget, start = 1
): void {
    validNoteNumber(start);
    if (target.notes.length > 0 && start + target.notes.length - 1 > 9999) {
        throw new Error('Renumbered notes would exceed note number 9999');
    }
    target.notes
        .sort((left, right) => left.number - right.number)
        .forEach((note, index) => { note.number = start + index; });
}

export function listStataCharacteristics(
    target: StataMetadataTarget
): StataCharacteristic[] {
    return target.characteristics.map(characteristic => ({ ...characteristic }));
}

export function getStataCharacteristic(
    target: StataMetadataTarget, name: string
): string | undefined {
    validCharacteristicName(name);
    return target.characteristics.find(item => item.name === name)?.value;
}

export function setStataCharacteristic(
    target: StataMetadataTarget, name: string, value: string
): void {
    validCharacteristicName(name);
    validMetadataValue(value);
    const existing = target.characteristics.find(item => item.name === name);
    if (existing === undefined) target.characteristics.push({ name, value });
    else existing.value = value;
}

export function dropStataCharacteristics(
    target: StataMetadataTarget, names?: readonly string[]
): void {
    if (names === undefined) {
        target.characteristics = [];
        return;
    }
    names.forEach(validCharacteristicName);
    const dropped = new Set(names);
    target.characteristics = target.characteristics.filter(
        characteristic => !dropped.has(characteristic.name)
    );
}
