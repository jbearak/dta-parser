import type { DtaMetadata, Row } from './types';
/**
 * Read observation rows from a .dta buffer.
 *
 * @param buffer - The full .dta file as an ArrayBuffer
 * @param metadata - Parsed metadata from parse_metadata()
 * @param start - First row index (0-based)
 * @param count - Number of rows to read
 * @param col_start - First column index (inclusive, optional)
 * @param col_end - Last column index (exclusive, optional)
 * @returns Array of rows, each row an array of cell values
 */
export declare function read_rows_from_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
/**
 * Read observation rows from a buffer that contains only
 * contiguous observation bytes, starting at `start`.
 */
export declare function read_rows_from_data_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
//# sourceMappingURL=data-reader.d.ts.map