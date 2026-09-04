# Mutation by reference

Most R code is copy-on-modify. `dtatools` deliberately is not, for the operations that translate Stata commands. This page explains what that means, why the package works this way, and what changes in your workflow as a result. No prior experience with pointers or `data.table` is assumed.

## The R model you are used to

In ordinary R, a name refers to a value, and changing a value through one name never affects another:

```r
a <- data.frame(x = 1:3)
b <- a
b$x <- b$x * 2

a$x
#> [1] 1 2 3
```

`b <- a` did not copy anything yet — R shares the data until one of the two is written to, and copies at that moment. This is *copy-on-modify*. It is why almost every R function takes a data frame and returns a new one, and why a function cannot change its caller's data:

```r
double_it <- function(d) {
    d$x <- d$x * 2
    d          # you must return it, and the caller must assign it
}
a <- double_it(a)
```

Stata works the other way. There is one dataset in memory, `replace x = x * 2` changes it, and nothing is assigned or returned. A translated Stata script written in ordinary R style would copy a multi-gigabyte dataset on every line.

## What dtatools does instead

A **dibble**, the container `read_dta()` returns, supports mutation by reference. Within its reserved column capacity, every name bound to it sees the change:

```r
survey <- read_dta("survey.dta")
copy <- survey

gen(survey, adjusted = income * 1.1)

names(copy)          # `copy` has the new column too
copy$adjusted[1]
```

This prepared dibble had spare capacity, so the append changed the existing table. `gen()` returns the updated dataset invisibly. Assigning that return value is useful when preparation or reallocation may be needed; in that case earlier aliases retain the original table.

Inside a function, return the updated table so the caller receives it even when capacity changes:

```r
add_flags <- function(data) {
    data <- gen(data, poor = income < 1000)
    data <- repl(data, poor = NA, where = is_missing(income))
    invisible(data)
}

survey <- add_flags(survey)    # receives a rebuilt table if capacity changes
```

## Which operations write by reference

By reference, on any supported container (dibble, tibble, base data frame, data table):

- `gen()`, `replace_values()` / `repl()`
- `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()`
- `reorder_dta_rows()`

By reference, on a dibble only:

