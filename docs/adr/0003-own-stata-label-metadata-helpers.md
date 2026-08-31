# Own Stata label-metadata helpers

The R package will own a small, exported label-metadata interface: variable- and value-label getters, replacement functions, and bulk setters compatible with the common `labelled` calls already used in dtatools documentation, plus the dtatools package's own dataset-label getter and replacement function. Depending on `labelled` would add avoidable materialization and metadata-loss behavior to compact Stata columns, while inventing unrelated variable- and value-label names would make migration harder. The implementations will therefore have no `labelled` runtime dependency, will preserve dtatools ALTREP storage and unrelated attributes, and will validate against Stata's metadata model rather than reproduce `labelled` behavior outside the tested call surface.

This compatibility boundary originally excluded tagged-missing creation and factor conversion. [ADR 0004](0004-own-stata-missing-and-factor-helpers.md) supersedes that exclusion. `labelled` interoperability is tested separately in CI, but the package neither suggests nor attaches it; documentation warns narrowly about its same-named helpers and attach-order masking.

[ADR 0014](0014-name-label-setters-for-dtatools-semantics.md) supersedes the
bulk-setter naming part of this decision.
