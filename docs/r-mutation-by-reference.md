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

This prepared dibble had spare capacity, so the append changed the existing table. `gen()` returns that same table invisibly. If capacity is insufficient, column additions automatically reserve more room by default. That requires a new table, so other names can still refer to the old table. The patterns below explain how to handle that case.

A function can make the same changes to its caller's table:

```r
add_flags <- function(data) {
    gen(data, poor = income < 1000)
    repl(data, poor = NA, where = is_missing(income))
    invisible(NULL)
}

add_flags(survey)             # the caller sees poor
```

Fresh dibbles, including those returned by `read_dta()`, have room for 1,024
additional columns by default. This example therefore needs no extra
reservation. If a function may receive a table whose spare capacity has been
used up or lost through copying or serialization, returning and assigning the
function's result handles automatic growth. Reserving in advance is another
defensive approach.

## Which operations write by reference

By reference, on any supported container (dibble, tibble, base data frame, data table):

- `gen()`, `egen()`, `replace_values()` / `repl()`
- `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()`
- `reorder_dta_rows()`
- table metadata setters: `set_var_label()`, `set_var_labels()`, `set_val_labels()`,
  `set_var_format()`, `set_var_formats()`, `set_dta_metadata()`, and the note and
  characteristic setters

These are ordinary containers, without additional subclass invariants. Unknown subclasses fail before runtime names, selectors, or updates are evaluated. Assign `data <- as_dibble(data)` to request conversion: it removes additional container classes, retains recognized grouping and metadata, and types numeric/string columns. Existing ordinary containers never undergo that conversion inside a helper.

