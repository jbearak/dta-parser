# dta-parser

Reads and writes Stata `.dta` files for TypeScript tools (npm) and for R
(dtatools).

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
