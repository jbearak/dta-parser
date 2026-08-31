import { describe, expect, it } from 'bun:test';

import {
    addStataNote,
    dropStataCharacteristics,
    dropStataNotes,
    getStataCharacteristic,
    getStataNote,
    listStataCharacteristics,
    listStataNotes,
    renumberStataNotes,
    setStataCharacteristic,
    setStataNote,
} from '../../src/index';
import {
    applyCharacteristicRecords,
    type StataMetadataTarget,
} from '../../src/stata-metadata';
import type { VariableInfo } from '../../src/types';

function metadata(): StataMetadataTarget {
    return { notes: [], characteristics: [] };
}

function variable(name: string): VariableInfo {
    return {
        name,
        type: 'byte',
        type_code: 65530,
        format: '%8.0g',
        label: '',
        value_label_name: '',
        notes: [],
        characteristics: [],
        byte_width: 1,
        byte_offset: 0,
    };
}

describe('Stata metadata accessors', () => {
    it('preserves note gaps, empty text, copies, and explicit renumbering', () => {
        const target = metadata();
        setStataNote(target, 4, 'four');
        setStataNote(target, 1, '');

        expect(listStataNotes(target)).toEqual([
            { number: 1, text: '' },
            { number: 4, text: 'four' },
        ]);
        expect(getStataNote(target, 3)).toBeUndefined();
        expect(addStataNote(target, 'five')).toBe(5);
        const copy = listStataNotes(target);
        copy[0].text = 'changed';
        expect(getStataNote(target, 1)).toBe('');

        dropStataNotes(target, [1, 5]);
        renumberStataNotes(target, 2);
        expect(listStataNotes(target)).toEqual([
            { number: 2, text: 'four' },
        ]);
        dropStataNotes(target);
        expect(listStataNotes(target)).toEqual([]);
    });

    it('preserves characteristic order, Unicode, empty values, and copies', () => {
        const target = metadata();
        setStataCharacteristic(target, 'source', '');
        setStataCharacteristic(target, 'café', 'naïve');
        setStataCharacteristic(target, 'source', 'revised');

        expect(listStataCharacteristics(target)).toEqual([
            { name: 'source', value: 'revised' },
            { name: 'café', value: 'naïve' },
        ]);
        expect(getStataCharacteristic(target, 'source')).toBe('revised');
        const copy = listStataCharacteristics(target);
        copy[0].value = 'changed';
        expect(getStataCharacteristic(target, 'source')).toBe('revised');
        dropStataCharacteristics(target, ['source']);
        expect(listStataCharacteristics(target)).toEqual([
            { name: 'café', value: 'naïve' },
        ]);
    });

    it('rejects invalid, reserved, and over-limit keys and note numbers', () => {
        const target = metadata();
        expect(() => setStataNote(target, 0, 'bad')).toThrow();
        expect(() => setStataNote(target, 10_000, 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, 'note2', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '_lang_list', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '_lang_c', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '_lang_v_en', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '_lang_l_en', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '2bad', 'bad')).toThrow();
        expect(() => setStataCharacteristic(
            target, 'source', 'x'.repeat(67_785)
        )).toThrow();
        expect(() => setStataCharacteristic(
            target, `a${'界'.repeat(32)}`, 'bad'
        )).toThrow();
    });
});

describe('DTA characteristic recovery', () => {
    it('uses last duplicate values, filters reserved records, and scopes variables', () => {
        const dataset = metadata();
        const variables = [variable('x')];
        applyCharacteristicRecords([
            { target: '_dta', name: 'note3', value: 'three' },
            { target: '_dta', name: 'note1', value: '' },
            { target: '_dta', name: 'source', value: 'old' },
            { target: '_dta', name: 'source', value: 'new' },
            { target: '_dta', name: 'note0', value: '9' },
            { target: '_dta', name: 'note10000', value: 'reserved' },
            { target: '_dta', name: '_lang_list', value: 'default' },
            { target: '_dta', name: '_lang_v_en', value: 'English label' },
            { target: 'x', name: '_lang_l_en', value: 'English labels' },
            { target: 'x', name: 'note2', value: 'variable' },
            { target: 'x', name: 'role', value: 'id' },
            { target: 'missing', name: 'source', value: 'ignored' },
        ], dataset, variables);

        expect(dataset.notes).toEqual([
            { number: 1, text: '' },
            { number: 3, text: 'three' },
        ]);
        expect(dataset.characteristics).toEqual([
            { name: 'source', value: 'new' },
        ]);
        expect(variables[0].notes).toEqual([
            { number: 2, text: 'variable' },
        ]);
        expect(variables[0].characteristics).toEqual([
            { name: 'role', value: 'id' },
        ]);
    });
});
