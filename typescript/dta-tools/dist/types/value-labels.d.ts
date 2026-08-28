import type { DtaMetadata } from './types';
/**
 * Parse all value label tables from the value_labels
 * section of a .dta file.
 *
 * Returns a Map of table_name to a Map of integer_value
 * to label_string.
 */
export declare function parse_value_labels(buffer: ArrayBuffer, metadata: DtaMetadata, base_offset?: number): Map<string, Map<number, string>>;
//# sourceMappingURL=value-labels.d.ts.map