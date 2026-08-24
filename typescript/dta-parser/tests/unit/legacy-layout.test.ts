import { describe, expect, it } from 'bun:test';
import { legacy_layout_for_version } from '../../src/legacy-layout';
import type { LegacyValueLabelLayout } from '../../src/legacy-layout';
import type { LegacyFormatVersion } from '../../src/types';

describe('legacy_layout_for_version', () => {
    it('centralizes value-label table layouts for every release', () => {
        const the_expected: Array<[
            LegacyFormatVersion,
            number,
            LegacyValueLabelLayout,
        ]> = [
            [105, 9, 'fixed8'],
            [108, 9, 'offset_table'],
            [110, 33, 'offset_table'],
            [111, 33, 'offset_table'],
            [113, 33, 'offset_table'],
            [114, 33, 'offset_table'],
            [115, 33, 'offset_table'],
        ];

        for (const [version, name_width, layout] of the_expected) {
            const my_layout = legacy_layout_for_version(version);
            expect(my_layout.value_label_table_name_width).toBe(
                name_width
            );
            expect(my_layout.value_label_layout).toBe(layout);
        }
    });
});
