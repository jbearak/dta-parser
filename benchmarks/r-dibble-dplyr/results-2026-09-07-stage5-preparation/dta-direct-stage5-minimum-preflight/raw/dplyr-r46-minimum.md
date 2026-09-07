# Minimum dplyr for the R 4.6.0 floor

Research date: 2026-09-07. Intended repository destination:
`docs/research/dplyr-r46-minimum.md`.

## Finding

Among released dplyr versions in dtatools' declared range, **1.2.1 is the first
pristine source-installable release in the qualified R 4.6.0 experiment**. Pristine releases
1.1.0, 1.1.1, 1.1.2, 1.1.3, 1.1.4 and 1.2.0 all fail native compilation because
they require declarations absent from R 4.6.0's public headers. The release
sequence is confirmed by the [CRAN source archive][cran-archive] and dplyr's
[release history][dplyr-news]. Exact installation results are below.

The inspected dtatools checkpoint `c52866071ac6b1baa75b7bb04c51dd5b254835d7`
declares R >= 4.6.0 and dplyr >= 1.1.0 in its
[`DESCRIPTION`][dtatools-description]. Those lower bounds do not describe an
installable pristine source minimum on the supported R floor. Stage 5 and
Stage 9 should explicitly distinguish that source-build minimum from the
versions of existing binary installations they intend to support. This result
alone does not establish that every older binary is unusable or justify silently
rejecting every older installed version. The final minimum declaration remains
a documented stage decision. This preparatory study changes no declaration or
production source.

Using R 4.5 would not qualify a package whose declared minimum is R 4.6.0.

This is an installation boundary, not the Stage 5 helper-adapter proof. The
latter must still exercise qualified helpers, aliases, arbitrary helper functions,
nesting, context restoration, captures, across/pick expansion and dtatools typing
against the actual adapter. The dependency versions below also do not establish
that every transitive dependency's separately declared lower bound is usable.

## Why R 4.6.0 does not rescue old dplyr

The official R 4.6.0 and 4.6.1 release copies of `Rinternals.h` are identical:
SHA-256 `6075da78d762507f235b3c654ba9434dd05193bd17dea13714204416f0a4757c`.
An independent retrieval of the [R 4.6.0 SVN tag header][r460-header] matches too.
That header omits `SET_PRENV`, `SET_PRCODE`, `SET_PRVALUE`, `PRVALUE` and `ENCLOS`.
It exposes `Rf_allocSExp`, `PRENV` and `Rf_findVarInFrame` only behind a legacy
function-declaration guard. Enabling that guard cannot restore the omitted
promise setters. The R include makefile installs `Rinternals.h` directly;
internal `Defn.h` is a separate header class. [R include makefile][r460-includes]

This is public declaration removal. It is not a claim that every corresponding
implementation or dynamic symbol vanished: R 4.6.0 still defines several of
these functions internally. [R 4.6.0 memory implementation][r460-memory]
The pinned extensions manual directs promise-accessor callers toward the new
binding API. [Writing R Extensions source][r460-manual]

Every inspected old tag calls the promise setters unconditionally in
`src/chop.cpp`. For example, see pristine [1.1.0][chop-110] and [1.2.0][chop-120].
The first source-compatible release includes commit
[`dd90e9495008532483561be3b210ce92ca5c2d49`][api-fix]. Its
[`env_bind_delayed()`][utils-121] selects `R_MakeDelayedBinding()` at R >= 4.6.0;
[`env_binding_is_delayed()`][chop-121] selects `R_GetBindingType()` at that floor.
The old promise code remains in branches for older R. A text-match inventory
therefore cannot decide whether 1.2.1 compiles the obsolete calls. The 1.2.1
release note identifies this change as compliance with the R C API.
[dplyr release history][dplyr-news]

## Actual installation matrix

Each candidate was exported from its pristine upstream tag to a fresh source
directory and installed into its own empty library with the source-built
R 4.6.0 described below. None of the old tags received compatibility declarations,
source patches or legacy API compiler flags. Every original exported source
file remained byte-identical after the experiment.

