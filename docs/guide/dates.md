# Dates and times

A `.dta` file has no date type. A date is a number, and its display
format says how to read it. Every Stata date and time counts from the
start of 1 January 1960:

| format | the number counts | 0 is | example: 1 means |
|---|---|---|---|
| `%td` (and the older `%d`) | days | 1 Jan 1960 | 2 Jan 1960 |
| `%tc` | milliseconds, ignoring leap seconds | 1 Jan 1960 00:00:00.000 | 00:00:00.001 |
| `%tC` | milliseconds, counting leap seconds | 1 Jan 1960 00:00:00.000 | 00:00:00.001 |
| `%tw` | weeks (52 per year; the last week of a year is 8 or 9 days) | the first week of 1960 | the second week of 1960 |
| `%tm` | months | January 1960 | February 1960 |
| `%tq` | quarters | 1960 Q1 | 1960 Q2 |
| `%th` | half-years | first half of 1960 | second half of 1960 |
| `%ty` | years | year 0 | year 1 (the number is the year itself: 2024 is 2024) |

A format may continue with a mask that changes only how the value is
shown, as in `%tdCCYY-NN-DD`; the number means the same.

For every format but `%ty`, negative numbers are before 1960. `.` and `.a` to `.z` are missing
dates.

## What each language does

**Python and Julia convert `%td` and `%tc`** unless you turn it off:

| | `%td` becomes | `%tc` becomes | `.` becomes | turn off |
|---|---|---|---|---|
| Python | `datetime64[s]` | `datetime64[ms]` | `NaT` | `read_dta(path, dates=False)` |
| Julia | `Date` | `DateTime` | `missing` | `read_dta(path; dates=false)` |

A column converts only if every value is a whole number in range and
none is `.a` to `.z`. Otherwise it stays a numeric column with its
format, so no value or missing code is lost. `%tC` always stays numeric:
a calendar type without leap seconds would put its values up to 27
seconds off. The other formats (`%tw`, `%tm`, `%tq`, `%th`, `%ty`) stay
numeric too; the language pages show how to convert them.

**R keeps every date as a number** with its `format` attribute. To get
a `Date`, add the days to 1960-01-01: `as.Date(unclass(x), origin =
"1960-01-01")`. Times: `as.POSIXct(unclass(x) / 1000, origin =
"1960-01-01", tz = "UTC")`. dtatools works this way so that a column
read and written comes back with the same numbers and missing codes.

**TypeScript keeps the numbers** and gives `formatValue(cell, format)`,
which shows a value as its format says (`%td` gives `02jan1980`;
`%tdCCYY-NN-DD` gives `1980-01-02`). To get a JavaScript `Date` from a
`%td` value, `new Date(Date.UTC(1960, 0, 1) + days * 86400000)`.

## Writing dates

| language | write | becomes |
|---|---|---|
| R | a `Date` column through `dibble()` or `as_dibble()` | long `%td` |
| R | a number with `format = "%td"` (or any date format) | its storage, with that format |
| Python | `datetime64` | long `%td` if every value is midnight, else double `%tc` (milliseconds; finer non-zero parts are an error); `NaT` is `.` |
| Julia | `Date`, `DateTime` | long `%td`, double `%tc` |
| TypeScript | a number with `format: "%td"` | its storage type, with that format |

A `%tc` value needs a double: milliseconds since 1960 pass the range of
a long within a month.
