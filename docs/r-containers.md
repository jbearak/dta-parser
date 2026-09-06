# Containers: what each operation does

`dtatools` supports four ordinary table containers. Explicit helpers mutate the supplied table on all four; ordinary replacement returns a changed copy. The tables below distinguish those operations and their column types.

| Container | What it is |
| --- | --- |
| **dibble** | A tibble that is a Stata dataset. Every numeric and string column carries Stata storage, every dataset operation on it returns a dibble, and it supports mutation by reference from its creation. The default result of `read_dta()`, `read_arrow()`, and `dta_append()`. |
| **tibble** | An ordinary `tbl_df`. Columns may carry Stata storage — the readers' columns do — but nothing enforces it. |
| **data.frame** | A base data frame, with the same caveat. |
| **data.table** | An ordinary data table, with keys, indexes, and its own `[` semantics. Available when the optional `data.table` package is installed. |

Choose a reader's container with `output = ` on the call, or session-wide with `options(dtatools.output = )`. `as_dibble()`, `tibble::as_tibble()`, `as.data.frame()`, and `data.table::as.data.table()` convert. `save_arrow()` records which of three its input was — dibble, tibble, or data table — and `read_arrow()` restores that by default. A plain data frame records no choice: it, and files written before the container was recorded, read back as `options(dtatools.output)` names, falling back to a dibble.

data.table support requires version 1.18.2.1 or newer, which uses the resizable
allocation protocol required by R 4.6. If an older version is installed, update
it with `install.packages("data.table")`; dtatools rejects its tables before
mutation. The other supported containers do not require data.table.

## Where the write lands

*Reference* means the operation modifies the dataset itself, so every name bound to it sees the change and no assignment is needed. *Copy* means R's ordinary copy-on-modify: a new object comes back and the input is untouched. See [mutation by reference](./r-mutation-by-reference.md).

| Operation | dibble | tibble | data.frame | data.table |
| --- | --- | --- | --- | --- |
| `gen(data, y = v)` | Reference | Reference; stays a tibble with existing columns unchanged | Reference; stays a base data frame with existing columns unchanged | Reference; installs a physical column |
| `egen(data, y = dta_mean(x))` | Reference | Reference; stays a tibble | Reference; stays a base data frame | Reference; installs a physical column |
| `repl(data, y = v, where = )` | Reference | Reference | Reference | Reference; invalidates keys and indexes on the changed column only |
| `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()` | Reference | Reference | Reference | Reference |
| `reorder_dta_rows(data, perm)` | Reference | Reference | Reference | Reference; drops the `sorted` marker and secondary indexes |
| `data[i, y := v]` | Reference | Error | Error | data.table's own `:=`: reference, ignoring declared Stata storage |
| `dplyr::mutate()` and the other verbs | Copy → dibble | Copy → tibble | Copy → data.frame | Copy → data.table |
| `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, `row.names<-` | Copy | Copy | Copy | Copy |
| `var_label(data$x) <-`, `val_labels(data$x) <-`, `attr(data$x, ...) <-` | Copy | Copy | Copy | Copy |
| `set_var_label()`, `set_var_labels()`, `set_val_labels()` on a data frame | Reference | Reference | Reference | Reference |
| `set_var_format()`, `set_var_formats()`, `set_dta_metadata()` on a data frame | Reference | Reference | Reference | Reference |
| `set_dta_note()`, `add_dta_note()`, `drop_dta_notes()`, `renumber_dta_notes()`, `set_dta_characteristic()`, `drop_dta_characteristics()` on a data frame | Reference | Reference | Reference | Reference |
| `slice_dta_rows(data, i)` | Copy → dibble | Copy → tibble | Copy → data.frame | Copy → data.table |
| `data[i, ]`, `subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()` | Copy → dibble | Copy → tibble | Copy → data.frame | data.table's own behavior |
| Joins, `bind_rows()` | Copy → dibble when the dibble is first | Copy → tibble | Copy → data.frame | Copy → data.table |
| `copy_data()`, `tibble::as_tibble()` | Copy, independent | Copy, independent | Copy, independent | Copy, independent |

`gen()` never changes what kind of table it was handed. A caller-prepared tibble stays a tibble, with R's own semantics for the replacement operators and its existing columns untouched, exactly as a base data frame does however often `gen()` has run on it. `is_dibble()` reports `FALSE` throughout. Call `as_dibble()` when you want the Stata dataset.

Ordinary replacement uses copy-and-rebind semantics in every container. For metadata writes that must reach a caller, use `set_var_format()`, `set_var_label()`, `set_val_labels()`, or the note and characteristic helpers. Converting with `data <- as_dibble(data)` does not make function-local nested replacement mutate the caller.

`[i, y := v]` is a dibble form. A data table runs its own bracket implementation, with its own storage and promotion rules; plain tibbles and data frames have no `:=` form. `gen()` and `repl()` are the explicit spellings shared by all four containers.

Grouping works the same way everywhere: `by = ` groups in current row order, `bysort = ` sorts by reference and then groups, and a grouped tibble or dibble supplies its dplyr groups. The order of operations is Stata's — groups first, then row selection and values per group, with `.n` and `.N` as the within-group row number and count — rather than data.table's, which applies `i` before grouping.

## Class identity and older objects

An ungrouped dibble has class
`c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")`.
Grouping and metadata classes follow the first two classes. Ordinary tibbles and
base frames can acquire `dtatools_ref_data` support through explicit helpers;
they do not acquire `dibble` or change their existing column classes.

