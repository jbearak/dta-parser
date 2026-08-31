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
const MAX_METADATA_BYTES = 67_784;

function noteNumber(name: string): number | null {
    const match = NOTE_NAME.exec(name);
    if (match === null) return null;
    const number = Number(match[1]);
    return Number.isInteger(number) && number >= 1 && number <= 9999
        ? number : null;
}

function upsertNote(notes: StataNote[], number: number, text: string): void {
    const existing = notes.find(note => note.number === number);
    if (existing === undefined) notes.push({ number, text });
    else existing.text = text;
}

function upsertCharacteristic(
    characteristics: StataCharacteristic[], name: string, value: string
): void {
    const existing = characteristics.find(item => item.name === name);
    if (existing === undefined) characteristics.push({ name, value });
    else existing.value = value;
}

export function applyCharacteristicRecords(
    records: StataCharacteristicRecord[],
    dataset: StataMetadataTarget,
    variables: VariableInfo[]
): void {
    const variableByName = new Map(
        variables.map(variable => [variable.name, variable])
    );
    for (const record of records) {
        const target = record.target === '_dta'
            ? dataset
            : variableByName.get(record.target);
        if (target === undefined) continue;
        const number = noteNumber(record.name);
        if (number !== null) {
            upsertNote(target.notes, number, record.value);
        } else if (!NOTE_NAME.test(record.name)
            && !(record.target === '_dta'
                && (record.name === '_lang_list' || record.name === '_lang_c'))) {
            upsertCharacteristic(target.characteristics, record.name, record.value);
        }
    }
    dataset.notes.sort((left, right) => left.number - right.number);
    for (const variable of variables) {
        variable.notes.sort((left, right) => left.number - right.number);
    }
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
        || NOTE_NAME.test(name)) {
        throw new Error('Invalid or reserved Stata characteristic name');
    }
}

function validMetadataValue(value: string): void {
    if (typeof value !== 'string'
        || value.includes('\0')
        || new TextEncoder().encode(value).length > MAX_METADATA_BYTES) {
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
    upsertNote(target.notes, number, text);
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
    upsertCharacteristic(target.characteristics, name, value);
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
