// Fixed-width text through a SAS setup file (plan 0009's reader, in
// datakit's module; plan 0021).

import { dtaError } from "./_shared/errors";
import * as wasm from "./wasm";

/** Options for `convertFixedWidth` and `readFixedWidth`. */
export interface FixedWidthOptions {
  /**
   * The setup's missing-value recodes (`IF (X = 98 OR X = 99) THEN X =
   * .;`). `"setup"` (the default) applies them as written: a code recoded
   * to `.` is `.`, one recoded to `.A` is `.a`. `"tagged"` keeps why each
   * value is missing: per variable, the codes recoded to `.` become `.a`,
   * `.b`, ... in the order the setup names them, and their value labels
   * move to those letters. `"none"` ignores them.
   */
  recodes?: "setup" | "tagged" | "none";
  /**
   * Read a PROC FORMAT step or FORMAT statement that the setup puts alone
   * in a block comment as code, as CDC's setups from 2006-2010 on do.
   * True by default; false reads every comment as a comment.
   */
  commentedFormats?: boolean;
}

const encoder = new TextEncoder();

/** The options checked, as the module takes them. */
export function fixedWidthMode(options: FixedWidthOptions): { recodes: number; commented: boolean } {
  const recodes = options.recodes ?? "setup";
  if (!Object.hasOwn(wasm.RECODES, recodes)) {
    throw dtaError("DTA_INVALID", `recodes must be "setup", "tagged" or "none", not ${JSON.stringify(recodes)}`, undefined, TypeError);
  }
  const commented = options.commentedFormats ?? true;
  if (typeof commented !== "boolean") throw dtaError("DTA_INVALID", `commentedFormats must be true or false, not ${JSON.stringify(commented)}`, undefined, TypeError);
  return { recodes: wasm.RECODES[recodes as keyof typeof wasm.RECODES], commented };
}

/** The setup files as bytes. */
export function setupBytes(setups: readonly (string | Uint8Array)[]): Uint8Array[] {
  if (setups.length === 0) throw dtaError("DTA_INVALID", "no setup file was given", undefined, TypeError);
  return setups.map((s) => (typeof s === "string" ? encoder.encode(s) : s));
}

/**
 * Read fixed-width text as SAS setup files describe it, in memory, into
 * the bytes of a .dta file (release 118), for `openDta`. `data` is the
 * data file's bytes; `setups` the setup files' (bytes, or their text), read
 * in order as one setup. Returns the bytes and the warnings: statements
 * not run, value labels Stata cannot hold, unknown names, fields that are
 * not numbers, short records. Needs no Node API.
 *
 * Memory: `data`, its copy in the module, and the .dta bytes. In Node,
 * `readFixedWidth` (from `@jbearak/datakit/node`) reads the data file
 * straight into the module and streams the .dta through a file instead.
 */
export function convertFixedWidth(
  data: Uint8Array,
  setups: readonly (string | Uint8Array)[],
  options: FixedWidthOptions = {},
): { dta: Uint8Array; warnings: string[] } {
  const { recodes, commented } = fixedWidthMode(options);
  const texts = setupBytes(setups);
  const placed = wasm.putBytes(data.length, (view) => view.set(data));
  const chunks: Uint8Array[] = [];
  let warnings: string[];
  try {
    warnings = wasm.fixedWidth(texts, placed, recodes, commented, (bytes) => chunks.push(bytes.slice()));
  } finally {
    wasm.freeBytes(placed);
  }
  wasm.giveMemoryBack();
  const dta = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    dta.set(c, at);
    at += c.length;
  }
  return { dta, warnings };
}
