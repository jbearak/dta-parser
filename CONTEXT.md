# dta-tools

dta-tools provides TypeScript and R libraries for reading and writing Stata DTA
files and for working with Stata-specific values and metadata in memory. The R
and Rust libraries are named `dtatools`; the TypeScript library keeps its
published npm name `dtaparser`.

## R package language

**Stata storage type**:
A variable's numeric representation in a DTA dataset: `byte`, `int`, `long`, `float`, or `double`. It determines the observed range, precision, and encodings reserved for missing codes.
_Avoid_: R type, display format

**Stata string missing**:
The empty string, which is Stata's only missing string representation. Exporting `NA_character_` converts it to an empty string and reports the conversion.
_Avoid_: String NA, tagged string missing

**Stata string vector**:
An R character vector with package-owned class and variable-level DTA metadata. It behaves like an ordinary character vector while preserving that metadata through supported vector operations.
_Avoid_: Labelled string, metadata-bearing character vector

**Compact representation**:
A read-mostly in-memory backing that stores a numeric column at its Stata storage type's width while presenting values to R as doubles. The column's storage type persists through supported mutations; operations that strip it require re-encoding with a storage-named constructor.
_Avoid_: ALTREP column, packed vector

**Stata import**:
Reading a Stata DTA file into R. Use dtatools for this operation, including in projects that use haven for file writing or other statistical formats.
_Avoid_: Default Stata reader, Haven replacement

**Haven-compatible read**:
A DTA read that accepts haven's common read arguments and returns equivalent values, labels, dates, and missing codes for valid supported inputs. It does not promise identical validation or encoding behavior.
_Avoid_: Drop-in replacement

**Output container**:
The table class a dataset operation returns, independently of the column representations and Stata metadata it contains. Readers produce tibbles or data tables; operations that follow an input may also preserve a base data frame.
_Avoid_: Output format, dataset type

**Dibble**:
A tibble that is a Stata dataset: every numeric and string column carries Stata storage, every dataset operation on it returns a dibble, and it carries dtatools reference state from its creation, so that bracket mutation and group-wise assignment are available on it. Everything that writes to a dibble writes by reference, the replacement operators `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, and `row.names<-` included, so a metadata setter such as `var_label(data$x) <- "Age"` reaches every binding of the dataset. Readers return dibbles by default; `gen()` and `replace_values()` accept any data frame and do not require one.
_Avoid_: Reference tibble, dtatools table

**Generate default**:
The Stata storage a bare double result takes through `gen()` or a new column created by `:=`: `float`, or `double` when the `dtatools.generate_type` option is set, as after Stata's `set type double`. It applies to those two translations of Stata's `generate` and to no other way a column enters a dibble.
_Avoid_: Default storage, float default

**Storage promotion**:
Widening a typed column to the narrowest Stata storage that holds every new value exactly when an operation overwrites it with values its declared storage cannot hold. Stata's `replace` instead promotes through `float`, where large integers lose digits.
_Avoid_: Type widening, upcasting

**Group-wise assignment**:
Evaluating one generation or replacement separately within each group of a dataset, in Stata's `by varlist:` order: the group is formed first, then the row selection and values are evaluated on that group's rows, with `.n` and `.N` as the within-group row number and row count. Groups come from `by`, from `bysort`, or from dplyr grouping.
_Avoid_: Grouped mutate, by-group operation

**Stored output container**:
The supported output container recorded in a standalone `.arrow` dataset and restored by default when the dataset is read. It excludes runtime data-table state such as keys, indexes, allocation capacity, and self-reference.
_Avoid_: Stored table state, serialized data table

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

**Stata total order**:
The ordering in which all finite numeric values precede system missing `.`, followed by extended missings `.a` through `.z`. Stata missing codes keep these ranks when sorting and are not relocated or removed by R's `na.last` argument.
_Avoid_: NA ordering, missing-last order

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

**Variable-level DTA metadata**:
Metadata that describes a Stata variable independently of which observations are retained, including its storage type, display format, variable label, value labels, and string storage.
_Avoid_: Custom attributes, column attributes

**Observation-dependent metadata**:
Metadata attached to a variable whose entries correspond to observations and must therefore be subset or reordered with the variable's values.
_Avoid_: Variable-level metadata, copied attributes

**Value labels**:
Mappings from nonmissing integers in Stata's `long` range or Stata extended missing codes (`.a` through `.z`) to human-readable category descriptions.
_Avoid_: Factor levels, variable labels

**Named value-label table**:
A dataset-scoped, named definition of value labels that any number of variables may use.
_Avoid_: Column labels, factor levels, resolved labels

**Value-label assignment**:
The relationship by which a variable uses one named value-label table.
_Avoid_: Value labels, table ownership, column labels

**Value-label registry**:
The collection of named value-label tables defined by a dataset, including tables with no variable assignments.
_Avoid_: Label attributes, factor levels, variable labels

**Dataset label**:
A human-readable description of a dataset as a whole, distinct from its file name and its variables' labels.
_Avoid_: Variable label, file name

**Dataset note**:
A numbered annotation attached to a dataset as a whole, distinct from a variable note and the dataset label.
_Avoid_: Dataset label, variable note

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

**Standalone `.arrow` dataset**:
A dataset written by `save_arrow()` in the dtatools format built on Apache Arrow. It may mix supported Stata-specific columns with ordinary R column classes and is an alternative to a `.dta` dataset, not its automatic companion.
_Avoid_: Arrow copy, DTA sidecar, checksummed Arrow IPC copy

**dtatools Arrow profile**:
The versioned metadata contract under which dtatools writes and reads `.arrow` datasets. It adds the metadata needed to preserve supported Stata and R semantics that standard Arrow types alone do not express.
_Avoid_: Arrow schema, Feather metadata

**Frozen profile version**:
A dtatools Arrow profile version covered by the stability promise: readable by every future package version. The experimental profile version carries no such promise.
_Avoid_: format release, draft profile

**Semantic Arrow round-trip**:
Saving and reading a dataset under the dtatools Arrow profile preserves its values, R classes, storage types, missing codes, labels, display formats, and notes. Attributes the profile does not recognize are dropped with a report.
_Avoid_: byte-identical round-trip, lossless copy

**Raw Stata missing storage**:
The profiled-column encoding in which system and extended missing codes are stored as Stata's own reserved values rather than Arrow nulls, so a profile-aware reader restores them exactly while a generic Arrow reader sees them as ordinary values.
_Avoid_: null encoding, missing bucket

**Data signature**:
An order-sensitive content signature of a dataset's read model: observation and variable counts, variable names and order, storage types, labels, display formats, notes, and values in row order. Containers holding the same read model sign identically.
_Avoid_: Stata datasignature, file checksum

**Load-time signature record**:
The data signature of the complete file on disk, recorded at read time on request and never updated afterwards. It is not a claim about the loaded object's current content.
_Avoid_: cached signature, object signature

**Lossy export conversion**:
A reported replacement required when an R value has no representation in the selected Stata storage. Numeric values become system missing, character missing values become empty strings, and factor classes become value-labelled `long` variables.
_Avoid_: Silent coercion, semantic round-trip