| dplyr | Exact upstream tag commit | R 4.6.0 installation | Runtime check |
| --- | --- | --- | --- |
| 1.1.0 | [`b67769f`][tag-110] | Exit 1, missing public declarations | Not run: package did not install |
| 1.1.1 | [`d2f79bb`][tag-111] | Exit 1, missing public declarations | Not run: package did not install |
| 1.1.2 | [`92ace94`][tag-112] | Exit 1, missing public declarations | Not run: package did not install |
| 1.1.3 | [`b4ebddb`][tag-113] | Exit 1, missing public declarations | Not run: package did not install |
| 1.1.4 | [`74de244`][tag-114] | Exit 1, missing public declarations | Not run: package did not install |
| 1.2.0 | [`6aee1cb`][tag-120] | Exit 1, missing public declarations | Not run: package did not install |
| 1.2.1 | [`9574097`][tag-121] | Exit 0, including staged and final load checks | Four small cases pass |

The successful cases use ordinary data frames with ungrouped, grouped, `.by`
and rowwise `mutate()`, including qualified `dplyr::n()`. They check the exact
installed version and path, values and group sizes. They are small upstream
smoke checks, not a substitute for upstream's full suite or the dtatools adapter
matrix. The installed package reports `Built: R 4.6.0`.

Retained Stage 1 CRAN-archive builds independently show pristine 1.1.0 and 1.2.0
failing on R 4.6.1 with the same missing declarations. Those original logs and
archives were copied without changes into `retained-stage1/` and hashed in
`manifests/retained-stage1.json`. They are compilation failures before package
execution. They were not rerun or relabeled as R 4.6.0 results. The current
installed dplyr 1.2.1 also loads and passes a small public mutation check on
R 4.6.1; that check is labeled as an existing-install smoke test, not a fresh
source installation.

## Older prebuilt binaries

Source compilation and binary loading are different questions. The clean
R 4.6.0 library still exports several old promise functions, confirmed by
`nm -gU`. Missing declarations alone cannot show that an already compiled
package will fail. The R installation manual also cautions that most macOS
binary packages with native code depend on the R major/minor series used to
build them. [R package installation manual][r-binary-manual]

The [current CRAN ARM64 R 4.6 index][r46-binaries] advertises dplyr 1.2.1,
built with R 4.6.0. Requests for 1.1.0, 1.1.4 and 1.2.0 binaries in that
repository returned HTTP 404 on the research date. This is a bounded inventory,
not proof that no other repository or existing installation contains an older
binary.

An official [CRAN ARM64 R 4.3 binary of dplyr 1.1.4][r43-dplyr-binary] is
still available. Its SHA-256 and MD5 both match the [repository index][r43-binaries].
The archive SHA-256 is
`f78dbdaaeebed0c314b54a8c632fcba5952954ada924286eceeadbec691c9876`.
Its native library names an absolute R 4.3 framework dependency. A subprocess
used a controlled `DYLD_LIBRARY_PATH` to direct that dependency to the clean
R 4.6.0 library, leaving the downloaded binary and R source unchanged. Native
image checks pass before and after the attempt, with exactly one loaded R.
The dplyr namespace nevertheless fails to load because
`_R_shallow_duplicate_attr` is absent from that library's exports. The R 4.6.0
release notes identify that entry point as hidden. [Pinned R release notes][r460-news]

All 68 extracted binary files remain identical to the archive, and all 2,447
accepted runtime/dependency/package files remain unchanged after this probe.
Commands, loader output and the checks are retained in
`manifests/older-binary-smoke.json`, `manifests/older-binary-disposition.json`
and `logs/older-binary-r43-on-r460-smoke.log`.

No verified older binary usable on this clean R 4.6.0 was established here.
The one archived binary's failure does not cover every older build or platform.
A Stage 5 support decision that retains an older installed version needs a
specific reproducible binary, a single supported R runtime, and the full helper
matrix. A source-build policy can use 1.2.1 as the demonstrated lower bound
without claiming that all older dplyr installations can never run.