Use `is_dibble(data)` for recognition across versions. It recognizes the new
class and supported older serialized dibbles that recorded their type only in
reference state. A stored `TRUE` means dibble; an absent flag falls back to stored
tibble classes. A stored `FALSE` without the new class remains ordinary.
Assigned `as_dibble()`, `copy_data()`, or `reserve_columns()` upgrades a legacy
dibble on a fresh object, leaving aliases unchanged. `as_tibble()` and
`as.data.frame()` remove dibble and shared reference dispatch.

The new leading class changes exact `class()` comparisons and S3 dispatch.
Type identity does not promise valid reference bookkeeping or spare capacity.
After R serialization, assign `data <- reserve_columns(data)` before structural
mutation. Current dibble identity survives that loss of preparation.

## What column type results

A dibble types the whole dataset. Plain tibbles, data frames, and data tables keep their existing column classes. `gen()` and `egen()` apply Stata generation rules to their new column on every supported container. Ordinary operations on the other containers retain their own R column semantics. The last column below describes those ordinary operations, not generation.

| Value produced by the expression | `gen()`, `egen()`, and a new `:=` column | `mutate()`, `transform()`, `$<-` on a dibble | tibble, data.frame, data.table |
| --- | --- | --- | --- |
| Bare double | `float` — Stata's `generate` default; `double` under `options(dtatools.generate_type = "double")` | `double` | Bare double |
| Bare integer | `long` | `long` | Bare integer |
| Logical | Logical; `save_dta()` writes `byte` | Logical | Logical |
| Character | Smallest fitting `str1`–`str2045`, or `strL` | Same | Bare character |
| `Date` | `float`, declared a Stata date | Same | `Date` |
| `POSIXct` | `double`, declared a Stata datetime | Same | `POSIXct` |
| Factor | Factor; `save_dta()` writes a value-labelled `long` | Same | Factor |
| `dta_byte()` … `dta_double()`, `dta_string()` | Its declared storage | Its declared storage | Its declared storage |
| Arithmetic on a typed column | The storage the Stata lattice gives the result | Same | Same |
| `haven_labelled` | Keeps its label metadata | Keeps its label metadata | Keeps its label metadata |
| `difftime`, `bit64::integer64`, raw, list | Rejected by `gen()` | Passes through untyped; `save_dta()` refuses it | Unchanged |

Overwriting a column that already has declared storage follows one rule on a dibble: keep that storage if every new value fits, otherwise take the narrowest storage that holds every value exactly — `byte`, `int`, `long`, `float`, `double`, or the smallest fitting `str#` — never narrowing the integers the column can hold, so an overflowing `long` goes to `double` rather than through `float`. `mutate()`, `:=`, `transform()`, `within()`, the replacement operators, and `replace_values()`/`repl()` all promote this way. `replace_values()` and `repl()` are the only ones that report the change, as Stata's `replace` does (``variable `x` was byte now int``); pass either of them `promote = FALSE` to keep declared storage fixed. Float targets can then round, while integer targets reject fractional or out-of-range values. See the [numeric replacement policy and examples](./r-stata-divergences.md#numeric-replacement) for this intentional difference from Stata. Rejection is still what you get from `[<-` applied to a Stata vector taken out of the dataset, as in `data$x[1] <- 1000L`, which is the vector's own strict assignment rather than a dataset operation.

