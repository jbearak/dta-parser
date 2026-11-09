# Plan: faster fixed-width reads

Status: done (Claude Sonnet and GPT Sol each proposed a plan; this is
their common ground).

## Problem

After ADR 0039, R's `read_fixed_width` read 1995's NSFG female
respondent file (142 MB of text, 10,847 records kept, 5,754 columns,
a 1.5 MB setup) in 1.27 s. Timing each step showed where it went:

| step | time |
|---|---|
| parsing the setup | 0.55 s, nearly all in the tokenizer |
| reading the data and selecting records | 0.09 s |
| the pass that finds each column's type, letters and invalid fields | 0.38 s, on one thread |
| filling R's vectors (already on three threads) and R's allocation | 0.2 s |

The tokenizer was quadratic. To learn the length of a symbol token
(`=`, `-`, `$`), `token()` decoded the rest of the file as UTF-8, so
each of the setup's many symbols checked up to 1.5 MB.

## Changes

1. **Tokenizer.** A character's length comes from its first byte;
   the source is already valid UTF-8. The setup parse goes from 0.55 s
   to 24 ms.
2. **Digits.** `parse_number` converts a field of 1 to 15 ASCII digits
   itself: such an integer is below 2^53, so the conversion is exact and
   equals what `str::parse` returns. Signs, points, exponents and longer
   fields still go through `str::parse`, so `-0`, `.5` and `1e3` read as
   before. A test compares the bits.
3. **The type pass on several threads.** `FixedWidth::read` splits the
   wanted columns into runs, one per worker (`threads::resolve`, at most
   three by default, one in wasm), and each worker reads its columns
   record by record. Each column's rows are still read in order, so
   its storage type, letters, first invalid record and string values
   are as before, and the warnings come out in column order as before.
   Files of under 2^20 values stay on one thread.

## Results

On the 1995 file, with output unchanged:

| path | before | after |
|---|---|---|
| R `datparser::read_fixed_width` | 1.27 s | 0.42 s |
| `fixed_width_to_dta` (Python, Julia, TypeScript) | 1.24 s | 0.47 s |

Checked on all 21 NSFG female respondent and pregnancy files, 1973 to
2017-2019: the `.dta` bytes `fixed_width_to_dta` writes are identical
with `recodes` "setup", "tagged" and "none", and R's
`read_fixed_width` gives identical columns, values, attributes and
warnings in six ways of reading each file.

## Not done

- **Caching parsed values** to skip parsing them twice: about 500 MB
  for this file.
- **A decimal fast path**: building a float from digits and a power of
  ten can round differently from `str::parse`.
- **Skipping the type pass for `n_max = 0`**, or limiting it to the rows
  read: the storage type and warnings describe every kept record today.
- **Splitting the type pass by records** instead of columns: it needs a
  merge of each column's summaries and of invalid-field counts, for no
  gain on wide files.
