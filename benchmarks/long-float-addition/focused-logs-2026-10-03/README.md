# Historical focused log supplement

The original publication omitted five `focused.log` files referenced by its
completion records. This supplement adds those original files without changing
the existing evidence, manifests, source maps, observations or historical
publisher snapshot. No package tests or timings were rerun.

Each log contains fixed labels and numeric assertion/block counts only. Its
bytes are unchanged: the original completion record's log hash and the
supplement's published hash are identical. `supplement.json` also binds each
original and published completion, source commit and test source. These counts
retain their original historical scope; they do not qualify the current tree.

Run `python3 verify.py` from this directory to verify the five logs against the
unchanged original publication. The verifier also runs with `python3 -O`.
