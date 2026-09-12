# DTA read performance investigation

The target is the India 2021 women's file, 724,115 rows and 5,972 columns.
The preceding refresh measured fresh-process read_dta at 1.928 seconds and
read_arrow at 0.696 seconds. Its warm medians were 1.547 and 0.398 seconds.
The new four-tool baseline is ten fresh processes per tool with rotated order.

This is a performance investigation, not a correctness failure with an existing
latency bound. The feedback loop is the same-file before/after timing worker,
with exact DTA data-signature equality as the correctness gate. Keep the India
input intact because its width and storage mix are the question under study;
use checked small fixtures to qualify any eventual numeric-kernel changes.
A hard time threshold or minimizing to another dataset would change the task.

Ranked hypotheses, stated before experimental timings:

1. Repeated per-value output dispatch/checks matter. Predict a batch compact
   numeric fill with checks outside the value loop will reduce decode time.
2. Column sharding harms cache locality. Predict contiguous weighted shards
   will improve decode time versus the current least-loaded interleaving.
3. Block synchronization/load balance matters. Predict a buffer/thread sweep
   will change read-and-decode time more than allocation or finalization.

Both readers already use compact backing and automatic worker counts capped at
8. DTA's original row layout cannot become Arrow's column layout without doing
the conversion somewhere. DTA uses bounded 8 MiB staging buffers and overlaps
input reads with column workers. Arrow fills contiguous column arrays and
claims work from a shared queue. DTA currently dispatches each numeric value
through the column sink; Arrow chooses its compact output kind outside the loop.

India's schema has 5,518 byte, 367 int, 76 long, two double and nine string
columns. The byte columns alone account for 3,995,666,570 values.

Do not compile or time experiments while the four-tool baseline runs. Baseline
and experimental installations must remain separate. Prefix temporary probes
with [DEBUG-dta-read-perf], and remove them before a production patch. Record
all experiments, including failures to improve. Do not change output semantics,
missing-code validation, metadata, projection, interruption or memory bounds
just to obtain a faster number.
