# dta-parser

dta-parser provides TypeScript and R libraries that read Stata DTA files without collapsing labels, display formats, long strings, or Stata missing codes.

## R package language

**Stata storage type**:
A variable's numeric representation in a DTA dataset: `byte`, `int`, `long`, `float`, or `double`. It determines the observed range, precision, and encodings reserved for missing codes.
_Avoid_: R type, display format

**Compact representation**:
A read-mostly in-memory backing that stores a numeric column at its Stata storage type's width while presenting values to R as doubles. The column's storage type persists through supported mutations; operations that strip it require re-encoding with a storage-named constructor.
_Avoid_: ALTREP column, packed vector

**Stata import**:
Reading a Stata DTA file into R. Use dtaparser for this operation, including in projects that use haven for file writing or other statistical formats.
_Avoid_: Default Stata reader, Haven replacement

**Haven-compatible read**:
A DTA read that accepts haven's common read arguments and returns equivalent values, labels, dates, and missing codes for valid supported inputs. It does not promise identical validation or encoding behavior.
_Avoid_: Drop-in replacement

**Tag-preserving recode**:
A recode that changes matched values while retaining each unmatched system or extended missing code.
_Avoid_: Missing-value-safe recode

**Tagged missing**:
The R representation of one Stata extended missing code, `.a` through `.z`, encoded in the payload of a double-precision missing value. It is distinct from ordinary `NA_real_`, which represents Stata system missing `.`.
_Avoid_: Tagged NA, value label

**Label-based factor conversion**:
An intentional, one-way conversion of a Stata numeric variable and its value-label metadata to an ordinary R factor for modeling, plotting, or data manipulation. It keeps distinct source codes distinct but does not support reconstruction of the original numeric representation.
_Avoid_: Stata factor, Haven factor conversion

**Label-aware tabulation**:
A frequency table that uses Stata value labels and, when requested, keeps system missing, extended missing codes, and R `NaN` as distinct categories.
_Avoid_: Safe tabulation

**Variable label**:
A human-readable description of a variable, distinct from its programmatic name.
_Avoid_: Column label, variable name

**Value labels**:
Mappings from nonmissing integers in Stata's `long` range or Stata extended missing codes (`.a` through `.z`) to human-readable category descriptions.
_Avoid_: Factor levels, variable labels

**Dataset label**:
A human-readable description of a dataset as a whole, distinct from its file name and its variables' labels.
_Avoid_: Variable label, file name
