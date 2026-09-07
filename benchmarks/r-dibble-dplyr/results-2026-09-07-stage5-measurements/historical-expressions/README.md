# Historical expression width and setup investigation

This archive records the investigation of the original Stage 5 expression
candidate `57309d40433a92d99849fefa155ae7b22b86b337`, the narrower repair-guard
variant `622ffc194372d9882a78637077dff42f657b14a3`, and the name-history variant
`ad976f7a6854be19db08549a3ef87373448fdfe9`. The baseline is Stage 4
`f622f1ddba04b2bb7ac07415faccf2b417aab0e6`. These are historical measurements.
The combined `a2d8b6a` expression grid and its acceptance checks have a separate
archive. Published source history retains the exact variants:

- [Original and combined source history](https://github.com/jbearak/dta-parser/tree/codex/provenance-stage5-combined-a2d8b6a)
- [Repair guard and name-history source history](https://github.com/jbearak/dta-parser/tree/codex/provenance-stage5-mask-names-ad976f7)

The original full comparison has four diagnostic flags on two 64-column cases.
A flag requires both a median increase above 10% and an increase above 1 ms.
Three paired width repeats confirmed the excess. A separate 12-row, 64-column
retain case preserved it with little payload work. The dependent-expression
case was not separately minimized to 12 rows.

Ordinary R sampling profiles show repeated metadata copying and table repair
during mask setup and result closing. The sampled call counts overlap; they
are not additive elapsed-time shares. The repair-guard variant skips table
repair for inputs that are not data.tables. It reduced the measured overhead,
but the dependent width case still had a diagnostic flag against its safe
reference. The name-history variant replaces repeated name-set unions with
scalar membership checks and appends. Its six measured width cases had no
flag against the safe reference. The separate combined-source archive provides
the later full-grid results. These bounded variant measurements alone do not
establish final performance acceptance.

The retained original full comparison uses `compare-measurements-v3.py`.
It explicitly records different Python launchers: a 33,816-byte pyenv executable
and a 34,640-byte Homebrew executable. The other 3,346 common input identities
match. This is not a claim that the complete Python runtime closure was frozen.
The later combined comparison uses the same pinned launcher on both sides.

The first baseline measurement, `baseline-f622-measure-01`, has an original
successful execution receipt but is rejected as performance evidence. Its
reported time conversion was wrong by a factor of 1,000, and its aggregate
reporter produced warnings. Its disposition remains plain and its original
receipt remains unchanged. The rejected comparison attempt and the disposition
of unused timing/write drafts are also retained. No successful process status
here overrides a recorded qualification rejection.

The selection contains 32 original receipt-bearing runsets, the completed width
coordinator and comparison records, associated driver and reviewer files, and
the original-manifest consistency audit. The audit checks those 32 retained
receipt/manifest/product chains without rerunning an experiment. Original
review reports can cite source installation and full-suite checks outside this
selection; the archive does not include every input to every cited review.

All selected original bytes and Unix modes appear in
[selection.json](selection.json). Functional drivers, reviewer scripts,
dispositions and this description remain plain files. Repeated indexes, logs,
profiles and saved data are in `records.tar.gz`. Tar timestamps and owner fields
are normalized. Verify exact membership, bytes and modes without extracting
filesystem paths:

```sh
python3 bundle-evidence-v1.py verify .
```

The bundle utility's tests and observed result are included. The result records
the root-observed test run and subsequent source hashes; it is not a
pre-consumption binding receipt for that test run.

Installed libraries, runtime trees, variant build products and some supporting
review inputs are omitted. Their original identities remain where recorded.
Absolute paths identify the original environment. This selective archive is
not a standalone replay bundle or a new execution of the experiments. Local
reviewers inspect the selected bytes; no claim is made that an external review
service inspects compressed contents. Historical failures, source differences
and reporting limits remain part of the evidence.
