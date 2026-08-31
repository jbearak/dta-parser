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
/** Incrementally folds raw characteristic records into canonical metadata. */
export declare class StataMetadataCollector {
    private readonly scopes;
    private readonly targetIndexes;
    private readonly indexes;
    constructor(dataset: StataMetadataTarget, variables: VariableInfo[]);
    accepts(target: string, name: string): boolean;
    push(record: StataCharacteristicRecord): void;
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