import type { DtaTextDecoder } from './text-encoding';
import {
    stataMetadataValueEnd,
    type AcceptedStataCharacteristic,
    type StataMetadataCollector,
} from './stata-metadata';

/** One accepted record whose value remains in the source metadata buffer. */
export interface FramedStataCharacteristic {
    accepted: AcceptedStataCharacteristic;
    valueStart: number;
    valueLength: number;
}

/** Decode values only after their complete enclosing section has been framed. */
export function decodeStataCharacteristicPayloads(
    bytes: Uint8Array,
    records: readonly FramedStataCharacteristic[],
    decoder: DtaTextDecoder,
    collector: StataMetadataCollector
): void {
    for (const record of records) {
        const valueEnd = stataMetadataValueEnd(
            bytes, record.valueStart, record.valueLength
        );
        collector.pushAcceptedLazy(record.accepted, () => {
            return decoder.decode(bytes.subarray(record.valueStart, valueEnd));
        });
    }
    collector.finish();
}
