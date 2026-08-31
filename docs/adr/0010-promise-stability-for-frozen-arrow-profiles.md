---
status: accepted
---

# Promise stability for frozen Arrow profiles

The dtatools Arrow format is a durable format, not a disposable cache: users
keep `.arrow` files long-term, so every frozen `dtatools:profile-version`
remains readable by all future package versions, indefinitely. Reader code for
a frozen profile is never removed once files with that version exist in the
wild. The reverse direction stays a hard error: a reader that encounters a
newer profile version, or malformed profile metadata it consumes, refuses with
a clear message rather than silently degrading a labeled dataset to plain
numerics. A projection consumes the dataset and selected field documents and
discards unselected field documents without parsing them; a full read consumes
every field document. An explicit escape hatch reads the raw storage arrays.

Because the promise makes each freeze irreversible, the prototype writes
profile version `"0"`, an experimental marker that carries no promise and that
released readers may reject. Version `"1"` is stamped only after the layout
decisions (raw Stata missing storage, per-buffer checksums, metadata
documents) survive the qualification and benchmark gate. Durability against
accidental corruption is part of the same decision: Arrow IPC has no native
checksums, so the profile records xxHash64 per buffer in the footer, verified
on read by default.

The considered alternative was a cache-only posture with no promise, where a
stranded file is regenerated from its source DTA. It was rejected because
`.arrow` files will also hold derived datasets with no DTA source of record.
