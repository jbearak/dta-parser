# dtaparser's tagged_na takes haven's name, one vector and only a to z

Plan 0015 adds `tagged_na(x)` to dtaparser, to make `.a` to `.z` for
values and labels a caller writes, such as a recode whose missing
reasons stay as letters. It takes haven's name, as the accessors take
haven's and labelled's (ADR 0023), and makes the same bits haven's
does.

It differs from haven's in three ways:

- **One vector, not `...`.** `c(...)` would turn `Refused = c("r",
  "d")` into names `Refused1` and `Refused2`. One vector keeps names
  exactly, and `tagged_na("a", "b")` is an "unused argument" error.
- **Names kept.** `tagged_na(c(Refused = "r"))` is a labels vector.
  haven's drops names, so with haven attached after dtaparser a bare
  `tagged_na()` builds labels with no text. The help page and
  `docs/r.md` say to write `dtaparser::tagged_na()` when the names
  matter.
- **Only `"a"` to `"z"`.** haven's makes `.a` from `"ab"`, a tag Stata
  cannot hold from `"A"`, and a plain `NA` from `NA` or `""`. Each is
  more likely a typo than a wish, so dtaparser's is an error naming the
  first bad value.

It is plain R: NA_real_'s bytes, little-endian, with the letter in byte
4, read with `readBin(endian = "little")`, as dtatools builds its `.a`
to `.z`. No C routine, so the ABI number does not change.

## Considered options

- **haven's signature exactly.** Code would move between the packages
  unchanged, but names would still differ, and `...` mangles them.
- **A C routine beside `letter_of`.** One file would hold both
  directions of the layout, at the cost of a routine that `readBin`
  does as well.
- **No constructor; callers use haven.** haven brings readr, vroom,
  forcats, hms, bit64 and six more packages to make one double.

## Consequences

- A bare `tagged_na()` with haven attached last gives unnamed values.
- dtatools' internal `tagged_na(letter)` is unchanged; dtatools does
  not import dtaparser's namespace (ADR 0016).
