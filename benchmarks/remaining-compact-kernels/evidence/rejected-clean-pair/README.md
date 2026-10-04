# Rejected clean-pair screen

Candidate2 added a bounded scan for clean mixed-arithmetic blocks before production, alongside separate integer and dense FLOAT reciprocal experiments. The clean-pair scan added complexity without a clear incremental benefit in this quick screen, so the final combination restores candidate1's mixed-pair header. The reciprocal changes remained under evaluation.

| Sparse mixed operation | Candidate1 earlier quick ms | Candidate2 quick ms | Candidate1 six-round median ms |
| --- | ---: | ---: | ---: |
| INT/FLOAT addition | 0.416 | 0.418 | 0.403 |
| INT/FLOAT multiplication | 0.368 | 0.421 | 0.407 |

The two quick screens were separate single rounds, not a balanced paired experiment. Three headers changed together. Host drift, ordering and code generation can affect the measurements, so these numbers do not establish a causal regression or a reliable speed ratio. They support the narrower engineering decision to remove the extra scan when it offered no observed benefit worth its complexity.

Each CSV contains six cases and three representations using the same qualified public worker as candidate1. The quick summary's `gain_over_candidate1` compares the two single-round screens and has the same limitations. Candidate1's six-round summary remains the stronger preliminary comparison.

`build-bindings.json` retains candidate2's measured three header hashes and DLL identity from its build receipt. In particular, the rejected pair header hash identifies the experimental body, rather than the subsequently restored source. This record makes no final-source, final-performance or test-suite completion claim.
