// @jbearak/datakit/node: the datakit functions that take paths (plan
// 0021). Parquet goes through this package's module, shared with the main
// entry; .dta through @jbearak/dta-parser, loaded on the first call that
// needs it, so a script that only reads and writes Parquet never compiles
// the .dta module.

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  ParquetReader,
  _internal,
  readDataset,
  writeParquetTo,
  type Characteristic,
  type Dataset,
  type ParquetInfo,
  type ParquetOptions,
  type ParquetVariable,
  type ParquetWriteOptions,
  type ReadDataset,
  type ReadDatasetOptions,
  type FixedWidthOptions,
  type ValueLabels,
} from "@jbearak/datakit";
import { toDta, type SaveDtaOptions } from "./save-dta";
import { warn } from "./dataset";
import { dtaError } from "./_shared/errors";

export type { SaveDtaOptions };

type DtaNode = typeof import("@jbearak/dta-parser/node");
let dtaNode: DtaNode | undefined;
/** dta-parser's Node entry, loaded on first use. */
function dta(): DtaNode {
  return (dtaNode ??= require("@jbearak/dta-parser/node") as DtaNode);
}


/** Reads of fewer bytes than this go through a block read ahead. */
const SMALL = 256 * 1024;
const BLOCK = 1 << 20;

/**
 * Open a Parquet file by path, or by a file descriptor the caller owns
 * and closes (so the file read is the one the caller checked). Opening
 * reads only the footer; each read then reads, through `fs.readSync`,
 * only the pages it needs. Small reads (page headers, small column
 * chunks) are served from a 1 MiB block read ahead, so a file of
 * thousands of columns costs few system calls.
 */
export function openParquetFile(file: string | number, options: ParquetOptions = {}): ParquetReader {
  const owned = typeof file === "string";
  const fd = owned ? fs.openSync(file, "r") : file;
  try {
    const length = fs.fstatSync(fd).size;
    const direct = (into: Uint8Array, offset: number) => {
      let done = 0;
      while (done < into.length) {
        const n = fs.readSync(fd, into, done, Math.min(into.length - done, 1 << 30), offset + done);
        if (n === 0) throw new RangeError("unexpected end of file");
        done += n;
      }
    };
    let block = new Uint8Array(0);
    let blockAt = -1;
    const read = (into: Uint8Array, offset: number) => {
      const end = offset + into.length;
      if (into.length >= SMALL || end > length) return direct(into, offset);
      if (!(blockAt >= 0 && offset >= blockAt && end <= blockAt + block.length)) {
        block = new Uint8Array(Math.min(BLOCK, length - offset));
        direct(block, offset);
        blockAt = offset;
      }
      into.set(block.subarray(offset - blockAt, end - blockAt));
    };
    return new ParquetReader(read, length, options, owned ? () => fs.closeSync(fd) : undefined);
  } catch (e) {
    if (owned) fs.closeSync(fd);
    throw e;
  }
}

/** Write a Parquet file to `path`, streaming it to disk; see `writeParquetTo`. */
export function writeParquetFile(path: string, data: Dataset, options: ParquetWriteOptions = {}): void {
  const fd = fs.openSync(path, "w");
  try {
    writeParquetTo(
      data,
      (bytes) => {
        let done = 0;
        while (done < bytes.length) done += fs.writeSync(fd, bytes, done, bytes.length - done);
      },
      options,
    );
  } catch (e) {
    fs.closeSync(fd);
    fs.rmSync(path, { force: true });
    throw e;
  }
  fs.closeSync(fd);
}


/** Options for `readParquet`: the variables and rows, and how the file is read. */
export interface ReadParquetOptions extends ReadDatasetOptions {
  /** As `ParquetOptions.int64`; default `"auto"`. */
  int64?: ParquetOptions["int64"];
  /** As `ParquetOptions.nested`; default `"error"`. */
  nested?: ParquetOptions["nested"];
}

/**
 * Read a Parquet file, or the columns and rows asked for, into a
 * `ReadDataset`: columns, labels, `.a` to `.z`, notes and
 * characteristics. See docs/typescript.md, "Read a whole file".
 */
export function readParquet(file: string, options: ReadParquetOptions = {}): ReadDataset {
  const open: ParquetOptions = {};
  if (options.int64 !== undefined) open.int64 = options.int64;
  if (options.nested !== undefined) open.nested = options.nested;
  const reader = openParquetFile(file, open);
  try {
    return readDataset(reader, options);
  } finally {
    reader.close();
  }
}

/** What `readParquetInfo` returns: the footer's account of a Parquet file. */
export interface ParquetFileInfo {
  info: ParquetInfo;
  variables: ParquetVariable[];
  /** Every value label set in the dta profile, used or not. */
  valueLabels: Record<string, ValueLabels>;
  characteristics: Characteristic[];
}

/**
 * What a Parquet file's footer says, with no data read: `info` (rows,
 * row groups, notes, key-value metadata keys), `variables` (each with its
 * column chunks), every value label set and the characteristics.
 */
