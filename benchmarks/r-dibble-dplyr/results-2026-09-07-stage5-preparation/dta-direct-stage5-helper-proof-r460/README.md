# The frozen helper proof on clean R 4.6.0

The unchanged 35-case helper matrix passes on the already qualified clean
R 4.6.0 runtime and its source-installed dplyr 1.2.1. The native loaded-image
probe confirms exactly one `libR` before and after the same R process runs the
cases. Both checkpoints identify the clean runtime's library.

This is additional preparation for Stage 5. It qualifies the existing bounded
prototype at the declared R minimum with this dplyr version. It is not a
dtatools Stage 5 candidate, full evaluator qualification, or a universal
supported-minimum decision. No cases or adapter code were changed.

Read [run-01/execution.log](run-01/execution.log) for all 35 results and the
before/after image guards. Detailed values and conditions remain in
`run-01/observations.rds` and `run-01/observations.txt`. Two intentional warning
records remain, for across dots deprecation and deliberate nested warnings.
All 828 dplyr namespace functions remain identical and locked, and the same
51 helper bodies and formals match the pinned pristine source.

The first 27,399 bytes of each runtime's `observations.txt`, containing every
observation record and the method inventory before the separate runtime list,
are byte-identical. Their SHA-256 is
`c815e9614b5723491b0ba1276e07ac9cb0f2700e351e49fa0545f3212719353a`.
The full raw files are preserved and differ in runtime metadata. This bounded
read-only comparison is recorded in
[cross-runtime-record-comparison.json](cross-runtime-record-comparison.json).
It performs no condition normalization or result rewriting.

The exact executed adapter remains
`/private/tmp/dta-direct-stage5-helper-proof/adapter-v2.R`, SHA-256
`c17300a7ff1f30a2389c8ac033c2982ef14f8dd0601c460783bd372182445d0d`.
The exact cases remain `cases-v4.R` in that original directory, SHA-256
`3f4540ad6e931127d652382790017fbc11e07265992982542a609a487d1e2ce9`.
The original 66-file archive and its index are verified against the frozen
index SHA-256
`bb907a08b4566579b6fad1ebad6f2bf8a588e2219ac162c06d2ef43306af1931`.
All 68 original files, including the index and its receipt, remain unchanged
during this run. Nothing was added to the original proof directory.

The launcher uses only these existing clean installations:

- R 4.6.0 revision 89956 at
  `/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install`.
- dplyr 1.2.1 at that study's `r460-clean-dplyr-libraries/1.2.1`.
- The 14 rebuilt dependencies at `r460-clean-dependencies`.

Their complete 2,447-file installed inventory still matches the accepted
minimum-version study. All required dependencies were present. No installation,
build, download, timing, production edit, Git operation that changes state, or
renv operation was performed. The rejected contaminated runtime paths and host
native R packages were not used.

The new [guarded-cases.R](guarded-cases.R) runs the frozen cases through
`source()` with their original two trailing arguments. It adapts the earlier
study's local `runtime-clean-probe/check.R` guard and uses the exact existing
native `images.so` without recompilation. Before execution the process sees only
the candidate dplyr library, clean dependency library, and clean R base library.
Eight namespaces are present at the first guard and 22 at the final guard.
Every namespace stays inside those three libraries. The final guard runs in a
`finally` block if the cases throw an error.

The native query records 364 loaded images before and 376 after. Each list
contains exactly one `libR.dylib`, at
`r460-clean-install/lib/R/lib/libR.dylib`. Every observed non-OS image and every
registered DLL is included in the pre-execution bindings. The clean dplyr DLL
SHA-256 is
`605f59d80dcbeddd3806e1657c35531125a32106ad2e6119e4a135926c4804ee`.
The clean `libR.dylib` SHA-256 is
`dcb38c2ee32750fbb953386cb976d89ca9d223fe98401f110a5964b025f5a730`.
The probe SHA-256 is
`23e3f098c2725266e75bd45e6410d462fa267ab16fd6227b23d85782513a3155`.

The launcher binds 3,009 inputs before running R. These include its own source,
the wrapper, frozen adapter and cases, original proof records, full clean
installation, pristine dplyr source checkout, accepted provenance manifests,
the native image probe and source, and eight existing external Homebrew dylibs.
Every bound input remains unchanged afterward. This strengthens the host
inventory for this new run; it does not retroactively add binary hashes to the
earlier minimum-version study or R 4.6.1 proof. OS shared-cache image binaries
and the complete Python runtime closure remain outside the byte-frozen inputs.

Fresh output and receipt paths are required before any R launch. The output
manifest is computed before opening its destination and explicitly excludes
itself. A separate receipt binds the completed manifest. The run receipt
SHA-256 is
`de3c0c65e6c67eeaaaaa45555e2801aded65f069114c772dbb71c73c5549c905`.
This first R 4.6.0 attempt succeeded; there were no failed attempts or new fixes.

To reproduce this exact experiment with a fresh output name:

```sh
python3 /private/tmp/dta-direct-stage5-helper-proof-r460/run-proof.py run-new-name
```

The original prototype's gaps remain. It invokes private optional expansion
helpers, evaluates one expression into chunks, and implements no Stata typing,
result assembly, full sequencing, native/foreign-storage adoption, or later-write
isolation. Its readable deferred snapshots differ from existing dtatools and
dplyr obsolete-mask errors. The two empty-rowwise fixtures consume real group
keys, so this does not qualify independent group-metadata assembly. Nine
supporting adapter methods remain unexercised. These are unchanged documented
limits, not newly accepted production behavior.

The original [PROVENANCE.md](../dta-direct-stage5-helper-proof/PROVENANCE.md)
records exact dplyr source/test adaptations and the full MIT notice. The source
reference remains `95740975c465c29cdb2abdfa13effddb948444dc`; no new dplyr
implementation was incorporated here. The prior
[minimum-version study](../dta-direct-stage5-minimum-preflight/dplyr-r46-minimum.md)
records how this runtime and dependency set were qualified and the limits of
its older-binary findings. Full Stage 5 implementation, review, package checks,
and supported-version policy remain required.
