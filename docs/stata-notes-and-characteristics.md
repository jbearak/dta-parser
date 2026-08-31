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
ignored. Stata's `_dta[_lang_list]` and `_dta[_lang_c]` records control the
active metadata language and are not user characteristics.

The DTA writer accepts note numbers 1 through 9,999. It rejects duplicate or
reserved keys, NUL characters, over-limit values, and characteristic names
that are not valid Stata names. It never truncates metadata. Modern releases
118 and 119 can be written; releases 105 through 115 and 117 through 119 can
be read.

## R

Use `stata_notes()` and `stata_characteristics()` to list metadata. Pass a
column name or one-based position as `variable` to select variable scope.

```r
survey <- set_stata_note(survey, 3, "Checked after import")
survey <- add_stata_note(survey, "Reviewed", variable = "age")
survey <- set_stata_characteristic(survey, "source", "baseline")

stata_notes(survey)                         # named by note number
stata_note(survey, 3)
stata_characteristics(survey)
stata_characteristic(survey, "source")
```

`set_stata_note()` and `set_stata_characteristic()` replace an existing value.
Passing `NULL` removes that key. `drop_stata_notes()` and
`drop_stata_characteristics()` remove selected keys or all keys.
`renumber_stata_notes()` closes gaps explicitly; reading, writing, and the
other setters do not renumber. Every mutation helper returns a changed copy,
unlike Stata commands that modify the current dataset.

## Rust

`DtaMetadata` and each `VariableInfo` expose `Vec<StataNote>` and
`Vec<StataCharacteristic>`. `StataNote` contains `number` and `text`;
`StataCharacteristic` contains `name` and `value`. The modern writer accepts
the corresponding `DtaWriteNote` and `DtaWriteCharacteristic` values at
dataset and column scope.

## TypeScript

`DtaMetadata` and `VariableInfo` expose `notes` and `characteristics` arrays.
The portable entrypoint exports list, get, set, add, drop, and renumber helpers.
These helpers mutate the supplied metadata target and return copies from list
operations. Dataset and variable metadata have the same shape, so callers pass
either `metadata` or one selected `metadata.variables` entry. A missing
variable lookup is handled by the caller before invoking a helper.

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
`note*` keys. Malformed profile metadata is a hard error unless profile
handling is explicitly disabled.
