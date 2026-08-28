# Contributing

This repository contains an independent TypeScript reader, a Rust read/write
core, and an R package built on that Rust core. Run checks for the code you
change, then run the shared conformance gate when parsing behavior changes.

## Requirements

- Bun for the TypeScript package
- Node.js 20 or newer for its Node entrypoint
- Rust 1.98.0 with Cargo, rustfmt, and Clippy
- R 4.1.0 or newer for the R package
- Python 3.11 or newer for repository archive checks

R package dependencies are listed in [`DESCRIPTION`](r-package/dtatools/DESCRIPTION). Stata is needed only for the benchmark modules that explicitly call it.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`typescript/dta-tools`](typescript/dta-tools) | TypeScript source, tests, distribution, and npm metadata |
| [`r-package/dtatools`](r-package/dtatools) | R source package and native bridge |
| [`r-package/dtatools/src/dta-tools`](r-package/dtatools/src/dta-tools) | Canonical Rust read/write core used by the R package |
| [`tests/fixtures/dta`](tests/fixtures/dta) | Shared immutable DTA fixtures |
| [`conformance`](conformance) | Cross-implementation case inventory |
| [`scripts`](scripts) | Conformance, packaging, release, and Cargo vendor checks |
| [`benchmarks`](benchmarks) | Benchmark runners, methodology, and dated reports |

The Rust core lives inside the R source package so `R CMD build` includes its source without copying a second first-party tree. The separate `src/rust` crate is the R bridge. It builds from a locked offline archive containing only third-party Cargo dependencies.

## TypeScript

Run package checks from its directory:

```sh
cd typescript/dta-tools
bun install --frozen-lockfile
bun run typecheck
bun run test
bun run build
bun run conformance
npm pack --dry-run
```

Package tests include unit tests, a data-browser smoke test, and the shared TypeScript integration tests under the repository root.

## Rust

Run Rust checks from the repository root:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --all-targets --locked
RUSTDOCFLAGS="-D warnings" cargo doc --workspace --locked --no-deps
cargo package -p dta-tools --locked --allow-dirty
```

Use `cargo test -p dta-tools --locked --test fuzz_smoke -- --nocapture` for the deterministic fixture-seeded fuzz smoke test.

## R

Install the dependencies declared in `DESCRIPTION`, then build and check the source archive from the repository root:

```sh
dtatools_version="$(sed -n 's/^Version: //p' r-package/dtatools/DESCRIPTION)"
dtatools_tarball="dtatools_${dtatools_version}.tar.gz"
R CMD build r-package/dtatools
R CMD check --no-manual "$dtatools_tarball"
```

The package builds its Rust bridge with `--locked --offline`. When Cargo dependencies change, rebuild and verify the archive:

```sh
scripts/rebuild-r-vendor.sh
scripts/check-r-cargo-vendor.sh
```

Commit the updated `vendor.tar.gz`, checksum, and bridge lock together.

## Conformance

The conformance inventory covers format and byte order, metadata, values, labels, long strings, missing tags, projections, row windows, and representative errors. Run the shared gate from the repository root:

```sh
scripts/conformance.sh
```

The command reports the R and haven comparison as `SKIP` when its R dependencies are unavailable. Require that comparison with:

```sh
DTA_REQUIRE_R_CONFORMANCE=1 scripts/conformance.sh
```

CI requires it on the R job. Parser changes should update both the relevant implementation tests and the shared inventory or fixture oracle when the cross-language contract changes.

## Benchmarks

Benchmarks provide evidence for investigation and do not impose timing thresholds. Follow [the benchmark runbook](benchmarks/README.md), including its provenance and correctness requirements. Keep measured results in dated files under `benchmarks/`, not in package READMEs.

## Documentation

Each document has one job:

- The root README helps readers choose TypeScript or R.
- Package READMEs cover installation, first use, and package-specific behavior.
- [`docs/compatibility.md`](docs/compatibility.md) owns shared format facts.
- R manual pages own exact R argument and return-value behavior.
- Rustdoc owns the Rust crate interface and its invariants.
- This file owns repository and maintainer procedures.

Use repository-relative links in root documentation. Package READMEs should use absolute GitHub links when they point outside their package directory because registry and package renderers do not share GitHub's directory context.

## Pull requests

Keep changes focused and include regression coverage for behavior changes. Run the checks for each affected language. Run conformance when parsing, encoding, missing-value, label, projection, or error behavior changes.

Before committing documentation, check that examples match the current interface and that shared compatibility facts appear only in the compatibility document.

## Maintainer release

The release command updates the npm, R, and Rust versions and lockfiles, runs local release checks, commits and tags the version, pushes it, and publishes a GitHub Release. Run it only from a clean `main` branch with `gh` authenticated:

```sh
scripts/bump-version.sh patch
```

Use `minor`, `major`, or an explicit `X.Y.Z` instead. The tag starts npm publishing. Publishing the GitHub Release starts the cross-platform R builds and attaches their binaries to that release.
