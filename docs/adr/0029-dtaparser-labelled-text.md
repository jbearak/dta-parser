# A label stands for its code in a labelled column's == and assignment

ADR 0028 and plan 0016 made text an incompatible type for a
`dtaparser_labelled`, so comparing with a label meant
`val_label(x) == "Yes"`. Factors take their labels directly, and code
that names labels reads more clearly than code that names codes, so
plan 0017 lets a string stand for the code it labels when it is
compared with `==` or `!=`, assigned with `[<-` or `:=`, or combined
by `if_else()`, `case_when()` and `coalesce()`.

Three limits keep text from giving wrong answers quietly:

- A string that labels no code, or two codes, is an error.
- `x == "Refused"`, where "Refused" labels `.r`, is an error: `NA`
  compares as `NA`, so it would be `NA` on every row. Assigning
  "Refused" is allowed and gives `.r`.
- `<`, `>`, `<=` and `>=` with text are errors, since labels have no
  order.

`%in%` and `match()` keep comparing codes through `mtfrm()`, which sees
one side only and cannot also serve `x %in% c(1, 5)`. So
`x %in% "Yes"` is `FALSE` throughout; the docs say to write
`val_label(x) %in% c(...)`.

## Considered options

- **Keep text out** (ADR 0028). No quiet `%in%` trap, but every
  comparison with a label needs `val_label()`.
- **`mtfrm()` gives label text.** `%in%` with labels would work, and
  `%in%` with codes would silently fail instead.

## Consequences

- `x == "Yes"` and `x == 1` are the same test.
- `x %in% "Yes"` is silently `FALSE`; it is the one place text fails
  without an error.
