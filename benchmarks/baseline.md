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
modern-all-types	file-io	6213	3	0.009931
modern-all-types	metadata	6213	3	0.010958
modern-all-types	slice-full-decode	6213	3	0.011083
modern-all-types	slice-projected-window	6213	3	0.004667
modern-all-types	bounded-file-projected-window	6213	3	0.020153
wide	file-io	86955	3	0.031681
wide	metadata	86955	3	0.014055
wide	slice-full-decode	86955	3	0.024986
wide	slice-projected-window	86955	3	0.013875
wide	bounded-file-projected-window	86955	3	0.056861
strl	file-io	2804	3	0.011236
strl	metadata	2804	3	0.001278
strl	slice-full-decode	2804	3	0.003667
strl	slice-projected-window	2804	3	0.001986
strl	bounded-file-projected-window	2804	3	0.006736
legacy	file-io	1729	3	0.010569
legacy	metadata	1729	3	0.001708
legacy	slice-full-decode	1729	3	0.003000
legacy	slice-projected-window	1729	3	0.001694
legacy	bounded-file-projected-window	1729	3	0.046361
```

## Raw TypeScript TSV

```text
case	phase	input_bytes	iterations	mean_ms
modern-all-types	file-io	6213	3	0.022375
modern-all-types	metadata	6213	3	0.036514
modern-all-types	buffer-full-decode	6213	3	0.067972
modern-all-types	node-file-projected-window	6213	3	0.066917
wide	file-io	86955	3	0.021528
wide	metadata	86955	3	0.067347
wide	buffer-full-decode	86955	3	0.237347
wide	node-file-projected-window	86955	3	0.007430
strl	file-io	2804	3	0.013055
strl	metadata	2804	3	0.006167
strl	buffer-full-decode	2804	3	0.002819
strl	node-file-projected-window	2804	3	0.082708
legacy	file-io	1729	3	0.013180
legacy	metadata	1729	3	0.011014
legacy	buffer-full-decode	1729	3	0.005306
legacy	node-file-projected-window	1729	3	0.003222
```

## Raw R TSV

```text
case	phase	input_bytes	iterations	mean_ms
modern_all_types	native-wrapper-allocation-population	6213	3	28.000000
modern_all_types	native-projected-wrapper	6213	3	1.333333
modern_all_types	haven-projected-reference	6213	3	5.333333
wide	native-wrapper-allocation-population	86955	3	1.000000
wide	native-projected-wrapper	86955	3	1.333333
wide	haven-projected-reference	86955	3	0.666667
strl	native-wrapper-allocation-population	2804	3	0.333333
strl	native-projected-wrapper	2804	3	0.333333
strl	haven-projected-reference	2804	3	0.333333
legacy	native-wrapper-allocation-population	1729	3	0.333333
legacy	native-projected-wrapper	1729	3	0.333333
legacy	haven-projected-reference	1729	3	0.333333
```

For comparison work, rerun at 100 or more iterations on an otherwise idle
machine and record the new environment and all three raw TSV reports.
