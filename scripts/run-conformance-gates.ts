import { readFileSync } from 'node:fs';
import path from 'node:path';

type Gate = { binary: string; test: string };
type Manifest = {
    identity: { fixture_oracle_gate: Gate };
    deterministic_cases: Array<{ name: string; gate: Gate }>;
};

const root = path.resolve(import.meta.dir, '..');
const manifest = JSON.parse(
    readFileSync(path.join(root, 'conformance/cases.json'), 'utf8')
) as Manifest;
const caseGates = manifest.deterministic_cases.map(item => ({
    label: item.name,
    ...item.gate,
}));
const gates = [
    ...caseGates,
    { label: 'fixture-canonical-oracle', ...manifest.identity.fixture_oracle_gate },
];

function run(arguments_: string[]): string {
    const result = Bun.spawnSync(arguments_, {
        cwd: root,
        stdout: 'pipe',
        stderr: 'pipe',
        env: process.env,
    });
    const stdout = result.stdout.toString();
    const stderr = result.stderr.toString();
    process.stdout.write(stdout);
    process.stderr.write(stderr);
    if (result.exitCode !== 0) {
        throw new Error(`command failed (${result.exitCode}): ${arguments_.join(' ')}`);
    }
    return `${stdout}\n${stderr}`;
}

const listedByBinary = new Map<string, string[]>();
for (const binary of new Set(gates.map(gate => gate.binary))) {
    const output = run([
        'cargo', 'test', '-p', 'dta-parser', '--locked',
        '--test', binary, '--', '--list',
    ]);
    const listed = output
        .split(/\r?\n/u)
        .map(line => /^(.*): test$/u.exec(line)?.[1])
        .filter((name): name is string => name !== undefined);
    listedByBinary.set(binary, listed);
}

for (const gate of gates) {
    const listed = listedByBinary.get(gate.binary);
    if (!listed || listed.filter(name => name === gate.test).length !== 1) {
        throw new Error(
            `${gate.label}: expected exactly listed test ${gate.binary}::${gate.test}`
        );
    }
    const output = run([
        'cargo', 'test', '-p', 'dta-parser', '--locked',
        '--test', gate.binary, gate.test, '--', '--exact', '--nocapture',
    ]);
    const resultLines = output.match(
        /test result: ok\. 1 passed; 0 failed; \d+ ignored; \d+ measured; \d+ filtered out;/gu
    ) ?? [];
    if (resultLines.length !== 1) {
        throw new Error(
            `${gate.label}: gate did not report exactly one passing test (${gate.binary}::${gate.test})`
        );
    }
}

process.stdout.write(
    `native conformance gates: PASS (${caseGates.length} deterministic cases + 1 fixture canonical oracle)\n`
);
