# Baseline report

Correctness status before collection: TypeScript canonical conformance,
Rust slice/file conformance, deterministic fuzz smoke, and root/R source and
archive identity all passed. These three-iteration smoke measurements validate
the benchmark paths; they are not statistically meaningful performance claims
and are never CI thresholds.

- Date: 2026-07-25
- Host: Darwin 25.5.0, arm64 (CPU model unavailable in the sandbox)
- Bun: 1.3.14
- Rust: rustc 1.97.1, release profile
- R: 4.6.1; current source installed through its locked offline Cargo archive;
  haven available
- Commands: `DTA_BENCH_ITERATIONS=3 cargo run --release -p dta-parser --example bench`
  and `DTA_BENCH_ITERATIONS=3 bun benchmarks/typescript.ts`, plus
  `Rscript benchmarks/r-benchmark.R 3` with the temporary current-source
  package library in `R_LIBS`

## Raw Rust TSV

```text
case	phase	input_bytes	iterations	mean_ms
modern-all-types	file-io	6213	3	0.012597
modern-all-types	metadata	6213	3	0.010972
modern-all-types	slice-full-decode	6213	3	0.011306
modern-all-types	slice-projected-window	6213	3	0.004889
modern-all-types	bounded-file-projected-window	6213	3	0.172139
wide	file-io	86955	3	0.016250
wide	metadata	86955	3	0.014472
wide	slice-full-decode	86955	3	0.025083
wide	slice-projected-window	86955	3	0.014972
wide	bounded-file-projected-window	86955	3	0.415611
strl	file-io	2804	3	0.011181
strl	metadata	2804	3	0.001361
strl	slice-full-decode	2804	3	0.003167
strl	slice-projected-window	2804	3	0.002111
strl	bounded-file-projected-window	2804	3	0.060194
legacy	file-io	1729	3	0.011000
legacy	metadata	1729	3	0.001514
legacy	slice-full-decode	1729	3	0.002153
legacy	slice-projected-window	1729	3	0.002042
legacy	bounded-file-projected-window	1729	3	0.079014
```

## Raw TypeScript TSV

```text
case	phase	input_bytes	iterations	mean_ms
modern-all-types	file-io	6213	3	0.019208
modern-all-types	metadata	6213	3	0.036389
modern-all-types	buffer-full-decode	6213	3	0.065167
modern-all-types	node-file-projected-window	6213	3	0.065347
wide	file-io	86955	3	0.020347
wide	metadata	86955	3	0.069750
wide	buffer-full-decode	86955	3	0.236986
wide	node-file-projected-window	86955	3	0.007583
strl	file-io	2804	3	0.012778
strl	metadata	2804	3	0.007833
strl	buffer-full-decode	2804	3	0.003222
strl	node-file-projected-window	2804	3	0.079264
legacy	file-io	1729	3	0.011694
legacy	metadata	1729	3	0.011750
legacy	buffer-full-decode	1729	3	0.005250
legacy	node-file-projected-window	1729	3	0.003305
```

## Raw R TSV

```text
case	phase	input_bytes	iterations	mean_ms
modern_all_types	native-wrapper-allocation-population	6213	3	0.333333
modern_all_types	native-projected-two-columns	6213	3	1.333333
modern_all_types	haven-projected-two-columns	6213	3	6.333333
wide	native-wrapper-allocation-population	86955	3	1.000000
wide	native-projected-two-columns	86955	3	1.000000
wide	haven-projected-two-columns	86955	3	1.333333
strl	native-wrapper-allocation-population	2804	3	0.333333
strl	native-projected-two-columns	2804	3	0.333333
strl	haven-projected-two-columns	2804	3	0.666667
legacy	native-wrapper-allocation-population	1729	3	0.333333
legacy	native-projected-two-columns	1729	3	0.333333
legacy	haven-projected-two-columns	1729	3	1.000000
```

For comparison work, rerun at 100 or more iterations on an otherwise idle
machine and record the new environment and all three raw TSV reports.
