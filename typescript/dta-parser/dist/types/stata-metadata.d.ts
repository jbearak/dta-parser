import type { StataCharacteristic, StataNote, VariableInfo } from './types';
export interface StataMetadataTarget {
    notes: StataNote[];
    characteristics: StataCharacteristic[];
}
export interface StataCharacteristicRecord {
    target: string;
    name: string;
    value: string;
}
export declare const MAX_STATA_METADATA_VALUE_BYTES = 67784;
/** Whether a raw key can be represented by the canonical public metadata. */
export declare function isRetainedStataCharacteristicName(name: string): boolean;
/** Incrementally folds raw characteristic records into canonical metadata. */
export declare class StataMetadataCollector {
    private readonly dataset;
    private readonly variables;
    private targetIndexes;
    private readonly indexes;
    constructor(dataset: StataMetadataTarget, variables: VariableInfo[]);
    private targetIndex;
    private scope;
    private scopeIndexes;
    private classify;
    push(record: StataCharacteristicRecord): void;
    pushLazy(target: string, name: string, value: () => string): boolean;
    private pushAccepted;
    finish(): void;
}
export declare function applyCharacteristicRecords(records: StataCharacteristicRecord[], dataset: StataMetadataTarget, variables: VariableInfo[]): void;
export declare function listStataNotes(target: StataMetadataTarget): StataNote[];
export declare function getStataNote(target: StataMetadataTarget, number: number): string | undefined;
export declare function setStataNote(target: StataMetadataTarget, number: number, text: string): void;
export declare function addStataNote(target: StataMetadataTarget, text: string): number;
export declare function dropStataNotes(target: StataMetadataTarget, numbers?: readonly number[]): void;
export declare function renumberStataNotes(target: StataMetadataTarget, start?: number): void;
export declare function listStataCharacteristics(target: StataMetadataTarget): StataCharacteristic[];
export declare function getStataCharacteristic(target: StataMetadataTarget, name: string): string | undefined;
export declare function setStataCharacteristic(target: StataMetadataTarget, name: string, value: string): void;
export declare function dropStataCharacteristics(target: StataMetadataTarget, names?: readonly string[]): void;
//# sourceMappingURL=stata-metadata.d.ts.map