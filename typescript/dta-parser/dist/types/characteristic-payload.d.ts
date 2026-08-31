import type { DtaTextDecoder } from './text-encoding';
import { type AcceptedStataCharacteristic, type StataMetadataCollector } from './stata-metadata';
/** One accepted record whose value remains in the source metadata buffer. */
export interface FramedStataCharacteristic {
    accepted: AcceptedStataCharacteristic;
    valueStart: number;
    valueLength: number;
}
/** Decode values only after their complete enclosing section has been framed. */
export declare function decodeStataCharacteristicPayloads(bytes: Uint8Array, records: readonly FramedStataCharacteristic[], decoder: DtaTextDecoder, collector: StataMetadataCollector): void;
//# sourceMappingURL=characteristic-payload.d.ts.map