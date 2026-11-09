// hyparquet reads back what @jbearak/datakit writes (plan 0018, PR 7; datakit since plan 0021).
//
// datakit writes tables of every type it writes, with nulls,
// .a to .z, a categorical and time zones, in each codec, and with small
// row groups; hyparquet (with hyparquet-compressors for zstd, gzip and
// lz4_raw) reads each file, and every value is checked against the data
// written. Run from the repository root after building js/ and js/datakit/ and
// installing bench/node:
//
//     node compat/parquet/readback.mjs bench/node/node_modules
//
// What hyparquet gives, by its own documented rules: INT64 as bigint,
// DATE as a Date at UTC midnight, TIMESTAMP as a Date in milliseconds,
// BOOLEAN as true and false, a dictionary column as its values, null
// for a null. .a to .z, written as tagged NaNs, read as NaN.

import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const modules = process.argv[2]
if (!modules) throw new Error('usage: node compat/parquet/readback.mjs PATH/TO/node_modules')
const { parquetReadObjects, parquetMetadata } = await import(pathToFileURL(join(modules, 'hyparquet', 'src', 'node.js')).href)
const { compressors } = await import(pathToFileURL(join(modules, 'hyparquet-compressors', 'src', 'index.js')).href)
const version = (m) => createRequire(import.meta.url)(join(process.cwd(), modules, m, 'package.json')).version
const require = createRequire(import.meta.url)
const { writeParquet, MISSING } = require('../../js/datakit/dist/index.js')

const N = 3000
const rows = Array.from({ length: N }, (_, i) => i)
const letter = (i) => MISSING[`.${'abcdefghijklmnopqrstuvwxyz'[i % 26]}`]
const columns = [
  // name, variable, what hyparquet should give for row i
  ['b8', { type: 'byte', values: rows.map((i) => (i % 7 === 0 ? null : (i % 200) - 100)) }, (i) => (i % 7 === 0 ? null : (i % 200) - 100)],
  ['i16', { type: 'int', values: rows.map((i) => (i % 9 === 1 ? null : i * 7 - 9000)) }, (i) => (i % 9 === 1 ? null : i * 7 - 9000)],
  ['i32', { type: 'long', values: rows.map((i) => i * 100003 - 2 ** 30) }, (i) => i * 100003 - 2 ** 30],
  ['f32', { type: 'float', values: rows.map((i) => (i % 5 === 2 ? null : Math.fround(i / 3))) }, (i) => (i % 5 === 2 ? null : Math.fround(i / 3))],
  ['f64', { values: rows.map((i) => (i % 11 === 0 ? null : i % 13 === 0 ? NaN : i * 1.25 - 7)) }, (i) => (i % 11 === 0 ? null : i % 13 === 0 ? NaN : i * 1.25 - 7)],
  ['letters', { type: 'byte', values: rows.map((i) => (i % 4 === 1 ? letter(i) : i % 4 === 2 ? null : i % 100)) }, (i) => (i % 4 === 1 ? NaN : i % 4 === 2 ? null : i % 100)],
  ['n64', { type: 'int64', values: rows.map((i) => (i % 17 === 0 ? null : BigInt(i) * 3n ** 30n)) }, (i) => (i % 17 === 0 ? null : BigInt(i) * 3n ** 30n)],
  ['flag', { type: 'bool', values: rows.map((i) => (i % 3 === 0 ? null : i % 2)) }, (i) => (i % 3 === 0 ? null : i % 2 === 1)],
  ['day', { type: 'date', values: rows.map((i) => (i % 19 === 0 ? null : i * 9 - 9000)) }, (i) => (i % 19 === 0 ? null : new Date((i * 9 - 9000) * 86400000))],
  ['when', { type: 'timestamp', unit: 'us', timeZone: 'Europe/Paris', values: rows.map((i) => (i % 23 === 0 ? null : 1.7e15 + i * 1000)) }, (i) => (i % 23 === 0 ? null : new Date(1.7e12 + i))],
  ['local', { type: 'timestamp', unit: 'ms', values: rows.map((i) => -1e12 + i * 86400001) }, (i) => new Date(-1e12 + i * 86400001)],
  ['word', { values: rows.map((i) => (i % 29 === 0 ? null : ['alpha', 'béta', '', 'gamma'][i % 4])) }, (i) => (i % 29 === 0 ? null : ['alpha', 'béta', '', 'gamma'][i % 4])],
  ['uniq', { values: rows.map((i) => `value ${i} ${'x'.repeat(i % 40)}`) }, (i) => `value ${i} ${'x'.repeat(i % 40)}`],
  ['blob', { type: 'binary', values: rows.map((i) => (i % 31 === 0 ? null : Uint8Array.of(i & 255, 1, 2))) }, (i) => (i % 31 === 0 ? null : Uint8Array.of(i & 255, 1, 2))],
  ['cat', { type: 'categorical', levels: ['low', 'mid', 'high', 'unused'], ordered: true, values: rows.map((i) => (i % 37 === 0 ? null : i % 3)) }, (i) => (i % 37 === 0 ? null : ['low', 'mid', 'high'][i % 3])],
  // A categorical holding .a to .z (plan 0022): DOUBLE level numbers from 1,
  // the letters NaN; with missingLetters false, text with nulls.
  ['catletters', { type: 'categorical', levels: ['low', 'mid', 'high'], values: rows.map((i) => (i % 5 === 1 ? letter(i) : i % 5 === 2 ? null : i % 3)) }, (i) => (i % 5 === 1 ? NaN : i % 5 === 2 ? null : (i % 3) + 1)],
]
const data = {
  label: 'Readback',
  valueLabels: { lbl: new Map([[1, 'one']]) },
  variables: columns.map(([name, v]) => ({ name, ...v, ...(name === 'b8' ? { valueLabels: 'lbl', label: 'Small' } : {}) })),
}

