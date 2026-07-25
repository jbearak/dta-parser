import { describe, expect, it } from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';

const R_PACKAGE = path.join(__dirname, '..', '..', 'r-package', 'dtaparser');

describe('R package native build configuration', () => {
    it('pins and validates the 64-bit GNU Windows Rust target', () => {
        const makevars = fs.readFileSync(
            path.join(R_PACKAGE, 'src', 'Makevars.win.in'),
            'utf8'
        );
        const configure = fs.readFileSync(
            path.join(R_PACKAGE, 'configure.win'),
            'utf8'
        );

        expect(makevars).toContain('RUST_WINDOWS_TARGET = x86_64-pc-windows-gnu');
        expect(makevars).toContain('--target $(RUST_WINDOWS_TARGET)');
        expect(makevars).toContain('-ladvapi32');
        expect(configure).toContain('rust_target=x86_64-pc-windows-gnu');
        expect(configure).toContain('rustc -vV');
        expect(configure).toContain('if test "$rust_host" != "$rust_target"');
    });

    it('uses the locked offline vendor archive on every platform', () => {
        for (const file of ['Makevars.in', 'Makevars.win.in']) {
            const makevars = fs.readFileSync(
                path.join(R_PACKAGE, 'src', file),
                'utf8'
            );
            expect(makevars).toContain('rust/vendor.tar.gz');
            expect(makevars).toContain('--locked --offline');
            expect(makevars).toContain('--config rust/cargo-config.toml');
        }
    });
});
