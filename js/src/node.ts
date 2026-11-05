// @jbearak/dta-parser/node: read .dta files from disk.

import * as fs from "node:fs";
import {
  DtaReader,
  ParquetReader,
  writeDtaTo,
  writeParquetTo,
  type Options,
  type ParquetOptions,
  type ParquetWriteOptions,
  type WriteDataset,
} from "@jbearak/dta-parser";

/**
 * Open a .dta file by path, or by a file descriptor the caller owns and
 * closes. Reads go through `fs.readSync` as they are needed, so the file
 * may be of any size, and an opened file can still be read after it is
 * unlinked.
 */
export function openDtaFile(file: string | number, options: Options = {}): DtaReader {
  const owned = typeof file === "string";
  const fd = owned ? fs.openSync(file, "r") : file;
  try {
    const length = fs.fstatSync(fd).size;
    const read = (into: Uint8Array, offset: number) => {
      let done = 0;
      while (done < into.length) {
        // Node rejects reads of 2 GiB or more, so take at most 1 GiB a time.
        const n = fs.readSync(fd, into, done, Math.min(into.length - done, 1 << 30), offset + done);
        if (n === 0) throw new RangeError("unexpected end of file");
        done += n;
      }
    };
    return new DtaReader(read, length, options, owned ? () => fs.closeSync(fd) : undefined);
  } catch (e) {
    if (owned) fs.closeSync(fd);
    throw e;
  }
}

/** Write a .dta file (release 118) to `path`, streaming it to disk. */
export function writeDtaFile(path: string, data: WriteDataset): void {
  const fd = fs.openSync(path, "w");
  try {
    writeDtaTo(data, (bytes) => {
      let done = 0;
      while (done < bytes.length) done += fs.writeSync(fd, bytes, done, bytes.length - done);
    });
  } catch (e) {
    fs.closeSync(fd);
    fs.rmSync(path, { force: true });
    throw e;
  }
  fs.closeSync(fd);
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
export function writeParquetFile(path: string, data: WriteDataset, options: ParquetWriteOptions = {}): void {
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
