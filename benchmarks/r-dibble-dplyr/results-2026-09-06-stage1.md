# Direct dibble column operations, 2026-09-06

The final stage 1 implementation replaces whole-table delegation for select,
rename and relocate with direct selector plans and a shared result finalizer.
It copies ordinary retained payloads and validates current string values through
the existing character-generation kernel. No native source changes. A copied
string result is reused only when its values and attributes are identical to
the source; missing values, stale declarations and unsupported encodings retain
the prior safe typing path.

## Fresh validation pending

Starting main is `5ad44406f9b80db81789dcf7b7e1756c28502559`. The revised source is
being committed for a fresh isolated build/check and benchmark. A preliminary
installed build passes the 1M by 16 string rename allocation gate at 128,044,928
bytes for both ordinary dta_string and declared character. Their timings were
132.53 and 132.64 ms, so this implementation does not meet the host-specific
60 ms target. Full exact-source results and independent reviews follow before
this PR opens.

The [interim scanner report](results-2026-09-06-scanner-prototype.md) records the
superseded native-scanner source `95685536`, its complete comparisons and checks.
Those measurements are not attributed to the final R-only revision. The original
2026-09-05 historical report and source revision labels remain unchanged.

## Recorded ownership prerequisites

The unchanged reference mutation runner fails on starting main and the initial
prototype at its first sparse-write allocation assertion. Every call allocates
5,000,048 bytes through `.deep_copy_value()` / `.mutation_copy()` /
`.mutate_data()` / `replace_values()`. The gate requires less than one compact
column even on the first write to an unprepared data frame. A
[minimized reproducer](diagnose-reference-sharing.R) confirms the failure.
It is not a passing gate, and its later assertions were not reached.

A separate [alias-escape reproduction](diagnose-mutation-alias-escape.R) fails
identically on starting main and the revised R-only installation. A fresh private
column is exported inside the replacement expression after the early sharing
check; both the supplied table and that alias change. Ordinary public preflight
currently masks this case by creating conservative references. Moving the entry
check earlier without solving expression-created aliases would expose it.

Both findings remain required ownership prerequisites before the next native
change and before epic completion. The original runner, sharing guard, rollback
checks and container coverage remain unchanged. See the
[plan](../../docs/plans/dibble-result-performance.md#recorded-prerequisite-for-native-changes)
for the required dependency repair and the independent applicability review.
