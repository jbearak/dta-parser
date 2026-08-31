import type { DtaTextDecoder } from './text-encoding';
import { type StataMetadataCollector } from './stata-metadata';
/** One format-specific locator supplied after a record's framing is valid. */
export interface StataCharacteristicLocator {
    namesStart: number;
    nameWidth: number;
    valueStart: number;
    valueLength: number;
}
/**
 * Collect accepted locators while callers validate format-specific framing.
 * Classification errors remain deferred until `finish()`, so a later framing
 * error still wins. Values decode only after the enclosing section is valid.
 */
export declare class StataCharacteristicFramePlan {
    private readonly bytes;
    private readonly decoder;
    private readonly collector;
    private readonly records;
    private classificationError;
    private hasClassificationError;
    constructor(bytes: Uint8Array, decoder: DtaTextDecoder, collector: StataMetadataCollector);
    add(locator: StataCharacteristicLocator): void;
    finish(): void;
}
//# sourceMappingURL=characteristic-payload.d.ts.map