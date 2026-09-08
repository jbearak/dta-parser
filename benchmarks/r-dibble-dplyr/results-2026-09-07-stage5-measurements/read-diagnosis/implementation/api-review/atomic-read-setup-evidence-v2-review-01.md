# Atomic read setup probe and v2 preparation review

Clear for the bounded setup correction and future v2 preparation, not overall performance acceptance. Both probe receipts and all eight products per run match; each run binds 48,241 inputs. Independently checked all recorded current input identities and the 24 namespace DESCRIPTION paths, including the failed cold run whose runner deliberately does not mark namespace coverage accepted.

Cold reproduces the unchanged <1,000,000-byte post-read rename allocation gate: R total 2,191,016 bytes, largest 82,104. Independent four-row rename warming passes: total 83,192, largest 40,112. Native allocation/copy counters and validation scans are zero in both retained metric rows. Cold remains return 1/accepted false; warm remains return 0/accepted true. Values/metadata/backing checks before the gate completed; the warm run also completed final source preservation and exact-install validation.

Saved-RDS-only inspection independently checked eighty column states across three pre-phase snapshots and source/result fork states per run. Every column retains its backing, expected 800,000 bytes, depth one and unexposed shared status. Renamed results have new handles pointing to the same backings. The unchanged profiler deletes primitive Rprofmem events; this review verifies bound aggregates, not raw event reconstruction. No timing was measured by the probe.

Actual v2 R diff is exactly the added independent four-row rename call before each measured fixture, with its comment. The Python diff changes only the selected R filename and scope wording. Existing selected case grids, fixtures, oracles, profile/timing bodies, ownership/gate logic, raw outputs, input/runtime guards and receipt behavior remain unchanged. Raw v1 and probe source/evidence were not changed. Restoring omitted original warm-up is supported by the cold reproduction and warm contrast. This does not isolate rename itself from compilation or dependency setup it invokes; both modes share the explicit timing omission.

Exact v2 source hashes and both probe receipt identities are retained in audit-atomic-read-setup-probes-01.json. Reviewer artifacts:

- audit-atomic-read-setup-probes-01.py: 97629f12006e93fc75e79600acbdcbebbdeeeb2272615b430783c1b67386d17f
- audit-atomic-read-setup-probes-01.json: 63345ac0660524fa390298730aa0c6c16e30eaba7888125c436de84b72a2f643
- check-atomic-read-setup-states-01.R: 282a183ed4ab275c1c11ed0a4b084dabfcb37958902a952de62b2f8a4f3118af
- check-atomic-read-setup-states-01.log: 1a8ddd7d60e5530170522da1cba43550291eeefd86d948124eafcd5151630c2d
