# Stage 8 selected evidence

The [performance and qualification note](../stage8-direct-joins-bindings-performance.md)
leads with the current measured results and limitations. This directory preserves
selected records for source `cf317730d3110568c72862719424e01c2876141b` and its
predecessor `af0bed0b9c200f82d37891902266d200a1819196`. These are reviewable historical
records, not a portable runtime or a new execution of the workloads.

The [complete comparison table](tables/comparisons.csv) contains all 120 paired
whole-operation comparisons. The three restricted bind_cols repeats are retained
separately in [pair 1](tables/bind-cols-repeat-01.csv),
[pair 2](tables/bind-cols-repeat-02.csv) and [pair 3](tables/bind-cols-repeat-03.csv).
The original wide-binding RSS outlier and both subsequent repeats remain in the
note and compressed records. Positive differences below the joint greater-than-10%
and greater-than-1 ms timing threshold are included.

## What is in the archive

[records.tar.gz](records.tar.gz) contains 5,788 regular-file members, totaling
349,824,685 bytes before compression. The archive is 12,482,228 bytes, with SHA256
`fe7b1f03e0b036bb3ac5013214158f07485cf5841206f28572939c9215c8211e`.
[selection.json](selection.json) maps each original absolute path to an archive
member, byte count, regular-file mode and SHA256. Its SHA256 is
`609f49d585ff4ea87d6c92c0c1823bf20b26298fe1d561244429e71144a30674`.

The archive includes:

- The selected whole-operation grids' retained timing, GC, Rprofmem and state
  records, comparisons, source/configuration copies, commands and receipts.
- Finite retained-heap histories, large-child RSS records and separately decoded
  later-write graphs, with original source and retained-role distinctions.
- Installed predecessor/candidate observation records and copied-control work,
  including earlier failed runs and the H01 retained-lifetime correction.
- Selected installation, full/minimum/native/package records, actual command
  results and logs, attribution files, linkage observations and corrected Rust
  source-reuse evidence.
- Complementary reviewer reports, saved-data readers, source freezes and prior
  preparation versions. Inclusion of an unused or failed version is not acceptance.

Records retain their original bytes and paths. A path such as
`/private/tmp/dta-direct-stage8-validation/full-cf317730-01/tests.csv` maps to
`records/dta-direct-stage8-validation/full-cf317730-01/tests.csv` inside the archive.
References in original JSON or Markdown may still name the original local paths;
use the member map to locate the selected record. Those paths do not imply that a
reader has access to the original computer.

For example, from this directory, inspect the full-suite table without extracting
or executing any archived script:

```sh
tar -xOf records.tar.gz records/dta-direct-stage8-validation/full-cf317730-01/tests.csv
```

The same prefix mapping applies to the source/receipt/review records. The readable
table copies have their own [copy map](readable-copy-map.json), and the archive and
transport sidecars have a separate [copy map](transport-copy-map.json).

## Verification and omissions

The [transport result](transport-result.json) records a successful comparison of
every archive member's exact name, type, mode, byte count and SHA256 to the selected
source identities. The bound [outer invocation](transport/build-launch-01.json)
and [completion](transport/build-launch-result-01.json) retain the selected Python,
collector and selection identities. This checks transport, not the domain meaning
of every record. Domain and evidence-chain reviews have their own stated scopes.

The archive builder's first draft silently missed the intended candidate attribution
directory and reread its selection after checking it. Draft 2 requires the actual
export path, parses and transports one verified selection buffer, and retains failed
build attempts and partial output names. Original draft 1 and selection 1 remain in
the archive. Twelve actual guard cases pass in
[normal Python](transport/guard-normal-02.json) and
[optimized Python](transport/guard-optimized-02.json), including a tiny archive
round trip and rejected source/selection changes. Those tests do not establish
concurrent-adversary safety, complete OS closure or successful workload replay.

Complete live dependency inventories, runtime/tool images, installed DLL/RDB files,
source/package tarballs and complete repository exports remain local. Original
manifests and selected endpoint identities are retained, but their presence does
not mean every referenced file is bundled. Some temporary child DLLs and native
profiling files no longer existed after their original producers; the relevant
reviews state those gaps. The corpus does not claim to reconstruct those bytes.

Selected source and output checks, complete saved performance arithmetic, semantic
graph comparisons and producer assertions support different parts of the result.
No single successful recorder is treated as proof of all behavior, every dependency
image, every callback or every possible input. R allocation and native counters
overlap; retained heap and whole-child peak RSS measure different quantities.

The [local disposition](root-local-disposition.json) accepts these Stage 8 outcomes
with their measured limits. Its original [performance draft](source-notes/root-performance-draft-03.md)
and [selection addendum](root-selection-addendum.json) are retained unchanged.
Implementation CodeRabbit, CI and normal merge remain separate gates. Stage 9,
issue #172, the twelve earlier base-R read regressions, four Stage 7 many-small-group
public latency limitations and actual fertility renv validation/restoration remain
open. This evidence publication does not close them.