Grouped tibbles and dibbles support `gen()`, `egen()`, and `repl()` using their dplyr groups. Metadata setters also support rowwise tables and retain the grouping. Structural helpers and `reorder_dta_rows()` require `data <- dplyr::ungroup(data)` first; assign preparation afterwards if needed. Rowwise tables do not support value mutation. See the complete [helper and grouping matrix](r-containers.md#restrictions).

By reference, on a dibble only:

- `data[i, y := value]`, the bracket assignment shape

These return a new object and leave their input alone:

- ordinary `$<-`, `[[<-`, `[<-`, `names<-`, `dimnames<-`, and `row.names<-`
- nested attribute and label replacement, including inside a function

- every dplyr verb (`mutate()`, `filter()`, `arrange()`, `select()`, `group_by()`, joins, `bind_rows()`)
- base `subset()`, `transform()`, `within()`, `head()`, `rbind()`, `cbind()`, and `[` subsetting without `:=`
- `slice_dta_rows()`, which returns the selected rows in a new table
- vector forms of the metadata setters, which return a changed copy
- `copy_data()` and `tibble::as_tibble()`, whose whole purpose is to produce an independent object

On a dibble those operations still return a dibble, so the two styles mix freely. A verb's result is a fresh dataset: a later `repl()` on it does not reach the input it came from, and a `repl()` on the input does not reach the result.

## Why

**Translation fidelity.** `replace x = 0 if y > 5` becomes `repl(data, x = 0, where = y > 5)` — one line, no assignment, no renaming of the dataset at each step. A script converted from Stata reads like the original.

**Cost.** Ordinary R replacement copies the table's column pointers and any column it changes as needed. Explicit helpers can reuse the supplied table and patch compact Stata storage directly. A column shared with a separate table detaches before values change; an unshared `byte` column can stay one byte per row throughout a sequence of replacements.

Dibble results can also share ordinary double values until a write requires
isolation. Selecting, renaming or relocating those columns creates independent
column attributes without copying their values. A first write to a borrowed or
shared column can copy that column; subsequent private sparse writes reuse its
backing. A full replacement installs the new values without copying the old
values first. These choices preserve the existing column classes and the helper
contract on base data frames, tibbles, dibbles and data tables.

**Explicit metadata setters reach the dataset.** `set_var_label(data, x, "Age")` labels the supplied table's column, so every binding sees the label, including the caller when the setter runs inside a function. Use `set_var_format(data, x, "%9.0g")` for display formats and the note or characteristic setters for those attributes.

## What changes in your workflow

**Aliases are the same dataset.** `b <- a` gives you a second name for one dataset, not a snapshot. Ordinary replacement and dibble subsets return independent tables. Explicit mutation detaches columns shared with any separate table while preserving all bindings to the supplied table. A same-storage patch changes all slots pointing to the identical vector within that table. Promotion and metadata setters replace only their named column. When you need an untouchable original, say so:

```r
original <- copy_data(survey)   # independent, keeps compact columns compact
snapshot <- tibble::as_tibble(survey)   # a plain tibble with R's semantics
```

`copy_data()` deep-copies the columns, their compact backing, and mutable dataset metadata. It rejects columns or attributes holding environments, functions, bytecode, external pointers, or weak references, because those cannot be isolated by copying.

**Return and assign from functions that may add columns.** A fresh dibble has
1,024 spare column slots by default, so extra reservation is usually unnecessary.
When additions outgrow those slots, `gen()`, `egen()`, and dibble bracket `:=`
automatically reserve more room. They update a directly named target and return
the resulting table. Inside a function, that target is the local parameter.
Return it and assign the result at the call site:

```r
add_flags <- function(data) {
    gen(data, poor = income < 1000)
    repl(data, poor = NA, where = is_missing(income))
    data
}

survey <- add_flags(survey)
```

If this function calls another function that may grow the table, assign that
function's returned table too. Each caller needs the updated result.

If the table's name, or the name of a plain list containing it, comes from an
enclosing environment, growth creates the replacement binding in the calling
scope, as `<-` does. The enclosing binding still refers to the old table.
Return the updated local table to pass it back to the caller.

When capacity is sufficient, this function mutates and returns the same table.
When growth requires a new table, the assignment updates `survey` to refer to
that result. Other names that referred to the old table still refer to the old
table. Automatic growth warns about this separation.

Returning and assigning is defensive here. In this example, it matters when
the function adds columns by reference and the supplied table has insufficient
capacity. If the caller then ignores the function's result, it keeps the old
table without the added column. A function that returns `NULL` cannot be used
with this pattern. Existing-column replacements need no spare slots.

Alternatively, check and reserve before calling a function that may add ten
columns:

```r
if (!can_add_columns(survey, n = 10L)) {
    survey <- reserve_columns(survey, n = 10L)
}
```

The function can then mutate without returning a new table, provided its
additions fit that reservation. If several names must see the same changes,
reserve before creating those aliases. Calling `reserve_columns()` itself
always returns an isolated table, so only call it when needed.

Set `options(dtatools.auto_grow = FALSE)` to require explicit reservation. In
this strict mode, insufficient capacity causes an error before values, row
selection, or `bysort` run, both at top level and inside a function. The default
is `TRUE`. [ADR 0035](adr/0035-grow-column-capacity-automatically.md) records why
automatic growth replaced the earlier strict default.

**There is no undo after a successful mutation.** Native writes either stage
validated values before committing or retain rollback data through fallible
writes. An interrupted native transaction preserves the original values and
ownership state. A completed `repl()` can only be reversed by supplying the old
values again.

**A `[` assignment does not print.** `[` always makes its result visible, so a bracket assignment at the console would print the whole dataset. As data.table does, dtatools skips the next top-level print of the mutated dataset, so `survey[income < 0, income := NA]` prints nothing and a bare `survey` on the next line prints as usual. The skip lasts only for the statement that made the assignment.

**Column capacity and aliases.** Dibble constructors and readers, and `copy_data()`, reserve 1,024 spare column-pointer slots by default. Control the reserve with `dtatools.alloccol`, for example `options(dtatools.alloccol = 4096L)` to request 4,096 spare slots. Automatic growth allows the requested additions plus the configured reserve. Every column remains in the physical list, so direct consumers and `attributes(data)$names` see the complete table. Reallocation creates an isolated table; old aliases keep a complete table with the values and columns it had when reallocation occurred.

`column_capacity(data)` reports total usable column slots, or `NA_real_` for an unprepared allocation. Subtract `ncol(data)` to find spare slots. `can_add_columns(data, n = 1L)` checks whether `n` additional columns fit. Its `n = 0` case also accepts an unprepared table because no growth is requested; it does not promise that columns can be dropped. A zero-column table reserved with `n = 0` has no resizable allocation and reports `NA_real_`.

`keep_vars()` and `drop_vars()` resolve and validate their column selections before checking capacity for the resulting table. Invalid selections keep their usual diagnostics, and a validated keep-all selection is a no-op even without preparation. A selection that removes columns needs a resizable allocation. Column-selector expressions can therefore run before a capacity error; no table changes have been committed. `rename_vars()`, `order_vars()`, `reorder_dta_rows()`, value replacements, and metadata setters need no spare slots. A bracket call checks all distinct new names before its first write, so insufficient capacity cannot leave an earlier assignment committed. After that check, assignments still run sequentially; an error in a later expression does not roll back earlier successful values.

Assign `data <- reserve_columns(data, n = 10L)` to allow ten extra columns on a base data frame, tibble, dibble, or data table. This preserves container and column classes, isolates columns, rebuilds legacy overlays, and creates fresh dibble bookkeeping without modifying another table's state. It creates an isolated table even when the input already has enough capacity, so use `can_add_columns()` to avoid unnecessary preparation before additions. A data.table also needs a valid self-reference for column-name edits, even without growth; the same preparation repairs it. Structural commits give that table isolated names and matching bookkeeping so another table created by ordinary R copying remains complete. Base `readRDS()`, `unserialize()`, and ordinary table copies can discard capacity. Additions prepare these tables automatically by default. Removing columns still requires assigned preparation when the table lacks a resizable allocation. For computed targets that cannot be rebound, assign the helper's returned table explicitly.

Dropping the last column preserves the row count of a base data frame, tibble, or dibble. A data.table follows its own empty-table convention and becomes a zero-row, zero-column table. Its stored row names are cleared too, so later generation cannot restore rows that its public shape had lost.

**ALTREP columns from elsewhere are detached.** A generic ALTREP column created by base R or another package is converted to an ordinary vector before replacement, because its private caches cannot be safely invalidated. A standalone alias to that former column keeps the old values.

Owned doubles still report `typeof(x) == "double"`. Native code that requests a
writable pointer gets independent backing when needed. Retaining that pointer
prevents later results from sharing its writable values. R serialization can
materialize an owned double column; values, classes and metadata survive, while
live ownership records do not. After restoration, additions can prepare the
table automatically; assign `reserve_columns()` first when using strict mode
or when subsequent operations need a resizable allocation to remove columns.

## Compared with data.table

If you know `data.table`, the model is familiar: `DT[, x := 1]` and `set()` modify in place, and `DT2 <- DT` gives a second name rather than a copy. dtatools' `:=` is deliberately the same shape. Three differences are worth knowing.

The bracket shape belongs to the dibble. `data[i, y := value]` works on a dibble; on a data table it runs data.table's own `:=`, which knows nothing about declared Stata storage; on a tibble or data frame it is whatever error their `[` raises. `gen()` and `repl()` work on all four containers, so they are the portable spelling.

The order of operations is Stata's, not data.table's. In `DT[i, j, by]`, data.table applies `i` first and groups only the surviving rows, so `.N` counts selected rows and a group emptied by `i` disappears. Here the groups are formed first, then `where` and the values are evaluated on each group's rows, so `.N` is the group's row count whatever `where` selects, and `where = .n == .N` marks each group's last row — which is what `bysort id: replace last = _n == _N` means in Stata.

data.table also provides [special symbols](https://rdatatable.gitlab.io/data.table/reference/special-symbols.html)
inside its brackets: `.SD` contains each group's data excluding grouping
columns, `.GRP` is the group number, and `.BY` holds the group's key values.
Dibble brackets do not supply these symbols. Their `j` argument, the part after
the comma, supports column selection and `:=` assignment, but does not evaluate
arbitrary expressions such as `survey[, mean(income)]` against the columns.

To aggregate rows into a separate summary table, use `dplyr::summarise()` with
dplyr installed. For example, this returns one mean income per region:

```r
income_by_region <- survey |>
    dplyr::group_by(region) |>
    dplyr::summarise(mean_income = mean(income), .groups = "drop")
```

The result is a new dibble; `survey` keeps its original rows and columns.
This is different from using `egen()` to add a group statistic to every row
of the existing dataset. dplyr supplies the public summary verb; dtatools
implements its behavior for dibbles.

## See also

- [Containers](./r-containers.md) — what each operation does on a dibble, tibble, data frame, and data table, and the column types that result
- [Where dtatools diverges from Stata](./r-stata-divergences.md)
- `?dibble`, `?"dibble-bracket"`, `?replace_values`, `?copy_data` in R

## Explicit metadata migration

Use explicit setters when a function must update its caller's table. This
works on all four supported containers. Ordinary dibble replacement follows
R's copy-and-rebind rules. Conversion to a dibble does not make nested `attr<-`
inside a function update its caller. Return and assign the result of ordinary
replacement, or use the explicit setters below.

```r
set_metadata <- function(data, my_name, mapping, table_name, metadata) {
    set_var_format(data, .(my_name), "%9.0g")
    set_var_label(data, .(my_name), "Interview status")
    set_dta_metadata(data, variable = my_name,
                     labels = mapping, value.label.name = table_name)
    set_dta_metadata(data, variable = my_name, .metadata = metadata)
}
metadata <- list(notes = c("First note", "Fourth note"),
                 stata.note.numbers = c(1L, 4L),
                 stata.characteristics = c(source = "survey"))
survey <- dibble(status = c(1, 2))
set_metadata(survey, "status", c(Complete = 1, Refused = 2),
             "interview_status", metadata)
```

`set_var_format()` accepts a bare name, quoted string, `!!my_name`, or
`.(my_name)`, just like `set_var_label()`. `set_var_formats()` supports named
arguments, runtime tags such as `.(my_name) := "%9.0g"`, and a named list through
`.formats`. The generic setter and note/characteristic helpers take an evaluated
`variable`, so `variable = my_name` works directly in a loop.

The metadata bundle replaces all supplied attributes together, preserving note
number gaps. Its raw `labels` update preserves empty display text and named
zero-length mappings exactly, with DTA validation before mutation.
`set_val_labels()` keeps its existing normalization that removes empty text. With `notes` alone, numbering starts at one. Clear complete bundles
explicitly when restoring absent metadata:

```r
set_dta_metadata(survey, variable = "status",
                 notes = NULL, stata.note.numbers = NULL,
                 stata.characteristics = NULL)
set_dta_metadata(survey, variable = "status", labels = NULL)
set_dta_metadata(survey, label = "Dataset label", source = "interviews")
```

Clearing labels also clears `value.label.name`. A table name requires a mapping;
a named zero-length mapping, `stats::setNames(double(), character())`, represents
an empty table and differs from `NULL`. The name is a serialization hint, not a
shared registry. To change notes individually, use `set_dta_note()`,
`add_dta_note()`, `drop_dta_notes()`, and `renumber_dta_notes()`; the characteristic
family has the same table mutation contract.

Metadata updates preserve compact column backing and existing capacity. They
repair stale shared bookkeeping on the supplied table without touching another
table's state. Such repair does not restore capacity lost to copying or base
serialization. Subsequent additions can reserve capacity automatically; use
`survey <- reserve_columns(survey)` when explicit preparation is needed.
Legacy overlay tables must be prepared this way before metadata mutation as well.

Generic metadata cannot edit structural, runtime, or storage attributes. Use
column/container operations for those changes. Custom metadata stays in R;
file writers can omit attributes outside their supported metadata profiles.
Vector setters keep their assigned-copy contract, for example
`x <- set_var_format(x, "%9.0g")`.

String storage declarations describe the Stata type, such as `str80` for up to
80 UTF-8 bytes per value. Shortening values with `repl()` or bracket `:=` keeps
the existing declaration. For example, a `str80` column whose values are now
only `"yes"` and `"no"` still has type `str80`.

If you want a new column with a narrower declaration, construct it in `gen()`
instead of assigning the protected `stata.string.storage` attribute later:

```r
gen(survey, status_copy = dta_string(as.character(status)))
set_var_label(survey, status_copy, NULL)
```

`as.character(status)` removes the old storage declaration, and `dta_string()`
chooses the smallest storage that fits the current UTF-8 byte widths. For the
`"yes"` and `"no"` example, `status_copy` is `str3`. To request a particular
declaration, supply it explicitly, for example
`dta_string(as.character(status), storage = "str20")`; all values must fit.
`gen()` keeps that declaration on the new column.

With the default promotion behavior, later `repl()` or bracket `:=` updates
preserve that width when ordinary character values fit and widen it when longer
values require more room. `repl(..., promote = FALSE)` requires values to fit
the existing width. Shorter replacement values do not shrink it.
Choosing a width here controls the new column's declared Stata type and its
field width in DTA output. It is not a recommendation to reserve longer strings
for efficiency.
