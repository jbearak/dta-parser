# `formatValue` takes a `%w.0g` format's digits from its width

Amends what `formatValue` documented since 1.0: "7 significant digits,
or `d` for `%w.dg` ... Widths are left to the caller."

A release audit of manuscript-markdown, which shows `.dta` files as
tables through `formatValue`, found that a double column at `%21.0g`
holding `12345678.12345` and `12345678.22345` showed both cells as
`12345678`. That was the documented behaviour, so no test caught it,
but a variable whose format someone widened to see more digits lost
them.

**A `%w.0g` format shows `w - 2` significant digits, at least 7 and at
most 15.** `%wg` with no `.d` is the same. The rest of `%g` is as it
was: the number as R prints it at that many digits (`format(x, digits =
d)`), trailing zeros dropped, in fixed notation unless scientific is
narrower.

| Format | Digits | `sqrt(2)` |
|---|---|---|
| `%8.0g` and narrower, `%g` | 7 | `1.414214` |
| `%9.0g` | 7 | `1.414214` |
| `%10.0g` | 8 | `1.4142136` |
| `%12.0g` | 10 | `1.414213562` |
| `%17.0g` and wider | 15 | `1.4142135623731` |

Why these three numbers:

- `w - 2`. A sign and a decimal point each take a character of the
  width, and the digits get the rest. Zeros that only place the decimal
  point are not counted (`-0.12345678` at `%10.0g` is 11 characters), so
  the text can still be longer than the width.
- At least 7. `%9.0g` is a float's usual format, a float holds about 7
  digits, and 7 is R's default. Narrower formats keep 7 too. They are
  the usual formats of byte and int variables, whose values need 5
  digits at most, so fewer digits would change output for no gain.
- At most 15. A double gives back any decimal of 15 significant digits
  unchanged (the Parquet reader's `DOUBLE_DIGITS` is the same number).
  Past 15 the digits are the double's binary rounding: `0.1 + 0.7`
  would show as `0.7999999999999999` at 16, and `0.1 + 0.2` as
  `0.30000000000000004` at 17.

This is the library's own rule. No rule of Stata's was looked up or
tested against (`AGENTS.md` forbids both), and the tests' expected text
is what R 4.6.2 prints with `format(x, digits = d)`.

Decisions that could have gone the other way:

- `%w.0gc` follows its width as well, and `c` adds its commas to the
  result as before. Keeping 7 digits there would have left `%21.0gc`
  showing the two values above alike. The commas are not counted against
  the width, so `1234567.891` at `%12.0gc` is `1,234,567.891`, 13
  characters.
- An explicit `d` (`%21.3g`) still means `d` digits, whatever the width.
- A format `formatValue` does not know (`%21x`) still shows 7.
- The width still does nothing else. The text is not padded or aligned,
  and it can be longer than the width, as it could before
  (`-0.3333333` at `%9.0g` is 10 characters).

What follows from it:

- A double at its usual `%10.0g` now shows 8 digits, not 7:
  `1234.56789` is `1234.5679`, not `1234.568`.
- A number with more integer digits than the width gives can move from
  scientific to fixed notation, because R compares the two widths at the
  new digit count. `1234567890123` at `%10.0g` was `1.234568e+12` and is
  `1234567890123` (at 8 digits both take 13 characters, and a tie goes
  to fixed).
- Two doubles that round to the same 15 digits still show alike.
- The last digit can differ from R's more often than at 7 digits. A
  value exactly halfway between two candidates (`4028701782226562.5` at
  15 digits) rounds up, as `formatValue` always has, where R rounds to
  even. R on a machine without extended precision (Apple silicon) can
  also round the other way when a value is within a rounding error of
  halfway. Of 20,000 random values at widths 9 to 22, 112 differed from
  R 4.6.2 on such a machine in the last digit, 79 exact ties and 33 within two
  units in the double's last place of one. All 20,000 were the double's
  exact value rounded half up.
- `formatValue` sees a value, not its storage type. A float variable
  given a wide format shows the digits of the double it was read into:
  0.1 stored as a float is `0.100000001490116` at `%21.0g`. At its usual
  `%9.0g` it is `0.1`.

The change is in `@jbearak/dta-parser` 2.0, which is not published yet,
so it adds a line to the 1.x to 2.0 migration notes and no version bump.
1.x keeps 7 digits.
