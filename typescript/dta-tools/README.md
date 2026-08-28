# @jbearak/dta-tools

TypeScript tools for reading Stata `.dta` files. The package ships JavaScript bundles for ESM and CommonJS callers. Use the portable entrypoint when you already have the file bytes, or the Node entrypoint for filesystem-backed random access.

The parser began inside [Sight](https://github.com/jbearak/sight). Sight, [manuscript-markdown](https://github.com/jbearak/manuscript-markdown), and [Table Viewer](https://github.com/jbearak/table-viewer) now use the standalone package.

## Installation

```sh
npm install @jbearak/dta-tools
```

Bun and pnpm can install the same package. The Node entrypoint requires Node.js 20 or newer.

## Choose an entrypoint

| Import | Use it when |
| --- | --- |
| `@jbearak/dta-tools/node` | The package should open a local file and read rows or columns on demand |
| `@jbearak/dta-tools` | The caller already has the complete file as an `ArrayBuffer` |

The `/node` suffix is an npm subpath export, not a directory in the installed package.

## Read a file in Node

```ts
import { DtaFile } from '@jbearak/dta-tools/node';

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
} from '@jbearak/dta-tools';

const response = await fetch('/datasets/auto.dta');
const buffer = await response.arrayBuffer();
const metadata = parse_metadata(buffer);
const rows = read_rows_from_buffer(buffer, metadata, 0, 25);

console.log(metadata.variables.map(variable => variable.name));
console.log(rows[0]);
```

Buffer helpers expect the complete file. Callers holding only contiguous observation bytes can use `read_rows_from_data_buffer()`.

## Data behavior

The parser covers Stata 5 through 19. Numeric values remain numbers and strings remain strings. Stata system and extended missing values remain distinct:

```ts
type MissingValue = {
    kind: 'missing';
    missing_type: '.' | '.a' | /* ... */ '.z';
};
```

Metadata includes variables, labels, display formats, notes, value-label tables, and section offsets. `DtaFile` resolves selected `strL` values and validates their object references.

Automatic text decoding uses Windows-1252 for pre-Unicode files and UTF-8 for Unicode files. Callers can override it with UTF-8, Windows-1252, or ISO-8859-1. See the repository's [compatibility contract](https://github.com/jbearak/dta-tools/blob/main/docs/compatibility.md) for exact releases and language differences.

## Main exports

The portable entrypoint includes `parse_metadata()`, `read_rows_from_buffer()`, display-format helpers, value-label parsing, `strL` helpers, missing-value helpers, and shared types. The Node entrypoint adds `DtaFile` and re-exports the portable interface.

TypeScript declarations ship with the package and provide the complete interface reference.

## Project links

- [Repository](https://github.com/jbearak/dta-tools)
- [Contributing](https://github.com/jbearak/dta-tools/blob/main/CONTRIBUTING.md)
- [Benchmarks](https://github.com/jbearak/dta-tools/tree/main/benchmarks)

## License

GPL-3.0. See [LICENSE](LICENSE).
