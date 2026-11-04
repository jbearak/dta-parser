# dtaparser writes `.dta` files; `save_dta` moves from dtatools

ADR 0016 put the writer in dtaparser's bridge but left `save_dta`, the
R function over it, in dtatools. So an analyst using dtaparser had to
install dtatools to write a file, and `save_dta` rejected what
dtaparser's `read_dta` returns: a `Date` column was an error. A
do-file translated to R writes `.dta` snapshots to compare with
Stata's, from tibbles that dtaparser read, so dtaparser now exports
`save_dta` and dtatools re-exports it.

The writer goes by each column's type and attributes alone: `storage`,
`format`, `label`, `labels` and `label_set` on columns; `label`,
`notes`, `characteristics`, `sort_order` and `timestamp` on the data
frame. dtatools' `dta_num` columns carry those attributes, so a dibble
writes as before, and dtaparser needs no knowledge of the class. A
`dtaparser_labelled` column is a number with `labels`, and a tagged NA
is `.a` to `.z`, as before.

What is new is the classes dtaparser's `read_dta` makes and the old
`save_dta` refused:

- **`Date`** is written as days since 1960 with format `%td`, as long
  when every day is whole and as double otherwise.
- **`POSIXct`** is written as milliseconds since 1960, as double, with
  `%tc`. Stata's datetimes have no time zone; the UTC clock time is
  written, which is what `read_dta` gives back.
- A `format` or `storage` attribute takes the place of either default.
- **A factor** is written as codes 1 to k, stored as long, with a
  value label set of the levels named by its `label_set` attribute or
  else the column's name. This is what Stata's `encode` makes and what
  haven's `write_dta()` does. A factor from
  `read_dta(factors = TRUE)` therefore comes back with codes 1 to k,
  not the file's own codes: that read kept only the labels. To write
  the file's codes, read with `factors = FALSE`, the default.

## Considered options

- **Keep `save_dta` in dtatools and accept `Date` there.** An analyst
  would still install a package built around dibbles to write a file.
- **A factor as a string column.** Keeps the text, but Stata code that
  compares with the codes (`if region == 2`) would fail on it, and the
  read back gives a character column where `factors = TRUE` gave
  labelled codes.
- **A factor as an error, as before.** Every translated script that
  read with `factors = TRUE` would need a conversion before each
  snapshot.
- **A writer generic that dtatools extends for `dta_num`.** Not needed
  while attributes say everything the writer needs, and it would put
  one more seam between the packages.

## Consequences

- dtaparser's `read_dta` does not keep storage types or display
  formats, so its round trip writes integers as long and doubles as
  double; values, labels, dates and `.a` to `.z` are kept.
- dtatools no longer forwards the writer's C callable; it calls
  dtaparser's `save_dta`.
- `save_dta` on a haven data frame writes its `Date` columns, where it
  stopped before.
