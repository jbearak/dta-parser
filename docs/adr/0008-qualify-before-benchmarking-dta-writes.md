---
status: accepted
---

# Qualify before benchmarking DTA writes

The writer receives a manual, hash-bound qualification against the established 1,823-file DHS, MICS, and NSFG performance corpus before its performance is compared with Stata. Qualification requires semantic read-write-read equality for all 1,821 inputs the current parser reads, plus matching dimensions when Stata 18 and haven open each output. The two existing source-read failures remain explicit SHA-256-bound exclusions. Generated files are deleted immediately, and retained results contain no private paths, labels, or values.

The write benchmark refuses a package build or corpus inventory that differs from the successful qualification manifest. It times dtaparser and Stata writes for all qualified inputs in fresh processes on the same filesystem, rotates writer order, and reports elapsed time, peak memory, and output size by corpus and source release. A separate synthetic wide-schema case covers release 119. Reports describe the inputs as a hash-bound local cache inventory, not as an upstream-authoritative corpus. Haven writes are reserved for the smaller repeated synthetic suite, where they add a useful third implementation without requiring another full private-corpus pass.
