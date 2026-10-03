# Adaptive compact-float reciprocals

[Results and limits](results-2026-10-03.md) cover the accepted adaptive kernel and the separately rejected prepare-every-block prototype. Both are compared with the previously accepted compact-float reciprocal implementation. The measured operation is public `1.01 / x`, using plain modern compact-float targets and unchanged typed-double controls.

The evidence records complete 216-observation screens and 36-case untimed qualification, exact value/storage/source and missing-cache checks, 1,980-case actual-header work proofs, release compiler evidence, and separate integration/archive qualification. Small-call controls retain the default 2,048-row native threshold. These results do not establish general double parity or reader throughput.

The [publication manifest](evidence/publication-manifest.json) binds the public files. The [source map](evidence/publication-source-map.json) records original and published hashes. Private paths and direct user identity values/digests are redacted; whole original artifact hashes are retained. Original completion and audit hashes refer to the private originals. The archived scripts contain placeholder paths and are historical snapshots, not portable commands to run from this directory.

Build receipt `variant` is the clean builder mode, not the benchmark role. Both logical roles used exact immutable Git exports, recorded as `baseline`; the benchmark controller separately pins the full commit for each role. Historical receipts and timings remain unchanged after publication integration.

A separate [PR302 integration supplement](polling-integration-2026-10-03/binding.json) records the later merge's clean build, 38,640 focused assertions and current polling work-count check. It does not replace the original measured or archive evidence.
