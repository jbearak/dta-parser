# Canonical compact-float evidence

These records describe two isolated public experiments and the final combined
qualification. The first experiment was rejected because routing entire spans
through the canonical writer slowed ordinary and prefix/suffix inputs. The
accepted correction changes the classifier only inside the existing exact
fallback. Its report retains measured costs and control movement.

The source commits are distinct:

- `213ceeee`: common isolated baseline.
- `452ac723`: rejected whole-span candidate.
- `19f57372`: accepted fallback-only candidate.
- `3eadb244`: final integration with the independently accepted polling,
  uniform-chunk locator and adaptive reciprocal changes.

No isolated timing is attributed to the integrated source. The original
34-case final acceptance panel is recorded separately, together with its own
baseline, controls and source bindings. The historical full installed suite
belongs to `452ac723`; the retained archive suite belongs to `3eadb244`.

`publication-source-map.json` maps each original artifact digest to its
published digest. `publication-manifest.json` checks the published files.
`omitted-artifacts.json` records private binary, archive, fixture or installed
children whose original bytes were checked but are not included in this text
bundle. Original whole-artifact digests remain unchanged. Public private-path
and direct identity fields are redacted, including their direct field digests.

Scripts under this evidence directory are historical snapshots. Redaction can
replace paths and literal patterns, and several scripts expect private build
directories. Restore those inputs before any replay; these snapshots are not
maintained runnable commands. The publisher preserves its own source unchanged
and checks this explicitly. Maintained controllers, current-source probes and
guard commands live in the parent benchmark directory and the repository CI.

The Rust command description and designated auxiliary source files are
explicitly post-run records. They are not presented as contemporaneous runtime
or compiler inventories. No new benchmark observations were collected while
assembling this publication.