- `data[i, y := value]`, the bracket assignment shape
- the replacement operators `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, `row.names<-`
- and therefore every metadata setter used in replacement form, because R spells `var_label(data$x) <- "Age"` as a `$<-` call: `var_label<-`, `val_labels<-`, and `attr<-` on `format.stata`, notes, or characteristics

Not by reference — these return a new object and leave their input alone:

- every dplyr verb (`mutate()`, `filter()`, `arrange()`, `select()`, `group_by()`, joins, `bind_rows()`)
- base `subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()`, and `[` subsetting without `:=`
- `slice_dta_rows()`, which returns the selected rows in a new table
- the metadata setters called in functional form (`set_var_label()`, `set_dta_note()`, and friends), which return a changed copy
- `copy_data()` and `tibble::as_tibble()`, whose whole purpose is to produce an independent object

On a dibble those operations still return a dibble, so the two styles mix freely. A verb's result is a fresh dataset: a later `repl()` on it does not reach the input it came from, and a `repl()` on the input does not reach the result.

## Why

**Translation fidelity.** `replace x = 0 if y > 5` becomes `repl(data, x = 0, where = y > 5)` — one line, no assignment, no renaming of the dataset at each step. A script converted from Stata reads like the original.

**Cost.** Copy-on-modify means a full dataset copy per modified column, and Stata scripts modify columns in long sequences. On the 5.2 GB, 5,972-column files this package is built for, that is the difference between a workflow that runs and one that does not. Writing through the reference also lets `gen()` and `repl()` patch a compact Stata column in its native storage — `byte` stays one byte per row — instead of materializing a double vector.

**Metadata setters reach the dataset.** `var_label(data$x) <- "Age"` in ordinary R extracts a column, labels the copy, and writes it back into a copy of the data frame. On a dibble it labels the dataset's own column, so the label is there for every binding, including the caller's when this happens inside a function.

## What changes in your workflow

**Aliases are the same dataset.** `b <- a` gives you a second name for one dataset, not a snapshot. Column-only subsets share their column payloads, so a mutation reaches them too. Row subsets have new payloads and are independent. When you need an untouchable original, say so:

```r
original <- copy_data(survey)   # independent, keeps compact columns compact
snapshot <- tibble::as_tibble(survey)   # a plain tibble with R's semantics
```

`copy_data()` deep-copies the columns, their compact backing, and mutable dataset metadata. It rejects columns or attributes holding environments, functions, bytecode, external pointers, or weak references, because those cannot be isolated by copying.

**Return tables from functions that can change capacity.** Within reserved capacity, a function mutates its argument in place. If preparation or reallocation is needed, only its local parameter is rebound. Return the updated table and assign it in the caller. Passing a prepared dibble to another function can modify it; use `copy_data()` for isolation.

**There is no undo.** A mutation commits. Interrupting one is safe — compact columns keep rollback bytes until the write commits, so `Ctrl-C` restores the original payload — but a completed `repl()` cannot be reversed except by writing the old values back.

**A `[` assignment does not print.** `[` always makes its result visible, so a bracket assignment at the console would print the whole dataset. As data.table does, dtatools skips the next top-level print of the mutated dataset, so `survey[income < 0, income := NA]` prints nothing and a bare `survey` on the next line prints as usual. The skip lasts only for the statement that made the assignment.

**Column capacity and aliases.** Constructors and readers reserve 5,000 spare column-pointer slots by default. Set `options(dtatools.alloccol = 5000L)` to change the number. Every column remains in the physical list: `unclass()`, `.subset()`, `bind_rows()`, `bind_cols()`, purrr, JSON, and `write.csv()` all see the complete table, and `attributes(data)$names` reports every column name. Within capacity, structural mutation preserves outer identity. When preparation or reallocation is necessary, the operation warns, shallow-copies the table without copying column payloads, and rebinds its target. Aliases retain the old complete table.

Automatic rebinding supports a symbol, simple `$` and `[[` extractions, and `get()` or `get0()`. Function entry points capture these destinations before values run. Bracket `:=` dispatch receives an already evaluated table, so assign its result for computed getter expressions. For other expressions assign the return value. Within a function, only the local parameter is rebound; return the table and assign the result in the caller when capacity changes.

Use `data <- reserve_columns(data, n = getOption("dtatools.alloccol", 5000L))` to prepare a base data frame, tibble, dibble, or data table explicitly. It preserves the container, rebuilds legacy overlays, and repairs a serialized dibble's current-object bookkeeping. Base `readRDS()` and `unserialize()` discard spare capacity: call and assign `reserve_columns()` before relying on dibble replacement aliases. `read_dta()` and `read_arrow()` already return prepared tables.

**ALTREP columns from elsewhere are detached.** A generic ALTREP column created by base R or another package is converted to an ordinary vector before replacement, because its private caches cannot be safely invalidated. A standalone alias to that former column keeps the old values.

## Compared with data.table

If you know `data.table`, the model is familiar: `DT[, x := 1]` and `set()` modify in place, and `DT2 <- DT` gives a second name rather than a copy. dtatools' `:=` is deliberately the same shape. Three differences are worth knowing.

The bracket shape belongs to the dibble. `data[i, y := value]` works on a dibble; on a data table it runs data.table's own `:=`, which knows nothing about declared Stata storage; on a tibble or data frame it is whatever error their `[` raises. `gen()` and `repl()` work on all four containers, so they are the portable spelling.

The order of operations is Stata's, not data.table's. In `DT[i, j, by]`, data.table applies `i` first and groups only the surviving rows, so `.N` counts selected rows and a group emptied by `i` disappears. Here the groups are formed first, then `where` and the values are evaluated on each group's rows, so `.N` is the group's row count whatever `where` selects, and `where = .n == .N` marks each group's last row — which is what `bysort id: replace last = _n == _N` means in Stata.

`.SD`, `.GRP`, and `.BY` are not provided, and `j` is not a general expression. Summaries stay with dplyr.

## See also

- [Containers](./r-containers.md) — what each operation does on a dibble, tibble, data frame, and data table, and the column types that result
- [Where dtatools diverges from Stata](./r-stata-divergences.md)
- `?dibble`, `?"dibble-bracket"`, `?replace_values`, `?copy_data` in R