## Isolated runtime and dependency provenance

The final runtime was built from the official [R 4.6.0 archive][r460-tar],
SHA-256 `b8dc9b4543660c7b596b87938df532394350360976527d344228ee0ed12e45ec`,
revision 89956 dated 2026-04-24. The comparison [R 4.6.1 source archive][r461-tar]
is revision 90187, SHA-256
`4da6e61d2c0aac5f14a2e7e432cb5fcc269efe83da4293050ba7f03dff4e2cf4`.
All 5,125 original files from the R 4.6.0 archive remained unchanged.

The host is Apple silicon on macOS. The build uses Apple clang 21.0.0,
GNU Fortran 16.2.0 and a private installation prefix. It disables optional
interactive/graphics frontends, ICU, recommended packages and Java; memory
profiling is not enabled. This runtime qualifies installation and the bounded
smoke cases, not benchmark performance or every optional R capability. The
successful configure command and compiler settings are retained in the build
logs and installed `Makeconf`.

The final build passes only the specific gettext, pcre2, libdeflate, zstd and xz
library directories to the linker. It excludes the generic Homebrew library
directory, which contains a `libR` symlink. All 14 non-base dplyr dependencies
were rebuilt from exact CRAN source archives into the private R 4.6.0 library:
cli 3.6.6, generics 0.1.4, glue 1.8.1, lifecycle 1.0.5, magrittr 2.0.5,
pillar 1.11.1, R6 2.6.1, rlang 1.3.0, tibble 3.3.1, tidyselect 1.2.1,
vctrs 0.7.3, utf8 1.2.6, pkgconfig 2.0.3 and withr 3.0.3. Archive URLs and hashes
are in `manifests/dependency-downloads.json`.

A native loaded-image query requires **exactly one loaded `libR`**, resolving to
the private R 4.6.0 installation, both before installing dependencies and after
loading dplyr and running the smoke cases. Both checks pass. All loaded R
namespaces are inside the private tree. `manifests/final-installed-files.json`
binds all 2,447 final runtime/dependency/dplyr files; final source and log checks
are in `manifests/final-qualification.json`.
The completed note, archives, recipes, logs and manifests are indexed separately
in `manifests/artifact-index.json`; it excludes its own file to avoid a recursive
hash dependency.

## Rejected setup attempts and evidence location

Keep these separate from the final matrix:

- The official macOS R 4.6.0 binary download returned an invalid-signature result
  from `pkgutil`. It was neither extracted nor executed. Its URL, hash and
  result are retained in `manifests/runtime-download.json`.
- The first source configure attempt lacked the lzma include path. Its setup
  error is retained in `logs/r460-configure-missing-lzma.log`.
- The first source build used a broad Homebrew library search path. A later
  loaded-image audit found that its LAPACK library had brought R 4.6.1 into the
  process. Its successful package install and smoke outputs are **rejected as
  isolated R 4.6.0 runtime evidence**, even though the compiler used the pinned
  4.6.0 headers. The entire attempt remains under the original `r460-*` paths;
  `manifests/initial-runtime-disposition.json` records the reason. Final accepted
  results use separate `r460-clean-*` paths and fresh installations.
- Small diagnostic-script errors are retained separately: the initial namespace
  printer mishandled the base namespace, the first image-query include conflicted
  with a legacy macOS boolean enum, and an early metadata writer included its
  still-open output log in its hash list. These are research-tool diagnostics,
  not dplyr compatibility results.

Local evidence root:
`/private/tmp/dta-direct-stage5-minimum-preflight`.
The key accepted files are:

- `manifests/r460-clean-dplyr-installs.json`, with all seven commands, exit codes,
  exact install logs and the successful smoke log hash.
- `logs/r460-clean-dplyr-1.2.1-smoke.log` and
  `logs/r460-clean-loaded-library-{before,after}.log`.
