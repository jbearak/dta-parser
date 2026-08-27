import type { FormatVersion } from './types';
/** Source encoding requested for textual fields in a Stata file. */
export type TextEncoding = 'auto' | 'utf-8' | 'windows-1252' | 'iso-8859-1';
/** Common labels accepted by the R and Rust APIs as well as canonical names. */
export type TextEncodingLabel = TextEncoding | 'UTF-8' | 'UTF8' | 'utf8' | 'Windows-1252' | 'CP1252' | 'cp1252' | 'ISO-8859-1' | 'latin1' | (string & Record<never, never>);
/** Concrete encoding selected after the file release is known. */
export type ResolvedTextEncoding = Exclude<TextEncoding, 'auto'>;
/** Options shared by metadata parsers and the Node file entrypoint. */
export interface TextEncodingOptions {
    /**
     * Source encoding for every textual field. `auto` uses Windows-1252
     * through release 117 and UTF-8 for releases 118--119.
     */
    encoding?: TextEncodingLabel;
}
export interface DtaTextDecoder {
    decode(input: Uint8Array): string;
}
/** Decode a byte range without allocating a view for the common ASCII case. */
export declare function decode_text_range(decoder: DtaTextDecoder, bytes: Uint8Array, start: number, end: number): string;
/** Validate an encoding label without requiring a file release. */
export declare function validate_text_encoding(encoding?: TextEncodingLabel): void;
/** Resolve the release-specific default or validate an explicit encoding. */
export declare function resolve_text_encoding(format_version: FormatVersion, encoding?: TextEncodingLabel): ResolvedTextEncoding;
/** Return the deterministic decoder for an already resolved encoding. */
export declare function text_decoder(encoding: ResolvedTextEncoding): DtaTextDecoder;
//# sourceMappingURL=text-encoding.d.ts.map