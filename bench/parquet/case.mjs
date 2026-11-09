// One Parquet benchmark case in Node, in a fresh process; run_node.py
// runs it under /usr/bin/time -l, five times per case (plan 0018, "Speed
// and memory", TypeScript).
//
//   node bench/parquet/case.mjs LIB TASK FILE OUT COLS SKIP N
//
// LIB is ours (@jbearak/dta-parser), hyparquet (with
// hyparquet-compressors) or parquet-wasm (with apache-arrow to bring the
// table out of wasm memory as JavaScript columns), and for writes
// hyparquet-writer. TASK is one of
//   full    read the whole file into JavaScript columns
//   five    read five named columns (COLS, comma-separated)
//   window  read N rows from row SKIP (0-based)
//   pass    read the whole file, then one pass over every value
//   write   read FILE (a .dta) with our reader, untimed, into the
//           library's own in-memory table, then time writing it to a
//           Parquet file with the library's defaults
//   zstd    the same, with zstd (level 3 where the library has levels)
// Only the task is timed (wall, and CPU time of the whole process: user
// plus system, all threads); OUT gets a JSON report.

import { createRequire } from 'node:module'
import { readFileSync, writeFileSync, statSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'

const [lib, task, path, out, colsArg, skipArg, nArg] = process.argv.slice(2)
const cols = colsArg ? colsArg.split(',') : []
const skip = Number(skipArg)
const n = Number(nArg)
const here = dirname(new URL(import.meta.url).pathname)
const root = join(here, '..', '..')
const require = createRequire(join(root, 'bench', 'node', 'package.json'))
// Our package is loaded only where it is used: our reads, and the
// untimed .dta read every write case starts from, so the other
// libraries' reads do not carry its memory.
const writing = task === 'write' || task === 'zstd'
// Parquet is @jbearak/datakit's (plan 0021), .dta @jbearak/dta-parser's.
const oursNode = lib === 'ours' || writing ? { ...require(join(root, 'js', 'dist', 'node.js')), ...require(join(root, 'js', 'datakit', 'dist', 'node.js')) } : null
const version = (m) => JSON.parse(readFileSync(join(root, 'bench', 'node', 'node_modules', m, 'package.json'), 'utf8')).version

let hyparquet, compressors, writer, pw, arrow, libVersion
if (lib === 'ours') libVersion = require(join(root, 'js', 'datakit', 'package.json')).version
if (lib === 'hyparquet') {
  hyparquet = await import(require.resolve('hyparquet'))
  compressors = (await import(require.resolve('hyparquet-compressors'))).compressors
  libVersion = version('hyparquet')
}
if (lib === 'hyparquet-writer') {
  writer = await import(require.resolve('hyparquet-writer'))
  libVersion = version('hyparquet-writer')
}
if (lib === 'parquet-wasm') {
  pw = require('parquet-wasm/node')
  arrow = require('apache-arrow')
  libVersion = version('parquet-wasm')
}
const loaded = Date.now() / 1000

const cpu = () => {
  const u = process.cpuUsage()
  return (u.user + u.system) / 1e6
}

/** One pass over every value of JavaScript columns: numbers summed, strings measured. */
function passColumns(columns) {
  let sum = 0
  for (const c of columns) {
    if (ArrayBuffer.isView(c) && !(c instanceof DataView)) {
      for (let i = 0; i < c.length; i++) {
        const x = c[i]
        sum += typeof x === 'bigint' ? Number(x & 255n) : x === x ? x : 0
      }
      continue
    }
    for (let i = 0; i < c.length; i++) {
      const x = c[i]
      if (typeof x === 'number') sum += x === x ? x : 0
      else if (typeof x === 'string') sum += x.length
      else if (typeof x === 'bigint') sum += Number(x & 255n)
      else if (x instanceof Uint8Array) sum += x.length
      else if (x instanceof Date) sum += x.getTime() % 7
    }
  }
  return sum
}

/** Our columns as plain arrays of what a pass visits. */
function passOurs(columns) {
  let sum = 0
  for (const c of columns) {
    if (c.kind === 'number') {
      const v = c.values
      const m = c.missing
      for (let i = 0; i < v.length; i++) if (m[i] === 0) sum += v[i] === v[i] ? v[i] : 0
    } else if (c.kind === 'bigint') {
      for (let i = 0; i < c.values.length; i++) if (!c.missing[i]) sum += Number(c.values[i] & 255n)
    } else if (c.kind === 'dictionary') {
      for (let i = 0; i < c.codes.length; i++) if (!c.missing[i]) sum += c.values[c.codes[i]].length
    } else {
      for (let i = 0; i < c.values.length; i++) if (!c.missing[i]) sum += c.values[i].length
    }
  }
  return sum
}

// ---------------------------------------------------------------- reads

function readOurs() {
  const r = oursNode.openParquetFile(path)
  const all = r.variables.map((_, i) => i)
  let result
  if (task === 'five') result = r.readColumns(cols)
  else if (task === 'window') result = r.readColumns(all, { start: skip, count: n })
  else result = r.readColumns(all)
  const checksum = task === 'pass' ? passOurs(result) : result.length
  r.close()
  return { rows: result[0]?.kind === 'dictionary' ? result[0].codes.length : result[0]?.values.length, checksum }
}

async function readHyparquet() {
  // The whole file in memory for whole reads; a file buffer reading only
  // the slices needed for a few columns or a window (hyparquet's two Node
  // routes, each where it is the faster).
  let file
  if (task === 'full' || task === 'pass') {
    const b = readFileSync(path)
    file = b.byteOffset === 0 && b.byteLength === b.buffer.byteLength ? b.buffer : b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength)
  } else {
    file = await hyparquet.asyncBufferFromFile(path)
  }
  const metadata = await hyparquet.parquetMetadataAsync(file)
  const names = metadata.schema.slice(1).filter((e) => !e.num_children).map((e) => e.name)
  const columns = task === 'five' ? cols : names
  const rowStart = task === 'window' ? skip : 0
  const rowEnd = task === 'window' ? skip + n : Number(metadata.num_rows)
  // Columns assembled from the chunks hyparquet hands over (its columnar
  // route; rows as objects cost more).
  const out = new Map(columns.map((c) => [c, []]))
  await hyparquet.parquetRead({
    file,
    metadata,
    columns,
    rowStart,
    rowEnd,
    compressors,
    onChunk({ columnName, columnData, rowStart: s, rowEnd: e }) {
      const target = out.get(columnName)
      if (!target) return
      const from = Math.max(0, rowStart - s)
      const to = Math.min(columnData.length, rowEnd - s)
      for (let i = from; i < to; i++) target.push(columnData[i])
    },
  })
  const result = [...out.values()]
  const checksum = task === 'pass' ? passColumns(result) : result.length
  return { rows: result[0]?.length, checksum }
}

