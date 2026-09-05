# Where dtatools diverges from Stata

`dtatools` treats Stata's behavior as the compatibility target: storage types, the 27 missing codes and their ordering, value labels, `merge`, `append`, `generate`, `replace`, and `by varlist:` all mean in R what they mean in Stata. This page records the places where it deliberately does something else, and why. Everything not listed here is either intended to match Stata or is a bug worth reporting.

Divergences fall into three kinds. Some exist because R is a language of functions and values rather than a command language operating on one current dataset. Some exist because Stata's behavior is lossy or nondeterministic and a lossless or reproducible alternative is available. The rest are Stata edge cases where following Stata would silently produce a wrong answer.

For a translated pipeline, start with [numeric replacement](#numeric-replacement) and [identifier migration](#migrating-identifiers). A difference in results can expose information loss in the Stata source as well as a translation error.

## Language shape

R has no command prefixes, no `if`/`in` qualifiers, and no leading-underscore names, so the translated spellings differ even where the semantics do not.

| Stata | dtatools | Why |
| --- | --- | --- |
| `_n`, `_N` | `.n`, `.N` in `values` and `where` | `_n` is not a valid R name. |
| `mi(x)` | `is_mi(x)`, or `is_missing(x)` | The package prefixes predicates with `is_`; `is_mi()` keeps Stata's shorthand recognizable. |
| `by varlist:` prefix | `by =` / `bysort =` arguments | R has no prefix syntax. The semantics are Stata's: groups are formed first, then `where` and the values are evaluated per group. |
| `bysort id (date):` | `arrange()` or `reorder_dta_rows()`, then `by = id` | Parenthesized sort-only keys would need a second grammar inside an argument that otherwise names grouping columns. |
| `generate x = exp if cond in 1/10` | `gen(data, x = exp, where = cond)` | `[in]` is a row-position selection, which `where` already accepts as numeric positions. |
| `generate x = exp, before(y)` | `gen()` appends; use `order_vars()` | Placement is a separate concern from generation, and `order_vars()` already spells Stata's `order`. |
| `generate x:lblname = exp` | `gen()` then `set_val_labels()` | Label authoring inside a generate expression has no natural R spelling. |
| `generate y = x` then `label variable`, `label copy`, `label values` | `gen(data, y = x)` alone | A bare column reference copies the variable label and value labels along with the values, because in R the labels are attributes of the vector. Stata's `generate` copies values only. An arithmetic expression, `gen(data, y = x + 0)`, and `repl()` produce an unlabelled result, as in Stata. |
| `note x: text`, `label var x "text"` | `set_dta_note()`, `set_var_label()` | See [notes and characteristics](./stata-notes-and-characteristics.md) and the [label metadata guide](./r-label-metadata.md). |

Stata commands report how many missing values `generate` produced and how many real changes `replace` made. dtatools omits those counts; `repl()` reports storage promotion. They signal problems as R conditions instead: an error where Stata would refuse, a warning where a conversion loses information.

Stata commands modify the dataset in memory. dtatools splits this: `gen()`, `repl()`, `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()`, `reorder_dta_rows()`, and `:=` modify the dataset by reference, as Stata does, while the notes, characteristics, and metadata setters called in functional form return a changed copy. Called in replacement form on a dibble — `var_label(data$x) <- "Age"` — the metadata setters are by reference again. See [mutation by reference](./r-mutation-by-reference.md).

## Egen calculations

`dta_mean()`, `dta_max()`, and the other migrated calculation functions are
ordinary R functions, available in `gen()`, `egen()`, and dibble `:=`.
The [egen guide](./r-egen.md) compares all eight forms. A filtered `egen()`
calculates over the selected sample; `gen()` and `:=` calculate over the full
group unless their function arguments explicitly filter the inputs.

`egen()` evaluates each value expression once per admitted group instead of
repeating expression evaluation inside a Stata ado. Errors leave the dataset
unchanged, including a requested `bysort` permutation. Explicit integer
storage too small for the result is an error rather than a missing-code cast.
All-missing row maxima become system missing; the checked Stata 18 ado can
retain the last input's missing tag. Group labels follow the per-variable
mapping model below, without a live shared-table replacement operation.

## Storage types

`?"dta-storage-defaults"` states the full mapping, and [containers](./r-containers.md#what-column-type-results) tabulates it. The following rules differ from Stata.

**Generation defaults apply at command assignment.** A bare double result from `gen(data, y = x * 2)` is stored as `float`, exactly as Stata's `generate` would, and `options(dtatools.generate_type = "double")` is the equivalent of Stata's `set type double`. New `:=` columns and untyped `egen()` results use the same default. `dplyr::mutate()`, `transform()`, `within()`, and the replacement operators follow R's types: the same expression takes `float` through `gen()` and `double` through `mutate()`. Standalone numeric calculation helpers retain double precision until assignment. See [ADR 0022](./adr/0022-give-gen-statas-generate-default.md) and [ADR 0027](./adr/0027-compose-egen-with-value-functions.md).

**Bare integer results are `long`, not `float`.** Stata's untyped `generate` produces `float` whatever the expression. An R integer vector comes from R rather than from a translated Stata line, and `float` cannot represent integers above 2^24, so `gen(data, y = 1L:n())` stores `long`.

One consequence worth knowing: a bare Arrow string read into a dibble carries the width of its dictionary, so a wider replacement string widens the declared `str#`.

Two more mapping choices are R-side rather than Stata-side, and are stated here because they surprise Stata users. Logical columns stay logical rather than becoming `byte`, because R idioms on flags (`filter(data, flag)`, `where = flag`) need a logical; `save_dta()` writes them as `byte`. Factors stay factors and are written as value-labelled `long`.

### Numeric replacement

`replace_values()` and its alias `repl()` preserve the input R numeric value
by default, widening declared storage when necessary. This intentionally
produces different results from Stata when Stata would round. The policy
also applies to typed-column replacement through `mutate()`, `:=`,
`transform()`, `within()`, and dataset replacement operators. See
`?replace_values`, `?"dta-storage-defaults"`, and the decision in
[ADR 0024](./adr/0024-promote-in-replace-values-as-stata-does.md).

With `promote = TRUE`, storage choice accounts for:

- **Range.** An out-of-range integer needs wider storage, such as `byte`
  receiving 200 becoming `int`.
- **Integrality.** Integer storage cannot hold fractions. A `byte` receiving
  1.5 becomes `float`; a `long` receiving 1.5 becomes `double` because
  promotion must retain the full integer capacity of `long`.
- **Precision.** Storage must preserve the input R double exactly. A `float`
  receiving 16777217 becomes `double`. A `byte` receiving 0.1 also becomes
  `double`, since binary32 cannot preserve that R double.

The search only widens, through `byte`, `int`, `long`, `float`, `double`,
skipping `float` from `long`. It keeps the declared type when all assigned
values fit exactly and otherwise chooses the narrowest eligible type that
also preserves retained values. "Exact" means the input binary64 R value,
not exact decimal arithmetic. R's 0.1 is already a binary approximation of
one tenth; promotion avoids further rounding to binary32. It cannot recover
digits lost before replacement, including values explicitly rounded with
`dta_float()`.

The following comparison was reported for dtatools 0.7.0 at
[`75bf5ec`](https://github.com/jbearak/dta-parser/commit/75bf5ec88c6e6fde090f07a8684f9916ff48e34c)
and Stata MP 18 in [issue #170](https://github.com/jbearak/dta-parser/issues/170).

| Input and replacement | Stata 18 | dtatools `promote = TRUE` | dtatools `promote = FALSE` |
| --- | --- | --- | --- |
| `float`, replace with 16777217 | `float`, 16777216 | `double`, 16777217 | `float`, 16777216 |
| `byte`, replace with 0.1 | `float`, rounded to float | `double`, exact input R double | Error |

```stata
clear
set obs 1
generate float x = 1
replace x = 16777217
assert x == 16777216
local storage : type x
assert "`storage'" == "float"
```

```r
data <- dtatools::dibble(x = dtatools::dta_float(1))
dtatools::repl(data, x = 16777217)
dtatools::dta_storage_type(data$x)  # "double"
as.double(data$x)                  # 16777217
```

Stata widens integer storage for range or integrality, but does not widen a
`float` for precision. The existing probe also records a range difference:
a `float` receiving 1e40 stays `float` and becomes missing in Stata, while
dtatools promotes it to `double` and preserves 1e40.

`promote = FALSE` disables widening and uses the declared storage's
conversion rules. A `float` can round without an error. Integer storage
rejects fractional or out-of-range replacements, so the `byte` receiving
0.1 errors and leaves the column unchanged. This option is neither a
general Stata-compatibility mode nor a guarantee against precision loss.

```r
fixed <- dtatools::dibble(x = dtatools::dta_float(1))
dtatools::repl(fixed, x = 16777217, promote = FALSE)
dtatools::dta_storage_type(fixed$x)  # "float"
as.double(fixed$x)                  # 16777216
```

`replace_values()` and `repl()` report promotion as an R message, such as
``variable `x` was byte now int``. Suppress it with `suppressMessages()`.
`:=` and `mutate()` promote silently. An assignment selecting no rows does
not promote.

The executable [Stata probe](../conformance/stata/replace-promotion.do) and
its [Stata 18 MP log](../conformance/stata/replace-promotion.log) check the
Stata side. The numeric replacement cases in
[`test-mutate-data.R`](../r-package/dtatools/tests/testthat/test-mutate-data.R)
check storage and values under both promotion settings in the R package
suite. Keep the table and examples consistent with those checks.

### Migrating identifiers

Choose sufficient destination storage in Stata **before assignment**.
`generate long cluster = source_cluster` preserves identifiers in Stata's
`long` range. Use `generate double cluster = source_cluster` for larger
identifiers within double's exact integer range. For an existing float
destination, `recast double cluster` before `replace cluster = source_cluster`
prevents rounding during that assignment. Widening an already rounded value
does not restore its lost digits. `set type double` changes the default for
future generation, not existing columns.

In the Viet Nam 2006 fertility-surveys pipeline, source cluster identifiers
were `long`, but the Stata destination was implicitly `float`. Copying the
identifiers rounded them. The R translation's promotion to `double`
revealed that production Stata bug. The correction belongs in the Stata
assignment. Investigate the source values and storage on both sides before
adding casts to an R translation that reproduce information loss.

## Expressions and rows

**An expression with a row selection is evaluated for every row, then selected.** Stata evaluates `generate x = exp if cond` only for the observations `cond` selects. dtatools evaluates `values` once against the whole dataset (or the whole group, under `by`/`bysort`) and then assigns to the selected rows. R expressions are vectorized over columns, and evaluating them twice — once to find the selection, once on a subset — would change the meaning of any aggregate in the expression. Where the difference matters, write the restriction into the expression as well as into `where`.

**Rows a selection excludes hold Stata's missing.** This matches Stata: a numeric column generated under `where` holds system missing outside the selection, a string column holds `""`. `replace_values()` leaves excluded rows untouched, as `replace` does.

**Strings have no `NA`.** Stata's only missing string is the empty string. `NA_character_` in a replacement value or an exported column becomes `""`, and the conversion is reported on export. Owned Stata string vectors reject `NA_character_` outright.

## Merge

`dta_merge()` follows Stata's `merge` in key identity — all 27 missing codes match only themselves — in requiring a declared `1:1`, `m:1`, or `1:m` relationship, in rejecting `m:m`, in the master-wins rule for overlapping variables, and in generating a value-labelled `_merge`. It diverges in three places. See [ADR 0009](./adr/0009-own-dta-identity-merge.md) and the [joins note](./r-joins-with-stata-columns.md).

**Result order.** Stata re-sorts the merged dataset by the key variables. `dta_merge()` returns master rows in master order followed by unmatched using rows in using order. Key order would make every merge pay for a sort under Stata's ordering of 27 missing codes, and stable input order is the more useful default in an R pipeline. Sort afterwards when Stata's order is wanted.

**Colliding value-label table names.** Stata stores named value-label definitions at dataset scope. When master and using define different mappings under the same name, Stata keeps master's definition and can then display it on a using-only variable — privacy labels on a month variable, for instance, which can silently misdirect a later recode written against label text. `dtatools` treats each variable's resolved code-to-text mapping as authoritative, so the using-only variable keeps its own labels. See [ADR 0016](./adr/0016-own-resolved-value-label-mappings.md) and the [label metadata guide](./r-label-metadata.md#compatibility-with-stata-merge). Correct accidental name collisions in the Stata source before comparing exact merge output.

**Warnings where Stata is silent.** Overlapping non-key variables resolve master-first, as in Stata, but `dta_merge()` warns and names them, and it warns again when the two sides disagree on a variable's metadata.

## Append

`dta_append()` reproduces `append using ..., force`: the union of variables in first-appearance order, missing values where a source lacks a variable, string storage widened to the widest contributor, numeric storage promoted losslessly, and labels, formats, and variable notes taken from the first source that contributes the variable.

**Sources are one list, not a master and a using.** Stata appends one or more using files to the dataset in memory. `dta_append(list(a, "b.dta", "c.arrow"))` resolves the schema union in a single pass instead of reallocating the result once per source.

**Dataset-level notes are an explicit argument.** Stata does not define what `append` does with them and keeps the master's. `dataset_notes` defaults to `"first"` to match that, with `"all"` and `"none"` available because neither is obviously wrong.

**`force` is an argument with a strict default.** A string/numeric conflict follows Stata's `force` — the first contributor's type wins, the conflicting rows hold missing, and a message names them — but `force = FALSE` makes it an error instead.

## Reports and diagnostics

**`labelbook(list_limit = )` lists a deterministic prefix.** Stata's `list(#)` shows a random subset of mappings. dtatools lists the first ones, so two runs of the same script produce the same report.

**Reports are data, not printed output.** `codebook()` and `labelbook()` return structured results — underlying numeric codes, missing counts, notes, diagnostics, and Stata-style missingness implications — so callers need not parse a printed report. `tab()` returns a base `table` object rather than Stata's formatted `tabulate` output.

**`recode()` is dplyr's interface, not Stata's command.** `dtatools::recode()` takes dplyr's replacement form and adds what dplyr loses: unmatched system and extended missing payloads survive, as do numeric classes, `haven_labelled`, `Date`, and `POSIXct`. Stata's `recode` rule syntax, including range rules, is not implemented. Value-label definitions are not rewritten when the codes they describe change.

**`datasig()` is stronger than `datasignature`.** It is order-sensitive and covers names and order, storage types, labels, display formats, notes, and every value in row order, so it detects changes Stata's `datasignature` misses: values swapped within a variable, reordered observations, and values exchanged between same-type variables. The signatures are therefore not comparable with Stata's; a signature is a claim about content under `datasig()`'s own definition.

**`factor_from_labels()` is one-way by design.** It keeps distinct source codes distinct even when their label text is identical, but it does not support reconstructing the numeric variable. Stata has no factor type; a reversible factor class would invite round-trips that cannot be honored. See [ADR 0004](./adr/0004-own-stata-missing-and-factor-helpers.md).

## Files

**The writer targets Stata 18 and 19 only.** It emits release 118, or 119 above 32,767 variables, and does not write older releases or the release 120/121 alias-variable layouts. Use haven for older releases.

**Output is always little-endian.** Byte order has no effect on the values Stata exposes, and fixing it makes output deterministic across writer hosts.

**Extensionless local names resolve to `.dta`**, as Stata's `use` and `save` do. On write, dtatools adds the extension with a warning rather than silently.

**Pre-Unicode encoding is a choice, not a fact read from the file.** Releases before 118 record no code page, so the reader defaults to Windows-1252 and accepts explicit UTF-8, Windows-1252, and true ISO-8859-1 overrides.

**Notes and characteristics on a variable named `_dta` are rejected on DTA export.** Arrow can hold them; DTA reserves that spelling for dataset scope, so changing their scope silently is not an option.

See the [compatibility contract](./compatibility.md) for supported releases, encodings, and the reader's stricter row-window validation, which differs from haven rather than from Stata.

## Divergences from R, not from Stata

Two behaviors surprise R users rather than Stata users, and are documented elsewhere:

- Stata missing codes are missing to `is.na()` and `is_missing()`, but vctrs equality must encode them as distinct comparable keys, so `vctrs::vec_detect_missing()` and completeness operations treat them as present, and dplyr's `na_matches` does not change their identity. See [Stata vector operations](./r-stata-vector-operations.md).
- On a dibble the replacement operators write by reference, which is not R's copy-on-modify. See [mutation by reference](./r-mutation-by-reference.md) and [containers](./r-containers.md).
