---
status: accepted
---

# Sign datasets order-sensitively from Arrow profile checksums

`datasig()` exists so that a git-tracked table of signatures can verify that
raw source files (for example, downloaded public-use survey data) have not
been modified. The signature is an order-sensitive digest of a dataset's read
model — observation and variable counts, variable names and order, storage
types, labels, display formats, notes, and values in row order — built from
the Arrow profile's canonical per-batch column hashes, so a `.dta` file, a
`.arrow` file at any compression, and their loaded read models all sign
identically. Reimplementing Stata's `datasignature` algorithm for
compatibility was rejected: its signature is invariant to observation order
and to value order within a variable, so it misses swapped values, reordered
rows, and cross-column swaps — the very corruptions a signature should catch.

`datasig()` always recomputes from current content. The considered
alternative — caching a signature and detecting post-load modification to
skip recomputation — is unsound in R: copy-on-modify carries cached
attributes onto modified copies, and object-address checks cannot
distinguish a mutation from a copy. The readers' `datasig = TRUE` option is
therefore defined as a never-updated load-time record of the complete file's
disk signature, not a claim about the object's current content.

The two readers derive that record asymmetrically. `read_arrow()` assembles
the signature from the checksums already stored in the file footer, so it
costs milliseconds and works under projection — refusing projected reads was
rejected because the non-projected columns' hashes are in the footer even
when their data is never read. The footer-derived value restates what the
file declares about itself; `verify = TRUE` on a full read is what validates
those declarations against the stored bytes. DTA files store no hashes, so
`read_dta()` hashes the decoded columns instead and refuses `col_select`,
`skip`, and `n_max`: a partial read cannot testify to the full file.

The signature payload is versioned (currently `"1"`) but carries no
stability promise yet: it embeds the profile's JSON metadata documents and
the fixed 65,536-row batch size, so it is only as stable as the experimental
profile version `"0"`. The signature's stability promise is made together
with the profile freeze governed by ADR 0010; until then, recorded
signatures may need re-baselining across package versions.
