# Gate 1, round 3: plan 0024 revision 3

Judges as in round 1. Both returned **CHANGES**. Sonnet marked every
round 2 id resolved except one point of R2-5 (R3-1 below); Sol kept
R2-1, R2-2 and R2-5 open and raised two new findings.

## Findings and what revision 4 did

S = Sonnet's round 3 ids; O = Sol's.

| id | finding | answer in revision 4 |
|---|---|---|
| O R2-1 (blocker) | with the common dtype, a mixed-key `merge` raised `KeyError` on pandas 3.0.5, and `DataFrame.to_numpy()` stays `object` | the promises are cut: a mixed-key merge is not supported, and the docs say to give both keys one dtype first; a merge of two `DtaArray` keys is tested (letters, `.`, unmatched); `DataFrame.to_numpy()` stays `object`, and the docs say `to_numpy(dtype=float)` |
| O R3-1 (blocker), S R3-2 | promotion to a float64-backed `DtaDtype` rounds int64/uint64 above 2^53; the type list was loose | each type listed: bool → `byte`, int8/uint8 → `int`, int16/uint16 → `long`, int32/uint32/float64 → `double`, float32 → `float`; int64 and uint64 give `None` (pandas makes `object`), tested with `2**53` and `2**53 + 1` |
| O R2-2 | the text rule contradicted the row rules and pandas' `Int64` (`[False, <NA>]`) | text compares element by element under row rule 2: a missing row is `<NA>`; a number against text is false for `==`, true for `!=`; ordering raises `TypeError`; tested |
| O R2-5 (blocker) | timestamps and times with nulls hold zeros under the bitmap, which numpy reads as the epoch or midnight | zero copy only for timestamp and time columns with no null; with nulls, and for every DATE, the native side writes int64's minimum (`NaT`) for each null into a new buffer; DATE, TIMESTAMP, INT96 and TIME with nulls tested |
| O R3-2 | the write table dropped binary strLs from `save_dta` | `object` of `bytes` writes a binary strL in `.dta` (as `dta.rs` does for a polars `Binary` today); a binary strL round trip is tested |
| S R3-1 | pandas copies numpy arrays into a new frame by default, so "without a copy" would not hold | Series and frames are built with `copy=False`; `np.shares_memory` is tested on pandas 2.2 and the latest; the copied kinds are named in the docs and the benchmark |
| S R3-3 | INT64, unsigned and BOOLEAN without nulls not named | named in the no-missing row |
| S R3-4 | the native side must never read a handed-out buffer; offsets for windows | stated; tests on a `skip`/`n_max` window |