export function readParquetInfo(file: string): ParquetFileInfo {
  const reader = openParquetFile(file);
  try {
    // Chunks are read from the footer on first use, which must be before close().
    for (const v of reader.variables) void v.chunks;
    const valueLabels: Record<string, ValueLabels> = Object.fromEntries(reader.valueLabelNames().map((name) => [name, reader.valueLabels(name)!]));
    return { info: reader.info, variables: [...reader.variables], valueLabels, characteristics: reader.characteristics() };
  } finally {
    reader.close();
  }
}

/** Save a dataset as a Parquet file at `file`, keeping labels and `.a` to `.z`; as `writeParquetFile`. */
export function saveParquet(data: Dataset, file: string, options: ParquetWriteOptions = {}): void {
  writeParquetFile(file, data, options);
}

/** Options for `readDta`: the variables and rows, and the text encoding of files before release 118. */
export interface ReadDtaOptions extends ReadDatasetOptions {
  /** As dta-parser's `Options.encoding`: `"windows-1252"` (the default), `"latin1"` or `"utf-8"`. */
  encoding?: "windows-1252" | "latin1" | "utf-8";
}

/**
 * Read a Stata .dta file (releases 104 to 119) into a `ReadDataset`, with
 * plan 0020's factors as categoricals. See docs/typescript.md, "Read a
 * whole file".
 */
export function readDta(file: string, options: ReadDtaOptions = {}): ReadDataset {
  const reader = dta().openDtaFile(file, options.encoding ? { encoding: options.encoding } : {});
  try {
    return readDataset(reader, options);
  } finally {
    reader.close();
  }
}

/**
 * Save a dataset as a Stata .dta file (release 118) at `file`, converting
 * what .dta holds differently: dates to `%td`, timestamps to `%tc`, 64-bit
 * and unsigned integers to the smallest type that holds them,
 * categoricals to labelled codes with plan 0020's marker. See
 * docs/typescript.md, "Save a dataset".
 */
export function saveDta(data: Dataset, file: string, options: SaveDtaOptions = {}): void {
  dta().writeDtaFile(file, toDta(data, options));
}

/** Options for `readFixedWidth`. */
export interface ReadFixedWidthOptions extends FixedWidthOptions, ReadDatasetOptions {}

/**
 * Read a fixed-width text file through its SAS setup file (or files, read
 * in order as one setup) into a `ReadDataset`, keeping the setup's
 * labels and its missing-value recodes. Statements the reader does not
 * run, and the other warnings, go to `onWarning`, or are emitted as one
 * warning (code `DATAKIT_FIXED_WIDTH`). See docs/typescript.md,
 * "Fixed-width files with a SAS setup file".
 */
export function readFixedWidth(file: string, setup: string | readonly string[], options: ReadFixedWidthOptions = {}): ReadDataset {
  const { recodes, commented } = _internal.fixedWidthMode(options);
  const setups = _internal.setupBytes((typeof setup === "string" ? [setup] : setup).map((p) => fs.readFileSync(p)));
  const fd = fs.openSync(file, "r");
  let placed: ReturnType<typeof _internal.putBytes>;
  try {
    const size = fs.fstatSync(fd).size;
    // One allocation in a wasm32 module holds at most 2 GiB.
    if (size >= 2 ** 31) throw dtaError("DTA_TOO_LARGE", `${file} is ${size} bytes; datakit's module can take a data file of at most 2 GiB`);
    try {
      placed = _internal.putBytes(size, (view) => {
        let done = 0;
        while (done < size) {
          const n = fs.readSync(fd, view, done, Math.min(size - done, 1 << 30), done);
          if (n === 0) throw new RangeError(`${file}: unexpected end of file`);
          done += n;
        }
      });
    } catch (e) {
      if ((e as { code?: string }).code === "DTA_TOO_LARGE") {
        throw dtaError("DTA_TOO_LARGE", `${file} is ${size} bytes, more than datakit's module has room for`, e);
      }
      throw e;
    }
  } finally {
    fs.closeSync(fd);
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "datakit-"));
  try {
    const out = path.join(dir, "data.dta");
    const outFd = fs.openSync(out, "wx", 0o600);
    let warnings: string[];
    try {
      warnings = _internal.fixedWidth(setups, placed!, recodes, commented, (bytes) => {
        let done = 0;
        while (done < bytes.length) done += fs.writeSync(outFd, bytes, done, bytes.length - done);
      });
    } finally {
      fs.closeSync(outFd);
      _internal.freeBytes(placed!);
      // Wasm memory never shrinks: a new instance gives the pages back,
      // when no Parquet reader is open on this one.
      _internal.giveMemoryBack();
    }
    const reader = dta().openDtaFile(out);
    let data: ReadDataset;
    try {
      data = readDataset(reader, options);
    } finally {
      reader.close();
    }
    if (warnings.length) {
      warn(options.onWarning ? warnings : ["The setup file was read with warnings:", ...warnings], "DATAKIT_FIXED_WIDTH", options.onWarning);
    }
    return data;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
