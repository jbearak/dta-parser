# Match Stata tabulation semantics

The R package will use Stata's `tabulate` behavior as the compatibility target for `tab()` rather than define independent frequency-table semantics. Existing R utilities do not provide the intended Stata workflow, and users should be able to carry that workflow into R. The package will claim parity only for command forms and behavior covered by tests against Stata; it will document unsupported forms explicitly.
