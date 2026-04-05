import type { DtaMetadata, LegacyFormatVersion } from './types';
/**
 * Compute the minimum buffer size needed to read all
 * metadata sections for a legacy .dta file, given nvar.
 * This is everything up to and including the expansion
 * fields terminator (we add a generous allowance for
 * expansion fields since they're typically tiny).
 */
export declare function legacy_metadata_buffer_size(nvar: number, format_version: LegacyFormatVersion): number;
/**
 * Parse legacy .dta metadata from a buffer containing at
 * least the header and all variable metadata sections.
 *
 * The buffer does NOT need to contain the entire file —
 * it only needs to extend past the expansion fields.
 *
 * @param buffer - Buffer starting at byte 0 of the file
 * @param file_size - Total file size (for end_of_file)
 */
export declare function parse_legacy_metadata(buffer: ArrayBuffer, file_size: number): DtaMetadata;
//# sourceMappingURL=legacy-header.d.ts.map