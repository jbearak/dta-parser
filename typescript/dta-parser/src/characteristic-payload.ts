import type { DtaTextDecoder } from './text-encoding';
import {
    stataMetadataValueEnd,
    type AcceptedStataCharacteristic,
    type StataMetadataCollector,
} from './stata-metadata';

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
    private deferredError: unknown;
    private hasDeferredError = false;

    constructor(
        private readonly bytes: Uint8Array,
        private readonly decoder: DtaTextDecoder,
        private readonly collector: StataMetadataCollector
    ) {}

    add(locator: StataCharacteristicLocator): void {
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
                this.records.push({
                    accepted,
                    valueStart: locator.valueStart,
                    valueEnd,
                });
            }
        } catch (error) {
            this.deferredError = error;
            this.hasDeferredError = true;
        }
    }

    finish(): void {
        if (this.hasDeferredError) throw this.deferredError;
        for (const record of this.records) {
            this.collector.pushAcceptedLazy(record.accepted, () => {
                return this.decoder.decode(
                    this.bytes.subarray(record.valueStart, record.valueEnd)
                );
            });
        }
        this.collector.finish();
    }
}
