# Stage 4 storage review, round 8 late read fixes

Reviewed at 2026-09-07T04:51:51.570940+00:00 against the immutable source snapshot captured at 2026-09-07T04:47:39.485532+00:00.

- Worktree at capture: `/private/tmp/dta-direct-stage4`
- HEAD at capture: `ca6b678e5f173ebc6acf921520d7fa562de42bb9`
- Package diff base: `7d56080f3e97bc4d73a848e363d729767b9629c0`
- Exact package diff SHA-256: `9585b7431e8ce1d10fe60efdfe68fb79ee01a054d0c68e30870fcca01ca043d0`
- Saved diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round8-late-read-fixes.diff`
- Exact source snapshot: `/private/tmp/dta-direct-stage4-validation/storage-review-round8-snapshot`
- Snapshot identities: `/private/tmp/dta-direct-stage4-validation/storage-review-round8-snapshot.json`
- Snapshot identity-document SHA-256: `725fcc076d2a162740e349bce8234340633b4e77359d05820d2c60de0737d160`

The saved diff is `git diff --binary 7d56080f3e97bc4d73a848e363d729767b9629c0 -- r-package/dtatools`. Two captures matched around the source copies. All nine copied files still match their recorded hashes. The parent was notified of this snapshot boundary before review. Later getter-cache prototypes or other working-tree changes are excluded from this disposition.

## Disposition

No actionable correctness, alias, storage-fact, encoding, GC or callback finding in the captured late read-fix source. The round-7 subset, adoption and constructor copy-boundary review remains applicable to unchanged source. This report does not accept residual performance, replace exact-source tests, approve a merge or complete Stage 4.

## Late constructor validation

The public `dta_string` constructor now validates the values that its result actually captured. Its initial width/NA checks can precede a foreign declaration or metadata callback that mutates borrowed input. The subsequent owned-width query observes the resulting payload and reports missingness as NA; the constructor rejects that result with the established Stata-string missingness error. If captured width grew, it rechecks the chosen storage declaration against the larger width. A replacement that remains within the declaration is accepted and stays isolated from later source writes. Compact dictionary results retain their established separate path.

The tests cover a declaration callback changing a 64-row data.table source to NA, to an over-wide value and to a valid wider value. They assert callback execution, the corresponding error or accepted values, declaration validity and isolation after a further source write. The large borrowed/unknown-class fixture now constructs its data.table input independently from the ordinary expected vector, avoiding an oracle that could share mutable storage.

## Arrow encoding and descriptor paths

`C_dtatools_owned_utf8_ready` admits only package-owned character handles. It protects their exact ordinary payload and scans current CHARSXPs, including exposed backing, without trusting a cached encoding fact. It accepts UTF-8-marked strings, ASCII and NA. It declines Latin1 or native non-ASCII strings to the existing conversion path, and declines CE_BYTES so the existing Arrow rejection supplies the same contextual error. The helper returns the tracked input handle. It never returns its ordinary backing or a raw pointer to R.

`C_dtatools_has_bytes_encoding` likewise scans the protected ordinary payload only for a verified owned handle. Foreign ALTSTRING input retains its existing element-access behavior. The pointer and element lifetimes in both scans remain protected, and no public writable exposure is introduced.

The late writer change restricts descriptor unwrapping to verified owned strings. DTA and Arrow therefore read the exact ordinary allocation for owned input, while other string representations remain represented by their original SEXP and access behavior. DTA explicitly roots its selected string input in the payload-root array. Arrow's existing root slot retains the exact owned allocation, while the call specification retains other value handles. Compact dictionary descriptor/cache pins remain intact. This preserves the earlier fix for later metadata callbacks detaching a prepared owned string column and does not assume arbitrary foreign data2 is an ordinary string payload.

## Compiled fallback and encoding tests

The R helper takes the ready-value path only while `base::enc2utf8` is primitive. When tracing wraps that binding, it runs the original bytes-rejection/conversion sequence. The revised test compares the result and tracer counts with a compiled copy of the original fallback in the package namespace. This matches the installed helper's bytecode behavior rather than assuming every enc2utf8 expression invokes a dynamically installed tracer. The test also separately observes that the fallback bytes checker runs.

The encoding fixture uses a non-ASCII CE_BYTES value and verifies its encoding before asserting rejection. It checks Latin1 conversion to UTF-8 without changing the source encoding, and ready UTF-8/ASCII/NA input without changing backing metadata. Existing writer callback regressions, initially private public callback writes, constructor metadata/fact checks and both alias directions remain in the snapshot.

## Evidence and limits

`read-fixes-working-15-parity.log` reports the owned-atoms suite completed without failures. `working-install-15-utf8.log` reports successful installation. These are working-source logs inspected by the reviewer; they are not exact archived-source or performance acceptance.

The earlier failed logs are retained. `read-fixes-working-15.log` records the original bytes-test expectation failure, and `read-fixes-working-15-fixture.log` records an expected tracer count of one versus zero. The later fixture establishes an actual CE_BYTES mark, and the compiled-reference test handles the tracer behavior documented by `enc2utf8-trace-probe.log` and `arrow-utf8-disassembly.log`. This review did not rerun or overwrite any of them.

No R processes, tests, builds, probes or timed workloads were run. No source files were edited. Work was limited to source snapshots, existing evidence reads, hashes and this review artifact.

## Reviewed source identities

- `r-package/dtatools/R/dta-numeric.R`: `58283825d778a1ef22f639c0a4295c1871da892bc969d5d24e44f8dd288dbff9`
- `r-package/dtatools/R/dta-string.R`: `f00206d492f012c4a4c8c17a88cb08d99f33ca400e880d9b99647115da3d3244`
- `r-package/dtatools/R/save-arrow.R`: `7cce2583a09d132b0fb9d35661815588917f6858ae6001cb66a8a01d4dc646de`
- `r-package/dtatools/inst/NOTICE`: `3c698aaef0c05e1e049142654af2fc29bf85da1fb0c42d2c3dadd5205e0e11f6`
- `r-package/dtatools/src/init.c`: `5c943313ca12fdd86526506c0cc5b670076dec4c43956145ba7ff89218a566d1`
- `r-package/dtatools/src/owned-columns.h`: `a337cea8c6d32da1322155c234ba40f3e9a7d7961bbad7e34afbcb87dd7178de`
- `r-package/dtatools/src/rust/src/arrow_ffi.rs`: `d9c295d7f808eb1bfd7d6e57381b1b10a10d9bd4873369ff375f2228897f2d8b`
- `r-package/dtatools/src/rust/src/lib.rs`: `593aa143a72c5e5492bb1289e39f6541805e846916b045bf81f4e2769bfe18e4`
- `r-package/dtatools/tests/testthat/test-owned-atoms.R`: `62c7a2f1101a760c1bb3dfbb790def970f2aa58ca1c793f6385a7cb0ed9ad84d`

## Evidence identities

- `read-fixes-working-15-parity.log`: `304f0bd9d3492d7caf4dce8e23e26e67a231b792bb05c1c1c36a6dcbe1d800d6`
- `read-fixes-working-15.log`: `a18319c68f674b4990cca2f1a7014472577ac87132067baa5984e68a2e8b805a`
- `read-fixes-working-15-fixture.log`: `7433ddc901e2c9431b0f3b9c74ba2edd56c2700aa50d667ea506866acd5e72ee`
- `enc2utf8-trace-probe.log`: `75ec0e5900734780e9be92dae2f272347f92c3ae2c850bd8bf8dfe9766387562`
- `arrow-utf8-disassembly.log`: `2ed44c377925b3a3f3a9de8cdff75a843ff676af894d44b6de952dc3bf5b2854`
- `working-install-15-utf8.log`: `69ba1176b25d74dc068d8f230e1f168162db2d40001e5bce77cb55194dc317a6`
