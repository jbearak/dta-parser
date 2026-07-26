import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

import { parse_metadata } from '../typescript/dta-parser/src/header';
import { parse_legacy_metadata } from '../typescript/dta-parser/src/legacy-header';
import { DtaFile } from '../typescript/dta-parser/src/node';

type FixtureCase = { name: string; sha256: string };
type Manifest = {
    schema_version: number;
    identity: {
        canonical_oracle: string;
        canonical_sha256: string;
        fixture_count: number;
        case_count: number;
        fixture_oracle_gate: { binary: string; test: string };
    };
    fixture_cases: FixtureCase[];
    deterministic_cases: Array<{
        name: string;
        kind: string;
        coverage: string;
        gate: { binary: string; test: string };
    }>;
};

const root = path.resolve(import.meta.dir, '..');
const fixtureDir = path.join(root, 'tests/fixtures/dta');
const manifest = JSON.parse(
    readFileSync(path.join(root, 'conformance/cases.json'), 'utf8')
) as Manifest;
const canonicalBytes = readFileSync(
    path.join(root, manifest.identity.canonical_oracle)
);
const canonical = JSON.parse(canonicalBytes.toString('utf8')) as {
    schema_version: number;
    fixtures: Record<string, { sha256: string }>;
};

function invariant(condition: unknown, message: string): asserts condition {
    if (!condition) throw new Error(`conformance: ${message}`);
}

invariant(manifest.schema_version === 1, 'unsupported manifest schema');
invariant(canonical.schema_version === 2, 'unsupported canonical schema');
invariant(
    createHash('sha256').update(canonicalBytes).digest('hex')
        === manifest.identity.canonical_sha256,
    'canonical oracle identity changed; regenerate intentionally'
);
invariant(
    manifest.fixture_cases.length === manifest.identity.fixture_count,
    'fixture count does not match manifest identity'
);
invariant(
    manifest.fixture_cases.length + manifest.deterministic_cases.length
        === manifest.identity.case_count,
    'total case count does not match manifest identity'
);
invariant(manifest.identity.case_count === 29, 'case inventory must remain 29');
invariant(
    manifest.identity.fixture_oracle_gate.binary.length > 0
        && manifest.identity.fixture_oracle_gate.test.length > 0,
    'fixture canonical-oracle gate identity is missing'
);
const declaredGates = new Set<string>();
for (const item of manifest.deterministic_cases) {
    invariant(item.kind.length > 0, `${item.name} has no kind`);
    invariant(item.coverage.length > 0, `${item.name} has no coverage statement`);
    invariant(item.gate.binary.length > 0, `${item.name} has no gate binary`);
    invariant(item.gate.test.length > 0, `${item.name} has no gate test`);
    const identity = `${item.gate.binary}::${item.gate.test}`;
    invariant(!declaredGates.has(identity), `${item.name} reuses gate ${identity}`);
    declaredGates.add(identity);
}
const fixtureOracleIdentity = `${manifest.identity.fixture_oracle_gate.binary}::${manifest.identity.fixture_oracle_gate.test}`;
invariant(
    !declaredGates.has(fixtureOracleIdentity),
    'fixture canonical-oracle gate must be separate from the seven deterministic cases'
);

const diskNames = readdirSync(fixtureDir)
    .filter(name => name.endsWith('.dta'))
    .sort();
const manifestNames = manifest.fixture_cases.map(item => item.name).sort();
invariant(
    JSON.stringify(diskNames) === JSON.stringify(manifestNames),
    'disk fixture inventory differs from the checked manifest'
);
invariant(
    JSON.stringify(Object.keys(canonical.fixtures).sort())
        === JSON.stringify(manifestNames),
    'canonical fixture inventory differs from the checked manifest'
);

for (const item of manifest.fixture_cases) {
    const bytes = readFileSync(path.join(fixtureDir, item.name));
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    invariant(sha256 === item.sha256, `${item.name} hash differs from manifest`);
    invariant(
        canonical.fixtures[item.name]?.sha256 === item.sha256,
        `${item.name} hash differs from canonical oracle`
    );

    const arrayBuffer = bytes.buffer.slice(
        bytes.byteOffset,
        bytes.byteOffset + bytes.byteLength
    );
    const metadata = bytes[0] >= 113 && bytes[0] <= 115
        ? parse_legacy_metadata(arrayBuffer, bytes.length)
        : parse_metadata(arrayBuffer);
    const file = await DtaFile.open(path.join(fixtureDir, item.name));
    try {
        invariant(file.nvar === metadata.nvar, `${item.name} nvar mismatch`);
        invariant(file.nobs === metadata.nobs, `${item.name} nobs mismatch`);
        invariant(
            JSON.stringify(file.variables) === JSON.stringify(metadata.variables),
            `${item.name} variable metadata mismatch`
        );
        const start = Math.min(1, metadata.nobs);
        const count = Math.min(2, Math.max(0, metadata.nobs - start));
        const projected = metadata.nvar === 0
            ? []
            : [metadata.nvar - 1, 0];
        const rows = await file.read_rows(start, count);
        const columns = await file.read_columns(projected, { chunk_rows: 64 });
        invariant(rows.length === count, `${item.name} row-window mismatch`);
        for (const index of projected) {
            invariant(
                columns.get(index)?.slice(start, start + count).length === count,
                `${item.name} projected row-window mismatch`
            );
        }
    } finally {
        file.close();
    }
}

process.stdout.write(
    `TypeScript fixture conformance: PASS (${manifest.fixture_cases.length} `
        + 'immutable fixtures); 7 deterministic native gate identities validated '
        + '(execution follows in scripts/conformance.sh)\n'
);
