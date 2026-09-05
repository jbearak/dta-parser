import type { DtaTextDecoder } from './text-encoding';
import {
    stataMetadataValueEnd,
    type AcceptedStataCharacteristic,
    type StataMetadataCollector,
} from './dta-metadata';

/** One format-specific locator supplied after a record's framing is valid. */
export interface StataCharacteristicLocator {
    namesStart: number;
    nameWidth: number;
    valueStart: number;
    valueLength: number;
}

/** One accepted record whose value remains in the source metadata buffer. */
interface FramedStataCharacteristic {
    accepted: AcceptedStataCharacteristic;
    valueStart: number;
    valueEnd: number;
}

function canonicalRecordKey(
    accepted: AcceptedStataCharacteristic
): string {
    const key = accepted.noteNumber === null
        ? `c:${accepted.name}`
        : `n:${accepted.noteNumber}`;
    return `${accepted.scopeIndex}\0${key}`;
}

function readFixedString(
    bytes: Uint8Array,
    start: number,
    width: number,
    decoder: DtaTextDecoder
): string {
    let end = start;
    const limit = start + width;
    while (end < limit && bytes[end] !== 0) end++;
    return decoder.decode(bytes.subarray(start, end));
}

/**
 * Collect accepted locators while callers validate format-specific framing.
 * Value-bound and classification errors remain deferred until `finish()`, so
 * a later framing error still wins. Every value is bounded, but rejected
 * records retain no descriptor. Values decode after the section is valid.
 */
export class StataCharacteristicFramePlan {
    private readonly records: FramedStataCharacteristic[] = [];
    private recordIndices: Map<string, number> | undefined = new Map();
    private deferredError: unknown;
    private hasDeferredError = false;

    constructor(
        private readonly bytes: Uint8Array,
        private readonly decoder: DtaTextDecoder,
        private readonly collector: StataMetadataCollector
    ) {}

    /** Number of distinct accepted scope/key locators retained for decoding. */
    get retainedCount(): number {
        return this.records.length;
    }

    /** Number of canonical-key lookup entries still retained for framing. */
    get retainedIndexCount(): number {
        return this.recordIndices?.size ?? 0;
    }

    add(locator: StataCharacteristicLocator): void {
        const recordIndices = this.recordIndices;
        if (recordIndices === undefined) {
            throw new Error('Stata characteristic frame plan is already finished');
        }
        let valueEnd: number;
        try {
            valueEnd = stataMetadataValueEnd(
                this.bytes, locator.valueStart, locator.valueLength
            );
        } catch (error) {
            if (!this.hasDeferredError) {
                this.deferredError = error;
                this.hasDeferredError = true;
            }
            return;
        }
        if (this.hasDeferredError) return;
        const target = readFixedString(
            this.bytes, locator.namesStart, locator.nameWidth, this.decoder
        );
        const name = readFixedString(
            this.bytes,
            locator.namesStart + locator.nameWidth,
            locator.nameWidth,
            this.decoder
        );
        try {
            const accepted = this.collector.accept(target, name);
            if (accepted !== null) {
                const key = canonicalRecordKey(accepted);
                const existing = recordIndices.get(key);
                if (existing === undefined) {
                    recordIndices.set(key, this.records.length);
                    this.records.push({
                        accepted,
                        valueStart: locator.valueStart,
                        valueEnd,
                    });
                } else {
                    const record = this.records[existing];
                    record.valueStart = locator.valueStart;
                    record.valueEnd = valueEnd;
                }
            }
        } catch (error) {
            this.deferredError = error;
            this.hasDeferredError = true;
        }
    }

    finish(): void {
        if (this.recordIndices === undefined) {
            throw new Error('Stata characteristic frame plan is already finished');
        }
        this.recordIndices = undefined;
        if (this.hasDeferredError) throw this.deferredError;
        for (const record of this.records) {
            this.collector.pushAcceptedUniqueLazy(record.accepted, () => {
                return this.decoder.decode(
                    this.bytes.subarray(record.valueStart, record.valueEnd)
                );
            });
        }
        this.collector.finish();
    }
}
