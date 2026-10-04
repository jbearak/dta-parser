# Captured all-missing fact for long/float addition

The proposed admission stays inside the existing full-length LONG/FLOAT pair,
addition, binary64 destination route. If either captured native descriptor has
`missing_count == length`, every output is computational system NA. No count
summation is used: the other source is irrelevant even when it contains observed
infinities, imported high finite values, or overlapping missing positions.

This is a source fact, not a scan result inferred from a sample. In source 387227,
`arithmetic_pair_admitted` excludes foreign providers, recycled scalar operands,
and temporal inputs. The caller captures both operands before output allocation.
`arithmetic_capture` roots the exact native descriptors and installs a read claim
on ordinary compact backing before any intervening allocation. Retained storage
is derived from a private handle that owns the captured buffers. Supported
reentrant public writes detach, so their updates cannot invalidate these captured
counts or bytes. Cleanup retains the existing claim/unwind rules.

The float cache counts exact format-specific missing codes and every IEEE NaN;
the long cache counts the matching modern/legacy integer codes. Those values
always make this addition output missing. Modern observed infinities are not
counted, but do not weaken the proof when the other source is entirely missing.

The fill must write canonical `NA_REAL` into the fresh DOUBLE output, advance its
missing count exactly once per output, and poll interrupts at intervals of no
more than 16,384 output rows. It should not request source spans or call either
proof or exact source loader. The fill primitive can be reusable, but this
change must not add reciprocal/general admission without its own proof/tests.

## Red execution

`all-missing-red-v1` executed the actual result/preflight/producer headers from
387227 with counters inserted into private copies. It preserves 130 previous
cases and adds 32 one-/both-sided all-missing cases: both operand orders, modern
and legacy imports, plain backing, 8191/16385 retained geometry and 7/11 geometry.
The complete 162-case matrix and execution order are enforced. The imported
counterpart covers signed zero, subnormals, high finite imports, infinities,
NaNs and all 27 tags.

Result: zero semantic failures and 58 expected work failures. This includes 24
previous small alternating cases whose complete inputs happen to be missing.
The red records canonical output bits, exact missing counts and interrupt
cadence, while rejecting all source-span, proof and exact-loader work on the
all-missing cases. This is a structural result; it does not measure CPU or test
real R allocation/reentry. Public tests must separately cover cache clearing,
copy-on-write and checkpoint mutation/materialization after capture.