- `manifests/dplyr-tags.json`, `manifests/dplyr-clean-git-archives.json`,
  `manifests/clean-runtime-build.json`, `manifests/clean-dependency-installs.json` and
  `manifests/final-qualification.json`.
- The retained build recipes `install-clean-dependencies.py`,
  `install-clean-dplyr-matrix.py`, `runtime-smoke.R` and
  `verify-final-preflight.py`, plus `runtime-clean-probe/`.

The recipes refuse to replace installed candidate directories. Reproduce in a
fresh isolated directory, retain the exact archives, and keep the before/after
loaded-image guards. This study copied upstream sources only for inspection and
build experiments; it introduced no upstream implementation into dtatools.

[cran-archive]: https://cran.r-project.org/src/contrib/Archive/dplyr/
[dplyr-news]: https://dplyr.tidyverse.org/news/index.html#dplyr-121
[dtatools-description]: https://github.com/jbearak/dta-parser/blob/c52866071ac6b1baa75b7bb04c51dd5b254835d7/r-package/dtatools/DESCRIPTION#L22-L24
[r460-header]: https://svn.r-project.org/R/tags/R-4-6-0/src/include/Rinternals.h
[r460-includes]: https://svn.r-project.org/R/tags/R-4-6-0/src/include/Makefile.in
[r460-memory]: https://svn.r-project.org/R/tags/R-4-6-0/src/main/memory.c
[r460-manual]: https://svn.r-project.org/R/tags/R-4-6-0/doc/manual/R-exts.texi
[r460-news]: https://svn.r-project.org/R/tags/R-4-6-0/doc/NEWS.Rd
[r-binary-manual]: https://cran.r-project.org/doc/manuals/r-release/R-admin.html#macOS-packages
[r46-binaries]: https://cran.r-project.org/bin/macosx/sonoma-arm64/contrib/4.6/PACKAGES.gz
[r43-binaries]: https://cran.r-project.org/bin/macosx/big-sur-arm64/contrib/4.3/PACKAGES.gz
[r43-dplyr-binary]: https://cran.r-project.org/bin/macosx/big-sur-arm64/contrib/4.3/dplyr_1.1.4.tgz
[r460-tar]: https://cran.r-project.org/src/base/R-4/R-4.6.0.tar.gz
[r461-tar]: https://cran.r-project.org/src/base/R-4/R-4.6.1.tar.gz
[api-fix]: https://github.com/tidyverse/dplyr/commit/dd90e9495008532483561be3b210ce92ca5c2d49
[chop-110]: https://github.com/tidyverse/dplyr/blob/b67769f92c32583ba7b5522f07fcd3790df39021/src/chop.cpp
[chop-120]: https://github.com/tidyverse/dplyr/blob/6aee1cbaa6ee8c666fa45a8bdf48a8ca008c5a2c/src/chop.cpp
[utils-121]: https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/src/utils.h#L44-L56
[chop-121]: https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/src/chop.cpp#L136-L153
[tag-110]: https://github.com/tidyverse/dplyr/tree/b67769f92c32583ba7b5522f07fcd3790df39021
[tag-111]: https://github.com/tidyverse/dplyr/tree/d2f79bbc4bb32985bcacb04844036a7d70a18896
[tag-112]: https://github.com/tidyverse/dplyr/tree/92ace94c682914e5c8aa736b6ec6c8cb3327cb46
[tag-113]: https://github.com/tidyverse/dplyr/tree/b4ebddb09c98d4bcded4973a9c7a5020aa5e627a
[tag-114]: https://github.com/tidyverse/dplyr/tree/74de24448833278fc03c8ba5f455aa7c888295b8
[tag-120]: https://github.com/tidyverse/dplyr/tree/6aee1cbaa6ee8c666fa45a8bdf48a8ca008c5a2c
[tag-121]: https://github.com/tidyverse/dplyr/tree/95740975c465c29cdb2abdfa13effddb948444dc
