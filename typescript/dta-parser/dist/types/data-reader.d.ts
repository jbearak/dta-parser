import type { DtaMetadata, Row, RowCell } from './types';
type DataBuffer = ArrayBuffer | Uint8Array;
/** Reject NaN and finite fractions; infinities retain sentinel semantics. */
export declare function assert_valid_row_range(start: number, count: number): void;
/** Read observation rows from a complete .dta file buffer. */
export declare function read_rows_from_buffer(buffer: ArrayBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
/** Read rows from a buffer containing contiguous observation bytes. */
export declare function read_rows_from_data_buffer(buffer: DataBuffer, metadata: DtaMetadata, start: number, count: number, col_start?: number, col_end?: number): Row[];
/**
 * Decode selected columns from contiguous observation bytes.
 *
 * When `out_offset` is present, values overwrite that range in each target.
 * Otherwise each target is appended to, preserving the original helper
 * contract for callers outside the Node reader.
 */
export declare function read_columns_from_data_buffer(buffer: DataBuffer, metadata: DtaMetadata, count: number, col_indices: number[], out: Map<number, RowCell[]>, out_offset?: number): void;
export {};
//# sourceMappingURL=data-reader.d.ts.map