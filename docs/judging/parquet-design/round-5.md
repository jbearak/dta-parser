# Gate 1, round 5: design review of plan 0018 (revision 5)

Same judges, fresh sessions.

**Terra: APPROVE.** Every round-4 finding resolved; yes for every
language and library; no new findings.

**Sonnet: CHANGES**, with every round-4 finding resolved and yes for
every library but pandas, on two new findings:

| id | finding | answer in revision 6 |
|---|---|---|
| H1 (should) | `write_parquet` drops a non-default index without a word | It warns once, naming the index and `reset_index()` |
| H2 (should) | All-midnight `datetime64` written as DATE reads back as `[s]`, and the type depends on the values | DATE only for a `%td` format; every other `datetime64` is TIMESTAMP in its own unit, as pandas writes it |
| H3 (nit) | Inferred levels marked ordered have an arbitrary order | Read as unordered |
| H4 (nit) | Stale sentence about dropping a reason from the ADR | Reworded: added to the ADR only if PR 7 measures a smaller module |
| H5 (nit) | Two unwrapped paragraphs | Re-wrapped |

Revision 6 changes only these lines. Sonnet's verdict on revision 6 is
in `round-6.md`.
