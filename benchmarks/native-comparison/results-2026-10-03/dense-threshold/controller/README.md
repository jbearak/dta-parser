# Dense missing guard for float-pair threshold dispatch

Private diagnostic only. No root worktree source is changed. This compares the clean e36e50c2 direct-float build with clean c21a79b3 threshold build and refuses different source receipts. Both original receipt variants remain unchanged. The controller binds the exact absolute Rscript/runtime, full build receipts, source/installed inventories and controller bytes before and after.

The matrix has one million rows, retained float spans of8191 for X and16385 for Y, ordinary typed-double controls, threads1, < and ==, three densities, and six rounds. There are144 measured observations. Each worker is a fresh R process for one build/round. Density order uses all six permutations; operation and build orders alternate; both representations occupy each position three times. Repeated public calls include output allocation and automatic GC. Calibration and all full-result validation are outside the recorded interval; retained intervals target300ms aggregate CPU.

- `random_half`: exactly500,000 tagged positions in each input, sampled independently with documented seeds29071 and60149. All27 ranks occur. The pair has a missing on roughly75% of rows; the exact count and rank hashes are recorded.
- `clustered_half`: the first500,000 positions of both inputs are tagged, then both are observed. Joint missing coverage is50%.
- `all_tags`: all one million positions of both inputs contain one of27 tags, including system missing. X cycles ascending ranks, Y descending ranks.

The different joint missing rates are intentional stress cases, not an isolated branch-prediction experiment. Finite values are exactly representable binary32 fractions, and the full logical oracle uses independent integer ranks plus ordinary observed comparisons. Input/rank/result/metadata hashes, every source representation state, and separate native eligibility must agree across builds and rounds. The screen does not cover temporal or arbitrary imported encodings; existing correctness tests cover those semantics separately.

Prepare only during a released setup window:

```
python3 <private-evidence>/density-screen/test-run.py
python3 -O <private-evidence>/density-screen/test-run.py
python3 <private-evidence>/density-screen/run.py \
  --repository <workspace> \
  --baseline <private-evidence>/float-direct-prototype \
  --candidate <private-evidence>/float-threshold-prototype \
  --qualify-only --output <private-evidence>/density-qualification-v1
```

After qualification and an exclusive timing release, run the same controller without --qualify-only, adding --qualification with that completed directory and a new --output directory. The controller requires identical qualification bindings and unchanged qualification artifacts. It reports every CPU/wall median, compact/typed ratio, baseline/candidate speedup and paired-round median speedup. Performance is report-only, so a measured regression is preserved for the explicit retain/reject decision rather than causing evidence to disappear.
