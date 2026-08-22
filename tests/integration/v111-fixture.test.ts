import { afterEach, describe, expect, it } from 'bun:test';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';


const ROOT = path.resolve(__dirname, '../..');
let temporary: string | null = null;

afterEach(() => {
    if (temporary !== null) {
        fs.rmSync(temporary, { recursive: true, force: true });
        temporary = null;
    }
});

describe('release-111 synthetic fixture', () => {
    it('is reproducible and identical in the Rust and R packages', () => {
        temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dta-v111-fixture-'));
        const generated = path.join(temporary, 'synthetic-v111.dta');
        const process = Bun.spawnSync([
            'python3',
            path.join(ROOT, 'tests/fixtures/generate_v111_fixture.py'),
            '--output',
            generated,
        ]);
        expect(process.exitCode).toBe(0);

        const expected = fs.readFileSync(generated);
        expect(fs.readFileSync(path.join(
            ROOT, 'r-package/dtaparser/src/dta-parser/tests/data/synthetic-v111.dta'
        ))).toEqual(expected);
        expect(fs.readFileSync(path.join(
            ROOT, 'r-package/dtaparser/inst/extdata/synthetic_v111.dta'
        ))).toEqual(expected);
    });
});
