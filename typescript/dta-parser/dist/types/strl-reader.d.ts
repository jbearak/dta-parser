import type { DtaMetadata } from './types';
import type { ResolvedTextEncoding } from './text-encoding';
export interface GsoEntry {
    content_offset: number;
    content_length: number;
    type: number;
}
export interface StrlPointer {
    v: number;
    o: number;
}
/**
 * Build an index of all GSO entries from the strls section.
 *
 * Returns a Map keyed by "v:o" string for O(1) lookup.
 * The map is empty when the dataset has no strL variables.
 */
export declare function build_gso_index(buffer: ArrayBuffer, metadata: DtaMetadata, base_offset?: number): Map<string, GsoEntry>;
/**
 * Resolve a strL pointer at the given byte offset in the
 * data section. Returns the string content, or an empty string
 * for a (v=0, o=0) null pointer. A missing non-null GSO key is
 * rejected as corrupt input.
 *
 * The pointer_offset must point to the first byte of an
 * 8-byte strL pointer field.
 */
export declare function resolve_strl(buffer: ArrayBuffer, metadata: DtaMetadata, gso_index: Map<string, GsoEntry>, pointer_offset: number): string;
export declare function read_strl_pointer(view: DataView, metadata: DtaMetadata, pointer_offset: number): StrlPointer | null;
export declare function decode_gso_entry(bytes: Uint8Array, entry: GsoEntry, encoding?: ResolvedTextEncoding): string;
//# sourceMappingURL=strl-reader.d.ts.map