import type { StataCharacteristic, StataNote, VariableInfo } from './types';
export interface StataMetadataTarget {
    notes?: StataNote[] | string[];
    characteristics?: StataCharacteristic[];
}
/** Whether this lazy target has allocated its notes array. */
export declare function isStataNotesMaterialized(target: object): boolean;
/** Whether this lazy target has allocated its characteristics array. */
export declare function isStataCharacteristicsMaterialized(target: object): boolean;
/** Add canonical metadata arrays without allocating them until first access. */
export declare function withLazyStataMetadata<T extends object>(target: T): T & {
    notes: StataNote[];
    characteristics: StataCharacteristic[];
};
export interface AcceptedStataCharacteristic {
    scopeIndex: number;
    name: string;
    noteNumber: number | null;
}
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
    private noteIndexes;
    private characteristicIndexes;
    accept(target: string, name: string): AcceptedStataCharacteristic | null;
    pushLazy(target: string, name: string, value: () => string): boolean;
    pushAcceptedLazy(accepted: AcceptedStataCharacteristic, value: () => string): void;
    private pushAccepted;
    finish(): void;
}
/** Return the canonical content end within a bounded raw metadata value. */
export declare function stataMetadataValueEnd(bytes: Uint8Array, start: number, length: number): number;
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