# Containers: what each operation does

`dtatools` works with four table classes, and the same call can mean different things on each. This page states what changes in place, what returns a new object, and what column types result.

| Container | What it is |
| --- | --- |
| **dibble** | A tibble that is a Stata dataset. Every numeric and string column carries Stata storage, every dataset operation on it returns a dibble, and it carries reference state from its creation. The default result of `read_dta()`, `read_arrow()`, and `dta_append()`. |
| **tibble** | An ordinary `tbl_df`. Columns may carry Stata storage — the readers' columns do — but nothing enforces it. |
| **data.frame** | A base data frame, with the same caveat. |
| **data.table** | An ordinary data table, with keys, indexes, and its own `[` semantics. Available when the optional `data.table` package is installed. |

Choose a reader's container with `output = ` on the call, or session-wide with `options(dtatools.output = )`. `as_dibble()`, `tibble::as_tibble()`, `as.data.frame()`, and `data.table::as.data.table()` convert. `save_arrow()` records which of three its input was — dibble, tibble, or data table — and `read_arrow()` restores that by default. A plain data frame records no choice: it, and files written before the container was recorded, read back as `options(dtatools.output)` names, falling back to a dibble.

## Where the write lands

*Reference* means the operation modifies the dataset itself, so every name bound to it sees the change and no assignment is needed. *Copy* means R's ordinary copy-on-modify: a new object comes back and the input is untouched. See [mutation by reference](./r-mutation-by-reference.md).

| Operation | dibble | tibble | data.frame | data.table |
| --- | --- | --- | --- | --- |
| `gen(data, y = v)` | Reference | Reference; stays a tibble with bare existing columns | Reference; stays a base data frame with bare existing columns | Reference; installs a physical column |
| `repl(data, y = v, where = )` | Reference | Reference | Reference | Reference; invalidates keys and indexes on the changed column only |
| `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()` | Reference | Reference | Reference | Reference |
| `reorder_dta_rows(data, perm)` | Reference | Reference | Reference | Reference; drops the `sorted` marker and secondary indexes |
| `data[i, y := v]` | Reference | Error | Error | data.table's own `:=`: reference, ignoring declared Stata storage |
| `dplyr::mutate()` and the other verbs | Copy → dibble | Copy → tibble | Copy → data.frame | Copy → data.table |
| `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, `row.names<-` | **Reference** | Copy | Copy | Copy |
| `var_label(data$x) <- `, `val_labels(data$x) <- `, `attr(data$x, ...) <- ` | **Reference** (they are `$<-` calls) | Copy | Copy | Copy |
| `set_var_label()`, `set_dta_note()` and the other functional setters | Copy | Copy | Copy | Copy |
| `slice_dta_rows(data, i)` | Copy → dibble | Copy → tibble | Copy → data.frame | Copy → data.table |
| `data[i, ]`, `subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()` | Copy → dibble | Copy → tibble | Copy → data.frame | data.table's own behavior |
| Joins, `bind_rows()` | Copy → dibble when the dibble is first | Copy → tibble | Copy → data.frame | Copy → data.table |
| `copy_data()`, `tibble::as_tibble()` | Copy, independent | Copy, independent | Copy, independent | Copy, independent |

`gen()` never changes what kind of table it was handed. A tibble gains reference state — that is what lets the write land in place — but stays a tibble, with R's own semantics for the replacement operators and its existing columns untouched, exactly as a base data frame does however often `gen()` has run on it. `is_dibble()` reports `FALSE` throughout. Call `as_dibble()` when you want the Stata dataset.

Two rows deserve emphasis. `$<-` and its relatives are by reference **only** on a dibble; this is the one place where a dibble stops behaving like an ordinary tibble, and it is what makes `var_label(data$x) <- "Age"` reach every binding of the dataset. And `[i, y := v]` is a dibble form: on a data table the brackets are data.table's, with data.table's storage and promotion rules, and on the other two containers there is no `:=` to find. `gen()` and `repl()` are the spellings that mean the same thing on all four.

Grouping works the same way everywhere: `by = ` groups in current row order, `bysort = ` sorts by reference and then groups, and a grouped tibble or dibble supplies its dplyr groups. The order of operations is Stata's — groups first, then row selection and values per group, with `.n` and `.N` as the within-group row number and count — rather than data.table's, which applies `i` before grouping.

## What column type results

Only a **dibble** types its columns. Every operation that adds or changes a column on a dibble gives a bare R vector a Stata storage type; the other three containers leave the value's own type alone, so a Stata storage type appears there only when the value already carried one — from a `dta_*()` constructor, from a reader, or from arithmetic on a column that had one.

| Value produced by the expression | `gen()` and a new `:=` column | `mutate()`, `transform()`, `$<-` on a dibble | tibble, data.frame, data.table |
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

Overwriting a column that already has declared storage follows one rule on a dibble: keep that storage if every new value fits, otherwise take the narrowest storage that holds every value exactly — `byte`, `int`, `long`, `float`, `double`, or the smallest fitting `str#` — never narrowing the integers the column can hold, so an overflowing `long` goes to `double` rather than through `float`. `mutate()`, `:=`, `transform()`, `within()`, the replacement operators, and `replace_values()`/`repl()` all promote this way. Only `repl()` reports the change, as Stata's `replace` does (``variable `x` was byte now int``); pass `promote = FALSE` to make it reject a value the declared storage cannot hold instead. Rejection is still what you get from `[<-` applied to a Stata vector taken out of the dataset, as in `data$x[1] <- 1000L`, which is the vector's own strict assignment rather than a dataset operation.

