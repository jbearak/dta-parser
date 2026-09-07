# Minimum-dplyr research evidence preview

This selection makes the existing installation research reviewable without
committing downloaded archives, installers, native products or build/install
trees. It preserves both the accepted experiments and rejected setup records.
It is preparation for Stage 5 review, not a dependency decision, adapter
qualification, new experiment or Stage 9 completion claim.

The original evidence remains at
`/private/tmp/dta-direct-stage5-minimum-preflight`. Its frozen
[189-file index](supplementary/original-artifact-index.json) has SHA-256
`f1b76e34ba9e53cf0e4dffb3413c213f87bb02fc342b13ee487a0287c8ec9d85`.
All 189 current source files matched its sizes and SHA-256 hashes during this
preparation. No R, build, benchmark, download or original qualification recipe
was run.

| Scope | Files | Bytes |
| --- | ---: | ---: |
| Complete original indexed collection | 189 | 230,388,071 |
| Selected exact indexed text files | 156 | 4,129,105 |
| Omitted indexed external inputs and generated native products | 33 | 226,258,966 |
| Additional readable provenance/license/configuration files | 18 | 66,713 |

The 18 supplements are the original index, its later root audit, one installed
Makeconf snapshot, the two license files from each of seven frozen dplyr Git
archives, and R's COPYING file from the frozen R 4.6.0 archive. These additions
have separate provenance records and are not relabelled as original index
entries. Authored inventories and this README are counted separately in the
final preview inventory.

## Review order

1. Read the unchanged [final research note](raw/dplyr-r46-minimum.md). Its
   demonstrated lower bound is pristine dplyr 1.2.1 source installation on the
   particular clean R 4.6.0 build. It does not establish universal failure of
   older binaries or validate dtatools' future expression adapter.
2. Inspect the [clean build record](raw/manifests/clean-runtime-build.json),
   [accepted configure snapshot](configuration-snapshots/r460-clean-build/config.log),
   [accepted Makeconf snapshot](configuration-snapshots/accepted-installed-Makeconf)
   and the complete before/after loaded-image logs in `raw/logs/`.
   `r460-clean-loaded-library-before.log` and
   `r460-clean-loaded-library-after.log` each record exactly one loaded R.
3. Follow [dependency archive identities](raw/manifests/dependency-downloads.json)
   to [14 fresh dependency installations](raw/manifests/clean-dependency-installs.json),
   then the [seven-version installation matrix](raw/manifests/r460-clean-dplyr-installs.json)
   and `raw/logs/r460-clean-dplyr-1.2.1-smoke.log`.
   Every underlying install and smoke log is selected verbatim.
4. Inspect [final qualification bindings](raw/manifests/final-qualification.json),
   the [2,447-file installed identity manifest](raw/manifests/final-installed-files.json),
   and the [new read-only binding audit](binding-audit.json).
   The installed files themselves are omitted. The current preparation checked
   the selected records, not the installed tree or the experiments again.
5. Read the rejected attempts and bounded older-binary evidence below. A
   successful-looking historical log does not override its recorded disposition.

The [selection index](selection-index.json) classifies every original indexed
artifact and maps it to its preview location or omission. Most text files
retain their relative path below `raw/`. Four individual `config.log` and
`config.status` files were copied below `configuration-snapshots/`; no build
directory was copied. The [source bindings](source-bindings.json) connect
retained upstream code to exact members of the frozen source archives.

## Preserve the failed-attempt distinctions

| Historical attempt | Selected evidence | Interpretation |
| --- | --- | --- |
| Official R 4.6.0 macOS installer | `raw/manifests/runtime-download.json`, `raw/logs/r460-package-signature.log` | Invalid signature; installer was neither extracted nor executed. Its URL and hash are retained externally. |
| First source configure | `raw/logs/r460-configure-missing-lzma.log` | Missing lzma headers. This is a setup failure, not a dplyr result. |
| Initial source runtime and dplyr matrix | `raw/manifests/initial-runtime-disposition.json`, `raw/manifests/r460-dplyr-installs.json`, original dependency/install/smoke/image logs, rejected configuration snapshots | Broad Homebrew linking introduced a second R runtime through LAPACK. These records do not qualify an isolated R 4.6.0 matrix. |
| Initial namespace printer | `raw/runtime-smoke-initial-diagnostic.R`, initial `r460-dplyr-1.2.1-smoke.log`, matrix driver traceback | The printer mishandled the base namespace. The later corrected smoke and the clean-runtime smoke remain separate files. |
| First image-query compilation | `raw/runtime-probe/images-initial-header-diagnostic.c`, `raw/logs/r460-image-probe-header-conflict.log` | Header enumeration conflict in the diagnostic helper. Corrected source and both runtime build logs remain available. |
| Misleadingly named initial library proof | `raw/logs/r460-loaded-library-initial-query.log`, `raw/logs/r460-loaded-library-proof.log`, `raw/logs/r460-loaded-images-diagnostic.log` | The first two logs contain failed one-R assertions. Their filenames do not make them passing proof. |
| Initial final-record writer | `raw/manifests/final-qualification-initial-self-log-diagnostic.json` | Contains a hash of the still-empty output log and a reference to an older verifier script. Neither is used as a final accepted binding. |
| Retained Stage 1 builds | `raw/retained-stage1/1.1.0/install.log`, `raw/retained-stage1/1.2.0/install.log`, copy manifest | Original R 4.6.1 compilation failures, not reruns or R 4.6.0 evidence. |
| Existing R 4.6.1 installation | `raw/logs/current-r-dependencies.log`, `raw/logs/r461-current-dplyr-smoke.log` | Existing-install inspection and smoke, not a fresh source build. |
| One official R 4.3 dplyr 1.1.4 binary | Older-binary download manifests, both repository entries, loader commands, smoke recipe/log and disposition | Download checksum matches the recorded index. Loading under the clean R 4.6.0 fails on `_R_shallow_duplicate_attr`; one-R guards run before and after. This is one bounded cross-series failure. All recorded 404 probes remain visible. |

