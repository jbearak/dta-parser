import { createHash } from 'node:crypto';
import { describe, expect, it } from 'bun:test';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { parse_metadata } from '../../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../../typescript/dta-parser/src/legacy-header';

const FIXTURE_DIR = path.join(__dirname, '..', 'fixtures', 'dta');

function isLegacyRelease(release: number): boolean {
    return release >= 113 && release <= 115;
}

describe('DTA fixture inventory', () => {
    it('recognizes the exact legacy release range', () => {
        expect([113, 114, 115].every(isLegacyRelease)).toBe(true);
        expect([112, 116, 117, 118, 119].some(isLegacyRelease)).toBe(false);
    });

    it('has distinct bytes and release-accurate names', () => {
        const fixtures = fs.readdirSync(FIXTURE_DIR)
            .filter(name => name.endsWith('.dta'))
            .sort();
        expect(fixtures).toHaveLength(22);
        expect(fixtures.some(name => /_v(?:114|119)[.]dta$/.test(name))).toBe(false);

        const seenHashes = new Map<string, string>();
        for (const fixture of fixtures) {
            const bytes = fs.readFileSync(path.join(FIXTURE_DIR, fixture));
            const hash = createHash('sha256').update(bytes).digest('hex');
            expect(seenHashes.get(hash)).toBeUndefined();
            seenHashes.set(hash, fixture);

            const arrayBuffer = bytes.buffer.slice(
                bytes.byteOffset,
                bytes.byteOffset + bytes.byteLength
            );
            const actualRelease = isLegacyRelease(bytes[0])
                ? parse_legacy_metadata(arrayBuffer, bytes.length).format_version
                : parse_metadata(arrayBuffer).format_version;
            const expectedRelease = fixture.endsWith('_v115.dta')
                ? 115
                : fixture.endsWith('_v117.dta')
                    ? 117
                    : 118;
            expect(actualRelease).toBe(expectedRelease);
        }
    });
});
