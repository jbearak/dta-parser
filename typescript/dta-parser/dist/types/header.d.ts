import type { FormatVersion, ParsedDtaMetadata, SectionOffsets } from './types';
import type { DtaTextDecoder, TextEncodingOptions } from './text-encoding';
import { resolve_text_encoding } from './text-encoding';
declare const FIELD_WIDTHS: {
    readonly 117: {
        readonly varname: 33;
        readonly format: 49;
        readonly value_label_name: 33;
        readonly variable_label: 81;
    };
    readonly 118: {
        readonly varname: 129;
        readonly format: 57;
        readonly value_label_name: 129;
        readonly variable_label: 321;
    };
    readonly 119: {
        readonly varname: 129;
        readonly format: 57;
        readonly value_label_name: 129;
        readonly variable_label: 321;
    };
};
type ModernFieldWidths = (typeof FIELD_WIDTHS)[keyof typeof FIELD_WIDTHS];
export interface ModernMetadataHeader {
    format_version: FormatVersion;
    text_encoding: ReturnType<typeof resolve_text_encoding>;
    decoder: DtaTextDecoder;
    widths: ModernFieldWidths;
    byte_order: 'MSF' | 'LSF';
    little_endian: boolean;
    nvar: number;
    nobs: number;
    dataset_label: string;
    section_offsets: SectionOffsets;
}
/** Parse the reusable header and section-map state from a modern prefix. */
export declare function parse_modern_metadata_header(buffer: ArrayBuffer, options?: TextEncodingOptions): ModernMetadataHeader;
export declare function parse_metadata(buffer: ArrayBuffer, options?: TextEncodingOptions): ParsedDtaMetadata;
/** Parse variable metadata using header state already obtained from a prefix. */
export declare function parse_metadata_from_header(buffer: ArrayBuffer, header: ModernMetadataHeader): ParsedDtaMetadata;
export {};
//# sourceMappingURL=header.d.ts.map