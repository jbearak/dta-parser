// The inflater the package uses where there is no zlib (a browser) to
// unpack its embedded module: it gives what zlib gives, for the module
// itself and for blocks of every kind (stored, fixed and dynamic codes).
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { constants, deflateRawSync } from "node:zlib";
import { build } from "esbuild";

const require = createRequire(import.meta.url);
const wasmPath = fileURLToPath(new URL("../build/dta.wasm", import.meta.url));

test("inflateRaw gives what zlib deflated", async () => {
  const out = join(mkdtempSync(join(tmpdir(), "dta-inflate-")), "inflate.js");
  await build({ entryPoints: [fileURLToPath(new URL("../src/inflate.ts", import.meta.url))], bundle: true, format: "cjs", platform: "node", outfile: out });
  const { inflateRaw } = require(out);
  const inputs = [
    Buffer.alloc(0),
    Buffer.from("x"),
    Buffer.from("hello hello hello ".repeat(5000)),
    randomBytes(200_000),
    Buffer.from(Array.from({ length: 70_000 }, (_, i) => (i * 7) % 251)),
  ];
  if (existsSync(wasmPath)) inputs.push(readFileSync(wasmPath));
  for (const input of inputs) {
    for (const level of [0, 1, 6, 9]) {
      for (const strategy of [constants.Z_DEFAULT_STRATEGY, constants.Z_FIXED, constants.Z_HUFFMAN_ONLY, constants.Z_RLE]) {
        const got = inflateRaw(deflateRawSync(input, { level, strategy }), input.length);
        assert.ok(Buffer.from(got).equals(input), `${input.length} bytes, level ${level}, strategy ${strategy}`);
      }
    }
  }
  assert.throws(() => inflateRaw(Uint8Array.of(7), 10), /damaged/);
  assert.throws(() => inflateRaw(deflateRawSync(Buffer.from("abc")), 2), /damaged/);
});
