# Native CodeQL extraction

Ordinary runs analyze Actions, JavaScript/TypeScript, Python and Rust without compiling the R package. Pull requests run only when those languages, their dependency manifests, Actions workflows or CodeQL files change. Merging a checked PR does not repeat the scan on `main`. The weekly schedule checks `main`, and manual dispatch remains available. Both run only these four fast analyses. Superseded pull-request runs are canceled.

Full C/C++ analysis is supplementary and can take hours. It runs locally only when useful for an investigation. GitHub has no C/C++ lane, including manual dispatch, and it is not a merge or release gate. Compiler diagnostics, focused native regression tests and measured performance qualification provide the primary validation. The fast CI guard runs the collector regression tests on ordinary changes. The four hosted analyses retain their default security suites and remote threat model.

`build.py` binds inputs to the checked-out commit on every run. It discovers package `src/*.c`, `.h` and `.inc` files dynamically and uses the package's unchanged configuration, R build flags and Rust archive. Rust dependencies are built offline before CodeQL tracing begins. The subsequent traced phase compiles every package C unit, the maintained standalone probes and the R test fixtures using their real includes. Current source hashes, compiler commands, installed R headers and generated probe-header mappings are retained with the coverage evidence. Generated instrumented headers are identified as derived inputs; they do not count as original production-header bodies.

`native-source-scope.json` lists the maintained standalone build inputs and 160 immutable historical C/header snapshots. The snapshots are archived benchmark data under the explicit manual-build policy. Their original classifications and publication bindings remain recorded. Every tracked C/C++/header/include path must be a discovered package input, a mapped maintained input or an unchanged historical snapshot. Unknown inputs, changed archived bytes and symlinks fail validation. A newly maintained standalone source needs a build route in the same reviewed change. Adding a package C source includes it automatically in the R build.

The local `collector.qualify()` function checks actual manual compilation records, source/header metrics, original-path function bodies, real R and descriptor type witnesses, extraction errors and reachable includes. It rejects archived headers reaching a maintained translation unit and unexpected traced dependency C units. The declaration-only `probe-bracket-live-cache.h` has explicit include, declaration and type checks. These checks cover the Linux LP64 build with R 4.6.0 and Rust 1.98.0. They do not establish every preprocessor branch, Windows or Apple-specific bodies, or full semantic equivalence of the extracted model.

The earlier 116-file no-build coverage contract failed and remains failed. Successful security-query evaluation alone did not prove acceptable extraction. The current manual active-source contract is a separately reviewed native coverage check. A requested deep scan is complete only when its full query evaluation and coverage verdict pass. Failed, pending or canceled scans remain unqualified; they are not ordinary merge gates.

Both hosted CodeQL actions are pinned to `2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2` and use their linked tools without a native build. The optional local recipe verifies the official CLI 2.27.1 Linux bundle, retains all 61 bundled `cpp-queries` 1.9.0 queries and requests `--max-disk-cache=32768` for their evaluation. This bounds the intermediate query cache, not total job storage or RAM. Extracting a database or validating command syntax alone does not prove the full query evaluation will complete.

Keep hosted action pins and their allowlist entries current through reviewed changes. Update the optional local bundle digest and query inventory together when changing its CLI. Revalidate coverage witnesses when the local CLI changes. Interface changes that affect the named type witnesses update those witnesses in the same PR.

GitHub rejects advanced CodeQL uploads while managed default setup is enabled. The repository already uses this advanced workflow with managed setup disabled. Changing its event routing requires no repository settings change. Existing uploaded results remain available; the private transition receipt records the earlier approved settings request.

For the complete local extraction recipe below, use a clean, committed Linux x86_64 worktree with R 4.6.0, Rust 1.98.0, Python, a C compiler, `make`, `curl`, `libuv` development headers and `pkg-config`. Its pinned Linux bundle cannot execute on macOS. A macOS investigation needs a matching macOS CodeQL installation and platform-specific build instructions; the complete coverage contract below has not been validated on macOS. Keep Cargo/R dependencies cached. Preparation reuses the unchanged Rust archive target when it is current. CodeQL requires one intentional traced C compilation in a fresh worktree; existing C objects would hide source from the extractor. Reuse the resulting database for additional checks instead of repeatedly compiling the R package. Ordinary package testing does not require this extraction.

The following commands prepare the pinned bundle, extract once and finalize a local database. They do not execute the expensive security suite:

```sh
CODEQL_TASK_ROOT="$(pwd -P)"
CODEQL_TASK_DIR="$(mktemp -d)"
export RUSTUP_TOOLCHAIN=1.98.0
python3 .github/codeql/build.py prebuild --root "$CODEQL_TASK_ROOT" --work "$CODEQL_TASK_DIR/native"
python3 .github/codeql/build.py bundle --root "$CODEQL_TASK_ROOT" --work "$CODEQL_TASK_DIR/native"
tar -xzf "$CODEQL_TASK_DIR/native/official-codeql-bundle.tar.gz" -C "$CODEQL_TASK_DIR"
CODEQL_TASK_CLI="$CODEQL_TASK_DIR/codeql/codeql"
CODEQL_TASK_DB="$CODEQL_TASK_DIR/cpp-db"
"$CODEQL_TASK_CLI" database init --language=cpp --build-mode=manual --source-root="$CODEQL_TASK_ROOT" "$CODEQL_TASK_DB"
"$CODEQL_TASK_CLI" database trace-command "$CODEQL_TASK_DB" -- python3 "$CODEQL_TASK_ROOT/.github/codeql/build.py" build --root "$CODEQL_TASK_ROOT" --work "$CODEQL_TASK_DIR/native"
"$CODEQL_TASK_CLI" database finalize --threads=2 --ram=3072 "$CODEQL_TASK_DB"
```

