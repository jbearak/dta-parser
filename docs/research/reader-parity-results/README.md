# Reader experiment evidence

These are local diagnostic screens. **None qualifies a release or enables an
experiment by default.** Read the [implementation report](../reader-parity-implementation-status.md)
for the decision, scope and remaining regressions.

## Files

- `observations.csv` and `summaries.csv` retain all completed reader screens,
  identified by `run`. Times are seconds and memory is bytes. `bindings.json`
  records the corresponding sources, installations, inputs and runtime settings.
- `downstream-observations.csv`, `downstream-summaries.csv` and
  `downstream-bindings.json` compare complete load-and-use workflows. The v2 run
  precedes direct typed summaries; v3 includes them. The consumer clock excludes
  loading and first-write copy setup. The workflow clock includes both.
- `qualification.json` records the final 209-case checks with the combined DTA
  and owned Arrow controls, and separately with bounded Arrow plus bulk copying.
  Each checks both readers against the installed baseline. Warning counts are
  retained; warning text and private input paths are omitted.
- `corpus.json` records opaque input IDs, hashes and the full corpus comparison
  summary. It omits private paths and error messages. Equality includes values,
  metadata, dimensions, warnings and failure messages in the local source records.
- `validation.json` records test and package-check outcomes and their source
  revisions. `activation.json` records untimed path-selection diagnostics.

The final measured package source is `9ac470bb07029db52e02b02780999cf8bec75291`,
package tree `12f5143920555cdd7d11f805dd336e67a083bc8e`. Its baseline is
`b41d8f9d8dba260b8c93d5c7d83cb12ee8102600`. Earlier screens bind their own
candidate revisions. Measurements apply to those recorded package trees.
Later README and documentation changes are not part of the measured builds.

## Interpreting the screens

Each reader screen has six fresh-process observations per method in one cohort,
with warm filesystem cache. Reader initialization is timed; process startup is
excluded. Stata reads the same DTA and checks dimensions. R readers additionally
qualify value and metadata signatures before timing. Stata semantic conformance
is covered separately, not by comparing R signatures with Stata signatures.

`parity=false` is deliberate for every screening row, even when a candidate
median is faster than Stata. The release gate requires the full manifest, both
fresh and warm modes, balanced repeated cohorts and resolved timing intervals.
Intervals shorter than 10 ms cannot qualify. Small differences in those cases
should not be interpreted as precise speed ratios.

Downstream runs alternate baseline/candidate order for six repetitions per
workload and check result equality. First-write runs also check that a captured
copy keeps its original value. They do not measure Stata consumer performance.
Process peak RSS includes startup, loading, setup and consumption; native owner
counters cover a different, narrower allocation scope.

The warm protocol in the controller uses one untimed read followed by collection.
Large cases then time one read, so it does not establish repeated-read steady
state. Separate native collection stress tests cover owner lifetime. No
cold-filesystem-cache result is included.

## Provenance and privacy

Build records bind source commit and package tree to hashes of installed files.
Here, `installed_manifest_sha256` hashes the complete installed-file mapping as
UTF-8 JSON, with sorted keys and separators `(',', ':')`. Input, worker and
executable hashes are retained. Controllers recheck bindings after each run.

The published records omit private input paths, selected variable names, local
job manifests and raw error/warning logs. Full local records remain outside the
repository. The [benchmark tools](../../../benchmarks/reader-parity/README.md)
describe how to produce equivalent bound records for an available corpus.
