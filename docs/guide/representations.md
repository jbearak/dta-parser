# How each language represents a file

The same file read in four languages. Each row says where to find one
part of the file.

| part of the file | R (dtatools) | Python (dta_parser) | Julia (DtaParser) | TypeScript (@jbearak/dta-parser) |
|---|---|---|---|---|
| the table | a dibble (a tibble subclass) | a pandas `DataFrame` | a `DtaTable` (Tables.jl); `DataFrame(t)` | a `DtaReader`; columns on request |
| a numeric column | `dta_num` (double) | numpy array in its storage width, `float` with `NaN`, or `StataArray` | `Vector{T}` or `DtaColumn{T}` | `NumberColumn`: `values` + `missing` |
| a string column | character | `str` / `object` | `Vector{String}` | `StringColumn`: `values` |
| `.` | `NA` | `NaN` | `missing` (code 1) | code 1; `MISSING["."]` |
| `.a` to `.z` | `NA` with the letter in its bits; `.a` ... `.z` | `dta_parser.missing.a` ... `.z` in a `StataArray` | `missing` (codes 2 to 27); `stata_code` | codes 2 to 27; `MISSING[".a"]` |
| storage type | `attr(x, "storage")` | `attrs["dta"]["columns"][c]["storage"]` and the dtype | `colmetadata(t, c, "storage")` | `variables[i].type` |
| variable label | `attr(x, "label")` | `attrs["dta"]["columns"][c]["label"]` | `colmetadata(t, c, "label")` | `variables[i].label` |
| display format | `attr(x, "format")` | `attrs["dta"]["columns"][c]["format"]` | `colmetadata(t, c, "format")` | `variables[i].format` |
| value label set of a column | `attr(x, "label_set")`; codes in `attr(x, "labels")` | `attrs["dta"]["columns"][c]["value_labels"]` | `colmetadata(t, c, "value_labels")` | `variables[i].valueLabels` |
| value label sets | `labelbook(df)` | `attrs["dta"]["value_labels"]` | `metadata(t, "value_labels")` | `reader.valueLabels(name)` |
| data label | `attr(df, "label")` | `attrs["dta"]["label"]` | `metadata(t, "label")` | `info.label` |
| notes | `attr(df, "notes")` | `attrs["dta"]["notes"]` | `metadata(t, "notes")` | `reader.notes()` |
| characteristics | not read | `attrs["dta"]["characteristics"]` | `metadata(t, "characteristics")` | `reader.characteristics()` |
| sort order | not read | `attrs["dta"]["sort_order"]` | `metadata(t, "sorted_by")` | `info.sortedBy` |
| timestamp | not read | `attrs["dta"]["timestamp"]` | `metadata(t, "timestamp")` | `info.timestamp` |
| release, byte order, encoding | not read | `attrs["dta"]["release"]`, `["byte_order"]`, `["encoding"]` | `metadata(t, "release")` ... | `info.release`, `info.byteOrder`, `info.encoding` |
| `%td`, `%tc` | numbers with the format | `datetime64` | `Date`, `DateTime` | numbers; `formatValue` |
| binary strL | an error | `bytes` | `Vector{UInt8}` | `Uint8Array` |

## Round trips

In every language, reading a file and writing what was read gives back
the same values, missing codes, storage types, variable labels, value
labels, display formats and notes. Python and Julia also keep
characteristics and the sort order. Text from a file older than release
118 comes back as UTF-8 in release 118. The bytes of the file may
differ (release, padding, the timestamp), but every reader sees the same
data.

Exceptions:

- R does not read characteristics, the sort order or binary strLs, so it
  cannot write them back.
- TypeScript does not write characteristics, the sort order or binary
  strLs.
- R and TypeScript write short text as `strN` even if it was a strL.
- Metadata in Python lives in `df.attrs`, which pandas drops in some
  operations; see the [Python page](../python.md#metadata).

## Moving data between languages

Write a `.dta` file in one language and read it in another: the codes,
labels and Stata keys are the same in all four. The Stata key for a
value is identical across languages (the double Stata itself stores),
so sorted orders match.
