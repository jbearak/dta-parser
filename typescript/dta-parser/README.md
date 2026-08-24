# @jbearak/dta-parser

A TypeScript parser for Stata `.dta` files. The package exposes portable
helpers for callers that already have file bytes and a Node entrypoint for
filesystem-backed random access.

This parser was first written inside
[Sight](https://github.com/jbearak/sight), then extracted so it could also be
used by [manuscript-markdown](https://github.com/jbearak/manuscript-markdown).
It is one of the libraries in the
[dta-parser multi-language repository](../../README.md); the repository also
contains an independent [Rust parser](../../r-package/dtaparser/src/dta-parser) and an
[R binding around that Rust parser](../../r-package/dtaparser).

## Installation

```sh
npm install @jbearak/dta-parser
bun add @jbearak/dta-parser
pnpm add @jbearak/dta-parser
```

Node.js 20 or newer is required.

## Entrypoints

The package has two public entrypoints:

- `@jbearak/dta-parser` provides portable parsing helpers for callers that
  already have `.dta` bytes, plus shared types, display formatting, value-label
  parsing, `strL` helpers, and missing-value helpers.
- `@jbearak/dta-parser/node` provides filesystem-backed access through
  `DtaFile`, including metadata, row reads, column reads, value labels, and
  `strL` resolution.

The `/node` suffix is an npm package subpath export, like `pkg/server` or
`pkg/browser`. It does not refer to a directory in an installed project.

```ts
import {
    apply_display_format,
    is_missing_value_object,
    missing_type_to_label_key,
    parse_metadata,
    read_rows_from_buffer,
} from '@jbearak/dta-parser';

import { DtaFile } from '@jbearak/dta-parser/node';
```

## Node quickstart

Use `@jbearak/dta-parser/node` when the package should open the file and keep
filesystem-backed random access available for row and column reads.

```ts
import {
    DtaFile,
    apply_display_format,
    is_missing_value_object,
    missing_type_to_label_key,
} from '@jbearak/dta-parser/node';

const dta_file = await DtaFile.open('data/auto.dta');

try {
    console.log(dta_file.dataset_label);
    console.log(`${dta_file.nobs} rows, ${dta_file.nvar} columns`);

    const rows = await dta_file.read_rows(0, 25);
    const columns = await dta_file.read_columns([0, 2, 5]);

    const price_index = dta_file.variables.findIndex(
        variable => variable.name === 'price'
    );
    const price_variable = dta_file.variables[price_index];
    const price_cell = rows[0]?.[price_index];
    const displayed_price =
        price_variable && typeof price_cell === 'number'
            ? apply_display_format(price_cell, price_variable.format)
            : price_cell && is_missing_value_object(price_cell)
                ? price_cell.missing_type
                : null;

    const foreign_index = dta_file.variables.findIndex(
        variable => variable.name === 'foreign'
    );
    const foreign_variable = dta_file.variables[foreign_index];
    const foreign_cell = rows[0]?.[foreign_index];
    const foreign_table = foreign_variable
        ? dta_file.value_label_tables.get(
            foreign_variable.value_label_name
        )
        : undefined;
    const foreign_key = typeof foreign_cell === 'number'
        ? foreign_cell
        : foreign_cell && is_missing_value_object(foreign_cell)
            ? missing_type_to_label_key(foreign_cell.missing_type)
            : undefined;

    console.log({
        displayed_price,
        foreign_label: foreign_key === undefined
            ? undefined
            : foreign_table?.get(foreign_key),
        first_make: columns.get(0)?.[0],
    });
} finally {
    dta_file.close();
}
```

`read_rows(start, count, col_start?, col_end?, options?)` uses zero-based row
and column indexes; `col_end` is exclusive. `read_columns(col_indices,
options?)` returns a `Map<number, RowCell[]>` keyed by the requested indexes.

## Portable buffer quickstart

Use the root entrypoint when the caller already has the entire file as an
`ArrayBuffer`.

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

`read_rows_from_buffer()` expects the full file. Callers that already hold
only contiguous observation bytes can use `read_rows_from_data_buffer()`.

## Text encoding

By default, the parser uses Windows-1252 for releases 105, 108, 110--111,
113--115, and 117, and UTF-8 for releases 118--119. Files through release 117
do not record a code page, so Windows-1252 is a pragmatic guess that commonly
recovers the intended text. Select UTF-8 explicitly for strict current-Stata
behavior:

```ts
const strict_file = await DtaFile.open(
    'data/legacy.dta',
    { encoding: 'utf-8' }
);

const metadata = parse_metadata(buffer, {
    encoding: 'windows-1252',
});
const rows = read_rows_from_buffer(buffer, metadata, 0, 25);
```

Supported values are `auto`, `utf-8`, `windows-1252`, and `iso-8859-1`.
The common `UTF8`, `CP1252`, and `latin1` aliases are also accepted
case-insensitively, with hyphens, underscores, and spaces ignored.
An explicit choice applies consistently to metadata, fixed strings,
value-label table names and values, dataset notes, and `strL` text.
`iso-8859-1` remains intentionally distinct from Windows-1252 at bytes
0x80--0x9f rather than following the Web Encoding Standard alias.

The resolved choice is available as `metadata.text_encoding` and
`dta_file.text_encoding`. Buffer helpers inherit it from the metadata object,
so callers select the encoding once when calling `parse_metadata()` or
`parse_legacy_metadata()`.

## Supported files and data model

The parser supports releases 105, 108, 110--111, 113--115, and 117--119,
covering Stata 5 onward for files using these format releases. Other formats are rejected.
It reads numeric and fixed-string values, `strL` long strings, labels,
display formats, value-label tables, and the missing values supported by each
release.

| Type | Shape |
| --- | --- |
| `DtaMetadata` | File metadata, dimensions, variables, section offsets, and observation width |
| `VariableInfo` | Name, type, storage code, format, label, value-label name, width, and offset |
| `Row` | A `RowCell[]` representing one observation |
| `RowCell` | `number`, `string`, or `MissingValue` |
| `MissingValue` | `{ kind: 'missing', missing_type: '.' \| '.a' \| ... \| '.z' }` |

Stata missing values remain tagged objects instead of becoming `null` or
`NaN`, so `.`, `.a`, and the remaining extended missing values stay distinct.

`DtaFile` and the buffer helpers apply strict Generic String Object (`strL`)
validation. Invalid or duplicate keys, unsupported types, truncated or
unterminated payloads, partial pointers, and dangling non-null references are
rejected.

## Common operations

Read a page or a column projection:

```ts
const page = await dta_file.read_rows(200, 100);
const selected_rows = await dta_file.read_rows(0, 100, 3, 8);
const selected_columns = await dta_file.read_columns([0, 4, 7]);
```

Cancel a long Node read:

```ts
const controller = new AbortController();
const rows = await dta_file.read_rows(
    0,
    dta_file.nobs,
    undefined,
    undefined,
    { signal: controller.signal, chunk_rows: 10_000 }
);
```

`read_columns()` accepts the same cancellation options. Cancellation is
cooperative and is enabled only when an options object supplies a signal.

## API reference

Root entrypoint exports:

| Export | Purpose |
| --- | --- |
| `parse_metadata(buffer, options?)` | Parse modern file metadata and select its text encoding |
| `parse_legacy_metadata(buffer, file_size, options?)` | Parse supported legacy metadata and select its text encoding |
| `read_rows_from_buffer()` | Decode rows from a full file buffer |
| `read_rows_from_data_buffer()` | Decode rows from observation bytes |
| `parse_value_labels()` | Parse value-label tables |
| `apply_display_format()` | Apply supported Stata display formats |
| `build_gso_index()`, `decode_gso_entry()`, `read_strl_pointer()`, `resolve_strl()` | Resolve `strL` values |
| Missing-value helpers | Classify, construct, inspect, and map Stata missing tags |
| Shared types | `DtaMetadata`, `VariableInfo`, `Row`, `RowCell`, `MissingValue`, `DtaType`, `FormatVersion`, and text-encoding option types |

Node entrypoint exports:

| Export | Purpose |
| --- | --- |
| `DtaFile.open(file_path, options?)` | Open a `.dta` file with an optional source encoding |
| `read_rows()` | Read a row window and optional contiguous column range |
| `read_columns()` | Read selected columns into a keyed `Map` |
| `close()` | Close the descriptor and clear cached sections |
| `DtaFileOpenOptions` | Source text-encoding option |
| `ReadRowsOptions`, `ReadColumnsOptions` | Cancellation and chunk-size options |
| Shared root exports | Types, formatting, and missing-value helpers |

## Development

From `typescript/dta-parser` in a repository checkout:

```sh
bun install --frozen-lockfile
bun run typecheck
bun run test
bun run build
bun run conformance
DTA_BENCH_ITERATIONS=100 bun run bench:ts
npm pack --dry-run
```

The package tests include its unit and data-browser smoke tests plus the
repository's TypeScript integration checks. Shared fixtures live at
[`../../tests/fixtures/dta`](../../tests/fixtures/dta), and the cross-language
contract is described in the [repository README](../../README.md).

## License

GPL-3.0. See [LICENSE](LICENSE).
