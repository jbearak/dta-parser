# dtatools 0.6.0

- Stata-backed numeric and temporal vectors now compare, order, group, deduplicate, match, and join using Stata missing-code identity and total order.
- Added owned Stata string vectors plus `dta_match()`, `dta_in()`, and metadata-preserving `dta_*` set operations.
- Raised the minimum supported R version from 4.1.0 to 4.5.0. Base matching support depends on the `mtfrm()` hook introduced in R 4.5.0.
