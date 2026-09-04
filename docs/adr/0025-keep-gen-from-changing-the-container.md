---
status: accepted
---

> ADR [0026](0026-reserve-physical-columns-and-rebind-on-reallocation.md) supersedes the guarantee that every binding sees structural changes when preparation or reallocation is needed.

# Keep `gen()` from changing the container it was handed

`gen()` and the other by-reference operations no longer turn a tibble into a dibble. Every container still acquires reference state at its first `gen()` — that is what lets the write land in the dataset so every binding sees it — but reference state is not dibble-ness. A tibble stays a tibble and a data frame a data frame, with their existing columns untouched, R's own copy-on-modify semantics for `$<-` and the other replacement operators, and `is_dibble()` reporting `FALSE`. Only the column `gen()` writes takes Stata storage, as it always did on a data frame. `dibble()`, `as_dibble()`, and the readers are the only ways to get a dibble. Dibble-ness is now recorded explicitly in the reference state rather than inferred from "reference state plus `tbl_df`", which is what made the conversion unavoidable.

ADR 0021 had a tibble become a dibble at its first `gen()` and its existing columns typed at that moment. The conversion was not a class change alone: it rewrote every existing numeric and string column in place, so every alias of the tibble saw column classes it never asked for, and one `gen()` call moved the table into a container with different rules for `$<-`, `[<-`, and `[i, j := v]`. It also changed answers. On a tibble, typing `x` first turned `x * 2` into Stata arithmetic and `gen(tbl, y = x * 2)` produced a `double`; the same call on a data frame produced Stata's `generate` default, `float`. A single `gen()` was doing more than the user asked for and more than they could see.

The alternative was to keep the conversion and document it, which leaves an aggressive and invisible change of container in the most common mutation call, or to have `gen()` on a tibble return a copy, which gives up the by-reference semantics that are the point of the verb. Neither is better than making the two properties independent.

The cost is accepted: expressions `gen()` evaluates on a tibble see the tibble's own columns, so `gen(tbl, n = .N, by = g)` on a bare character `g` groups `NA` and `""` as two groups where a dibble makes them one Stata string value and one group. That is precisely how a base data frame behaves, and it is the right answer — Stata's collation applies where a Stata dataset is. `as_dibble()` is the one call that asks for one.
