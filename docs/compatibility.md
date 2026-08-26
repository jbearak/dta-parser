# DTA compatibility

The TypeScript and Rust parsers are independent implementations. The R package uses the Rust parser and converts its result into R vectors and a tibble. All three interfaces are checked against the same fixtures and case inventory.

## Supported releases

| DTA format code | Stata versions |
| ---: | --- |
| 105 | Stata 5 |
| 108 | Stata 6 |
| 110 | Stata 7 |
| 111 | Stata 7/SE |
| 113 | Stata 8 through 9 |
| 114 | Stata 10 through 11 |
| 115 | Stata 12 |
| 117 | Stata 13 |
| 118 | Stata 14 through 19 |
| 119 | Stata 15 through 19 files with more than 32,767 variables |

Other format codes are rejected.

## Shared parsing contract

Both parsers retain:

- format release and byte order;
- dataset and variable metadata;
- numeric storage types and fixed strings;
- dataset notes and display formats;
- value-label tables in source order;
- `strL` long-string values;
- row windows and column projections;
- system and extended missing values when the format supports them.

Modern `strL` data, mapped sections, value-label tables, and legacy sequential layouts receive strict structural validation. Truncated sections, invalid offsets, duplicate or dangling long-string keys, and unsupported storage types produce errors instead of partial results.

## Text encoding

Automatic text decoding uses Windows-1252 for releases 105, 108, 110 through 111, 113 through 115, and 117. It uses UTF-8 for releases 118 and 119. Pre-Unicode DTA files do not record a code page, so the Windows-1252 choice is a practical default rather than information read from the file.

Every interface accepts explicit UTF-8, Windows-1252, and true ISO-8859-1 overrides. The override applies to metadata, fixed strings, long strings, and value-label names and text. ISO-8859-1 remains distinct from Windows-1252 at bytes `0x80` through `0x9f`.

## Missing values

Releases 105 through 111 encode one system-missing value per numeric storage type. Releases 113 and newer can encode system missing `.` plus the 26 extended codes `.a` through `.z`. The parsers preserve the exact code.

| Interface | Representation |
| --- | --- |
| TypeScript | `{ kind: "missing", missing_type: "." \| ".a" \| ... \| ".z" }` |
| Rust | Original numeric storage plus a parallel `MissingTag` classification |
| R | `NA_real_` for `.` and haven-compatible tagged-NA payloads for `.a` through `.z` |

R exposes Stata byte, int, and long columns as doubles because R integers have only one missing representation. Numeric ALTREP retains the compact source width until R requests a materialized double vector.

## Interface differences

| Behavior | TypeScript | Rust | R |
| --- | --- | --- | --- |
| Whole-file bytes | `ArrayBuffer` helpers | Byte-slice functions | Raw vector or resolved input source |
| Seekable file access | Node `DtaFile` | `DtaFile<Read + Seek>` | Internal path-based reader |
| Main result | Metadata plus rows or columns | Storage-preserving column model | Tibble |
| Dates and times | Original numeric value and format | Original numeric value and format | `%td` and `%d*` become `Date`; `%tc` and `%tC` become UTC `POSIXct` |
| Value labels | Tables keyed by numeric code | Ordered table entries | `haven_labelled` attributes |
| Cancellation | `AbortSignal` for Node reads | Cooperative callback | R user interrupts |

The TypeScript package has portable buffer and Node filesystem entrypoints. The Rust parser supports both full byte-slice decoding and bounded seekable reads. The R package accepts paths, raw bytes, binary connections, and URLs through `readr::datasource()` and uses temporary files for inputs that cannot be passed directly to the native path reader.

## R row-window behavior

`dtaparser::read_dta()` follows haven's useful `n_max` convention while rejecting ambiguous numeric coercions before opening the file.

| Input | dtaparser behavior | haven 2.5.5 behavior |
| --- | --- | --- |
| Fractional non-negative `n_max` | Error | Truncates |
| `NaN` `n_max` | Error | Reads all rows |
| Negative, missing, or infinite `skip` | Error | Native-coercion-dependent window |
| Fractional `skip` | Error | Native error |
| Non-scalar or non-numeric value | Error | Error |
| Whole `skip` through `2^53` | Deterministic row window | Platform-dependent native coercion at the extreme |
| Value greater than `2^53` | Error | Integer overflow or coercion behavior |

For `n_max`, `NA`, either infinity, and negative finite values mean all remaining rows. Non-negative `n_max` and `skip` values must be exactly representable whole numbers no larger than `2^53`.

## Conformance

[`conformance/cases.json`](../conformance/cases.json) records the shared cases. See [Contributing](../CONTRIBUTING.md#conformance) for the local and required-CI commands.
