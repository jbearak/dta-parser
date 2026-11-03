# Plan: tagged_na(), to make .a to .z in dtaparser

Status: approved by Sonnet 5.5 (two rounds) and GPT-6.1 Terra (two
rounds); implemented.

## Problem

dtaparser reads `.a` to `.z` into doubles as haven's tagged NAs (ADR
0017), and plan 0013's accessors read them back: `na_tag()`,
`is_tagged_na()`, and `val_label()`, which matches a tagged value to
its label by letter. Nothing in dtaparser makes one. Code that builds
its own labelled column, such as a recode that turns "refused" and
"don't know" into missing values that keep their reason, has to call
`haven::tagged_na()`. haven is in Suggests here, and taking it to make
one double brings readr, vroom, forcats, hms, bit64 and six more
packages into a project that has none of them.

Plan 0013 left a constructor out ("comparisons go through
`is_tagged_na(x, "d")`"). That holds for comparisons. Writing values
and labels needs a constructor, so this plan replaces that bullet.

## Export

One function, in `r/dtaparser/R/accessors.R`, documented on the
`na_tag` help page:

```r
tagged_na(x)
```

`x` is a character vector of lowercase letters `"a"` to `"z"`. The
result is a double vector as long as `x`, keeping its names: each
element `NA_real_` with its letter in bits 32 to 39, the layout
`read_dta` writes (`r_double` in `src/rust/lib.rs`), `letter_of` in
`src/init.c` reads, and haven's `tagged_na()` makes. No class. So

```r
tagged_na(c(Refused = "r", "Don't know" = "d"))
```

is a labels vector ready for a `labels` attribute.

One vector, not haven's `...`. A call with one argument,
`tagged_na("d")` or `tagged_na(tags)`, makes the same bits in both
packages for lowercase letters; only dtaparser's keeps names.
`c(...)` would turn `Refused = c("r", "d")` into names `Refused1` and
`Refused2`; one vector keeps names exactly. `tagged_na("a", "b")` is
an "unused argument" error, which says what to write.

Each element must be one lowercase letter, checked with
`x %in% letters` as `is_tagged_na()` checks `tag`, so the locale does
not matter. Anything else is an error:

```
x must be lowercase letters "a" to "z", not "ab"
```

naming the first bad value (`NA`, `""`, `"ab"`, `"A"`, `".d"`, `"é"`),
or, for input that is not character (a number, a factor, a list,
`NULL`), `x must be a character vector, not <class>`. haven is looser:
`"ab"` makes `.a`, `"A"` and `"é"` make tags Stata cannot hold, `NA`
and `""` make a plain `NA`. Each of those is more likely a typo than a
wish. `tagged_na(character())` gives `numeric(0)`; `tagged_na()` is
R's missing-argument error, where haven's says `x` must be a
character vector.

Done in plain R, as dtatools' internal `tagged_na()` builds `.a` to
`.z` (`r/dtatools/R/missing.R`): repeat NA_real_'s eight bytes
(`a2 07 00 00 00 00 f0 7f`, little-endian) once per element, write each
letter's byte at offset 4, and read them back with
`readBin(..., "double", size = 8, endian = "little")`. Naming the byte
order makes it the same on any machine. No new C routine, so `init.c`
and the ABI number do not change.

## Names, and the packages that share them

`tagged_na` is haven's name, as the accessors take haven's and
labelled's (ADR 0023). With both attached, a bare `tagged_na()` finds
the one attached last. For a vector of lowercase letters both give the
same bits, but haven's drops names: with haven attached after
dtaparser, `tagged_na(c(Refused = "r"))` is an unnamed `NA`, and a
labels vector built that way has no text. So the help page and
`docs/r.md` say to write `dtaparser::tagged_na()` when the names
matter, as they already say for `val_label()`. The two also differ on
input dtaparser rejects, and haven's takes its letters as `...`. dtatools has an internal `tagged_na(letter)`. It is
not exported, and dtatools does not import dtaparser's namespace (ADR
0016), so nothing changes there.

