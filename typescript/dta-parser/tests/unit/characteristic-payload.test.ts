import { describe, expect, it } from 'bun:test';

import {
    StataCharacteristicFramePlan,
    type StataCharacteristicLocator,
} from '../../src/characteristic-payload';
import {
    isStataCharacteristicsMaterialized,
    isStataNotesMaterialized,
    StataMetadataCollector,
    type StataMetadataTarget,
    withLazyStataMetadata,
} from '../../src/stata-metadata';
import { text_decoder, type DtaTextDecoder } from '../../src/text-encoding';
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

function lazyVariable(name: string, byteOffset: number): VariableInfo {
    return withLazyStataMetadata({
        name,
        type: 'byte',
        type_code: 65530,
        format: '%8.0g',
        label: '',
        value_label_name: '',
        byte_width: 1,
        byte_offset: byteOffset,
    });
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
    it('releases duplicate indexes before decoding and finishes once', () => {
        const dataset: StataMetadataTarget = {
            notes: [], characteristics: [],
        };
        const collector = new StataMetadataCollector(dataset, []);
        const encoded = encodeRecords(129, [
            { target: '_dta', name: 'source', value: 'payload' },
        ]);
        const decodedIndexCounts: number[] = [];
        const utf8 = text_decoder('utf-8');
        let plan: StataCharacteristicFramePlan;
        const decoder: DtaTextDecoder = {
            decode(input): string {
                const value = utf8.decode(input);
                if (value === 'payload') {
                    decodedIndexCounts.push(plan.retainedIndexCount);
                }
                return value;
            },
        };
        plan = new StataCharacteristicFramePlan(
            encoded.bytes, decoder, collector
        );
        plan.add(encoded.locators[0]);

        expect(plan.retainedIndexCount).toBe(1);
        plan.finish();

        expect(decodedIndexCounts).toEqual([0]);
        expect(plan.retainedIndexCount).toBe(0);
        expect(dataset.characteristics).toEqual([
            { name: 'source', value: 'payload' },
        ]);
        expect(() => plan.finish()).toThrow('already finished');
    });

    it('materializes 120,000 unique scopes without rebuilding indexes', () => {
        const count = 120_000;
        const width = 129;
        const stride = 2 * width + 1;
        const variables = Array.from(
            { length: count },
            (_, index) => lazyVariable(`v${index}`, index)
        );
        const bytes = new Uint8Array(count * stride);
        const encoder = new TextEncoder();
        const characteristic = encoder.encode('source');
        const collector = new StataMetadataCollector(
            { notes: [], characteristics: [] }, variables
        );
        let plan: StataCharacteristicFramePlan;
        let redundantIndexObserved = false;
        const utf8 = text_decoder('utf-8');
        const decoder: DtaTextDecoder = {
            decode(input): string {
                if (input.length === 1 && input[0] === 0x78) {
                    redundantIndexObserved ||= plan.retainedIndexCount !== 0
                        || collector.retainedTargetIndexCount !== 0
                        || collector.indexedScopeCount !== 0;
                }
                return utf8.decode(input);
            },
        };
        plan = new StataCharacteristicFramePlan(bytes, decoder, collector);
        for (let index = 0; index < count; index++) {
            const start = index * stride;
            bytes.set(encoder.encode(`v${index}`), start);
            bytes.set(characteristic, start + width);
            bytes[start + 2 * width] = 0x78;
            plan.add({
                namesStart: start,
                nameWidth: width,
                valueStart: start + 2 * width,
                valueLength: 1,
            });
        }

        expect(plan.retainedCount).toBe(count);
        expect(plan.retainedIndexCount).toBe(count);
        expect(collector.indexedScopeCount).toBe(0);
        plan.finish();

        expect(redundantIndexObserved).toBeFalse();
        expect(plan.retainedIndexCount).toBe(0);
        expect(collector.retainedTargetIndexCount).toBe(0);
        expect(collector.indexedScopeCount).toBe(0);
        expect(variables.every(isStataCharacteristicsMaterialized)).toBeTrue();
        expect(variables.every(variable =>
            !isStataNotesMaterialized(variable)
        )).toBeTrue();
        expect(variables[0].characteristics).toEqual([
            { name: 'source', value: 'x' },
        ]);
        variables[0].characteristics[0].value = 'first only';
        expect(variables[count - 1].characteristics).toEqual([
            { name: 'source', value: 'x' },
        ]);
    });

    it('sorts notes and targets the last duplicate variable name', () => {
        const dataset: StataMetadataTarget = {
            notes: [], characteristics: [],
        };
        const variables = [
            lazyVariable('duplicate', 0),
            lazyVariable('duplicate', 1),
        ];
        const collector = new StataMetadataCollector(dataset, variables);
        const encoded = encodeRecords(129, [
            { target: 'duplicate', name: 'note9', value: 'nine' },
            { target: 'duplicate', name: 'role', value: 'old' },
            { target: 'duplicate', name: 'note2', value: 'two' },
            { target: 'duplicate', name: 'role', value: 'new' },
        ]);
        const plan = new StataCharacteristicFramePlan(
            encoded.bytes, text_decoder('utf-8'), collector
        );
        for (const locator of encoded.locators) plan.add(locator);

        plan.finish();

        expect(isStataNotesMaterialized(variables[0])).toBeFalse();
        expect(isStataCharacteristicsMaterialized(variables[0])).toBeFalse();
        expect(variables[1].notes).toEqual([
            { number: 2, text: 'two' },
            { number: 9, text: 'nine' },
        ]);
        expect(variables[1].characteristics).toEqual([
            { name: 'role', value: 'new' },
        ]);
    });

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
