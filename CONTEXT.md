# dta-tools

dta-tools provides TypeScript and R libraries for reading and writing Stata DTA
files and for working with Stata-specific values and metadata in memory.

## R package language

**Stata storage type**:
A variable's numeric representation in a DTA dataset: `byte`, `int`, `long`, `float`, or `double`. It determines the observed range, precision, and encodings reserved for missing codes.
_Avoid_: R type, display format

**Stata string missing**:
The empty string, which is Stata's only missing string representation. Exporting `NA_character_` converts it to an empty string and reports the conversion.
_Avoid_: String NA, tagged string missing

**Compact representation**:
A read-mostly in-memory backing that stores a numeric column at its Stata storage type's width while presenting values to R as doubles. The column's storage type persists through supported mutations; operations that strip it require re-encoding with a storage-named constructor.
_Avoid_: ALTREP column, packed vector

**Stata import**:
Reading a Stata DTA file into R. Use dtatools for this operation, including in projects that use haven for file writing or other statistical formats.
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

**Factor export**:
A one-way conversion of an R factor's level positions to Stata `long` values with its levels as value labels. The R factor class and orderedness do not survive a semantic DTA round-trip.
_Avoid_: Factor round-trip, Stata factor

**DTA merge**:
A package-owned merge of a master dataset with a using dataset that matches keys under Stata missing-code identity, requires a declared merge relationship, records each row's match result, and keeps the master's values for overlapping variables.
_Avoid_: Stata merge, base merge wrapper, Stata join

**Stata missing-code identity**:
Key equality in which system missing `.` and each extended missing `.a` through `.z` are distinct values that match only themselves.
_Avoid_: NA matching, missing bucket

**Merge relationship**:
The declared key multiplicity between the master and using datasets: `1:1`, `m:1`, or `1:m`. Many-to-many merges are rejected.
_Avoid_: join cardinality, relationship check

**Match result**:
The per-row outcome of a DTA merge, recorded in the generated `_merge` variable: only in the master (x), only in the using (y), or matched.
_Avoid_: join indicator, merge status

**Coalesced variable**:
A variable present in both inputs of a DTA merge, resolved into one column: keys take matched values from either side, and overlapping non-key variables keep the master's values. Metadata the inputs disagree on resolves master-first with a warning.
_Avoid_: overlapping column, suffixed column

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

**Target Stata version**:
The Stata application generation an exported dataset targets. It is distinct from the DTA format release stored in the file header.
_Avoid_: DTA release, file format code

**DTA format release**:
The numeric code identifying a DTA file's on-disk layout. Several Stata application generations may read the same release.
_Avoid_: Target Stata version, Stata version

**Implicit DTA extension**:
Resolving a local filename with no extension by appending `.dta`, matching Stata's `save` and `use` commands. An explicit filename extension remains part of the requested name.
_Avoid_: Missing-file fallback, extension repair

**Standalone DTA dataset**:
A single DTA dataset with no cross-frame alias variables. It may use release 118 or the wide-dataset release 119 when targeting Stata 18 or 19.
_Avoid_: Frameset, alias-variable dataset

**Semantic DTA round-trip**:
After any reported export conversions, writing and reading a dataset preserves its represented values, storage types, missing codes, display formats, labels, and notes. It does not require byte-identical output or preserve source details absent from the in-memory model.
_Avoid_: Byte-identical round-trip, source-file reproduction

**Lossy export conversion**:
A reported replacement required when an R value has no representation in the selected Stata storage. Numeric values become system missing, character missing values become empty strings, and factor classes become value-labelled `long` variables.
_Avoid_: Silent coercion, semantic round-trip
