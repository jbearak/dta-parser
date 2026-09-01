---
status: accepted
---

# Use Stata identity across vector operations

Stata-backed vectors use Stata missing-code identity across relational equality, vctrs equality, grouping, deduplication, and matching: system missing `.` and extended missings `.a` through `.z` are distinct values that equal only themselves. This supersedes ADR-0009's decision to keep the general vctrs equality proxy unchanged. The package prioritizes consistent Stata behavior even though vctrs must then treat these codes as comparable domain values rather than missing entries: `is.na()` still identifies them as missing, while `vec_detect_missing()` and completeness operations do not, and dplyr's `na_matches` setting does not change their identity. Package-owned `dta_match()`, `dta_in()`, and `dta_*` set operations provide symmetric identity for bare and Stata-backed operands because base matching and set operations do not expose sufficient class dispatch for every operand arrangement. `dta_merge()` remains the package-owned implementation of Stata's merge command, but ordinary equality, grouping, deduplication, and matching no longer collapse Stata missing codes into one R missing bucket.
