# Current review clarifications

These additions clarify the selective archives after external review. Every
original selection, bundle, selected source and historical result remains
unchanged. The new [record check](check-current-records.py) reads selected saved
records and verifies their original selected bytes and modes. It does not run
historical reviewers, R code, fixtures, profilers or benchmarks.

The old Python review scripts use `assert`. Their optimization flags were not
retained and are unknown: this archive makes no claim that those historical
audits were safe under `-O` or `PYTHONOPTIMIZE`. The archived scripts are records
of the review process, not hardened prospective validators. This limitation
applies to `owned-combined-integrity-review-01.py` and
`atomic-read-repeat-preparation-review-01.py`, as well as other preserved
assert-based scripts. The current record check uses explicit raises and tests
its malformed-input guards under normal Python and `-O`. These new checks do
not establish the optimization mode of an earlier process.

| Finding | Current disposition |
| --- | --- |
| Namespace key | Original comparison reviewer `-01.py` failed with `KeyError`. Its source and log remain historical failures. The [accepted correction](../current-expressions/implementation/semantics-review/combined-measurement-comparison-review-02.json) records that history and uses `name`/`path`. |
| Omitted minimum review input | The original [root-driver-review-03.json](original-inputs/root-driver-review-03.json) is now included here: 6,226 bytes, SHA-256 `7f97a226d0bb8d75c82a214414274c9e7c3ca9a61bcd59222452e003b91493a2`. Its binding matches retained `check-candidate-v4.py`. This does not supply omitted runtimes or make the old script executable in place. |
| Historical assertion guards | The optimization-mode limit above is explicit. Original scripts and reports remain unchanged. |
| Incorrect timing units | The first baseline remains rejected for performance comparisons and is explicitly [superseded](superseded-measurement.json). Original numbers, source and disposition remain unchanged. |
| Allegedly absent native-control review | `implementation/api-review/native-read-control-source-review-01.json` is already in `read-diagnosis/records.tar.gz` and its [selection](../read-diagnosis/selection.json). The current check verifies its 2,692 selected bytes and mode. |
| Ownership flags | Among 3,672 saved state rows, 147 factor and 147 ordered-factor rows have private backing; all handles are shared. Restoring `!backing_private` would reject valid observations. The accepted reader checks the original byte/depth/no-exposure/stable-backing invariants and retains both observed flags. |
| Namespace cardinality | The historical reviewer selected the first match without an explicit uniqueness check. The current check requires exactly one `dtatools` row and unique namespace names in each of six saved tables. Missing and duplicate fixtures must fail. This does not retroactively strengthen the old reviewer. |

Run the bounded current check into a fresh directory:

```sh
python3 check-current-records.py /absolute/path/to/fresh-output
```

It binds selected archives, indexes, plain inputs, its source, Python executable
identities and actual argv before reading the facts. It records current
optimization flags, relevant environment values and failed receipts. The copied
review input is also checked against its retained local source; that local path
is required for this exact copy comparison. This is not a standalone replay or
a complete Python/OS/runtime closure. Historical qualification and measurement
scopes remain unchanged.
