import type { LegacyFormatVersion } from './types';
export type LegacyValueLabelLayout = 'fixed8' | 'offset_table';
export interface LegacyLayout {
    header_size: number;
    dataset_label_width: number;
    varname_width: number;
    format_width: number;
    value_label_name_width: number;
    variable_label_width: number;
    expansion_length_width: 2 | 4;
    value_label_table_name_width: number;
    value_label_layout: LegacyValueLabelLayout;
}
export declare function legacy_layout_for_version(version: LegacyFormatVersion): LegacyLayout;
export declare function legacy_expansion_header_size(layout: LegacyLayout): number;
//# sourceMappingURL=legacy-layout.d.ts.map