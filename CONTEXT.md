# dta-parser

Reads and writes Stata `.dta` files for TypeScript tools (npm) and for R
(dtaparser, and dtatools on top of it).

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
with `save_dta`, and holds the Rust bridge that dtatools reads through.

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
`read_fixed_width` reads the data through it.
_Avoid_: dictionary (Stata's own `.dct` format), codebook

**Missing-value recode**:
A setup file statement that turns a code into a missing value, such as
`IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;`. `read_fixed_width`
applies them as written, gives each code its own letter (`.a`, `.b`,
...) or ignores them.
