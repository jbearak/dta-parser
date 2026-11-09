# Gate 1, round 4: plan 0022 revision 4

Judge: GPT-6.1 Terra (`gpt-6.1-terra`, reasoning effort high), in a
fresh session given `brief.md`, with the core already built in the
working tree. Sonnet had approved in round 3; revision 4 changed only
what answered Terra's round 3 findings. Terra returned **CHANGES**,
noting every earlier finding answered.

## Findings and what revision 5 did

| id | finding | answer in revision 5 |
|---|---|---|
| T1 | `saveDta` builds a categorical's set from its levels alone and reuses a set only if it is equal, so a label on a letter (`.r` "Refused") in the set the variable names is lost | the built set takes the letter entries of the variable's `valueLabels` set, and starts from that name (after `categorical.labelSet`), so the set read is written back under its own name with its letter labels; tested through a write and a read-back |
