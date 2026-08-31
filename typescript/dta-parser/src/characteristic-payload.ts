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
    valueLength: number;
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
 * Classification errors remain deferred until `finish()`, so a later framing
 * error still wins. Values decode only after the enclosing section is valid.
 */
export class StataCharacteristicFramePlan {
    private readonly records: FramedStataCharacteristic[] = [];
    private classificationError: unknown;
    private hasClassificationError = false;

    constructor(
        private readonly bytes: Uint8Array,
        private readonly decoder: DtaTextDecoder,
        private readonly collector: StataMetadataCollector
    ) {}

    add(locator: StataCharacteristicLocator): void {
        if (this.hasClassificationError) return;
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
                    valueLength: locator.valueLength,
                });
            }
        } catch (error) {
            this.classificationError = error;
            this.hasClassificationError = true;
        }
    }

    finish(): void {
        if (this.hasClassificationError) throw this.classificationError;
        for (const record of this.records) {
            const valueEnd = stataMetadataValueEnd(
                this.bytes, record.valueStart, record.valueLength
            );
            this.collector.pushAcceptedLazy(record.accepted, () => {
                return this.decoder.decode(
                    this.bytes.subarray(record.valueStart, valueEnd)
                );
            });
        }
        this.collector.finish();
    }
}
