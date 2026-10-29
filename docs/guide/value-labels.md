# Value labels

Survey data stores answers as numbers: 1 for "female", 2 for "male".
A *value label set* is a named table in the file that maps such numbers
to text. A numeric variable may name one set; several variables can
share a set (a `yesno` set for every yes/no question, say). A set can
also label the missing values `.a` to `.z`, as in `.d` = "Don't know".

The file stores the codes in the rows and each set once, at the end.
dta-parser reads the codes as numbers and gives you the sets, so the
values stay what they are in the file and you choose when to turn them
into text.

Only integers can be labelled in Stata, and string variables cannot have
value labels.

## Where to find them

| language | which set a column uses | the set itself |
|---|---|---|
| R | `attr(x, "label_set")` | `val_labels(x)` (named codes); `labelbook(df)` for every column |
| Python | `df.attrs["dta"]["columns"][col]["value_labels"]` | `df.attrs["dta"]["value_labels"][set]`, a `dict` from code to text |
| Julia | `colmetadata(t, col, "value_labels")` | `metadata(t, "value_labels")[set]`, a `Dict` from Stata key to text |
| TypeScript | `reader.variables[i].valueLabels` | `reader.valueLabels(set)`, a `Map` from code to text |

How a labelled missing value appears as a key:

| language | key for `.d` |
|---|---|
| R | the code `.d` (`dtatools::.d`) inside the named vector |
| Python | `dta_parser.missing.d` |
| Julia | `stata_key(".d")` |
| TypeScript | `MISSING[".d"]` |

In Julia every key is a `Float64` Stata key, so look up a number with
`labels[1]` (Julia's `Dict` treats `1` and `1.0` as the same key) and a
missing value with `labels[stata_key(".d")]`.

## Turning codes into text

Each language page has a recipe: R `val_label(x, x)` and
`factor(...)`; Python `Series.map(labels)` or `pd.Categorical`; Julia a
comprehension over the column; TypeScript `formatValue(cell, format,
labels)`. Converting is a choice you make: a categorical column cannot
keep codes that have no label, and writing it back gives new codes
(0, 1, 2, ... in Python), not the original ones.

## Writing them

Every language writes value label sets with release 118:

- **R:** give a column a `labels` attribute (a named numeric vector: the
  codes, named by their text) and, to share a set, a `label_set`
  attribute naming it. `dta_num(x, labels = c(No = 0, Yes = 1))` does
  the first.
- **Python:** put the sets in `df.attrs["dta"]["value_labels"]` and name
  each column's set in `df.attrs["dta"]["columns"][col]["value_labels"]`.
  A pandas `category` column writes its categories as a set of its own,
  coded 0, 1, 2, ....
- **Julia:** pass `value_labels = Dict("set" => Dict(1 => "Yes", ...))`
  and `column_value_labels = Dict(:col => "set")` to `write_dta`, or
  write a table that already carries them as metadata.
- **TypeScript:** pass `valueLabels: { set: new Map(...) }` in the
  dataset and `valueLabels: "set"` on each variable.

A set that no column uses is still written. A column that names a set
that does not exist is written with that name; Stata shows its codes as
numbers.
