import type { ArrowType, ArrowVariable } from './arrow-types';
export interface ArrowSource {
    readonly size: number;
    read(offset: number, length: number): Uint8Array;
}
export interface IpcField extends ArrowVariable {
    bufferIndex: number;
    dictionaryId?: bigint;
}
export interface IpcBlock {
    offset: number;
    metadataLength: number;
    bodyLength: number;
}
export interface IpcBatch {
    block: IpcBlock;
    rows: number;
    nodes: Array<{
        length: number;
        nullCount: number;
    }>;
    buffers: Array<{
        offset: number;
        length: number;
    }>;
    compression?: 0 | 1;
    dictionaryId?: bigint;
    delta?: boolean;
}
export interface IpcFooter {
    fields: IpcField[];
    batches: IpcBatch[];
    dictionaries: IpcBatch[];
    metadata: Map<string, string>;
    customMetadata: Map<string, string>;
    rows: number;
}
export declare function safeSize(value: number, name: string): number;
export declare function bufferCount(field: Pick<IpcField, 'type'>): number;
export declare function physicalWidth(type: ArrowType): number;
export declare function readFooter(source: ArrowSource): IpcFooter;
export declare function readIpcBuffer(source: ArrowSource, batch: IpcBatch, index: number, maxBytes: number, expectedLength: number): Uint8Array;
//# sourceMappingURL=arrow-ipc.d.ts.map