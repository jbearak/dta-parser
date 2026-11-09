# Gate 1, round 3: plan 0025 revision 3

Judges as in round 1. **Sonnet approved revision 3**, with two nits.
Sol returned **CHANGES**: every earlier id resolved except part of
Sonnet's F2, plus one nit.

| id | finding | answer in revision 4 |
|---|---|---|
| Sol F2 (should) | `r/datakit/src/init.c`'s `link()` hard-codes `found != 3`; bumping only the listed places would leave datakit's tibble Parquet calls unlinked | `link()` is named among the places that change; it fetches the old and new callables under 4; a fresh-session tibble read and save without polars or nanoarrow is the smoke test |
| Sol N1 (nit) | Python's `read_dta` takes paths only | the error baseline covers Parquet from a path, bytes and a file object, and `.dta` from a path |
| Sonnet 1 (nit) | a LazyFrame falls to the default save method | it gets an error saying to `$collect()` first; tested |
| Sonnet 2 (nit) | the `PyUnicode*` calls in `lib.rs` are not part of the enum | stated: string conversion stays in the binding; the variants cover what the moved code raises |

Sonnet's approval covers revision 3; revision 4 answers Sol's findings
and both judges' nits, which Sol reviews alone, as in plans 0023 and
0024.