A short ADR, `docs/adr/0025-dtaparser-tagged-na.md`, records the name,
the single argument and the strict letters. ADR 0023 stays as it is:
it is about the accessors' names, and its count of exports was true
when written.

## Docs

- `accessors.R` roxygen for the `na_tag` page: the description says
  `tagged_na()` makes what `na_tag()` reads; `@param x` covers the
  character vector for `tagged_na()`; `@return` gains `tagged_na()`;
  the "haven's names" paragraph says how `tagged_na()` differs from
  haven's (one vector, names kept, lowercase letters only) and to call
  `dtaparser::tagged_na()` when haven is attached too; the example
  adds `x <- c(1, tagged_na("d"), NA)`, `na_tag(x)` and `is.na(x)`.
  Regenerate `na_tag.Rd` and `NAMESPACE`.
- `docs/r.md`, "Plain R types: dtaparser": after the `na_tag` block, a
  short block making a labels vector with `dtaparser::tagged_na()` and
  reading it back with `dtaparser::val_label()`. The API reference says
  "five accessors, and `tagged_na(x)` to make `.a` to `.z`", listing it
  beside `na_tag(x)`.
- Plan 0013's "Not in this change" bullet on a constructor gets
  "(plan 0015 adds `tagged_na()`)".

## Tests

In `r/dtaparser/tests/testthat/test-accessors.R`. Expected bits come
from `haven::tagged_na()`, an open-source library, compared byte by
byte with `writeBin()`, since `identical()` does not look at NaN
payloads.

- For all 26 letters at once, `writeBin(tagged_na(letters), raw())`
  equals `writeBin(haven::tagged_na(letters), raw())`.
- `na_tag(tagged_na(letters))` is `letters`; `is.na()` is all `TRUE`;
  `is_tagged_na(tagged_na(c("d", "r")), "d")` is `TRUE FALSE`.
- Names kept exactly: `tagged_na(c(Refused = "r", "d"))` has names
  `c("Refused", "")`; an unnamed `x` gives no names.
- `tagged_na(character())` is `numeric(0)`.
- Errors naming the bad value for `NA_character_`, `""`, `"ab"`,
  `"A"`, `".d"` and `"é"`; type errors for `1`, `factor("a")`,
  `list("a")` and `NULL`; `tagged_na("a", "b")` is an error.
- The letter survives what a recode does to a column: `c(1, x, NA)`,
  subsetting, and setting the `labels` attribute.
- `val_label()` on a double whose `labels` attribute mixes answers
  and reasons, `c(No = 0, Yes = 1, tagged_na(c(Refused = "r",
  "Not asked" = "n")))`, with values `0, 1, .r, .n, ., 2`: it gives
  `"No" "Yes" "Refused" "Not asked" NA NA`, so a plain `NA` and an
  unlabelled number match nothing, and the pair works without haven.

Each new test is broken once by a scratch edit and seen to fail, then
restored. dtatools' docs test checks that every dtaparser export has a
help page. Its check that `docs/r.md` names each export cannot fail
for `tagged_na`, since the "Coming from haven" table already shows
haven's `tagged_na("d")`, so the new `docs/r.md` block rests on review.

## Release

A separate PR sets both R packages to 1.3.0, and tag `r-v1.3.0`
publishes it, as for 1.2.0. dtatools does not use `tagged_na()`, so its
`Imports` stay at dtaparser 1.2.0. Code that calls `tagged_na()` needs
dtaparser 1.3.0 and says so in its own `DESCRIPTION`.

## Not in this change

- `.a` to `.z` as exported objects, as dtatools has: `tagged_na("d")`
  is the one way.
- Uppercase, digit or other tags, which haven allows and Stata does
  not.
- Any promise that arithmetic keeps the letter. A recode assigns
  values; it does not compute with missing ones.
- A labelled class, or printing tagged NAs with their letter.
