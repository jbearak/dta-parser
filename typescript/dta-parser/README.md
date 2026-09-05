# @jbearak/dta-parser

A TypeScript reader for Stata `.dta` and Arrow IPC `.arrow` files. It ships JavaScript bundles for ESM and CommonJS callers. Use the portable entrypoint when you already have the file bytes, or the Node entrypoint for filesystem-backed random access.

The parser began inside [Sight](https://github.com/jbearak/sight). Sight, [manuscript-markdown](https://github.com/jbearak/manuscript-markdown), and [Table Viewer](https://github.com/jbearak/table-viewer) now use the standalone package.

## Installation

```sh
npm install @jbearak/dta-parser
```

Bun and pnpm can install the same package. The Node entrypoint requires Node.js 20 or newer.

## Choose an entrypoint

Section offsets now use `dta_data` and `dta_data_close`; the exported missing-value
constant is `DTA_MISSING_B`. These replace their previous `stata_` and `STATA_`
spellings.

| Import | Use it when |
| --- | --- |
| `@jbearak/dta-parser/node` | The package should open a local file and read rows or columns on demand |
| `@jbearak/dta-parser` | The caller already has the complete file as an `ArrayBuffer` |

The `/node` suffix is an npm subpath export, not a directory in the installed package.

## Read a file in Node

```ts
import { DtaFile } from '@jbearak/dta-parser/node';

const file = await DtaFile.open('data/auto.dta');

try {
    console.log(`${file.nobs} rows, ${file.nvar} columns`);
    console.log(file.variables.map(variable => variable.name));

    const rows = await file.read_rows(0, 25);
    console.log(rows[0]);
} finally {
    file.close();
}
```

`read_rows(start, count, col_start?, col_end?, options?)` uses zero-based indexes and an exclusive `col_end`. `read_columns(col_indices, options?)` returns a `Map` keyed by the requested column indexes. Both methods accept an `AbortSignal` for cooperative cancellation.

## Read an ArrayBuffer

```ts
import {
    parse_metadata,
    read_rows_from_buffer,
} from '@jbearak/dta-parser';

const response = await fetch('/datasets/auto.dta');
const buffer = await response.arrayBuffer();
const metadata = parse_metadata(buffer);
const rows = read_rows_from_buffer(buffer, metadata, 0, 25);

console.log(metadata.variables.map(variable => variable.name));
console.log(rows[0]);
```

Buffer helpers expect the complete file. Callers holding only contiguous observation bytes can use `read_rows_from_data_buffer()`.

## Data behavior

The following describes DTA reads. Arrow's additional value types are described
under [Read Arrow files](#read-arrow-files).

The parser covers Stata 5 through 19. Numeric values remain numbers and strings remain strings. Stata system and extended missing values remain distinct:

```ts
type MissingValue = {
    kind: 'missing';
    missing_type: '.' | '.a' | /* ... */ '.z';
};
```

Metadata includes variables, labels, display formats, numbered notes, arbitrary
characteristics, value-label tables, and section offsets. Dataset metadata and
each variable expose `notes: { number, text }[]` and
`characteristics: { name, value }[]`. Caller-built metadata may omit either
field, and legacy `notes: string[]` inputs are normalized to consecutive note
numbers when first passed to a metadata helper. Parser return types use the
stricter `ParsedDtaMetadata` and `ParsedVariableInfo` interfaces, whose arrays
are always present. List, get, set, add, drop, and renumber
helpers are exported from the portable entrypoint; mutation helpers change the
supplied metadata target. The Node entrypoint re-exports those helpers, and
`DtaFile.metadata` exposes editable dataset-scoped metadata. Its on-disk row
geometry is held separately, so editing exported counts, offsets, or variable
descriptors cannot redirect later file reads. `DtaFile` resolves selected
`strL` values and validates their object references. Numeric `note*` keys and
Stata's `_lang_list` and `_lang_c` language-control keys are reserved.

Automatic text decoding uses Windows-1252 for pre-Unicode files and UTF-8 for Unicode files. Callers can override it with UTF-8, Windows-1252, or ISO-8859-1. See the repository's [compatibility contract](https://github.com/jbearak/dta-parser/blob/main/docs/compatibility.md) for exact releases and language differences.

## Main exports

The portable entrypoint includes `parse_metadata()`, `read_rows_from_buffer()`, display-format helpers, value-label parsing, `strL` helpers, missing-value helpers, and shared types. The Node entrypoint adds `DtaFile` and re-exports the portable interface.

TypeScript declarations ship with the package and provide the complete interface reference.

## Read Arrow files

```ts
import { ArrowFile } from '@jbearak/dta-parser/node';

const file = await ArrowFile.open('survey.arrow');
try {
    const rows = await file.read_rows(0, 25);
    console.log(file.variables, rows);
    // Codes in dictionary columns index these levels, starting at zero.
    console.log(file.dictionaries);
} finally {
    file.close();
}
```

Use `ArrowBuffer.open(buffer)` from the portable entrypoint for synchronous
reads from complete `ArrayBuffer` or `Uint8Array` file bytes. Its `read_rows()`
and `read_columns()` methods return results directly. `ArrowFile` returns
promises and accepts `AbortSignal` through the final read-options argument.
Both readers support the same compressed and uncompressed files.

Both expose `nobs`, `nvar`, `variables`, `metadata`, `dictionaries`, and
`get_dictionary(columnIndex)`. Row and column indexes are zero-based.
`read_rows(start, count, col_start?, col_end?, options?)` uses an exclusive
column end; `read_columns(indices, options?)` returns a map of selected column
indexes to full columns, preserving requested order and removing duplicate
indexes. Reads past the last row return the remaining rows.

Arrow cells have a separate `ArrowCell` type. Integers stored at 64 bits use
`bigint`; other numeric values use `number`. Booleans, strings, `null`, and
Stata missing objects remain distinct. Dictionary cells hold zero-based codes;
their levels and orderedness are available through `get_dictionary()`.
Temporal values retain their stored ticks. Variables describe the physical
unit, epoch, and timezone, with `temporal_semantics` for recorded R temporal
units. Formatting is the caller's responsibility. Convert `bigint` explicitly
before ordinary JSON serialization.

Opening a Node file reads its footer and batch headers. Row windows skip other
batch bodies, and column projections read only selected buffers and their
dictionaries. Compressed buffers are decoded in full when selected. Reading
`metadata` or `variables` validates every profile field; an ordinary projected
read validates selected field documents. Returned metadata and dictionaries
are copies, so editing them does not change subsequent decoding.

Open options default to `{ profile: true, verify: true }`. `profile: false`
reads raw Arrow storage and disables profile checksums. `verify: false` skips
checksums while retaining profile semantics. `max_buffer_bytes` limits each
stored or decoded buffer to 256 MiB by default; raise it explicitly for larger
buffers. `max_output_rows` optionally limits each read's row count. Node read
options accept `chunk_rows`, which bounds decoded output between cancellation
checks; one compressed buffer decode remains synchronous.

See the repository's
[Arrow compatibility contract](https://github.com/jbearak/dta-parser/blob/main/docs/compatibility.md#arrow-read-compatibility)
for supported types, profile versions, validation, and compression coverage.
The readers do not write files. Zstandard decoding includes MIT-licensed code
derived from [fzstd](https://github.com/101arrowz/fzstd); its license is retained
in the distributed bundles.

## Project links

- [Repository](https://github.com/jbearak/dta-parser)
- [Contributing](https://github.com/jbearak/dta-parser/blob/main/CONTRIBUTING.md)
- [Benchmarks](https://github.com/jbearak/dta-parser/tree/main/benchmarks)

## License

GPL-3.0. See [LICENSE](LICENSE).
