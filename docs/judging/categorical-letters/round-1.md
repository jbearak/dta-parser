# Gate 1, round 1: plan 0022 revision 1

Judges: Claude Sonnet 5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra
(`gpt-6.1-terra`, reasoning effort high), each in a fresh session given
`brief.md`. Both returned **CHANGES**.

## Findings and what revision 2 did

S = Sonnet, T = Terra.

| id | finding | answer in revision 2 |
|---|---|---|
| S1, T1 (blockers) | the bad-value fallback (drop the categorical) depends on the rows read, so a window could change type, and the type reported at open could differ | the type is decided at open from the schema and profile; a bad value reads as `.` with one warning per column (per read call in R, Python, Julia; per reader in TypeScript); tests with a bad value in a later row group, windows before and over it, repeated reads |
| S2 | the core read path underspecified: `Output::Levels` and Arrow `Keys` need text | `levels` stays None for the DOUBLE form; bindings read it as a DOUBLE column with letters and map values with one core function, `level_index` |
| S3, T2 (blocker) | damaged or contradictory profile entries | a table: `logical` without a valid `categorical`, on a non-DOUBLE column, `categorical` without `logical`, with `storage`, with `value_labels`; each with its warning and type, tested; `profile_for` leaves `storage` and `value_labels` unset; `from_name`'s message |
| T2 | a synthesized set can collide with a set the file has | the column's name, reused if it maps 1 to k to the levels, else `name_2`, ...; tested through a write-back |
| S4 | Python accepts letters on an Enum only with a value label set; `Categorical` overclaimed | Python's read sets `meta.columns[x].value_labels` and the set; the writer row says `Enum` only; `letters="columns"` pairs the column |
| S5 | the `letters` hint for categoricals | stated: `Some(true)`, `Some(false)` writes nulls, `None` scans; bindings compute it |
| S6, T3 | `saveDta`: codes, storage, unused levels, the marker decision | as plan 0021 writes categoricals; the marker by the values written (letters: none); stale markers dropped; no letters-to-nulls option exists; a comparison with Python's `save_dta` |
| T4 | stripping `logical` does not test an old reader | the file is read with npm `@jbearak/dta-parser` 1.1.0, the published old parser |
| S7 | the date | 2026-11-08 |
| S8 | "Not in this plan" items covered elsewhere | cut |
| (own) | Julia's DtaColumn{Int32} | `DtaColumn{Float64}`, as a DOUBLE column with letters reads |
