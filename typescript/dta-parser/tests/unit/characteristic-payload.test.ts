import { describe, expect, it } from 'bun:test';

import {
    StataCharacteristicFramePlan,
    type StataCharacteristicLocator,
} from '../../src/characteristic-payload';
import {
    StataMetadataCollector,
    type StataMetadataTarget,
} from '../../src/stata-metadata';
import { text_decoder } from '../../src/text-encoding';
import type { VariableInfo } from '../../src/types';

interface RawCharacteristic {
    target: string;
    name: string;
    value: string | Uint8Array;
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

function encodeRecords(
    width: number,
    records: RawCharacteristic[]
): { bytes: Uint8Array; locators: StataCharacteristicLocator[] } {
    const encoder = new TextEncoder();
    const encoded = records.map(record => ({
        target: encoder.encode(record.target),
        name: encoder.encode(record.name),
        value: typeof record.value === 'string'
            ? encoder.encode(record.value)
            : record.value,
    }));
    const bytes = new Uint8Array(encoded.reduce(
        (length, record) => length + 2 * width + record.value.length,
        0
    ));
    const locators: StataCharacteristicLocator[] = [];
    let position = 0;
    for (const record of encoded) {
        bytes.set(record.target, position);
        bytes.set(record.name, position + width);
        bytes.set(record.value, position + 2 * width);
        locators.push({
            namesStart: position,
            nameWidth: width,
            valueStart: position + 2 * width,
            valueLength: record.value.length,
        });
        position += 2 * width + record.value.length;
    }
    return { bytes, locators };
}

function framePlan(
    width: number,
    records: RawCharacteristic[]
): {
    dataset: StataMetadataTarget;
    variables: VariableInfo[];
    plan: StataCharacteristicFramePlan;
} {
    const dataset: StataMetadataTarget = { notes: [], characteristics: [] };
    const variables = [variable('x')];
    const collector = new StataMetadataCollector(dataset, variables);
    const { bytes, locators } = encodeRecords(width, records);
    const plan = new StataCharacteristicFramePlan(
        bytes, text_decoder('utf-8'), collector
    );
    for (const locator of locators) plan.add(locator);
    return { dataset, variables, plan };
}

describe('Stata characteristic frame plan', () => {
    for (const [format, width] of [
        ['modern', 129],
        ['legacy', 33],
    ] as const) {
        it(`compacts 10,000 duplicate ${format} locators by scope and key`, () => {
            const records: RawCharacteristic[] = [
                { target: '_dta', name: 'source', value: 'first' },
                { target: '_dta', name: 'note7', value: 'first note' },
                { target: '_dta', name: 'other', value: 'other value' },
                { target: 'x', name: 'role', value: 'first role' },
            ];
            for (let index = 0; index < 9_999; index++) {
                records.push({
                    target: '_dta', name: 'source', value: 'middle',
                });
            }
            records.push(
                { target: '_dta', name: 'source', value: 'final' },
                { target: '_dta', name: 'note7', value: 'final note' },
                { target: 'x', name: 'role', value: 'final role' },
            );

            const { dataset, variables, plan } = framePlan(width, records);
            expect(plan.retainedCount).toBe(4);
            plan.finish();

            expect(dataset.notes).toEqual([
                { number: 7, text: 'final note' },
            ]);
            expect(dataset.characteristics).toEqual([
                { name: 'source', value: 'final' },
                { name: 'other', value: 'other value' },
            ]);
            expect(variables[0].characteristics).toEqual([
                { name: 'role', value: 'final role' },
            ]);
        });

        it(`rejects a malformed superseded ${format} value after 10,000 replacements`, () => {
            const records: RawCharacteristic[] = [
                { target: '_dta', name: 'source', value: 'first' },
                {
                    target: '_dta',
                    name: 'source',
                    value: new Uint8Array(67_785).fill(0x78),
                },
            ];
            for (let index = 0; index < 10_000; index++) {
                records.push({
                    target: '_dta', name: 'source', value: 'replacement',
                });
            }

            const { plan } = framePlan(width, records);
            expect(plan.retainedCount).toBe(1);
            expect(() => plan.finish()).toThrow('67,784-byte limit');
        });
    }
});
