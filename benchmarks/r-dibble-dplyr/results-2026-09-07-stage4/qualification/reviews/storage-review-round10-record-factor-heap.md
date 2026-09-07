# Storage review round 10: record, factor duplication and heap supplement

No actionable correctness, storage, alias, callback, GC or evidence-integrity defect was found in the bounded snapshot below. This is source and stored-evidence review, not performance acceptance or completion of Stage 4. No R process, build, test, benchmark, synthetic probe or package mutation was run by this reviewer.

## Exact scope

Snapshot captured at `2026-09-07T05:39:22.943970+00:00` in `/private/tmp/dta-direct-stage4`, HEAD `ca6b678e5f173ebc6acf921520d7fa562de42bb9`. Production comparison base is `7d56080f3e97bc4d73a848e363d729767b9629c0`; logical Stage 4 base remains `ec10a6ac34602f3bd691e8043019c1b479babda4`.

The exact package diff against 7d is saved as `storage-review-round10-record-factor-heap.diff`, SHA-256 `4491f3e4498394153e7d47e55931c5cbd9b845b1bb07cf126f71d2a369e5e073`. `storage-review-round10-snapshot.json` records every snapshot file's complete SHA-256 and size. Copies reside under `storage-review-round10-snapshot/`. The incremental owned-columns/test/ADR comparison to round 9 is `storage-review-round10-increment.diff`, SHA-256 `20b62253138906797f44b9180caf8876fd2eec82f60d003a10fe0792508e17af`; Makevars and root heap files were inspected separately.

Primary reviewed paths:

- `r-package/dtatools/src/owned-columns.h` (`8f878d034f93db4d029d1db1eaac128a30c88c274ad9e878ee493923971209ca`): external-pointer record, cached read pointer, writable-preparation flags reuse and factor deep duplication; earlier read/gather changes remain covered by rounds 7–9.
- `r-package/dtatools/src/init.c` (`ab3204cc0fe18017d420b14dc101b2911ec4b14f1eea32acfedc1a5aa5b9ca62`): unchanged since round 9; audited record consumers, exact payload roots, read views, commit and rollback identity handling.
- `r-package/dtatools/src/Makevars.rust` (`cabb38a3bda5e7d87661c3b3cbbd58e9c61360bf925f48e70d09809bd5656585`).
- `r-package/dtatools/tests/testthat/test-owned-atoms.R` (`51724de690b9e861b3b927f865dfec4875d7497e0c172b21d699cf168eccd2ab`): new record-replacement/GC, factor export and mixed-gather callback-order assertions; existing pointer, serialization and callback regressions.
- `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` (`648ff313a8cbcde86c013dee66c2812b1a4eaeb205e93d0cb2b965a433696850`) and `docs/plans/dibble-result-performance-progress.md` (`9eed5d0cf25b7769bdd6c3316c230b17807ddd5ed6e0bffe99a21c5f12a89ba5`, unchanged since round 9).
- `benchmarks/r-dibble-dplyr/owned-heap.R` (`cfe7259861d558b6ffdd48f0b05921269ca209aea0cd28d8d3ebe82808dd5f58`).
- `benchmarks/r-dibble-dplyr/run-heap-qualification.py` (`39fd4814b59eec2e3fcbc8ff4cc7af608c8ef76b52f71e70f794e6a4d75fe9f3`).
- `benchmarks/r-dibble-dplyr/README.md` (`3356e86a156cd90c69b41c0761142e14d821f6fc6976b939b043d2901eee6d0f`).

Supporting unchanged `mutation-write.h` was inspected at SHA-256 `d8e5f6abbe970c4ed12fb923fa55b76e6278e9c1072089356a7698f9cd8c489d`, along with the existing atomic/double memory runners and helper identity checks. These runners' hashes match the smoke and guard manifests. Later working-tree edits to owned-columns, test-owned-atoms, ADR and generated NOTICE had appeared by the end of review; they are deliberately excluded, including the logical-subset experiment.

## Record and mutation disposition

The record is an R-managed `EXTPTRSXP`. Its protected field retains the exact ordinary vector, its tag retains the integer flags/facts, and its address caches that vector's read address. `owned_adopt` still rejects foreign ALTREP payloads. The record owns no separately allocated native memory, so there is no new finalizer, native lifetime or native-memory omission to account for. There is no new route returning the ordinary payload to R.

All record construction/replacement uses the complete record. `owned_prepare` reacquires the flags pointer after detachment, invalidates facts on that current record and marks public writable exposure as before. Atomic and numeric transaction commits replace data1 with the destination record, and existing protected saved-data1 state retains the old allocation and facts together for rollback. Scans/subsets that hold a record across callbacks now retrieve its payload/tag through external-pointer accessors. No remaining owned-record consumer indexes the former two-element VECSXP layout. Non-owned uses of `R_altrep_data1` retain their separate representations.

The cached Elt/Dataptr/Dataptr_or_null readers do not allocate or invoke a foreign payload method. String writes still use `SET_STRING_ELT` on the rooted ordinary vector, preserving R's barrier. Retained writable-pointer exposure continues to prevent future backing sharing; exact rooted pointer probes, writer descriptors and operand plans keep their earlier lifetime protections. data2's ordinary/read-view policy is unchanged. No Serialized_state hook is added, so the existing materializing serialization fallback remains applicable instead of serializing an external pointer address. Existing version-2/version-3 serialization tests require ordinary restored values and recapture isolation.

