import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { decodeArrowBuffer } from '../../src/arrow-codecs.js';
const fixture = (name: string) => new Uint8Array(readFileSync(new URL(`../fixtures/arrow/${name}`, import.meta.url)));
describe('portable Arrow IPC codecs', () => {
  for (const [name, codec] of [['lz4', 0], ['zstd', 1]] as const) {
    test(`${name} decodes canonical Rust output`, () => { const raw = fixture('codec.raw'); expect(decodeArrowBuffer(codec, fixture(`codec.${name}`), raw.length)).toEqual(raw); });
    test(`${name} rejects incorrect output sizes and truncated frames`, () => {
      const raw = fixture('codec.raw'), encoded = fixture(`codec.${name}`);
      expect(() => decodeArrowBuffer(codec, encoded, raw.length - 1)).toThrow();
      expect(() => decodeArrowBuffer(codec, encoded, raw.length + 1)).toThrow();
      for (const end of [0, 1, 4, 6, encoded.length - 1]) expect(() => decodeArrowBuffer(codec, encoded.subarray(0, end), raw.length)).toThrow();
    });
  }
  test('rejects malformed LZ4 header checksum', () => { const bytes = fixture('codec.lz4'); bytes[6] ^= 1; expect(() => decodeArrowBuffer(0, bytes, fixture('codec.raw').length)).toThrow(); });
});

test('Zstandard decodes backreferences beyond the upstream 32 MiB guarantee', () => {
  const expected = new Uint8Array(96 * 1024 * 1024 + 256 * 1024);
  let seed = 0x12345678;
  for (let i = 0; i < 128 * 1024; i++) { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; expected[i] = seed; }
  expected.copyWithin(expected.length - 128 * 1024, 0, 128 * 1024);
  for (let i = expected.length - 128 * 1024; i < expected.length - 128 * 1024 + 32; i++) expected[i] ^= 255;
  const decoded = decodeArrowBuffer(1, fixture('codec-wide-offset.zstd'), expected.length);
  expect(Buffer.compare(decoded, expected)).toBe(0);
});

test('Zstandard rejects content checksum corruption', () => {
  const encoded = fixture('codec-wide-offset.zstd'); encoded[encoded.length - 1] ^= 1;
  expect(() => decodeArrowBuffer(1, encoded, 96 * 1024 * 1024 + 256 * 1024)).toThrow('checksum');
});