The full mapping, including the reasoning, is `?"stata-storage-defaults"`. The `gen()`/`mutate()` split is [ADR 0022](./adr/0022-give-gen-statas-generate-default.md) and is listed in [the divergences page](./r-stata-divergences.md#storage-types).

## Worked comparison

```r
survey <- read_dta("survey.dta")          # a dibble
tbl <- tibble::as_tibble(survey)          # a snapshot, ordinary tibble

gen(survey, adjusted = income * 1.1)      # by reference; `adjusted` is float
survey[income < 0, income := NA]          # by reference; prints nothing
survey$region <- 1:nrow(survey)           # by reference; `region` is long
var_label(survey$region) <- "Region"      # by reference; reaches the dataset

tbl2 <- dplyr::mutate(tbl, adjusted = income * 1.1)   # a copy; `adjusted` is a bare double
tbl$region <- 1:nrow(tbl)                             # a copy; nothing else sees it
tbl[income < 0, income := NA]                         # error: tibbles have no `:=`

gen(tbl, flag = income > 0)               # by reference — and `tbl` is still a tibble
```

The last line is the one to remember: `gen()` writes into `tbl` itself, so every binding to it sees `flag`, but `tbl` is a tibble before the call and a tibble after. Its existing columns are untouched; only `flag` takes Stata storage, as it would on a base data frame. `is_dibble(tbl)` is `FALSE`. `tbl <- as_dibble(tbl)` is how you ask for the Stata dataset.

One consequence to expect: the expressions `gen()` evaluates on a tibble see the tibble's own columns, so `gen(tbl, n = .N, by = g)` on a bare character `g` treats `NA` and `""` as two groups. In a dibble they are one Stata string value and one group. Stata's collation applies where a Stata dataset is.

## Restrictions

A dibble needs unique, non-empty column names, because its reference state indexes columns by name. The readers repair names first, so only `.name_repair = "minimal"` can produce names a dibble rejects; ask for `output = "tibble"` for such a read.

Rowwise tibbles are rejected by `gen()` and `repl()`; `copy_data()` accepts them. Custom `data.table` subclasses are rejected by mutating and table-producing operations, because dtatools cannot know their invariants. A data table converted with `as_dibble()` is copied rather than shared — a dibble cannot hold data.table's self-reference — and its keys, indexes, and allocation capacity are left behind. Keys, indexes, allocation capacity, and `.internal.selfref` are runtime state and are never stored in `.arrow` files.

## See also

- [Mutation by reference](./r-mutation-by-reference.md)
- [Where dtatools diverges from Stata](./r-stata-divergences.md)
- [Stata vector operations](./r-stata-vector-operations.md) — the rules columns follow outside a dibble
- `?dibble`, `?"dibble-bracket"`, `?"stata-storage-defaults"`, `?replace_values` in R
