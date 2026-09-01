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
 * Value-bound and classification errors remain deferred until `finish()`, so
 * a later framing error still wins. Every value is bounded, but rejected
 * records retain no descriptor. Values decode after the section is valid.
 */
export declare class StataCharacteristicFramePlan {
    private readonly bytes;
    private readonly decoder;
    private readonly collector;
    private readonly records;
    private recordIndices;
    private deferredError;
    private hasDeferredError;
    constructor(bytes: Uint8Array, decoder: DtaTextDecoder, collector: StataMetadataCollector);
    /** Number of distinct accepted scope/key locators retained for decoding. */
    get retainedCount(): number;
    /** Number of canonical-key lookup entries still retained for framing. */
    get retainedIndexCount(): number;
    add(locator: StataCharacteristicLocator): void;
    finish(): void;
}
//# sourceMappingURL=characteristic-payload.d.ts.map