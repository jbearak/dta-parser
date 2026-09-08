# Expression write and memory evidence review

Clear within the two retained write matrices and eight isolated memory processes. All ten completed receipts, current bound inputs and complete products were independently checked. Exact baseline f622 and combined a2 source identities and unchanged writes-v2/memory commands agree.

The two write runs contain forty seven-sample series, 280 elapsed-millisecond samples and 13,600 state rows. Independently recomputed every median, checked complete mode/case/row/iteration coverage, and verified all warm-up/profile/timed before-and-after target and untouched-column backing transitions. Profiled target-copy counters match the recorded initial sharing/private state; full replacement retains a zero old-journal counter. All nineteen untouched columns retain their backing for each action. No paired same-mode write case meets the strict greater-than-10-percent AND greater-than-1-ms timing flag. Each action used a fresh pair as the bound driver requires.

The write samples retain elapsed milliseconds from bench::system_time conversion; primitive clock seconds and per-timed-call native counter deltas are not saved. Source review establishes that conversion and the per-call gates, while this review independently recalculates saved medians and profiled target-copy budgets. Successful bound execution retains value, metadata, capture and alias checks, but payload values themselves are not saved for independent reconstruction. Primitive Rprofmem traces were deleted; R and native aggregates overlap and must not be summed.

All eight memory logs retain successful fifty-call value/state checks and whole-process /usr/bin/time -l observations. The three CSV checkpoints per process are calls 0, 5 and 50; each has depth one and positive retained heap counts. Saved-RDS-only review independently verifies all 48 source/result states and 768 column records: correct types, bytes, owned/unexposed/shared status, unchanged source and retained result columns, and a new result x backing after calls. Whole-process peak RSS includes startup, fixture construction, GC, checks and operations. It is distinct from retained R heap after GC and cumulative allocation. Rounded R used-megabyte fields are retained as reported rather than treated as exact byte counts.

This review adds no workload execution or broad performance acceptance. The paired f622 Arrow flag and fifteen original ec10 owned-operation flags belong to the separately pending owned-evidence assessment and are not cleared by these expression results.

Exact run receipts, product/input counts, saved metrics and paired write calculations are in audit-expression-write-memory-01.json. Reviewer artifacts:

- audit-expression-write-memory-01.py: cf5a1efe951d7d7c8882afc0e8c10a0908e786dcbc703bcb9148a54666f19a87
- audit-expression-write-memory-01.json: a387c6e557e2e88562abda483432231e3dc538b0508cbb412fe6cc88cc6ded89
- check-expression-memory-states-01.R: 50a172d701a8ef64d708b862b4297257ef657361666215f361491867313a6e12
- check-expression-memory-states-01.log: 7d70910fb799c6f84f8e549e8d775568fc793ca0b09365db92054ff956f706a9
