# Where dtatools diverges from Stata

`dtatools` treats Stata's behavior as the compatibility target: storage types, the 27 missing codes and their ordering, value labels, `merge`, `append`, `generate`, `replace`, and `by varlist:` all mean in R what they mean in Stata. This page records the places where it deliberately does something else, and why. Everything not listed here is either intended to match Stata or is a bug worth reporting.

Divergences fall into three kinds. Some exist because R is a language of functions and values rather than a command language operating on one current dataset. Some exist because Stata's behavior is lossy or nondeterministic and a lossless or reproducible alternative is available. The rest are Stata edge cases where following Stata would silently produce a wrong answer.

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
| `note x: text`, `label var x "text"` | `set_dta_note()`, `set_var_label()` | See [notes and characteristics](./stata-notes-and-characteristics.md) and the [label metadata guide](./r-label-metadata.md). |

Stata commands print a report — how many missing values `generate` produced, how many real changes `replace` made. dtatools functions do not print one. They signal problems as R conditions instead: an error where Stata would refuse, a warning where a conversion loses information.

Stata commands modify the dataset in memory. dtatools splits this: `gen()`, `repl()`, `keep_vars()`, `drop_vars()`, `order_vars()`, `rename_vars()`, `reorder_dta_rows()`, and `:=` modify the dataset by reference, as Stata does, while the notes, characteristics, and metadata setters called in functional form return a changed copy. Called in replacement form on a dibble — `var_label(data$x) <- "Age"` — the metadata setters are by reference again. See [mutation by reference](./r-mutation-by-reference.md).

## Storage types

`?"stata-storage-defaults"` states the full mapping, and [containers](./r-containers.md#what-column-type-results) tabulates it. Three of its rules diverge from Stata.

**`generate`'s default reaches only `gen()` and `:=`.** A bare double result from `gen(data, y = x * 2)` is stored as `float`, exactly as Stata's `generate` would, and `options(dtatools.generate_type = "double")` is the equivalent of `set type double`. But `dplyr::mutate()`, `transform()`, `within()`, and the replacement operators are R operations on a container, not translations of a Stata command, and they follow R's types: the same expression takes `float` through `gen()` and `double` through `mutate()`. Making `gen()` alone follow `generate` is what lets a translated Stata script keep the storage the original produced without restating `dta_float()` on every line; making the R verbs follow R types is what keeps `mutate()` from silently narrowing an R pipeline's doubles. See [ADR 0022](./adr/0022-give-gen-statas-generate-default.md).

**Bare integer results are `long`, not `float`.** Stata's untyped `generate` produces `float` whatever the expression. An R integer vector comes from R rather than from a translated Stata line, and `float` cannot represent integers above 2^24, so `gen(data, y = 1L:n())` stores `long`.

**Promotion is Stata's, except that precision promotes too.** When `mutate()`, `:=`, `transform()`, `within()`, a replacement operator, or `repl()` overwrites a typed column with values its storage cannot hold, the column takes the narrowest of `byte`, `int`, `long`, `float`, `double` that holds every new value exactly and never narrows the integers the column can hold — so an overflowing `long` goes to `double` rather than through `float`, which carries seven fewer bits of integer precision.

That matches Stata on every case in [`conformance/stata/replace-promotion.do`](../conformance/stata/replace-promotion.do), which was measured against Stata 18.0 MP rather than recalled. Stata widens when the declared type cannot represent a value **at all** — through range (`byte` given 200 becomes `int`) or through integrality (`byte` given 1.5 becomes `float`, `long` given 1.5 becomes `double`). Stata never widens for **precision**, and this is the one place dtatools differs:

```r
# Stata: `replace z = 1.234567890123456` on a float stays float and
#         stores 1.234567880630493, with no message.
repl(data, z = 1.234567890123456)   #> variable `z` was float now double
```

Stata's silence there is a data loss, not a convenience, so dtatools promotes and keeps the value exact. The same asymmetry appears in Stata's `generate` default: `gen x = 16777217` creates a `float` holding `16777216`, silently. `options(dtatools.generate_type = "double")` is the way out, as `set type double` is in Stata.

**`replace_values()` reports its promotions; `:=` and `mutate()` do not.** `replace_values()` and its short name `repl()` translate Stata's `replace`, so they print what Stata prints:

```r
repl(data, x = 1000)      #> variable `x` was byte now int
data[, x := 1000]         #> promotes to int, silently
```

`:=` and `mutate()` follow dplyr's contract that the right-hand side defines the column, and R verbs are expected to be quiet, so they promote without a message. An assignment that selects no rows promotes nothing, as Stata's `(0 real changes made)` does not. Pass `promote = FALSE` to `replace_values()` or `repl()` to hold a column to its declared storage and get an error instead — useful when a translated script should fail loudly rather than widen. Suppress the note with `suppressMessages()`.

One consequence worth knowing: a bare Arrow string read into a dibble carries the width of its dictionary, so a wider replacement string widens the declared `str#`.

Two more mapping choices are R-side rather than Stata-side, and are stated here because they surprise Stata users. Logical columns stay logical rather than becoming `byte`, because R idioms on flags (`filter(data, flag)`, `where = flag`) need a logical; `save_dta()` writes them as `byte`. Factors stay factors and are written as value-labelled `long`.

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
