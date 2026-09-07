# R 4.6.0 source evidence for the dplyr minimum preflight

Inspected 2026-09-07. This is a bounded source study. No R build, package installation, R execution, or tests were performed for this note. No repository files or dependency declarations were changed.

R 4.6.0 already has the public-header incompatibility seen with pristine dplyr 1.1.0 and 1.2.0 on R 4.6.1. Its `Rinternals.h` is byte for byte identical to the 4.6.1 release header. The evidence supports declaration removal before 4.6.1. It does not establish the result of installing either package on an actual R 4.6.0 runtime. Sources are the official [R 4.6.0 release archive](https://cran.r-project.org/src/base/R-4/R-4.6.0.tar.gz), [R 4.6.1 release archive](https://cran.r-project.org/src/base/R-4/R-4.6.1.tar.gz), and [R 4.6.0 SVN tag header](https://svn.r-project.org/R/tags/R-4-6-0/src/include/Rinternals.h).

## Pinned source identity

| Source | Release revision | SHA-256 |
| --- | --- | --- |
| `R-4.6.0.tar.gz` | `VERSION` 4.6.0; `SVN-REVISION` 89956, 2026-04-24 | `b8dc9b4543660c7b596b87938df532394350360976527d344228ee0ed12e45ec` |
| `R-4.6.1.tar.gz` | `VERSION` 4.6.1; `SVN-REVISION` 90187, 2026-06-24 | `4da6e61d2c0aac5f14a2e7e432cb5fcc269efe83da4293050ba7f03dff4e2cf4` |
| Both release copies of `src/include/Rinternals.h`, plus independently retrieved `R-4-6-0` SVN tag header | Identical 44,416-byte files | `6075da78d762507f235b3c654ba9434dd05193bd17dea13714204416f0a4757c` |

The archive metadata files are retained beside the extracted sources. The official SVN response reports `Last-Modified: Thu, 16 Apr 2026 12:58:53 GMT` and ETag `89897//tags/R-4-6-0/src/include/Rinternals.h`. These are saved in `svn-tag-response-headers.txt`. The ETag is response metadata, not a separate investigation of the exact removal commit. [Official header](https://svn.r-project.org/R/tags/R-4-6-0/src/include/Rinternals.h)

## Exact declaration evidence

In the pinned [R 4.6.0 header](https://svn.r-project.org/R/tags/R-4-6-0/src/include/Rinternals.h):

- `SET_PRENV`, `SET_PRCODE`, `SET_PRVALUE`, `PRVALUE`, and `ENCLOS` have no occurrences anywhere in the file. Enabling its legacy declaration guards therefore cannot restore those declarations.
- Lines 1247 to 1250 make `ENABLE_LEGACY_NONAPI` define `ENABLE_LEGACY_NONAPI_FUNS` and `ENABLE_LEGACY_NONAPI_VARS`.
- The function guard starts at line 1258. It contains `Rf_findVarInFrame` at 1262, `PRENV` at 1264, and `Rf_allocSExp` at 1266. Their function declarations are conditional on `ENABLE_LEGACY_NONAPI_FUNS`.
- The older name-remapping macros for `findVarInFrame` at 919 and `allocSExp` at 874 do not supply function declarations.
- `R_ParentEnv` is declared at 354, `R_GetBindingType` at 656, and `R_MakeDelayedBinding` at 670.

The release's `src/include/Makefile.in` puts `Rinternals.h` in `SRC_HEADERS` at line 16 and copies that set directly into the installed include directory at lines 89 to 91. `Defn.h` belongs to `INT_HEADERS` at line 20. Its internal declarations do not make these functions available through the normal installed package headers. A text scan also found none of the five omitted names in `R.h`, `Rdefines.h`, `Rembedded.h`, `Rinterface.h`, or the `R_ext` source headers. [Official include makefile](https://svn.r-project.org/R/tags/R-4-6-0/src/include/Makefile.in)

## Matching pristine dplyr callers

The local dplyr checkout was inspected through `git show` and `git grep` against immutable tag commits. It was not checked out, patched, or built. Tag source files were copied under this evidence directory.

| dplyr release | Pinned commit | Required declarations absent in R 4.6.0 |
| --- | --- | --- |
| 1.1.0 | `b67769f92c32583ba7b5522f07fcd3790df39021` | `src/chop.cpp` uses `SET_PRENV` at 18 and 57, `SET_PRCODE` at 31, 34, 37 and 58, `SET_PRVALUE` at 40 and 59, and `PRVALUE` at 132. `ENCLOS` is used in `src/dplyr.h` at 128 and `src/mask.cpp` at 70 and 104. |
| 1.2.0 | `6aee1cbaa6ee8c666fa45a8bdf48a8ca008c5a2c` | The same setter call sites remain in `src/chop.cpp`; `PRVALUE` is at 134. |

Sources are dplyr's own [1.1.0 chop.cpp](https://github.com/tidyverse/dplyr/blob/b67769f92c32583ba7b5522f07fcd3790df39021/src/chop.cpp), [1.1.0 dplyr.h](https://github.com/tidyverse/dplyr/blob/b67769f92c32583ba7b5522f07fcd3790df39021/src/dplyr.h), [1.1.0 mask.cpp](https://github.com/tidyverse/dplyr/blob/b67769f92c32583ba7b5522f07fcd3790df39021/src/mask.cpp), and [1.2.0 chop.cpp](https://github.com/tidyverse/dplyr/blob/6aee1cbaa6ee8c666fa45a8bdf48a8ca008c5a2c/src/chop.cpp). Both tag versions of `src/dplyr.h` include `Rinternals.h` at line 6. Neither tag's `src` or `inst/include` files define these missing declarations or enable the legacy guard.

Inference: pristine C++ callers requiring these missing declarations are source-incompatible with the ordinary installed R 4.6.0 headers. This explains why a 4.6.1 compiler failure involving these names is not uniquely a 4.6.1 change. A modified package or injected compatibility declarations would be a different qualification target.

## Documentation and inference boundaries

The R 4.6.0 manual directs users of the promise accessors and setters to the binding API added in 4.6.0 at `doc/manual/R-exts.texi` lines 17782 to 17786. It recommends `R_ParentEnv` for `ENCLOS` at 17746 to 17747. [Pinned Writing R Extensions source](https://svn.r-project.org/R/tags/R-4-6-0/doc/manual/R-exts.texi)

The R 4.6.0 NEWS groups `ENCLOS` with declaration removals, but its promise-entry note still describes check warnings in preparation for removal. Use the actual release header to decide declaration availability. [R 4.6.0 release announcement](https://stat.ethz.ch/pipermail/r-devel/2026-April/084500.html)

Do not describe the result as complete removal of the implementations or proof of missing dynamic-library exports. `src/main/memory.c` still defines `ENCLOS` at 4687, `PRVALUE` at 4720, `SET_PRENV` at 4729, `SET_PRCODE` at 4730, and `SET_PRVALUE` at 4733. Those functions also have internal declarations in `Defn.h`. The normal public declarations are the relevant limitation for these pristine callers. [Pinned memory.c](https://svn.r-project.org/R/tags/R-4-6-0/src/main/memory.c)

This study neither qualifies a usable dplyr minimum nor proves all earlier dplyr releases fail. It establishes the named source blockers for 1.1.0 and 1.2.0 and the equality of the 4.6.0 and 4.6.1 public headers. Runtime installation results, dependency versions, dplyr semantics, and platform coverage belong to the coordinated validation work.

`SHA256SUMS` hashes the downloaded archives, selected R source files, and copied dplyr files. `source-inspection.json` records the exact header comparisons and symbol line matches; `dplyr-revisions.json` records the tag commits.
