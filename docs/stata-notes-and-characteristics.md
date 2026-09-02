# Stata notes and characteristics

Stata stores both notes and arbitrary characteristics as characteristic
records. A record has a target (`_dta` for the dataset or a variable name), a
key, and a string value. Keys named `note1` through `note9999` are notes;
`note0` is Stata's advisory count and is not a note. Other numeric `note*` keys
are reserved and are not exposed as arbitrary characteristics.

dtatools retains the note number rather than treating notes as an unnumbered
list. Gaps and empty text survive reads and writes. Notes are returned in
ascending number order. Arbitrary characteristics retain their source order,
scope, Unicode text, and empty values. If a malformed source repeats a key,
the last value wins without moving the key. Records for unknown variables are
ignored. Stata's `_lang_list` and `_lang_c` records control the active
metadata language, while `_lang_v_<language>` and `_lang_l_<language>` carry
alternate dataset/variable labels and value-label attachments. These records
are not user characteristics. The alias-variable keys `fralias_from` and
`fralias_varname` likewise describe Stata's alias structure rather than user
metadata. Authoring APIs reject every structural family, so a record cannot
be accepted on write and then disappear from the public model on read.

Raw characteristic names that are not valid Stata names are malformed input
and cause the read to fail. A DTA source value may contain at most 67,784 raw
bytes through its first optional NUL terminator; the terminator itself does not
consume the limit. Decoding a legacy single-byte value can expand that text to
at most 203,352 UTF-8 bytes. The metadata accessors and Arrow profile retain
that canonical decoded form. Newly authored values and DTA output remain bound
to the 67,784-byte target-format limit.

The DTA writer accepts note numbers 1 through 9,999. It rejects duplicate or
reserved keys, NUL characters, over-limit values, and characteristic names
that are not valid Stata names. It never truncates metadata. Modern releases
118 and 119 can be written; releases 105 through 115 and 117 through 119 can
be read.

## R

Use `dta_notes()` and `dta_characteristics()` to list metadata. Pass a
column name or one-based position as `variable` to select variable scope.

```r
survey <- set_dta_note(survey, 3, "Checked after import")
survey <- add_dta_note(survey, "Reviewed", variable = "age")
survey <- set_dta_characteristic(survey, "source", "baseline")

dta_notes(survey)                         # named by note number
dta_note(survey, 3)
dta_characteristics(survey)
dta_characteristic(survey, "source")
```

`set_dta_note()` and `set_dta_characteristic()` replace an existing value.
Passing `NULL` removes that key. `drop_dta_notes()` and
`drop_dta_characteristics()` remove selected keys or all keys.
`renumber_dta_notes()` closes gaps explicitly; reading, writing, and the
other setters do not renumber. Every mutation helper returns a changed copy,
unlike Stata commands that modify the current dataset.

Frames carrying notes or characteristics have an internal restoration class.
For both base data frames and tibbles, a data-frame-preserving `[` subset keeps
dataset metadata and the notes and characteristics of every retained variable.
A base subset that drops one column to a vector keeps that variable's metadata;
tibbles retain their normal non-dropping behavior. The preserved subset can be
passed directly to `save_dta()` or `save_arrow()` without losing metadata.

`_dta` is also a valid variable name, but DTA uses that same target spelling
for dataset metadata. Arrow can retain notes and characteristics on a variable
named `_dta`; a DTA write rejects that variable metadata instead of silently
changing its scope to the dataset.

## Rust

`DtaMetadata` and each `VariableInfo` expose `Vec<StataNote>` and
`Vec<StataCharacteristic>`. `StataNote` contains `number` and `text`;
`StataCharacteristic` contains `name` and `value`. The modern writer accepts
the corresponding `DtaWriteNote` and `DtaWriteCharacteristic` values at
dataset and column scope. Convert strings into `DtaWriteNote` for consecutive
numbering, or use `DtaWriteNote::numbered()` to preserve an explicit number;
an explicitly supplied zero is invalid rather than an auto-numbering marker.

## TypeScript

Parser-produced `DtaMetadata` and `VariableInfo` expose `notes` and
`characteristics` arrays. Caller-built objects remain source-compatible when
those fields are omitted, and legacy `notes: string[]` values are normalized
to consecutive numbered notes by the helpers. Parser results use the stricter
`ParsedDtaMetadata` and `ParsedVariableInfo` types, whose arrays are always
present.
The portable entrypoint exports list, get, set, add, drop, and renumber helpers.
These helpers mutate the supplied metadata target and return copies from list
operations. Dataset and variable metadata have the same shape, so callers pass
either `metadata` or one selected `metadata.variables` entry. A missing
variable lookup is handled by the caller before invoking a helper.
The Node `DtaFile.metadata` getter exposes the dataset target, and the Node
entrypoint re-exports the same helpers as the portable entrypoint. File reads
use a private snapshot of row geometry, so mutating exported offsets, counts,
or variable descriptors does not alter subsequent buffered reads.

```ts
const metadata = parse_metadata(buffer);
setStataNote(metadata, 3, 'Checked after import');
setStataCharacteristic(metadata, 'source', 'baseline');
```

## Arrow profile 0

The experimental Arrow profile records the same arrays in the
`dtatools:dataset` schema document and each `dtatools:field` document. Older
profile-0 files whose `notes` value is a string array remain readable; their
notes receive consecutive numbers beginning at 1. New files use numbered note
objects. Empty arrays are omitted, and an omitted array has the same behavior
as an empty one.

```json
{
  "version": 0,
  "label": "Survey",
  "notes": [{"number": 3, "text": "Checked"}],
  "characteristics": [{"name": "source", "value": "baseline"}],
  "value_labels": {}
}
```

A field document uses the same `notes` and `characteristics` members alongside
its variable label, format, storage, value-label, missing-value, and R-semantics
members. Notes must have unique ascending numbers from 1 through 9,999.
Characteristic names must be unique, valid Stata names, and not numeric
`note*` keys or structural language/alias keys. A full read validates the
dataset document and every field document. A predicate-free projection
validates the dataset document and the selected fields' documents, then
discards unselected fields' private documents without parsing them. A profiled
tidyselect predicate first reads a full profile summary, and `datasig = TRUE`
with profile handling enabled parses the full schema, so both validate every
field document even when the returned data are projected. Malformed metadata
that the read consumes is a hard error unless profile handling is explicitly
disabled.
