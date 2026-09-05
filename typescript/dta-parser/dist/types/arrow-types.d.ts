import type { MissingValue } from './types';
import type { ArrowFieldDocument, DatasetDocument } from './arrow-profile';
export type ArrowType = 'bool' | 'int8' | 'int16' | 'int32' | 'int64' | 'uint8' | 'uint16' | 'uint32' | 'uint64' | 'float32' | 'float64' | 'utf8' | 'large-utf8' | 'date32' | 'timestamp' | 'duration' | 'dictionary';
export type ArrowTimeUnit = 'second' | 'millisecond' | 'microsecond' | 'nanosecond';
export type ArrowCell = number | bigint | boolean | string | null | MissingValue;
export type ArrowRow = ArrowCell[];
export interface ArrowVariable {
    name: string;
    type: ArrowType;
    nullable: boolean;
    unit?: ArrowTimeUnit | 'day';
    timezone?: string;
    /** Physical epoch; timestamps without timezone retain a timezone-free epoch. */
    epoch?: string;
    /** Recorded R temporal semantics, separate from the Arrow storage unit. */
    temporal_semantics?: {
        unit: string;
        epoch?: string;
        timezone?: string;
    };
    dictionaryKeyType?: 'int8' | 'int16' | 'int32' | 'int64';
    dictionaryValueType?: 'utf8' | 'large-utf8';
    dictionaryOrdered?: boolean;
    /** Original Arrow field metadata. */
    custom_metadata: Map<string, string>;
    /** Validated dtatools field document, when profile handling is enabled. */
    profile?: ArrowFieldDocument;
}
export interface ArrowMetadata {
    nobs: number;
    nvar: number;
    profile_version?: string;
    dataset?: DatasetDocument;
    variables: ArrowVariable[];
    custom_metadata: Map<string, string>;
    footer_metadata: Map<string, string>;
}
export interface ArrowOpenOptions {
    /** Apply dtatools metadata and missing semantics. Default true. */
    profile?: boolean;
    /** Check canonical profile buffer checksums. Default true. */
    verify?: boolean;
    /** Maximum stored or decoded individual buffer bytes. Default 256 MiB. */
    max_buffer_bytes?: number;
    /** Optional bound on rows returned by one read. */
    max_output_rows?: number;
}
export interface ArrowReadOptions {
    /** Node reads yield between chunks so cancellation can be observed. */
    signal?: AbortSignal;
    /** Maximum output rows decoded between cancellation checks. Default 65536. */
    chunk_rows?: number;
}
export interface ArrowDictionary {
    /** Arrow dictionary codes are zero-based positions in these levels. */
    levels: Array<string | null>;
    ordered: boolean;
}
//# sourceMappingURL=arrow-types.d.ts.map