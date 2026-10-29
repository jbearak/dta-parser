# Guide: what is in a `.dta` file, and what each language gets

These pages explain the parts of a Stata `.dta` file that change how you
read or write one, and what dta-parser turns each part into in R,
Python, Julia and TypeScript. The language pages
([R](../r.md), [Python](../python.md), [Julia](../julia.md),
[TypeScript](../typescript.md)) show the calls; these pages explain why
the results look the way they do.

| page | read it when |
|---|---|
| [Releases](releases.md) | a file will not open, or you need to know what an old file can hold |
| [Storage types](storage-types.md) | you wonder why a column is `Int8` or `float32`, or a write fails with "does not fit" |
| [Missing values](missing-values.md) | you need `.a` to `.z`, or a filter or sort treats missing values in a way you did not expect |
| [Value labels](value-labels.md) | a column holds codes such as 1 and 2 and you want the text |
| [Text encodings](encodings.md) | accented letters come out wrong in a file older than Stata 14 |
| [strLs](strls.md) | a file has long text or binary values |
| [Dates and times](dates.md) | a column with a `%td` or `%tc` format should be dates |
| [How each language represents a file](representations.md) | you work in more than one language, or move data between them |
| [Memory and speed](performance.md) | a file is large |

## A `.dta` file in one paragraph

A `.dta` file holds one table. It has a header (the release, the number
of rows and variables, a data label and a timestamp), then a descriptor
for each variable (its name, storage type, display format, variable
label and the name of its value label set), then optional
characteristics and notes, then the rows, then long strings (strLs) and
value label sets. Stata calls rows *observations* and columns
*variables*; these pages use both pairs of words.

dta-parser reads releases 104 to 119 in either byte order and writes
release 118. The format is implemented once, in Rust; each language
package calls that one implementation, so the four packages read every
file the same way.
