---
status: accepted
---

# Rename the project to dtatools

The project now reads and writes DTA files, owns Stata-aware data types and
metadata, and provides data operations beyond parsing. `dtaparser` therefore
describes only part of the package. Use `dtatools` for the R package,
and `dta-tools` for the Rust crate and repository. Keep
`@jbearak/dta-parser` for the TypeScript package because it remains a parser
and is already published under that name. Keep DTA terminology where it names
the file format or an actual parsing operation. The
[registry check](../research/dtatools-name-availability.md) found no current
collision for the new public names on 2026-08-28.

We rejected `dta` because it is ambiguous outside Stata, `dtautils` because it
understates the core reader and writer, `dtakit` because it is less literal,
and `stataio` because the package also owns in-memory Stata semantics and data
operations.
