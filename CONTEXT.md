# dta-parser

Reads and writes Stata `.dta` files for TypeScript tools (npm) and for R
(dtaparser, with datakit and dtatools on top of it).

## Language

**Release**:
The `.dta` format version number stored in a file, such as 114 or 118.
_Avoid_: Stata version (Stata 14 writes release 118), format number

**Storage type**:
How a variable's values are stored: byte, int, long, float, double, strN
(fixed width, up to 2045 bytes) or strL.
_Avoid_: data type, column type

**Missing code**:
One of the 27 numeric missing values: system missing `.` and the
extended missing values `.a` through `.z`. Missing codes sort after every
number, and `.` sorts before `.a`.
_Avoid_: NA, tagged NA (R's names for its representation of them)

**Value label set**:
A named table mapping integer codes, including missing codes, to text.
Several variables may share one set.
_Avoid_: label book, value label (for the whole table)

**Variable label**:
The free-text description of one variable.

**Display format**:
The `%`-format that says how Stata shows a variable's values, such as
`%9.2f` or `%td`.
_Avoid_: format (unqualified)

**Characteristic**:
A named text attribute attached to the dataset (`_dta`) or to a
variable. Notes are characteristics.

**strL**:
A long string stored outside the row data in the strL section. It is
either text or binary.
_Avoid_: GSO (the on-disk record's name)

**Packed column**:
A string column dtaparser has read but whose values are still the bytes
from the file; R strings are made from them when the values are used.
Once all are made, the column is *made*.
_Avoid_: lazy column, deferred strings (R's name for its own)

**Dictionary column**:
A packed column stored as its distinct values plus a code per row,
because few of its values are distinct.
_Avoid_: factor (a different R type), categorical

**dtaparser**:
The R package that reads files into standard R types (integers,
doubles, `Date`, factors on request; every missing value `NA`, with
`.a` to `.z` keeping their letter in doubles), writes data frames back
with `save_dta`, and holds the Rust bridge that dtatools and datakit
reach the core through.

**datakit**:
The data preparation package, one per language. In R: `d[i,
name, by = g] := value` on data frames under R's rules,
`read_fixed_width`, and `read_parquet`, `read_parquet_info` and
`save_parquet`; it imports dtaparser and reaches the Rust bridge
through it. In Julia, `Datakit`: `read_parquet`, `read_parquet_info`,
`save_parquet` and `read_fixed_width` into DataFrames, labels in their
metadata and `.a` to `.z` in `DtaColumn`s, with no `:=`; it reaches the
native library through `DtaParser.Internals` and checks DtaParser's ABI
version when it loads. In Python, `datakit` (distribution
`dta-datakit`): `read_parquet`, `read_parquet_info`, `save_parquet`,
`read_dta`, `save_dta` and `read_fixed_width` into polars DataFrames,
with labels and `.a` to `.z` in a **Meta** beside the frame and no `:=`;
it is pure Python, calls `dta_parser._native`, and checks its
`ABI_VERSION` when imported. Python's has `.dta` too because its frames
are polars and dta_parser's are pandas. In TypeScript,
`@jbearak/datakit`: Parquet (`ParquetReader`, `readParquet`,
`saveParquet`), `readFixedWidth`, and `readDta` and `saveDta` into a
**Dataset**; it has its own wasm module, not the format package's, and
takes `MISSING` and the column types from `@jbearak/dta-parser`, its
peer dependency.
_Avoid_: using datakit for `.dta` reading or labels in R or Julia
(those are dtaparser's and DtaParser's)

**Dataset**:
In TypeScript's datakit, a whole table in memory: `variables` (each a
name, type, format, label, value label set name and `values`, a reader's
column) and the dataset's label, notes, every value label set,
characteristics, sort order and `.dta` timestamp. `readDta`,
`readParquet`, `readFixedWidth` and `readDataset` return one
(`ReadDataset`, every field filled); `saveParquet` and `saveDta` take
one. Its columns hold `.a` to `.z` in their `missing` codes, so no
**Meta** or companion column is needed.
_Avoid_: frame, table (unqualified)

**Meta**:
In Python's datakit, the dataclass returned beside every polars frame,
since a polars `DataFrame` has no column metadata: the data label,
notes, characteristics, sort order, time stamp, each column's `Column`
(variable label, display format, value label set, `ordered`), the value
label sets, and the letters: `missing`, a Series of `LETTERS` per column
aligned with the rows as read, and `letter_columns`, the companion
column pairs. It does not follow polars operations.
_Avoid_: attrs (pandas'), metadata (unqualified)

**Companion column**:
In Python's datakit, a column `x_letter` of dtype `LETTERS` (polars'
Enum of `.a` to `.z`) beside column `x` in the frame, holding `x`'s
letters where `x` is null and null elsewhere. Being a column, it follows
its rows through filter, sort, join and concat, where `meta.missing`
does not; saving writes its letters into `x` and does not write it as
a column.
_Avoid_: letter column (ambiguous with a column of letters as values)

**dtatools**:
The R package that reads files into dibbles, whose `dta_num` columns
follow Stata's rules for missing values. It exists for a testthat suite.
_Avoid_: using dtatools to analyse data (use dtaparser)

**Plain mode**:
How dtaparser's bridge fills columns for its own `read_dta`: integers
for byte, int and long (doubles once they hold `.a` to `.z`), `NA` for
every missing value with the letter kept in doubles, dates converted.
Its other mode fills dtatools' `dta_num` columns.

**Setup file**:
A SAS program published with a fixed-width text data file, saying
where each variable's columns are, its variable label and value labels,
and which codes are missing values. CDC publishes one for each NSFG
file from 1973 to 2017-2019 (in 2002, split into three files).
datakit's `read_fixed_width` reads the data through it.
_Avoid_: dictionary (Stata's own `.dct` format), codebook

**dta profile**:
The JSON entry, under the key `dta` in a Parquet file's metadata, that
holds what Parquet cannot say about a table: variable and value labels,
display formats, notes, characteristics, factor levels, time zones, and
the storage type of a column written as DOUBLE because it holds `.a` to
`.z`. Other Parquet tools ignore it.
_Avoid_: schema (Parquet's own), metadata (unqualified)

**Missing-value recode**:
A setup file statement that turns a code into a missing value, such as
`IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`. `read_fixed_width`
applies them as written, gives each code its own letter (`.a`, `.b`,
...) or ignores them.
