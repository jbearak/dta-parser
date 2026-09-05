import type { FormatVersion, MissingType, MissingValue, StataCharacteristic, StataNote } from './types';
export declare const ARROW_PROFILE_VERSION = "0";
export declare const ARROW_PROFILE_VERSION_KEY = "dtatools:profile-version";
export declare const ARROW_DATASET_KEY = "dtatools:dataset";
export declare const ARROW_FIELD_KEY = "dtatools:field";
export declare const ARROW_CHECKSUMS_KEY = "dtatools:checksums";
export interface ArrowValueLabelEntry {
    value?: number;
    tag?: MissingType;
    label: string;
}
export interface DatasetDocument {
    version: number;
    output_container?: string;
    label: string;
    notes: StataNote[];
    characteristics: StataCharacteristic[];
    value_labels: Record<string, ArrowValueLabelEntry[]>;
}
export type StataStorage = 'byte' | 'int' | 'long' | 'float' | 'double';
export interface ArrowRSemantics {
    class: string;
    ordered?: boolean;
    tz?: string;
    units?: string;
}
export interface ArrowFieldDocument {
    version: number;
    label: string;
    format: string;
    notes: StataNote[];
    characteristics: StataCharacteristic[];
    storage?: StataStorage;
    string_storage?: string;
    value_labels?: string;
    missing?: 'sentinel' | 'payload';
    missing_release?: FormatVersion;
    r?: ArrowRSemantics;
}
export interface ProfileFieldDescriptor {
    name: string;
    type: string;
    nullable: boolean;
    dictionaryKeyType?: string;
    dictionaryValueType?: string;
}
export interface BatchChecksums {
    columns: string[][];
}
export interface ChecksumsDocument {
    version: number;
    algorithm: string;
    batches: BatchChecksums[];
    dictionaries: Record<string, string[]>;
}
export declare function validateProfileVersion(version: string): void;
/** JSON.parse accepts duplicate keys. Profile documents require unique decoded keys. */
export declare function parseProfileJson(json: string): unknown;
/** Validate all registry entries, retaining only requested tables on a projection. */
export declare function validateDatasetDocument(raw: unknown, selectedValueLabels?: ReadonlySet<string>): DatasetDocument;
export declare function validateFieldDocument(raw: unknown, field: ProfileFieldDescriptor): ArrowFieldDocument;
export declare function validateValueLabelReference(field: ProfileFieldDescriptor, document: ArrowFieldDocument, dataset: DatasetDocument): void;
export declare function validateChecksumsDocument(raw: unknown): ChecksumsDocument;
/** Inspect stored bits before converting floats to JavaScript numbers. */
export declare function classifyProfileMissing(bytes: Uint8Array, offset: number, document: ArrowFieldDocument): MissingValue | null;
//# sourceMappingURL=arrow-profile.d.ts.map