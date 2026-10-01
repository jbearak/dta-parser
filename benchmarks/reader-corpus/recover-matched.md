# Recovering the historical 1,812-file comparison set

The original August 24 `raw.tsv` is no longer available locally. The refreshed
comparison retains the published Haven and Stata aggregates from
[the September 16 CSV](results-2026-09-16-base-r/corpus-summary.csv); it does not
create replacement per-file comparator observations or run either comparator.

The original inventory can be recovered exactly. Running the metadata-only
inventory block from commit `9a4ec764897c1c0238dde93cbfcf1816ebb090bb` produces
the same 1,823-row TSV and SHA-256 recorded in the
[September provenance](results-2026-09-16-base-r/provenance.json):
`8f8964891ab2d9429988a8bcddf8ddb3a32338b3a4399ad154dc70df8a370367`.
The block lists regular DTA files, records sizes and modification times, and
writes the original ordering and numeric formatting. It invokes no file reader.

An archived August 25 tool result retains the original per-format summary,
including common-file counts and exact byte totals. The
[source excerpt](results-2026-10-01-matched/recovery/historical-source-excerpt.txt)
and [provenance](results-2026-10-01-matched/recovery/provenance.json) identify the
command, output lines and hashes. The public
[inventory](results-2026-10-01-matched/recovery/inventory.csv) contains anonymous
historical IDs, corpus, release code and byte size; survey paths remain private.

`recover-matched.py` exhaustively enumerates candidate memberships within each
format group. It requires exactly one subset with the archived count and byte
sum. All 16 groups have one solution. The recovered sets are disjoint and total:

| Corpus | Matched files | DTA bytes |
| --- | ---: | ---: |
| DHS | 641 | 46,903,402,101 |
| MICS | 949 | 3,690,394,621 |
| NSFG | 222 | 5,771,879,262 |

The helper checks those totals against every reader's coverage in the published
September CSV. Nine readable files and two malformed MICS inputs remain outside
the comparison, as they did in the original measurements. Missing groups,
duplicate IDs or summaries, changed counts, fractional-byte targets and ambiguous
memberships fail the reconstruction.

Reproduce the public membership proof without survey files:

```sh
python3 benchmarks/reader-corpus/recover-matched.py --output "$NEW_PUBLIC_PROOF"
python3 benchmarks/reader-corpus/recover-matched-test.py
```

To bind the proof to the private cache, first reproduce the original inventory:

```sh
Rscript --vanilla benchmarks/reader-corpus/recover-matched-inventory.R \
  "$CACHE_ROOT" "$NEW_INVENTORY_DIR"
python3 benchmarks/reader-corpus/recover-matched.py \
  --original-inventory "$NEW_INVENTORY_DIR/inventory.tsv" \
  --cache "$CACHE_ROOT" --output "$NEW_PRIVATE_PROOF"
```

This second command requires the fixed historical inventory SHA-256, then checks
every current size, modification time and header release code. Its
`membership-private.json` is an array in original inventory order, with `corpus`,
`id`, `relative_path`, `bytes`, `mtime`, `release` and boolean `common`. The timing
controller uses only rows where `common` is true. Counts and sizes are recorded
as strings in the private manifest, matching the original TSV.

This proof recovers the historical membership, not historical per-file clocks.
The original inventory binds paths, sizes and modification times; it does not
contain file-content hashes. The new benchmark separately qualifies values and
metadata and binds current input contents before and after timing. Retained
comparator aggregates remain measurements from August 24, 2026.
