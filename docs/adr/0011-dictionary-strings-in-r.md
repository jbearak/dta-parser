# String columns with few distinct values are read as a dictionary

Packed columns (ADR 0010) make reading fast, but the first full pass over
a column still made one R string per row, and R has no way to make
strings outside its global cache (`docs/research/r-string-cost.md`).
Survey data repeats a few values over millions of rows, so `read_dta`
now keeps such a column as its distinct values plus a 32-bit code per
row. R makes one string per distinct value; making the whole column is
a pointer copy per row. `tab`, `dta_group_id` and `is_missing` read the
codes directly and never touch a string per row.

The dictionary is built while reading, in the R bridge, not later when
the column is first used. Built later, it would not help operations that
reach values one row at a time through ALTREP (`==`, `is_missing`), and
the packed column would keep its full text in memory. A front cache of
recent values keeps the per-row cost within run-to-run noise.

A column gives the dictionary up, and is read as a plain packed column,
once more than half of at least 65,536 rows are distinct, or when the
dictionary would pass 2^31 − 1 entries, or when values collide in the
hash table more than a crafted file could make them by chance. The rule
is checked per new value, so it does not depend on how many rows a read
chunk holds. A column that starts distinct and repeats later may give
up early; it is then read as before, which is correct, only slower.

Considered and rejected:

- **Strategy 4 of the research note, an Arrow export:** avoids R
  strings entirely, but only for users who leave base R and the dibble;
  the workload this serves would gain nothing. Kept as a follow-up.
- **Sorting or hashing bytes in Rust for every column in dtatools'
  functions:** the most code; with dictionaries, the cheap form above
  covers the low-cardinality columns where it matters.
- **Factors:** a factor is not a character vector, so every caller
  would see a different type than `read_dta` documents.
