# Recommend dtaparser for Stata imports

The R package documentation will recommend `dtaparser::read_dta()` instead of `haven::read_dta()` for importing Stata DTA files, based on its broad performance results and haven-compatible read contract. The recommendation is limited to imports: projects may continue to use haven for writing files, other statistical formats, or related helpers. Read-only support describes the package today but is not a permanent scope boundary; future work will follow the needs of Stata users rather than seek haven feature parity for its own sake.
