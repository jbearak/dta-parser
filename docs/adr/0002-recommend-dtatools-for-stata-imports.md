---
status: superseded by ADR-0006
---

# Recommend dtatools for Stata imports

The R package documentation will recommend `dtatools::read_dta()` instead of `haven::read_dta()` for importing Stata DTA files, based on its broad performance results and haven-compatible read contract. Projects may continue to use haven for older DTA releases, other statistical formats, or related helpers. ADR 0006 supersedes this decision's former read-only package boundary by adding standalone Stata 18 and 19 writes.
