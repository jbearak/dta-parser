# `@jbearak/dta-parser`

TypeScript parser for Stata `.dta` files.

This package was first written inside
[Sight](https://github.com/jbearak/sight), then extracted so the same parser
could be used by Sight and
[manuscript-markdown](https://github.com/jbearak/manuscript-markdown).
Sight uses it for its data browser in VS Code and forks that support VS Code
extensions, where users can open Stata datasets and inspect rows, columns,
formats, and value labels. `manuscript-markdown` uses it for embedded table
workflows, where manuscript or documentation sources can include tables backed
by external `.dta` files.

## Installation

```sh
npm install @jbearak/dta-parser
bun add @jbearak/dta-parser
pnpm add @jbearak/dta-parser
```

The root entrypoint works with bytes supplied by the caller. The
`@jbearak/dta-parser/node` entrypoint requires Node.js because it opens files
through filesystem APIs.

## Entrypoints

This package has two public entrypoints:

- `@jbearak/dta-parser`: portable parsing helpers for callers that already
  have file bytes, plus shared types, display formatting, value label parsing,
  `strL` helpers, and missing-value helpers.
- `@jbearak/dta-parser/node`: Node filesystem-backed `.dta` access through
  `DtaFile`, including metadata, row reads, column reads, value labels, and
  `strL` resolution.

The `/node` suffix is an npm package subpath export, like `pkg/server` or
`pkg/browser`. It does not refer to a directory on disk in your project, a
checkout, or a vendored copy.

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

Use the root entrypoint when you already have file bytes or data buffers and
want portable parsing utilities. Use `@jbearak/dta-parser/node` when you want
`DtaFile` to open a `.dta` file from disk and read rows or columns with
filesystem-backed random access.

| Entrypoint | Use For | Notable Exports |
| --- | --- | --- |
| `@jbearak/dta-parser` | You already have a full `.dta` `ArrayBuffer` or need low-level parser utilities. | `parse_metadata`, `read_rows_from_buffer`, `parse_value_labels`, `apply_display_format`, `is_missing_value_object` |
| `@jbearak/dta-parser/node` | You want to open a `.dta` file from disk and read rows or columns on demand. | `DtaFile`, `ReadRowsOptions`, `ReadColumnsOptions` |

## Node Quickstart

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
        price_variable && (
            typeof price_cell === 'number'
                || typeof price_cell === 'string'
        )
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
    const foreign_label_key =
        typeof foreign_cell === 'number'
            ? foreign_cell
            : foreign_cell && is_missing_value_object(foreign_cell)
                ? missing_type_to_label_key(foreign_cell.missing_type)
                : undefined;
    const foreign_label = foreign_label_key === undefined
        ? undefined
        : foreign_table?.get(foreign_label_key);

    const make_column = columns.get(0) ?? [];

    console.log({
        displayed_price,
        foreign_label,
        first_make: make_column[0],
    });
} finally {
    dta_file.close();
}
```

`read_rows(start, count, col_start?, col_end?, options?)` uses zero-based row
and column indexes. `col_end` is exclusive. `read_columns(col_indices,
options?)` returns a `Map<number, RowCell[]>` keyed by the requested column
indexes.

## Portable Buffer Quickstart

Use the root entrypoint when your code already has the file bytes and wants
parser functions directly.

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

`read_rows_from_buffer()` expects the full `.dta` file as an `ArrayBuffer`.
For callers that already hold only contiguous observation bytes, the root
entrypoint also exports `read_rows_from_data_buffer()`.

## Data Model

| Type | Shape |
| --- | --- |
| `DtaMetadata` | File-level metadata: `format_version`, `byte_order`, `nvar`, `nobs`, `dataset_label`, `variables`, `section_offsets`, and `obs_length`. |
| `VariableInfo` | Column metadata: `name`, `type`, `type_code`, `format`, `label`, `value_label_name`, `byte_width`, and `byte_offset`. |
| `Row` | A `RowCell[]` representing one observation. |
| `RowCell` | `number`, `string`, or `MissingValue`. |
| `MissingValue` | Object with `kind: 'missing'` and `missing_type` set to `.`, `.a`, through `.z`. |

Stata numeric missing values are preserved as tagged objects instead of being
collapsed to `null` or `NaN`. This keeps `.`, `.a`, `.b`, and the rest of the
Stata missing range distinguishable when rendering cells or resolving value
labels.

## Common Tasks

Read a page of rows:

```ts
const page_size = 100;
const page_index = 2;
const rows = await dta_file.read_rows(
    page_index * page_size,
    page_size
);
```

Read rows 0 through 99, but only include zero-based columns 3 through 7
(`col_end` is exclusive):

```ts
const row_start = 0;
const row_count = 100;
const col_start = 3;
const col_end = 8;

const rows = await dta_file.read_rows(
    row_start,
    row_count,
    col_start,
    col_end
);
```

Read selected zero-based columns 0, 4, and 7. The returned `Map` is keyed by
those same column indexes:

```ts
const requested_columns = [0, 4, 7];
const columns = await dta_file.read_columns(requested_columns);
const fourth_column = columns.get(4) ?? [];
```

Apply display formats:

```ts
import type { RowCell, VariableInfo } from '@jbearak/dta-parser';
import {
    apply_display_format,
    is_missing_value_object,
} from '@jbearak/dta-parser';

function render_cell(
    cell: RowCell,
    variable: VariableInfo
): string {
    if (is_missing_value_object(cell)) {
        return cell.missing_type;
    }

    return apply_display_format(cell, variable.format) ?? '';
}
```

Resolve value labels:

```ts
import type { RowCell, VariableInfo } from '@jbearak/dta-parser';
import {
    is_missing_value_object,
    missing_type_to_label_key,
} from '@jbearak/dta-parser';

function label_for_cell(
    cell: RowCell,
    variable: VariableInfo,
    tables: Map<string, Map<number, string>>
): string | undefined {
    const table = tables.get(variable.value_label_name);
    if (!table) return undefined;

    const key = typeof cell === 'number'
        ? cell
        : is_missing_value_object(cell)
            ? missing_type_to_label_key(cell.missing_type)
            : undefined;

    return key === undefined ? undefined : table.get(key);
}
```

Detect or render missing values:

```ts
import type { RowCell } from '@jbearak/dta-parser';
import { is_missing_value_object } from '@jbearak/dta-parser';

function describe_cell(cell: RowCell): string {
    if (is_missing_value_object(cell)) {
        // `.`, `.a`, ..., `.z` are preserved as distinct tags.
        return `missing (${cell.missing_type})`;
    }

    return typeof cell === 'number' ? `number ${cell}` : `text ${cell}`;
}
```

Cancel a long Node read:

```ts
const controller = new AbortController();

const rows = await dta_file.read_rows(
    0,
    dta_file.nobs,
    undefined,
    undefined,
    { signal: controller.signal, chunk_rows: 10000 }
);
```

`read_rows()` observes `AbortSignal` only when an options object with `signal`
is provided. `read_columns()` accepts the same cancellation options.

## Supported Files

Supported `.dta` format versions:

- `113` (Stata 8)
- `114` (Stata 10)
- `115` (Stata 12)
- `117` (Stata 13)
- `118` (Stata 14-19)
- `119` (Stata 15-19 for datasets with more than 32,767 variables)

Older `.dta` formats are rejected during metadata parsing. `DtaFile` resolves
`strL` values in supported files. If you are parsing from buffers instead of
using `DtaFile`, the root entrypoint exports helpers for working with the
`strL` long-string section. Stata's file-format documentation calls each
long-string record a Generic String Object (GSO); each such record starts with
the literal `GSO` marker. The `build_gso_index()` and `decode_gso_entry()`
names follow that file-format term.

## API Reference

Root entrypoint exports:

| Export | Purpose |
| --- | --- |
| `parse_metadata(buffer)` | Parse file metadata from a full `.dta` `ArrayBuffer`. |
| `parse_legacy_metadata(buffer, file_size)` | Parse metadata for legacy supported formats. |
| `legacy_metadata_buffer_size(nvar, format_version)` | Compute the metadata byte length for a supported legacy file. |
| `read_rows_from_buffer(buffer, metadata, start, count, col_start?, col_end?)` | Decode rows from a full `.dta` buffer. |
| `read_rows_from_data_buffer(buffer, metadata, start, count, col_start?, col_end?)` | Decode rows from a buffer containing only observation bytes. |
| `parse_value_labels(buffer, metadata, base_offset?)` | Parse value label tables into `Map<string, Map<number, string>>`. |
| `apply_display_format(value, format)` | Apply Stata display formats for supported numeric, string, date, and time formats. |
| `build_gso_index()`, `decode_gso_entry()`, `read_strl_pointer()`, `resolve_strl()` | Helpers for resolving `strL` values from GSO records in the long-string section. |
| `classify_missing_value()`, `is_missing_value()`, `is_missing_value_object()`, `make_missing_value()`, `missing_type_to_label_key()` | Missing-value helpers. |
| `DtaMetadata`, `VariableInfo`, `Row`, `RowCell`, `MissingValue`, `DtaType`, `FormatVersion` | Shared TypeScript types. |

Node entrypoint exports:

| Export | Purpose |
| --- | --- |
| `DtaFile.open(file_path)` | Open a `.dta` file and parse metadata and value labels. |
| `dta_file.nobs`, `dta_file.nvar`, `dta_file.variables`, `dta_file.dataset_label` | Metadata accessors. |
| `dta_file.value_label_tables` | Value label tables keyed by label table name. |
| `dta_file.read_rows(start, count, col_start?, col_end?, options?)` | Read rows from disk-backed observation data. |
| `dta_file.read_columns(col_indices, options?)` | Read selected zero-based columns into a keyed `Map`. |
| `dta_file.close()` | Close the file descriptor and clear cached sections. |
| `ReadRowsOptions`, `ReadColumnsOptions` | Option types for cancellation and chunk sizing. |
| Shared root types and helpers | The Node entrypoint re-exports shared types, display formatting, and missing-value helpers. |

## Development

```sh
npm install
npm run build
npm run typecheck
npm test
```
