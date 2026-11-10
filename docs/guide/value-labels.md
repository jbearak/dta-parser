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
| TypeScript | `reader.variables[i].valueLabels` | `reader.valueLabels(set)`, a `Map` from code to text |

How a labelled missing value appears as a key:

| language | key for `.d` |
|---|---|
| R | the code `.d` (`dtatools::.d`) inside the named vector |
| TypeScript | `MISSING[".d"]` |

## Turning codes into text

Each language page has a recipe: R `val_label(x, x)` and
`factor(...)`; TypeScript `formatValue(cell, format, labels)`.
Converting is a choice you make: a factor cannot keep codes that have
no label.

## Writing them

Both languages write value label sets with release 118:

- **R:** give a column a `labels` attribute (a named numeric vector: the
  codes, named by their text) and, to share a set, a `label_set`
  attribute naming it. `dta_num(x, labels = c(No = 0, Yes = 1))` does
  the first.
- **TypeScript:** pass `valueLabels: { set: new Map(...) }` in the
  dataset and `valueLabels: "set"` on each variable.

A set that no column uses is still written. A column that names a set
that does not exist is written with that name; Stata shows its codes as
numbers.
