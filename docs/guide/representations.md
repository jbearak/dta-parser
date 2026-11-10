# How each language represents a file

The same file read in R and TypeScript. Each row says where to find one
part of the file.

| part of the file | R (dtatools) | TypeScript (@jbearak/dta-parser) |
|---|---|---|
| the table | a dibble (a tibble subclass) | a `DtaReader`; columns on request |
| a numeric column | `dta_num` (double) | `NumberColumn`: `values` (`Float64Array`) |
| a string column | character | `StringColumn`: `values` |
| `.` | `NA` | `NA` in a column (`missingCode` 1); `MISSING["."]` in a row |
| `.a` to `.z` | `NA` with the letter in its bits; `.a` ... `.z` | a NaN with the letter in its bits in a column (`missingCode` 2 to 27); `MISSING[".a"]` in a row |
| storage type | `attr(x, "storage")` | `variables[i].type` |
| variable label | `attr(x, "label")` | `variables[i].label` |
| display format | `attr(x, "format")` | `variables[i].format` |
| value label set of a column | `attr(x, "label_set")`; codes in `attr(x, "labels")` | `variables[i].valueLabels` |
| value label sets | `labelbook(df)` | `reader.valueLabels(name)` |
| data label | `attr(df, "label")` | `info.label` |
| notes | `attr(df, "notes")` | `reader.notes()` |
| characteristics | `attr(df, "characteristics")` | `reader.characteristics()` |
| sort order | `attr(df, "sort_order")` | `info.sortedBy` |
| timestamp | `attr(df, "timestamp")` | `info.timestamp` |
| release, byte order, encoding | not read | `info.release`, `info.byteOrder`, `info.encoding` |
| `%td`, `%tc` | numbers with the format | numbers; `formatValue` |
| binary strL | an error | `Uint8Array` |

## Round trips

In both languages, reading a file and writing what was read gives back
the same values, missing codes, storage types, variable labels, value
labels, display formats, notes, characteristics and the sort order. Text from a file older than release
118 comes back as UTF-8 in release 118. The bytes of the file may
differ (release, padding, the timestamp), but every reader sees the same
data.

Exceptions:

- R does not read binary strLs, so it cannot write them back.
- If you write only some of the columns, characteristics of the others
  are dropped, and the sort order keeps only its leading keys that are
  written (data sorted by a, b, c is still sorted by a, not by a and c).
- Short text is written as `strN` even if it was a strL.

## Moving data between languages

Write a `.dta` file in one language and read it in another: the codes,
labels and Stata keys are the same in both. The Stata key for a
value is identical across languages (the double Stata itself stores),
so sorted orders match.
