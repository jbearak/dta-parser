# Dataset behavior details

This guide covers copying, aliases, column capacity, and container behavior
when writing R functions or integrating dtatools with other packages. For an
introduction to changing data in place, see [mutation by reference](r-mutation-by-reference.md).

Readers return dibbles by default: a dibble is a Stata dataset held in a
tibble. It carries dtatools reference state from creation, so `gen()` and the
other by-reference operations find it ready, and two invariants follow. Every
numeric and string column carries Stata storage: `dibble()`, `as_dibble()`,
and every operation that adds or changes a column give a bare column the
storage that `?"dta-storage-defaults"` maps its R type to. Logical columns
stay logical and factors stay factors. And every dataset operation on a dibble
returns a dibble: the dplyr verbs, joins and `bind_rows()` with a dibble first, base
`subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()`, and `[`
subsetting. Each result is a fresh object following copy-on-modify, so a
by-reference `:=` or `replace_values()` on the input or the result leaves the
other as it was; untouched columns are shared copy-on-write, so compact
columns stay compact. `tibble::as_tibble()` returns a tibble snapshot.

Ordinary `$<-`, `[[<-`, `[<-`, names, row-name, and nested attribute
replacement use R copy-and-rebind semantics. Existing aliases stay unchanged.
Converting a table with `as_dibble()` does not make function-local replacement
reach its caller. Return and assign the result, or use explicit helpers such as
`set_var_format(data, x, "%9.0g")`, `set_var_label()`, `set_dta_metadata()`,
`gen()`, and `repl()` when caller mutation is intended.

Fresh dibbles have room for 1,024 additional columns by default, controlled by
`dtatools.alloccol`. `gen()`, `egen()`, and dibble `:=` automatically reserve
more room when additions need it. Reallocation creates an isolated table and
warns that old aliases still refer to the old table. Functions that may add
columns should return their updated table, and callers should assign it,
for example `survey <- add_flags(survey)`. Alternatively, prepare before the
call with `survey <- reserve_columns(survey, n = 10L)` and create aliases
afterwards when they must see the same changes. Set
`options(dtatools.auto_grow = FALSE)` to require explicit reservation.
`column_capacity(survey)` reports total usable slots; `can_add_columns(survey, 10L)`
checks room for ten additions. Ordinary copies and base serialization can lose
capacity; `copy_data()` returns a prepared independent table. Dropping columns
still needs assigned preparation if the allocation is not resizable. See the
[mutation guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-mutation-by-reference.md)
for both defensive patterns and their alias behavior. Data.table
support requires version 1.18.2.1 or newer; update an older installation before
using that container.

`dibble()` builds one like `tibble::tibble()`, `as_dibble()` converts a data
frame, tibble, or data table (a data table is copied, since a dibble cannot
share its self-reference), and `is_dibble()` tests for one. `as_dibble()` of a
grouped tibble keeps its grouping. Set one session-wide default container or
override it for one read:

```r
options(dtatools.output = "data.table")
survey <- read_dta("survey.dta")
survey_tbl <- read_dta("survey.dta", output = "tibble")
```

The data.table package remains optional. Requesting data-table output without
it installed is an error. Direct reader construction retains compact numeric
and dictionary-string columns; it does not build a tibble and convert it.

`save_arrow()` records whether its input is an ordinary dibble, tibble, or data
table. `read_arrow()` restores that container by default. An explicit `output`
argument overrides the stored choice. Older Arrow files and files saved from a
plain data frame use `dtatools.output`, then fall back to a dibble; a recorded
container this release does not know reads as a tibble.

Exported whole-table operations support ordinary data tables. `gen()` installs
a physical column, and `repl()` invalidates keys or secondary indexes that use
the changed column while preserving unrelated lookup state. Keys, indexes,
allocation capacity, and `.internal.selfref` are runtime state and are not
stored in Arrow files. Explicit mutators reject additional data-frame, tibble
and data.table subclasses whose invariants dtatools cannot preserve. Assign
`data <- as_dibble(data)` to request conversion, removing those classes and
applying Stata column typing. See the
[supported helper and grouping matrix](https://github.com/jbearak/dta-parser/blob/main/docs/r-containers.md#restrictions).
Other table-producing operations retain their documented subclass restrictions.

`gen()`, `replace_values()`, `keep_vars()`, and `drop_vars()` mutate the supplied data frame or tibble. Dataset
aliases observe the change. Separate tables sharing a column remain isolated. Call `copy_data()`
first when the original dataset, its compact storage, and its metadata must
remain independent. See `?replace_values` for selection, evaluation, formula,
grouping, and Stata compatibility details, and
[mutation by reference](./r-mutation-by-reference.md) for what writing
by reference means and how it changes a workflow.
[Containers](./r-containers.md) tabulates what `gen()`, `repl()`,
`:=`, `mutate()`, and the replacement operators do on a dibble, tibble, data
frame, and data table, and the column types each produces.

The [egen guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-egen.md)
compares `gen()`, `egen()`, and `:=` for all eight calculations. All three
can use the same value functions; `egen()` differs by calculating over the
selected sample when a row filter is supplied.

`order_vars()` and `rename_vars()` mutate by reference too, as Stata's `order`
and `rename` do: `order_vars()` moves the selected columns to the front and
leaves the rest in their existing relative order, and `rename_vars()` takes
`new_name = old_name` pairs, or a complete `.names` vector. Both leave the
column vectors, their storage declarations, and their metadata untouched, and
both reach columns created by `gen()`.

`slice_dta_rows()` returns the selected rows in the input's container, and
`reorder_dta_rows()` applies a permutation to a table in place, so every
reference to it sees the new order. Both gather compact Stata numeric columns
through the native kernel rather than dispatching `[` once per column, which
matters for wide data, and leave compact columns unmaterialized. For a data
table they drop the `sorted` marker and secondary indexes, which a row
selection or permutation invalidates.

```r
order_vars(survey, region)
rename_vars(survey, age_years = v1)
reorder_dta_rows(survey, order(survey$id))
first_ten <- slice_dta_rows(survey, 1:10)
```

For a dibble with at least ten rows, `slice_dta_rows(survey, 1:10)` and
`survey[1:10, ]` both return the first ten rows with all columns, preserving
Stata metadata and leaving `survey` unchanged. Both share batch row gathering.
Brackets retain tibble indexing rules; `slice_dta_rows()` uses vctrs location
rules and rejects unknown row names or out-of-range positive locations. Grouped
results rebuild their groups and retain `.drop`; rowwise results retain their
identifier variables. Missing string rows become Stata's empty string before
grouping is rebuilt.