## Dependencies and omitted inputs

[External inputs](external-inputs.json) accounts for every omitted indexed file.
There are 29 archives, compressed repository indexes and installers, plus four
generated probe `.o`/`.so` files. Downloaded inputs carry their recorded primary
URL and exact frozen SHA-256. The seven local Git archives instead carry a
pinned source URL, matching archive PAX commit and exact local tar hash. A
source-page URL is not a claim that downloading that page recreates the tar
bytes.

[The dependency graph](package-dependency-graph.json) was read from DESCRIPTION
members of the frozen 14 CRAN dependency archives and seven dplyr Git archives.
Every declared mandatory dependency name resolves to one of those 14 packages
or an R base package. It records the actual clean installation order. This is
a source inventory, not a new package-resolution or lower-bound test.

The recipe chain is explicit. The clean dependency installer consumes the
14 bound archives and clean R runtime. The dplyr installer consumes the seven
expanded Git exports and private dependency library, then `runtime-smoke.R`.
The image guard loads a generated native probe whose selected C source and
compiler/linker log explain the omitted output. The older-binary wrapper uses
that same guard before and after its load attempt. The final verifier consumes
archives, expanded sources, installed trees, logs and probe products.

The preview retains the source checksums for omitted expanded R/dplyr files
and maps upstream members back to their archive and primary source. It also
identifies two generated source-search reports. The accepted installed tree,
rejected initial trees and extracted older binary remain external products.
Their existing manifests and dispositions are included; this selection does
not claim those products are physically archived here.

Recipes retain their original absolute paths and historical behavior. They are
review records, not commands to execute in place against this preview. A later
reproduction needs a fresh destination and the omitted inputs. No final recipe
is presented as the missing source of an earlier inline diagnostic.

## Limits requiring accurate labels

- The original 189-file index and study JSON manifests have no mode fields.
  Current original modes were captured and preserved on copies. Historical
  filesystem mode equality cannot be established. License supplements record
  their archive-member modes separately.
- The initial writer names verifier SHA-256
  `498330446ccb43acf245a327b0dc6d1f3fb6b9c663649a297e6bc7ccfe0192a2`.
  Those historical bytes were not retained in the indexed collection or found
  among adjacent verifier/draft files. The final verifier has a different hash.
  The initial writer also hashes the still-empty final output log. Both stale
  references remain visible in the binding audit.
- The historical Stage 5 handoff hash in `preflight-inputs.json` differs from
  the current draft. No adjacent exact backup was found. It is omitted rather
  than replaced with current text. The other four recorded context inputs still
  match; none is an input consumed by the installation/smoke recipes.
- Original records identify eight external Homebrew dylibs by versioned paths,
  with the actual before/after loaded-image guards preserved. They do not freeze
  dylib/tool binary hashes, acquisition URLs, or the complete inherited host
  environment. These are limits on replaying this particular host setup.
- The two retained Stage 1 archives have primary links in the retained CRAN
  index and exact hashes, but no original download-request receipt in this
  collection. The original Git export commands and some one-off diagnostic
  shell recipes were also not saved as separate scripts. The inventories
  distinguish observed commands from reconstruction guidance.

All 33 omitted indexed artifacts have an explained origin. None of the
downloaded archives/installers lacks an exact hash and primary source link.
Generated native products have source/build references instead of fictitious
download URLs. The missing historical writer/context bytes and host identities
above prevent describing this preview as a complete replay bundle.

Stage 5's implementation parent and two independent reviewers still need to
qualify final inclusion, the actual expression adapter and the supported-version
decision. Package absence, full optional integration, final downstream
validation and issue closure remain later stage obligations.

The copied dplyr source is study material from the exact commits in
`raw/manifests/dplyr-tags.json`. Its original MIT notices are in
`supplementary/licenses/`. The retained R header is accompanied by the exact
R 4.6.0 COPYING text. No upstream implementation is incorporated into dtatools
by this preview. Any later source adaptation requires its own production
attribution and packaged-notice checks.