Run the seven extraction fact queries against that same database and apply the existing coverage validator:

```sh
mkdir -p "$CODEQL_TASK_DIR/coverage"
for query in diagnostics compilations includes files bodies includes-absolute types; do
  "$CODEQL_TASK_CLI" query run --database="$CODEQL_TASK_DB" --search-path="$CODEQL_TASK_DIR/codeql/qlpacks" --threads=2 --ram=3072 --max-disk-cache=1024 --output="$CODEQL_TASK_DIR/coverage/$query.bqrs" "$CODEQL_TASK_ROOT/.github/codeql/queries/$query.ql"
  "$CODEQL_TASK_CLI" bqrs decode --format=csv --result-set='#select' --output="$CODEQL_TASK_DIR/coverage/$query.csv" "$CODEQL_TASK_DIR/coverage/$query.bqrs"
done
python3 - "$CODEQL_TASK_ROOT" "$CODEQL_TASK_DIR" <<'PY'
import importlib.util, json, pathlib, sys
root, work = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("collector", root / ".github/codeql/collector.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
read = lambda name: json.loads((work / "native" / name).read_text())
verdict = collector.qualify(collector.tables_at(work / "coverage"), read("active-scope.json"), read("prebuild.json"), read("build.json"))
(work / "coverage/verdict.json").write_text(json.dumps(verdict, indent=2) + "\n")
print(verdict["status"])
if verdict["status"] != "PASS_MANUAL_ACTIVE_EXTRACTION":
    raise SystemExit(1)
PY
```

This local verdict proves the declared extraction witnesses, not full security evaluation or GitHub uploads. The collector's historical action-specific `initialized`/`collect` phases are not called by the current hosted workflow and are not substitutes for this standalone local procedure.

If a full local scan is useful, reuse the database and generate the unchanged 61-query suite from the pinned inventory. This optional step can take hours:

```sh
python3 - "$CODEQL_TASK_ROOT" "$CODEQL_TASK_DIR" <<'PY'
import json, pathlib, sys
root, work = map(pathlib.Path, sys.argv[1:])
names = json.loads((root / ".github/codeql/expected-query-names.json").read_text())
pack = work / "codeql/qlpacks/codeql/cpp-queries/1.9.0"
paths = [pack / name.removeprefix("codeql/cpp-queries/") for name in names]
if len(paths) != 61 or not all(path.is_file() for path in paths):
    raise SystemExit("Pinned 61-query inventory is unavailable")
(work / "full-default.qls").write_text(json.dumps([{"query": str(path)} for path in paths], indent=2) + "\n")
PY
"$CODEQL_TASK_CLI" database run-queries --threads=2 --ram=8192 --max-disk-cache=32768 "$CODEQL_TASK_DB" "$CODEQL_TASK_DIR/full-default.qls"
"$CODEQL_TASK_CLI" database interpret-results --format=sarif-latest --sarif-category=/language:c-cpp --output="$CODEQL_TASK_DIR/cpp.sarif" "$CODEQL_TASK_DB" "$CODEQL_TASK_DIR/full-default.qls"
```

Hosted scanning uses `.github/workflows/codeql.yml`. Local native investigation tools are `.github/codeql/{build.py,collector.py,test_collector.py,cpp.yml,native-source-scope.json,expected-query-names.json,README.md}` and `.github/codeql/queries/{qlpack.yml,diagnostics.ql,compilations.ql,includes.ql,files.ql,bodies.ql,includes-absolute.ql,types.ql}`. Collector regression tests run in the fast CI guard; no hosted native preparation follows them. Private adaptation scripts, replay receipts and rollout metadata are not hosted workflow inputs.

Primary references: [workflow configuration](https://docs.github.com/en/code-security/reference/code-scanning/workflow-configuration-options), [database initialization](https://docs.github.com/en/code-security/reference/code-scanning/codeql/codeql-cli-manual/database-init), [build tracing](https://docs.github.com/en/code-security/reference/code-scanning/codeql/codeql-cli-manual/database-trace-command), [query execution](https://docs.github.com/en/code-security/reference/code-scanning/codeql/codeql-cli-manual/database-run-queries), [result interpretation](https://docs.github.com/en/code-security/reference/code-scanning/codeql/codeql-cli-manual/database-interpret-results), and [default-setup upload restriction](https://docs.github.com/en/code-security/reference/code-scanning/sarif-files/troubleshoot-sarif-uploads/default-setup-enabled).
