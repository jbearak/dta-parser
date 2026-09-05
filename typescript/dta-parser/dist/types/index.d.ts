export { parse_metadata } from './header';
export { ArrowBuffer } from './arrow-reader';
export type { ArrowCell, ArrowRow, ArrowType, ArrowTimeUnit, ArrowVariable, ArrowMetadata, ArrowDictionary, ArrowOpenOptions, ArrowReadOptions } from './arrow-types';
export type { ArrowFieldDocument, DatasetDocument, ArrowRSemantics, ArrowValueLabelEntry } from './arrow-profile';
export { parse_legacy_metadata, legacy_metadata_buffer_size, } from './legacy-header';
export { read_rows_from_buffer, read_rows_from_data_buffer, } from './data-reader';
export { build_gso_index, decode_gso_entry, read_strl_pointer, resolve_strl, type GsoEntry, } from './strl-reader';
export { parse_value_labels } from './value-labels';
export { apply_display_format } from './display-format';
export { addStataNote, dropStataCharacteristics, dropStataNotes, getStataCharacteristic, getStataNote, listStataCharacteristics, listStataNotes, renumberStataNotes, setStataCharacteristic, setStataNote, } from './stata-metadata';
export type { StataMetadataTarget } from './stata-metadata';
export type { VariableInfo, Row, RowCell, MissingType, MissingValue, DtaMetadata, ParsedDtaMetadata, ParsedVariableInfo, DtaType, FormatVersion, LegacyFormatVersion, SectionOffsets, StataCharacteristic, StataNote, } from './types';
export type { TextEncoding, TextEncodingLabel, ResolvedTextEncoding, TextEncodingOptions, } from './text-encoding';
export { resolve_text_encoding } from './text-encoding';
export { is_legacy_format } from './types';
export { classify_missing_value, classify_raw_float_missing, classify_raw_double_missing_at, is_missing_value, is_missing_value_object, make_missing_value, missing_type_to_label_key, STATA_MISSING_B, } from './missing-values';
//# sourceMappingURL=index.d.ts.map