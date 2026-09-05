import { xxh64 } from './arrow-checksum.js';
import { decompressFrame } from './vendor/fzstd.js';

const u32 = (data: Uint8Array, offset: number): number =>
  new DataView(data.buffer, data.byteOffset, data.byteLength).getUint32(offset, true);
const rotl = (n: number, count: number): number => (n << count) | (n >>> (32 - count));

/** LZ4 frame header and optional block/content checksums use XXH32, seed zero. */
function xxh32(data: Uint8Array): number {
  const p1 = 0x9e3779b1, p2 = 0x85ebca77, p3 = 0xc2b2ae3d, p4 = 0x27d4eb2f, p5 = 0x165667b1;
  const round = (v: number, n: number) => Math.imul(rotl(v + Math.imul(n, p2), 13), p1);
  let at = 0, h: number;
  if (data.length >= 16) {
    let a = p1 + p2, b = p2, c = 0, d = -p1;
    while (at <= data.length - 16) { a = round(a, u32(data, at)); b = round(b, u32(data, at + 4)); c = round(c, u32(data, at + 8)); d = round(d, u32(data, at + 12)); at += 16; }
    h = rotl(a, 1) + rotl(b, 7) + rotl(c, 12) + rotl(d, 18);
  } else h = p5;
  h += data.length;
  while (at + 4 <= data.length) { h = Math.imul(rotl(h + Math.imul(u32(data, at), p3), 17), p4); at += 4; }
  while (at < data.length) h = Math.imul(rotl(h + Math.imul(data[at++], p5), 11), p1);
  h ^= h >>> 15; h = Math.imul(h, p2); h ^= h >>> 13; h = Math.imul(h, p3); h ^= h >>> 16;
  return h >>> 0;
}

function fail(message: string): never { throw new Error(`Invalid Arrow compressed buffer: ${message}`); }

function lz4(data: Uint8Array, out: Uint8Array): void {
  let at = 0, written = 0;
  const need = (count: number) => { if (count > data.length - at) fail('truncated LZ4 frame'); };
  while (at < data.length) {
    need(4); const magic = u32(data, at); at += 4;
    if ((magic >>> 4) === 0x184d2a5) { need(4); const size = u32(data, at); at += 4; need(size); at += size; continue; }
    if (magic !== 0x184d2204) fail('LZ4 frame magic');
    need(3); const header = at, flags = data[at++], descriptor = data[at++];
    if ((flags >>> 6) !== 1 || (flags & 2) || (descriptor & 0x8f)) fail('LZ4 frame flags');
    const blockCode = (descriptor >>> 4) & 7;
    if (blockCode < 4 || blockCode > 7) fail('LZ4 maximum block size');
    const blockMax = 2 ** (8 + blockCode * 2), frameStart = written;
    let contentSize: bigint | undefined;
    if (flags & 8) { need(8); contentSize = new DataView(data.buffer, data.byteOffset + at, 8).getBigUint64(0, true); at += 8; if (contentSize > BigInt(out.length - written)) fail('LZ4 content exceeds declared Arrow buffer length'); }
    if (flags & 1) { need(4); if (u32(data, at) !== 0) fail('LZ4 external dictionary is unsupported'); at += 4; }
    need(1); if (((xxh32(data.subarray(header, at)) >>> 8) & 255) !== data[at++]) fail('LZ4 header checksum mismatch');
    for (;;) {
      need(4); const block = u32(data, at); at += 4;
      if (block === 0) break;
      const length = block & 0x7fffffff; if (!length || length > blockMax) fail('LZ4 block size');
      need(length); const end = at + length, blockStart = at, outputStart = written;
      if (block >>> 31) { if (length > out.length - written) fail('LZ4 output exceeds declared Arrow buffer length'); out.set(data.subarray(at, end), written); written += length; at = end; }
      else {
        const extension = (base: number): number => { if (base !== 15) return base; let n: number; do { if (at >= end) fail('truncated LZ4 length'); n = data[at++]; base += n; } while (n === 255); return base; };
        while (at < end) {
          const token = data[at++], literals = extension(token >>> 4);
          if (literals > end - at || literals > out.length - written) fail('LZ4 literal length');
          out.set(data.subarray(at, at + literals), written); at += literals; written += literals;
          if (at === end) break;
          if (end - at < 2) fail('truncated LZ4 match offset');
          const offset = data[at] + data[at + 1] * 256; at += 2;
          const match = extension(token & 15) + 4;
          if (!offset || offset > written - ((flags & 32) ? outputStart : frameStart)) fail('LZ4 match offset');
          if (match > out.length - written) fail('LZ4 output exceeds declared Arrow buffer length');
          for (let i = 0; i < match; i++) { out[written] = out[written - offset]; written++; }
        }
      }
      if (written - outputStart > blockMax) fail('LZ4 decoded block exceeds maximum size');
      if (flags & 16) { need(4); if (u32(data, at) !== xxh32(data.subarray(blockStart, end))) fail('LZ4 block checksum mismatch'); at += 4; }
    }
    if (contentSize !== undefined && contentSize !== BigInt(written - frameStart)) fail('LZ4 content size mismatch');
    if (flags & 4) { need(4); if (u32(data, at) !== xxh32(out.subarray(frameStart, written))) fail('LZ4 content checksum mismatch'); at += 4; }
  }
  if (written !== out.length) fail('LZ4 output length mismatch');
}

/** Decode a BUFFER-compressed IPC payload after its 8-byte length prefix. */
export function decodeArrowBuffer(codec: 0 | 1, input: Uint8Array, expectedLength: number): Uint8Array {
  if (!Number.isSafeInteger(expectedLength) || expectedLength < 0) fail('invalid decompressed length');
  const output = new Uint8Array(expectedLength);
  if (!input.length) fail('missing compression frame');
  if (codec === 0) { lz4(input, output); return output; }
  if (codec !== 1) fail('unsupported compression codec');
  let at = 0, written = 0;
  while (at < input.length) {
    if (input.length - at < 4) fail('truncated Zstandard frame');
    if ((u32(input, at) >>> 4) === 0x184d2a5) {
      if (input.length - at < 8) fail('truncated Zstandard skippable frame');
      const size = u32(input, at + 4); if (size > input.length - at - 8) fail('truncated Zstandard skippable frame'); at += size + 8; continue;
    }
    const frame = decompressFrame(input.subarray(at), output.subarray(written));
    if (frame.checksumOffset !== undefined && Number(xxh64(output.subarray(written, written + frame.written)) & 0xffffffffn) !== u32(input, at + frame.checksumOffset)) fail('Zstandard content checksum mismatch');
    written += frame.written; at += frame.consumed;
  }
  if (written !== expectedLength) fail('Zstandard output length mismatch');
  return output;
}
