/** xxHash64 with the profile's fixed zero seed. */
export declare function xxh64(bytes: Uint8Array): bigint;
export interface CanonicalArrowBuffers {
    type: string;
    length: number;
    offset?: number;
    /** Omit when the logical array has no null bitmap. */
    validity?: Uint8Array;
    validityOffset?: number;
    /** Data buffers, excluding validity. */
    buffers: readonly Uint8Array[];
    dictionaryKeyType?: string;
}
/** Dictionary arrays hash keys here; hash their shared values separately. */
export declare function canonicalBufferHashes(array: CanonicalArrowBuffers): string[];
//# sourceMappingURL=arrow-checksum.d.ts.map