const same = (a, b) => {
  if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime()
  if (a instanceof Uint8Array && b instanceof Uint8Array) return a.length === b.length && a.every((x, k) => x === b[k])
  return Object.is(a, b)
}

let checked = 0
const failures = []
for (const [label, options] of [
  ['snappy', {}],
  ['zstd', { compression: 'zstd' }],
  ['gzip', { compression: 'gzip' }],
  ['lz4_raw', { compression: 'lz4_raw' }],
  ['none', { compression: 'none' }],
  ['row groups of 700', { rowGroupSize: 700 }],
  ['missingLetters false', { missingLetters: false }],
]) {
  const bytes = writeParquet(data, options)
  const file = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length)
  const meta = parquetMetadata(file)
  assert.equal(Number(meta.num_rows), N)
  assert.ok(meta.key_value_metadata.some((kv) => kv.key === 'dta'), 'the dta profile')
  const got = await parquetReadObjects({ file, compressors, utf8: false })
  for (const [name, , want] of columns) {
    for (const i of rows) {
      let w = want(i)
      if (name === 'letters' && options.missingLetters === false && i % 4 === 1) w = null
      if (name === 'catletters' && options.missingLetters === false) w = i % 5 === 1 || i % 5 === 2 ? null : ['low', 'mid', 'high'][i % 3]
      let g = got[i][name]
      // hyparquet gives unannotated BYTE_ARRAY as bytes with utf8: false.
      if (typeof w === 'string' && g instanceof Uint8Array) g = new TextDecoder().decode(g)
      if (!same(g, w)) failures.push(`${label}: ${name} row ${i}: got ${String(g)}, want ${String(w)}`)
      checked++
    }
  }
}
console.log(`hyparquet ${version('hyparquet')} (hyparquet-compressors ${version('hyparquet-compressors')}): ${checked} values checked, ${failures.length} differ`)
for (const f of failures.slice(0, 20)) console.log('  ' + f)
if (failures.length) process.exit(1)
