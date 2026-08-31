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
import type { StataMetadataTarget } from '../../src/stata-metadata';
import type { DtaMetadata, VariableInfo } from '../../src/types';

function metadata(): StataMetadataTarget {
    return { notes: [], characteristics: [] };
}

function oldVariable(name: string): VariableInfo {
    return {
        name,
        type: 'byte',
        type_code: 65530,
        format: '%8.0g',
        label: '',
        value_label_name: '',
        byte_width: 1,
        byte_offset: 0,
    };
}

describe('Stata metadata accessors', () => {
    it('normalizes omitted metadata and legacy string-note arrays', () => {
        const omitted: StataMetadataTarget = {};
        setStataNote(omitted, 3, 'three');
        setStataCharacteristic(omitted, 'source', 'survey');
        expect(listStataNotes(omitted)).toEqual([
            { number: 3, text: 'three' },
        ]);
        expect(listStataCharacteristics(omitted)).toEqual([
            { name: 'source', value: 'survey' },
        ]);

        const legacy: StataMetadataTarget = {
            notes: ['first', 'second'],
        };
        expect(listStataNotes(legacy)).toEqual([
            { number: 1, text: 'first' },
            { number: 2, text: 'second' },
        ]);
        expect(addStataNote(legacy, 'third')).toBe(3);
        expect(legacy.notes).toEqual([
            { number: 1, text: 'first' },
            { number: 2, text: 'second' },
            { number: 3, text: 'third' },
        ]);

        const variables = [oldVariable('x')];
        setStataNote(variables[0], 2, 'variable');
        setStataCharacteristic(variables[0], 'role', 'id');
        expect(listStataNotes(variables[0])).toEqual([
            { number: 2, text: 'variable' },
        ]);
        expect(listStataCharacteristics(variables[0])).toEqual([
            { name: 'role', value: 'id' },
        ]);

        const oldMetadata: DtaMetadata = {
            format_version: 118,
            byte_order: 'LSF',
            nvar: 1,
            nobs: 0,
            dataset_label: '',
            notes: ['legacy dataset note'],
            variables,
            section_offsets: {
                stata_data: 0, map: 0, variable_types: 0, varnames: 0,
                sortlist: 0, formats: 0, value_label_names: 0,
                variable_labels: 0, characteristics: 0, data: 0,
                strls: 0, value_labels: 0, stata_data_close: 0,
                end_of_file: 0,
            },
            obs_length: 1,
        };
        expect(listStataNotes(oldMetadata)).toEqual([
            { number: 1, text: 'legacy dataset note' },
        ]);
    });
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
        expect(() => setStataCharacteristic(target, 'fralias_from', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, 'fralias_varname', 'bad')).toThrow();
        expect(() => setStataCharacteristic(target, '2bad', 'bad')).toThrow();
        expect(() => setStataCharacteristic(
            target, 'source', 'x'.repeat(67_785)
        )).toThrow();
        expect(() => setStataCharacteristic(
            target, `a${'界'.repeat(32)}`, 'bad'
        )).toThrow();
    });

    it('validates caller-provided note arrays before reading or changing them', () => {
        const malformed: StataMetadataTarget[] = [
            { notes: [
                { number: 1, text: 'one' },
                { number: 1, text: 'duplicate' },
            ] },
            { notes: [{ number: 1.5, text: 'fractional' }] },
            { notes: [{ number: 0, text: 'low' }] },
            { notes: [{ number: 10_000, text: 'high' }] },
            { notes: [{ number: 1, text: 'nul\0text' }] },
            { notes: [{ number: 1, text: 'x'.repeat(67_785) }] },
            { notes: [{ number: 1, text: '€'.repeat(67_785) }] },
            { notes: ['valid', 2] as unknown as string[] },
        ];
        for (const target of malformed) {
            expect(() => listStataNotes(target)).toThrow(
                'Malformed Stata note metadata'
            );
        }
        expect(() => dropStataNotes(malformed[0])).toThrow(
            'Malformed Stata note metadata'
        );

        const decoded: StataMetadataTarget = {
            notes: ['€'.repeat(67_784)],
        };
        expect(listStataNotes(decoded)).toEqual([
            { number: 1, text: '€'.repeat(67_784) },
        ]);
        expect(() => setStataNote(decoded, 1, '€'.repeat(22_595))).toThrow(
            'Invalid or over-limit Stata metadata value'
        );
    });

    it('validates caller-provided characteristic arrays before use', () => {
        const malformed = [
            [
                { name: 'source', value: 'one' },
                { name: 'source', value: 'duplicate' },
            ],
            [{ name: 'note01', value: 'reserved' }],
            [{ name: 'fralias_from', value: 'reserved' }],
            [{ name: '2bad', value: 'invalid' }],
            [{ name: 'source', value: 'nul\0text' }],
            [{ name: 'source', value: 'x'.repeat(67_785) }],
            [{ name: 'source', value: '€'.repeat(67_785) }],
            [{ name: 'source', value: 1 }],
        ];
        for (const characteristics of malformed) {
            const target = {
                characteristics,
            } as unknown as StataMetadataTarget;
            expect(() => listStataCharacteristics(target)).toThrow(
                'Malformed Stata characteristic metadata'
            );
        }
        const duplicate = {
            characteristics: malformed[0],
        } as StataMetadataTarget;
        expect(() => dropStataCharacteristics(duplicate)).toThrow(
            'Malformed Stata characteristic metadata'
        );

        const decoded: StataMetadataTarget = {
            characteristics: [{
                name: 'source', value: '€'.repeat(67_784),
            }],
        };
        expect(listStataCharacteristics(decoded)).toEqual(
            decoded.characteristics
        );
    });
});