The new GC regression checks all fixture kinds and a double through shared sparse detachment, a further write, complete replacement, collection, and preservation of older handles. The current change adds no callback boundary inside the record accessor or preparation fast path.

## Factor deep duplication disposition

The new branch is restricted to deep duplication of a supported non-S4 owned integer with known factor class. It duplicates the exact protected ordinary integer payload and copies the handle attributes to the new ordinary vector. It does not return the source payload, change the source record, mark source backing exposed, or dispatch through factor levels or arbitrary attribute methods. Unknown classes retain the existing path. Shallow duplication and explicit metadata-copy entry points retain owned forks.

The factor/ordered regression requires a real owned source, an ordinary attribute-free `as.integer` export equal to the independent ordinary source oracle, unchanged source backing, retained metadata-fork sharing, ordered-range value parity, and isolation after writes in both directions. The mixed-gather regression also compares the complete result, mutated source and callback count against real vctrs for both column orders, strengthening round 9's all-or-nothing fallback guard.

`factor-export-working-18-red.log` contains exactly the two expected ordinary-export ALTREP assertion failures (factor and ordered). `read-fixes-working-19-factor-duplicate.log` ends with DONE and no failure. Earlier rebuilt record and flags-preparation focused logs also end with DONE. These are stored development results, not reviewer reruns or final archive validation.

The initial working-17 apparent test/timing is explicitly excluded: `working-17-stale-object-disclosure.json` records reuse of working-16 DLL `0481edb4704ad346098f59ef6a3a6a3f` because init.o omitted the two header prerequisites. The Makevars fix adds `owned-columns.h` and `mutation-write.h`; the rebuilt install log shows actual compilation. Root records rebuilt working-17 DLL `4c8d10d0ca8530a8f2a2f551359d9fae` and working-18 DLL `d1ed0790068301e6d175ca0197ac5065`. Parent reports working-19 DLL `79d08b...`; no claim here upgrades that report or these focused logs to exact final-source qualification.

## Heap supplement and evidence disposition

The R wrapper sources the original atomic/double memory runner in a child environment with a local commandArgs adapter. It does not patch a namespace, replace the workload or move its five saved gc checkpoints. It captures/checks all eight R-file hashes, validates the install again after the workload, and leaves the original value, metadata, backing/depth and vector-heap assertions active.

The wrapper derives header bytes per cell only when one integer size agrees with every checkpoint's raw Ncells and R-reported rounded memory total. Combined used heap is `Ncells * inferred_size + Vcells * 8`. The driver independently reconstructs the size and every difference, validates finite integral metrics and ordered complete checkpoints, and applies the candidate's less-than-1-MB bounds to both retained and post-drop combined heap. These are used R heap measurements; external native allocations, unused heap capacity and whole-process RSS remain separate. The README makes that distinction and states that fixed bookkeeping/caches can remain after drop.

The Python driver binds its own bytes plus all eight R dependencies to a full runner commit before creating output, rejects existing output, verifies runtime package/case/file identities, checks process status and evidence hashes, and rechecks runner bytes after every case. Guards use explicit exceptions and remain active under optimization. The matrix is 36 fresh processes per side: six kinds, two sizes and three operations. No operation-time claim is made. Root's latest wrapper/driver remain uncommitted in this snapshot; the README correctly requires committing them before full qualification.

Read-only consistency checks found no mismatch in:

- The current two-case, 40-row smoke source identities, log hashes and independent checkpoint arithmetic. It uses the exact initial 7d package and does not claim a final candidate or full-size qualification. Its header size is 56 bytes; double/logical combined retained heap is 227,104/223,544 bytes and post-drop excess is 193,640/209,720 bytes. The incorrect-source invocation has empty stdout and a rejection in stderr.
- All 24 stored synthetic CLI records: eight scenarios under default, `-O` and `PYTHONOPTIMIZE=1`. Probe/stub/input/outer-log hashes match. Preflight failures make zero child calls; malformed runtime cases make one and produce no complete manifest; successful protocol cases make 36. Existing-output sentinels remain intact.
- All 108 stored successful synthetic case logs across the three modes, their manifest hashes and reported heap derivations. These are fake-Rscript protocol checks, not 108 R measurements or package tests.

The read-only audit results and evidence hashes are saved in `storage-review-round10-evidence-check.json`. Key artifacts are current smoke manifest SHA-256 `cbbfc7f29bdd4e8be1656d8c3883481b3c8e9efa45ee9817cf6d98bf41713404`, CLI guard summary `2413790c6ea860787bd216589486c00b1c15b598f7d662cd17383ea0eb9cea74`, and synthetic guard source `43de94456b24785aa60cfff27d569577d670690cea3326bc1773c1c7476b7001`.

No findings remain for this snapshot. Later source changes, exact final archive/native gates, the complete read/performance matrices and full-size heap qualification remain outside this review's disposition.
