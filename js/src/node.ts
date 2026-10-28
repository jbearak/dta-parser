// @jbearak/dta-parser/node: read .dta files from disk.

import * as fs from "node:fs";
import { DtaReader, writeDtaTo, type Options, type WriteDataset } from "@jbearak/dta-parser";

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
        const n = fs.readSync(fd, into, done, into.length - done, offset + done);
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
