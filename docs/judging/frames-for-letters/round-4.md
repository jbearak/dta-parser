# Gate 1, round 4: plan 0024 revision 4

Judges as in round 1. **Sonnet approved revision 4**, with two nits.
Sol returned **CHANGES**: every earlier id resolved, one new should and
one nit.

## Findings and what revision 5 did

| id | finding | answer in revision 5 |
|---|---|---|
| Sol R4-1 (should) | the writer checks omit alignment; `write.rs` reads through typed pointers, and a C-contiguous numpy array can be unaligned | Python passes `np.require(a, requirements=["C", "A"])`; the native side also checks the pointer's alignment for its type; both writers tested with an unaligned column |
| Sol R4-2 (nit) | `pd.Series([1, missing.a, None])` is `object` without calling `_get_common_dtype` | "Series of mixed values" cut; the docs build such a Series with `dtype="dta[double]"` |
| Sonnet N1 (nit) | a tz-aware timestamp built by `DatetimeTZDtype` or `tz_localize` copies; an int64 view `astype` to UTC shares | built from the int64 view, `astype` to UTC, then `tz_convert`; if that copies on a version, tz-aware timestamps are named among the copied kinds |
| Sonnet N2 (nit) | `copy=False` warns (`Pandas4Warning`) on pandas 3 | construction is version-gated, with `np.shares_memory` as the arbiter and no warning left to the user |

Sonnet's approval covers revision 4; revision 5 answers Sol's findings
and both judges' nits, which Sol reviewed alone, as in plan 0023's gate.