function readParquetWasm() {
  const bytes = readFileSync(path)
  const options = task === 'five' ? { columns: cols } : task === 'window' ? { offset: skip, limit: n } : {}
  const wasmTable = pw.readParquet(bytes, options)
  // Into JavaScript: an apache-arrow Table, then its columns.
  const table = arrow.tableFromIPC(wasmTable.intoIPCStream())
  const wanted = task === 'five' ? cols : table.schema.fields.map((f) => f.name)
  const columns = wanted.map((name) => table.getChild(name))
  let checksum = columns.length
  if (task === 'pass') checksum = passColumns(columns.map((v) => v.toArray()))
  return { rows: table.numRows, checksum }
}

// ---------------------------------------------------------------- writes

/** The .dta file as our columns, with its variables and labels (untimed). */
function dtaFrame() {
  const r = oursNode.openDtaFile(path)
  const columns = r.readColumns(r.variables.map((_, i) => i))
  const valueLabels = {}
  for (const v of r.variables) {
    const l = v.valueLabels && r.valueLabels(v.valueLabels)
    if (l) valueLabels[v.valueLabels] = l
  }
  const frame = { label: r.info.label, notes: r.notes(), valueLabels, variables: r.variables.map((v, k) => ({ ...v, values: columns[k] })) }
  r.close()
  return frame
}

/** A column as an array with null for every missing value (hyparquet-writer's input). */
function withNulls(c) {
  if (c.kind === 'string') return c.values
  const out = new Array(c.values.length)
  for (let i = 0; i < out.length; i++) out[i] = c.missing[i] ? null : c.values[i]
  return out
}

const INT = new Set(['byte', 'int', 'long'])

async function write(dest) {
  const frame = dtaFrame()
  const zstd = task === 'zstd'
  if (lib === 'ours') {
    const t0 = performance.now()
    const c0 = cpu()
    oursNode.writeParquetFile(dest, frame, zstd ? { compression: 'zstd', compressionLevel: 3 } : {})
    return { wall: (performance.now() - t0) / 1000, cpu: cpu() - c0 }
  }
  if (lib === 'hyparquet-writer') {
    if (zstd) throw new Error('hyparquet-writer writes zstd only with a compressor the caller supplies')
    const columnData = frame.variables.map((v) => ({
      name: v.name,
      data: withNulls(v.values),
      type: v.values.kind === 'string' ? 'STRING' : INT.has(v.type) ? 'INT32' : v.type === 'float' ? 'FLOAT' : 'DOUBLE',
    }))
    const t0 = performance.now()
    const c0 = cpu()
    writer.parquetWriteFile({ filename: dest, columnData })
    return { wall: (performance.now() - t0) / 1000, cpu: cpu() - c0 }
  }
  // parquet-wasm writes an Arrow table: the frame is an apache-arrow Table.
  const data = {}
  for (const v of frame.variables) {
    const c = v.values
    data[v.name] =
      c.kind === 'string'
        ? arrow.vectorFromArray(c.values, new arrow.Utf8())
        : arrow.vectorFromArray(withNulls(c), INT.has(v.type) ? new arrow.Int32() : v.type === 'float' ? new arrow.Float32() : new arrow.Float64())
  }
  const table = new arrow.Table(data)
  const t0 = performance.now()
  const c0 = cpu()
  const props = zstd ? new pw.WriterPropertiesBuilder().setCompression(pw.Compression.ZSTD).build() : undefined
  const bytes = pw.writeParquet(pw.Table.fromIPCStream(arrow.tableToIPC(table, 'stream')), props)
  writeFileSync(dest, bytes)
  return { wall: (performance.now() - t0) / 1000, cpu: cpu() - c0 }
}

// ---------------------------------------------------------------- run

let report
if (task === 'write' || task === 'zstd') {
  const dest = join(dirname(out), `node-write-${process.pid}.parquet`)
  try {
    const m = await write(dest)
    report = { ...m, bytes: statSync(dest).size }
  } finally {
    rmSync(dest, { force: true })
  }
} else {
  const t0 = performance.now()
  const c0 = cpu()
  const r = lib === 'ours' ? readOurs() : lib === 'hyparquet' ? await readHyparquet() : readParquetWasm()
  report = { wall: (performance.now() - t0) / 1000, cpu: cpu() - c0, ...r }
}
writeFileSync(out, JSON.stringify({ loaded, version: libVersion, threads: 1, node: process.version, ...report }))
