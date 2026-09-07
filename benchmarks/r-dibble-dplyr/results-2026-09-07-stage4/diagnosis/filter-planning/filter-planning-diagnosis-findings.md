# Delegated filter diagnosis

This is a development decomposition on the exact installed package
`e343b3b56a8529e9ee0ac40f8bd88beebcd2be15`, DLL MD5
`18837c14dcd6597169dc0e3d99186dab`. It supplements the unchanged full paired
matrix; it does not replace that matrix or declare performance acceptance.

The full matrix flags the same three `filter_half` regressions against both
baseline runs at one million rows and eight columns. The predicate is
`seq_len(n()) %% 2L == 0L`, so it does not read any source column. The other twelve
flags concern element-based missingness, aggregation and coercion. They require
a separate acceptance decision.

The 21-case decomposition uses 21 iterations per case. Fixture construction,
ordinary value/type/attribute oracles, source preservation checks, allocation
profiling and CPU sampling run outside those timed iterations. Every case passes
its oracle, and installed source, DLL, helper bytes and source backings pass
before/after guards. Timings below are milliseconds.

| Boundary | Logical | Factor | Ordered factor |
| --- | ---: | ---: | ---: |
| Full dibble filter | 9.017 | 7.801 | 7.711 |
| Filter on owned-column tibble snapshot | 7.688 | 7.434 | 7.478 |
| Filter on ordinary-column tibble | 4.489 | 4.159 | 4.092 |
| vctrs slice of owned-column snapshot | 4.679 | 4.776 | 4.685 |
| vctrs slice of ordinary-column tibble | 1.410 | 1.371 | 1.368 |
| Existing validated batch gather | 1.602 | 1.606 | 1.644 |
| Close a precomputed sliced snapshot | 1.074 | 0.185 | 0.187 |

Both slice controls and the batch gather allocate 16,000,384 R bytes. The
logical close captures 16,000,000 payload bytes because its public ALTREP subset
returns a fresh ordinary logical vector. Factor and ordered-factor subsets
already carry owned backing and their closure records no payload capture.
All native target-copy and old-journal counters remain zero in these reads.

The three ranked predictions are supported. Slicing accounts for about 3.3 ms
of excess cost, while subtracting each slice from its filter gives similar
predicate/mask overhead for owned and ordinary columns. Result capture adds
about 1 ms for logical columns, with only about 0.19 ms of closure work for
factors. The current shared batch gather is within 0.28 ms of ordinary vctrs
slicing and adopts its output without the logical recapture.

Separate sampling identifies the current route as `filter.dtatools_ref_data`
through ordinary delegation, `dplyr_row_slice.data.frame`, `vctrs::vec_slice`,
`vec_slice_altrep` and base `.subset`. For the ordered snapshot-slice sample,
95.65% of self samples are in `.subset`. The package gather route avoids that
per-column fallback. R's retained `VectorSubset` source calls `makeSubscript`
before the ALTREP extraction hook, so an optimized hook cannot remove the
preceding normalization. Timing the boundaries does not isolate every native
instruction inside `.subset`; attribution to repeated subscript planning also
uses that source inspection and the earlier direct-kernel experiments.

Sampling requested 0.1 ms, but this R build clamps it to 1 ms. All nine warnings
and the actual intervals remain in the logs; the samples support call routing,
not the wall-time medians. Later `trace()` probes did not intercept vctrs' cached
closure. Absence of their trace lines is not evidence that fallback was skipped.
The first runner attempt also remains preserved. It incorrectly supplied
`result = TRUE` to `bench::mark()` with `check = FALSE`, causing the independent
result guard to fail before any measurement row was recorded. The successful
driver uses `check = TRUE`, as the unchanged full benchmark does.

The three filter flags are unresolved costs of the recorded compatibility
delegation. They are separate from the twelve remaining per-element costs.
Stage 6 already requires the shared expression evaluator to produce row plans
for this batch gatherer. The present measurements identify that existing route
as the appropriate fix, while preserving the Stage 5 helper-context proof and
Stage 6 predicate/grouping contracts. No temporary dispatch class, namespace
patch, weakened isolation check or early filter implementation was introduced.
These measurements do not certify a complete direct filter implementation and
do not erase the current regression. Root retains the performance acceptance
decision and the full staged completion obligation.
