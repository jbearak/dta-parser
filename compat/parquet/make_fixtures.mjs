// Write Parquet fixtures with hyparquet-writer, from data made here, into
// compat/parquet/fixtures/. Then run expected.py, which records what
// pyarrow reads from them.
//
// hyparquet-writer is not a dependency of this repository: install it in
// a scratch directory and pass its path, running from the repository
// root:
//
//     (cd SCRATCH && npm install hyparquet-writer)
//     node compat/parquet/make_fixtures.mjs SCRATCH/node_modules/hyparquet-writer
//
// The files cover hyparquet-writer's encodings (DELTA_BINARY_PACKED,
// DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY and BYTE_STREAM_SPLIT, chosen
// per column, and its own defaults), and types no other writer here
// gives: DECIMAL in a BYTE_ARRAY and ENUM; plus unsigned integers, JSON,
// UUID and millisecond timestamps, with nulls.

import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const dir = process.argv[2]
if (!dir) throw new Error('usage: node make_fixtures.mjs PATH/TO/node_modules/hyparquet-writer')
const { parquetWriteFile } = await import(pathToFileURL(join(dir, 'src', 'node.js')).href)
const { version } = (await import(pathToFileURL(join(dir, 'package.json')).href, { with: { type: 'json' } })).default

const OUT = join(import.meta.dirname, 'fixtures')
const N = 600
const rows = Array.from({ length: N }, (_, i) => i)
const masked = (f, every, offset = 3) => rows.map(i => (i % every === offset ? null : f(i)))

/** Columns: [name, schema element (without name), values, encoding]. */
function columns() {
  const opt = { repetition_type: 'OPTIONAL' }
  return [
    ['i32', { type: 'INT32', ...opt }, masked(i => ((i * 2654435761) % 2 ** 32) - 2 ** 31, 10), 'DELTA_BINARY_PACKED'],
    ['i64', { type: 'INT64', ...opt }, masked(i => BigInt(i) * 3000000000017n - 2n ** 62n, 11), 'DELTA_BINARY_PACKED'],
    ['u32', { type: 'INT32', converted_type: 'UINT_32', ...opt }, masked(i => (i * 7158271) % 2 ** 32, 12), undefined],
    ['f32', { type: 'FLOAT', ...opt }, masked(i => i * 0.25 - 50, 13), 'BYTE_STREAM_SPLIT'],
    ['f64', { type: 'DOUBLE', ...opt }, masked(i => i / 7, 14), 'BYTE_STREAM_SPLIT'],
    ['word', { type: 'BYTE_ARRAY', converted_type: 'UTF8', ...opt }, masked(i => `word ${i % 40} ü`, 15), 'DELTA_BYTE_ARRAY'],
    ['unique', { type: 'BYTE_ARRAY', converted_type: 'UTF8', ...opt }, masked(i => `row number ${i}`, 16), 'DELTA_LENGTH_BYTE_ARRAY'],
    ['plain_word', { type: 'BYTE_ARRAY', converted_type: 'UTF8', ...opt }, masked(i => `word ${i % 40}`, 17), undefined],
    ['kind', { type: 'BYTE_ARRAY', converted_type: 'ENUM', ...opt }, masked(i => ['low', 'mid', 'high'][i % 3], 18), undefined],
    ['doc', { type: 'BYTE_ARRAY', converted_type: 'JSON', ...opt }, masked(i => ({ row: i, even: i % 2 === 0 }), 19), undefined],
    ['uid', { type: 'FIXED_LEN_BYTE_ARRAY', type_length: 16, logical_type: { type: 'UUID' }, ...opt },
      masked(i => Uint8Array.from({ length: 16 }, (_, k) => (i + k) % 256), 20), undefined],
    ['dec', { type: 'BYTE_ARRAY', converted_type: 'DECIMAL', precision: 30, scale: 4, ...opt },
      masked(i => (BigInt(i) - 300n) * 123456789012345678901n + BigInt(i), 21), undefined],
    ['dec_small', { type: 'BYTE_ARRAY', converted_type: 'DECIMAL', precision: 9, scale: 2, ...opt },
      masked(i => BigInt(i * 1237 - 300000), 22), undefined],
    ['when', { type: 'INT64', converted_type: 'TIMESTAMP_MILLIS', ...opt }, masked(i => new Date(1577836800000 + i * 61001), 23), undefined],
  ]
}

function write(file, options, encodings) {
  const cols = columns()
  parquetWriteFile({
    filename: join(OUT, file),
    schema: [{ name: 'root', num_children: cols.length }, ...cols.map(([name, element]) => ({ name, ...element }))],
    columnData: cols.map(([name, , data, encoding]) => (encodings && encoding ? { name, data, encoding } : { name, data })),
    ...options,
  })
}

// The encodings chosen per column, in pages of about 1 KiB and row
// groups of 250 rows; and hyparquet-writer's own choices.
write('hyparquet_delta.parquet', { codec: 'UNCOMPRESSED', pageSize: 1024, rowGroupSize: 250 }, true)
write('hyparquet_default.parquet', {}, false)
console.log(`hyparquet-writer ${version}, node ${process.version}`)
