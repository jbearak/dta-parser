# Narrowed read-driver setup diagnosis

The original full atomic matrix on exact `a2d8b6a` passed. The new narrowed
`atomic-read-repeat-v1` candidate process failed its first post-read rename gate
after `declared_character / any_na / 100000 rows / 8 columns`. The read recorded
zero profiled R allocation; the later rename failed the unchanged `< 1000000`
R-allocation bound. The failed run retains unchanged inputs and its original
source, log and receipt. Its first timing row is diagnostic evidence, not an
accepted paired repeat matrix.

The original full runner executes its selector phase before its read phase.
It explicitly warms each selector on a separate four-row fixture before
profiling. The narrowed driver omitted that phase, so its post-read rename
became its first rename. This difference is observed source behavior; its causal
role remains a hypothesis until the controlled comparison runs.

Root showed these ranked predictions before any new probe:

1. Cold rename setup dominates the first allocation profile. One unprofiled
   rename on a separate four-row fixture should remove the excess while leaving
   ownership, copy, scan and allocation gates intact.
2. New saved source-state records or retained diagnostic objects change source
   sharing. Removing only that save should remove the failure; independent
   rename warm-up should not.
3. General profiler or JIT warm-up from the omitted selector phase is required.
   A trivial profile warm-up should remove the failure while unprofiled rename
   alone should not.

`atomic-read-setup-probe-v1.R/.py` preserves the first-case fixture, setup writes,
read checks, ordinary profiling and saved source states. It omits bench timing
in both modes for an allocation-only probe. A cold run must reproduce the same
gate failure before the warm contrast is interpreted. The sole difference
between its fresh-process modes is one unprofiled rename on an independent
four-row fixture, before the measured source exists.

The probe saves all fork metrics before the unchanged selector gate and retains
source/result state observations. The unchanged profiler deletes its raw
Rprofmem file, so this probe retains aggregate allocation metrics rather than raw
allocation events. No namespace bodies or production code are changed.

Both source reviews cleared the probe before root ran its two fresh processes
in a coordinated quiet window. The cold run reproduced the exact gate failure
at 2,191,016 allocated R bytes, with an 82,104-byte largest allocation. The warm
run passed at 83,192 bytes, with a 40,112-byte largest allocation. All native
allocation/copy and validation-scan counters were zero in both runs. Their
receipts are `d40409404f4ae99facc2905f187288fe82b8723505178a0b78cf211ccbf4d61d`
and `79b928f65b9b0b3db1ec9ebd07937a5391ec99d70c176c82fe11204db4139b15`.
The cold receipt remains rejected; no failed record was relabeled.

This contrast supports restoring the original tiny-fixture rename warm-up.
It does not isolate one internal source of the setup allocation: the warm-up
also exercises fixture and rename dependencies. No further profiler is needed
to make this bounded driver correction.

The new `atomic-read-repeat-v2.R/.py` restores that warm-up before each measured
fixture. Its measured loop and all gates are unchanged. Both actual-diff reviews
are pending. New baseline/candidate repeat pairs remain required; the failed v1
records do not qualify v2 or establish a paired timing result.
