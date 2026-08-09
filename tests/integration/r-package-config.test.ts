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

    it('namespaces native outputs by the pinned parser tree', () => {
        const canonicalPin = fs.readFileSync(
            path.join(R_PACKAGE, '..', '..', 'rust', 'dta-parser.tree.sha256'),
            'utf8'
        );
        const mirrorPin = fs.readFileSync(
            path.join(R_PACKAGE, 'src', 'vendor', 'dta-parser.tree.sha256'),
            'utf8'
        );
        expect(mirrorPin).toBe(canonicalPin);
        expect(mirrorPin).toMatch(
            /^[0-9a-f]{64}  dta-parser-runtime-tree-v1\n$/
        );

        for (const file of ['Makevars.in', 'Makevars.win.in']) {
            const makevars = fs.readFileSync(
                path.join(R_PACKAGE, 'src', file),
                'utf8'
            );
            expect(makevars).toContain(
                'DTA_PARSER_PIN = vendor/dta-parser.tree.sha256'
            );
            expect(makevars).toContain(
                'DTA_PARSER_NAMESPACE = @DTA_PARSER_NAMESPACE@'
            );
            expect(makevars).toContain('dta-parser-$(DTA_PARSER_NAMESPACE)');
            expect(makevars).toContain('$(DTA_PARSER_PIN)');
            expect(makevars).toContain('$(RUST_SOURCES)');
        }
    });

    it('refreshes extracted Cargo dependencies on every configure run', () => {
        for (const file of ['configure', 'configure.win']) {
            const configure = fs.readFileSync(
                path.join(R_PACKAGE, file),
                'utf8'
            );
            expect(configure).toContain('rm -rf src/rust/v');
            expect(configure).toContain(
                'tar -xzf src/rust/vendor.tar.gz -C src/rust'
            );
            expect(configure).toContain('test -d src/rust/v');
            expect(configure).not.toContain('if test ! -d src/rust/v');
        }
    });
});