The full mapping, including the reasoning, is `?"dta-storage-defaults"`. The `gen()`/`mutate()` split is [ADR 0022](./adr/0022-give-gen-statas-generate-default.md) and is listed in [the divergences page](./r-stata-divergences.md#storage-types).

## Worked comparison

```r
survey <- read_dta("survey.dta")          # a dibble
tbl <- tibble::as_tibble(survey)          # a snapshot, ordinary tibble

gen(survey, adjusted = income * 1.1)      # by reference; `adjusted` is float
survey[income < 0, income := NA]          # by reference; prints nothing
survey$region <- 1:nrow(survey)           # copy and rebind; `region` is long
set_var_label(survey, region, "Region")  # by reference; reaches the dataset

tbl2 <- dplyr::mutate(tbl, adjusted = income * 1.1)   # a copy; `adjusted` is a bare double
tbl$region <- 1:nrow(tbl)                             # a copy; nothing else sees it
tbl[income < 0, income := NA]                         # error: tibbles have no `:=`

tbl <- reserve_columns(tbl)             # assign preparation before growth
gen(tbl, flag = income > 0)               # by reference — and `tbl` is still a tibble
```

Assign `reserve_columns()` before `gen()` when the input is an ordinary unprepared tibble. `tbl` remains a tibble and includes `flag`; existing columns keep their classes and `flag` keeps the logical type of its expression. `is_dibble(tbl)` remains `FALSE`. `tbl <- as_dibble(tbl)` explicitly asks for a Stata-typed dataset. Without preparation, generation stops before evaluating its values or changing the table.

One consequence to expect: the expressions `gen()` evaluates on a tibble see the tibble's own columns, so `gen(tbl, n = .N, by = g)` on a bare character `g` treats `NA` and `""` as two groups. In a dibble they are one Stata string value and one group. Stata's collation applies where a Stata dataset is.

## Restrictions

A dibble needs unique, non-empty column names, to identify columns. The readers repair names first, so only `.name_repair = "minimal"` can produce names a dibble rejects; ask for `output = "tibble"` for such a read.

Explicit helpers accept complete ordinary class chains plus dtatools' metadata and reference markers. Additional data-frame, tibble, or data.table subclasses are rejected before runtime target names, update values, or column selectors are evaluated. A data.table cannot carry the dibble reference marker. Malformed names, row counts, or grouping metadata are rejected too. These checks do not attempt to undo side effects a caller performs while constructing the table itself.

Assign `data <- as_dibble(data)` to explicitly convert an unsupported subclass. Conversion removes additional container classes, keeps recognized grouped or rowwise structure and dataset metadata, and gives bare numeric/string columns Stata storage. It leaves the source unchanged and does not claim to preserve the removed subclass's invariants. An ordinary dibble is returned as is. A data.table is copied into a fresh tibble with its keys, indexes, allocation capacity, and self-reference left behind. Those properties are runtime state and are never stored in `.arrow` files.

| Explicit helper family | Ungrouped ordinary containers | Grouped tibble or dibble | Rowwise tibble or dibble |
| --- | --- | --- | --- |
| `gen()`, `egen()`, `replace_values()` / `repl()` | By reference | By reference, using dplyr groups | Error |
| Dibble bracket `:=` | By reference on dibbles | By reference on dibbles | Error |
| `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()` | By reference | Error; ungroup first | Error; ungroup first |
| `reorder_dta_rows()` | By reference | Error; ungroup first | Error; ungroup first |
| Label, display-format, generic metadata, note and characteristic setters, including add/drop/renumber variants | By reference | By reference; groups retained | By reference; groups retained |
| `copy_data()`, `reserve_columns()` | Assigned isolated result | Assigned isolated result; groups retained | Assigned isolated result; groups retained |
| `column_capacity()`, `can_add_columns()` | Read-only | Read-only | Read-only |

Group rows must form a valid partition in physical row order and match distinct stored group keys. Rowwise identifiers may repeat. When ordinary edits have made that metadata stale, assign `data <- dplyr::ungroup(data)` and group again. For structural edits, assign ungrouping first and then `data <- reserve_columns(data)` if preparation is needed. No helper silently drops grouping.

Dropping a data.table's last column produces a zero-row, zero-column data.table, matching its own empty-table convention. Stored row names, serialization, conversion, and later generation all use zero rows. Dropping the last column of a base data frame, tibble, or dibble retains its row count; later generation fills that many rows.

## See also

- [Mutation by reference](./r-mutation-by-reference.md)
- [Where dtatools diverges from Stata](./r-stata-divergences.md)
- [Stata vector operations](./r-stata-vector-operations.md) — the rules columns follow outside a dibble
- `?dibble`, `?"dibble-bracket"`, `?"dta-storage-defaults"`, `?replace_values` in R

Constructors, readers, and `copy_data()` reserve 5,000 spare column-pointer slots, controlled by `dtatools.alloccol`. Helpers stop when growth cannot fit the supplied table; they never rebind it. Inspect `column_capacity(data)` and `can_add_columns(data, n)`, and assign `data <- reserve_columns(data, n)` before passing a table into a function that needs more slots. Base serialization and ordinary copies can discard capacity. `keep_vars()` and `drop_vars()` also require preparation to shrink. Renaming, ordering, value replacement, and metadata edits need no spare slots. A copied or serialized data.table still needs assigned preparation before column-name edits because its self-reference no longer belongs to the supplied table. See [column capacity and aliases](r-mutation-by-reference.md) for the exact query and preparation contracts.

## Explicit metadata updates

All table metadata setters edit the supplied table, including through function
parameters and runtime column names. They need no spare column capacity and
preserve the existing allocation. They isolate copied reference bookkeeping
without rebuilding the physical table. A table that already lost capacity
still needs assigned `reserve_columns()` before later additions or removals of columns.
Vector forms return copies and require assignment.

Use `set_var_format(data, .(my_name), "%9.0g")` for formats,
`set_var_label(data, .(my_name), "Age")` for variable labels, and
`set_dta_metadata(data, variable = my_name, labels = mapping,
value.label.name = table_name)` to restore a named value-label mapping.
`set_dta_note(data, 4L, "Checked", variable = my_name)` and
`set_dta_characteristic(data, "source", "survey", variable = my_name)`
edit variable notes and characteristics. See the
[metadata migration examples](r-mutation-by-reference.md#explicit-metadata-migration)
for complete note bundles and clearing metadata.
