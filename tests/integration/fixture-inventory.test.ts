import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'bun:test';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { parse_metadata } from '../../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../../typescript/dta-parser/src/legacy-header';

const FIXTURE_DIR = path.join(__dirname, '..', 'fixtures', 'dta');

function isLegacyRelease(release: number): boolean {
    return [105, 108, 110, 111, 113, 114, 115].includes(release);
}

describe('DTA fixture inventory', () => {
    it('recognizes the exact legacy release range', () => {
        expect([105, 108, 110, 111, 113, 114, 115].every(isLegacyRelease)).toBe(true);
        expect([104, 106, 107, 109, 112, 116, 117, 118, 119]
            .some(isLegacyRelease)).toBe(false);
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

    it('reproduces every checked-in pre-111 fixture byte for byte', () => {
        const root = path.resolve(__dirname, '..', '..');
        const generated = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-pre111-'));
        try {
            execFileSync('python3', [
                path.join(root, 'tests', 'fixtures', 'generate_pre111_fixtures.py'),
                '--output-dir', generated,
            ]);
            for (const release of [105, 108, 110]) {
                const expected = fs.readFileSync(
                    path.join(generated, `synthetic-v${release}.dta`)
                );
                const rust = fs.readFileSync(path.join(
                    root, 'rust', 'dta-parser', 'tests', 'data',
                    `synthetic-v${release}.dta`
                ));
                const r = fs.readFileSync(path.join(
                    root, 'r-package', 'dtaparser', 'inst', 'extdata',
                    `synthetic_v${release}.dta`
                ));
                expect(rust.equals(expected)).toBe(true);
                expect(r.equals(expected)).toBe(true);
            }
        } finally {
            fs.rmSync(generated, { recursive: true, force: true });
        }
    });
});
