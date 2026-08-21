import type { LegacyFormatVersion } from './types';

export interface LegacyLayout {
    header_size: number;
    dataset_label_width: number;
    varname_width: number;
    format_width: number;
    value_label_name_width: number;
    variable_label_width: number;
    expansion_length_width: 2 | 4;
}

const LAYOUTS: Record<LegacyFormatVersion, LegacyLayout> = {
    105: { header_size: 60, dataset_label_width: 32, varname_width: 9, format_width: 12, value_label_name_width: 9, variable_label_width: 32, expansion_length_width: 2 },
    108: { header_size: 109, dataset_label_width: 81, varname_width: 9, format_width: 12, value_label_name_width: 9, variable_label_width: 81, expansion_length_width: 2 },
    110: { header_size: 109, dataset_label_width: 81, varname_width: 33, format_width: 12, value_label_name_width: 33, variable_label_width: 81, expansion_length_width: 4 },
    111: { header_size: 109, dataset_label_width: 81, varname_width: 33, format_width: 12, value_label_name_width: 33, variable_label_width: 81, expansion_length_width: 4 },
    113: { header_size: 109, dataset_label_width: 81, varname_width: 33, format_width: 12, value_label_name_width: 33, variable_label_width: 81, expansion_length_width: 4 },
    114: { header_size: 109, dataset_label_width: 81, varname_width: 33, format_width: 49, value_label_name_width: 33, variable_label_width: 81, expansion_length_width: 4 },
    115: { header_size: 109, dataset_label_width: 81, varname_width: 33, format_width: 49, value_label_name_width: 33, variable_label_width: 81, expansion_length_width: 4 },
};

export function legacy_layout_for_version(version: LegacyFormatVersion): LegacyLayout {
    return LAYOUTS[version];
}

export function legacy_expansion_header_size(layout: LegacyLayout): number {
    return 1 + layout.expansion_length_width;
}
