# DTA identifier naming

Package-owned underscore identifiers use `dta_` and `_dta`, with `DTA_` for
constants. Code that inspects classes, calls private helpers, or reads section
offsets must use the new names.

| Previous name | Current name |
| --- | --- |
| R `stata_numeric`, `stata_byte`, `stata_int`, `stata_long`, `stata_float`, `stata_double` | `dta_numeric`, `dta_byte`, `dta_int`, `dta_long`, `dta_float`, `dta_double` |
| R `stata_string`, `stata_temporal`, `stata_date`, `stata_datetime` | `dta_string`, `dta_temporal`, `dta_date`, `dta_datetime` |
| R `dtatools_stata_metadata`, `dtatools_stata_metadata_vector` | `dtatools_dta_metadata`, `dtatools_dta_metadata_vector` |
| R help topic `stata-storage-defaults` | `dta-storage-defaults` |
| Rust and TypeScript `section_offsets.stata_data`, `section_offsets.stata_data_close` | `section_offsets.dta_data`, `section_offsets.dta_data_close` |
| TypeScript `STATA_MISSING_B` | `DTA_MISSING_B` |

The existing public R constructors and dataset helpers already use DTA names.
For example, `dta_byte()`, `dta_string()`, `read_dta()`, and `save_dta()` keep their
names. S3 dispatch and native bindings now use the same class names as the
constructors. Old S3 names have no aliases. Re-read saved DTA or Arrow datasets
to obtain current classes; RDS objects containing the previous S3 names need
reconstruction with the current constructors.

Arrow field metadata accepts `dta_numeric` as an explicit numeric class. The
reader also accepts the previous `stata_numeric` field metadata and restores
current R classes. The R writer records compact numeric storage without a
redundant class field. Older package versions may reject files that explicitly
record the new class in their Arrow metadata.

Stata's required `<stata_dta>` file tags retain their spelling. Dot-separated
metadata attributes such as `format.stata` and `stata.storage` also retain
their existing names. Names identifying an external Stata executable, its
benchmark results, or Stata-generated reference fixtures remain Stata names.
Research quotations and links pinned to historical commits retain the names
used at those commits.
