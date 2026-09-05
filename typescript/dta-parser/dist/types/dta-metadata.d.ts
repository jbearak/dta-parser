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
    private uniqueNoteScopes;
    private uniqueCharacteristicScopes;
    constructor(dataset: StataMetadataTarget, variables: VariableInfo[]);
    /** Variable-name lookup entries still retained by this collector. */
    get retainedTargetIndexCount(): number;
    private targetIndex;
    private scope;
    private uniqueNotes;
    private uniqueCharacteristics;
    accept(target: string, name: string): AcceptedStataCharacteristic | null;
    /** Materialize a record from a plan that already resolved duplicates. */
    pushAcceptedUniqueLazy(accepted: AcceptedStataCharacteristic, value: () => string): void;
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
//# sourceMappingURL=dta-metadata.d.ts.map