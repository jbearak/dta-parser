// Raw DEFLATE (RFC 1951) decompression, for the embedded wasm module
// where no zlib is at hand (a browser). Node uses its own zlib instead.
// Written from the RFC: canonical Huffman codes decoded a bit at a time,
// which is slow but small, and runs once per process.

/** Lengths 257 to 285: base lengths and extra bits; distances 0 to 29 likewise. */
const LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
/** The order code length codes are given in. */
const ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

/** A canonical Huffman code: how many codes of each length, and the symbols in code order. */
interface Huffman {
  counts: Uint16Array;
  symbols: Uint16Array;
}

function huffman(lengths: ArrayLike<number>, n: number): Huffman {
  const counts = new Uint16Array(16);
  for (let i = 0; i < n; i++) counts[lengths[i]]++;
  counts[0] = 0;
  const offsets = new Uint16Array(16);
  for (let len = 1; len < 15; len++) offsets[len + 1] = offsets[len] + counts[len];
  const symbols = new Uint16Array(n);
  for (let i = 0; i < n; i++) if (lengths[i] !== 0) symbols[offsets[lengths[i]]++] = i;
  return { counts, symbols };
}

let fixedLit: Huffman | undefined;
let fixedDist: Huffman | undefined;

/** Decompress raw DEFLATE data that makes `size` bytes. */
export function inflateRaw(src: Uint8Array, size: number): Uint8Array {
  const out = new Uint8Array(size);
  let op = 0;
  let pos = 0;
  let bitBuf = 0;
  let bitCount = 0;
  const fail = (why: string): never => {
    throw new Error(`the embedded module is damaged: ${why}`);
  };
  const bits = (n: number): number => {
    while (bitCount < n) {
      if (pos >= src.length) fail("it ends early");
      bitBuf |= src[pos++] << bitCount;
      bitCount += 8;
    }
    const v = bitBuf & ((1 << n) - 1);
    bitBuf >>>= n;
    bitCount -= n;
    return v;
  };
  const decode = (h: Huffman): number => {
    let code = 0;
    let first = 0;
    let index = 0;
    for (let len = 1; len <= 15; len++) {
      code |= bits(1);
      const count = h.counts[len];
      if (code - first < count) return h.symbols[index + code - first];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    return fail("a code is not in its table");
  };
  const codes = (lit: Huffman, dist: Huffman) => {
    for (;;) {
      const sym = decode(lit);
      if (sym < 256) {
        if (op >= size) fail("it makes too many bytes");
        out[op++] = sym;
      } else if (sym === 256) {
        return;
      } else {
        const k = sym - 257;
        if (k >= 29) fail("a length code is invalid");
        const len = LEN_BASE[k] + bits(LEN_EXTRA[k]);
        const d = decode(dist);
        if (d >= 30) fail("a distance code is invalid");
        const back = DIST_BASE[d] + bits(DIST_EXTRA[d]);
        if (back > op || op + len > size) fail("a match runs outside the output");
        for (let i = 0; i < len; i++, op++) out[op] = out[op - back];
      }
    }
  };
  let last = 0;
  while (!last) {
    last = bits(1);
    const type = bits(2);
    if (type === 0) {
      bitBuf = 0;
      bitCount = 0;
      if (pos + 4 > src.length) fail("a stored block ends early");
      const len = src[pos] | (src[pos + 1] << 8);
      pos += 4;
      if (pos + len > src.length || op + len > size) fail("a stored block runs outside");
      out.set(src.subarray(pos, pos + len), op);
      pos += len;
      op += len;
    } else if (type === 1) {
      if (!fixedLit) {
        const l = new Uint8Array(288);
        l.fill(8, 0, 144);
        l.fill(9, 144, 256);
        l.fill(7, 256, 280);
        l.fill(8, 280, 288);
        fixedLit = huffman(l, 288);
        fixedDist = huffman(new Uint8Array(30).fill(5), 30);
      }
      codes(fixedLit, fixedDist!);
    } else if (type === 2) {
      const nlen = bits(5) + 257;
      const ndist = bits(5) + 1;
      const ncode = bits(4) + 4;
      const lengths = new Uint8Array(320);
      for (let i = 0; i < ncode; i++) lengths[ORDER[i]] = bits(3);
      const lencode = huffman(lengths, 19);
      lengths.fill(0);
      for (let i = 0; i < nlen + ndist; ) {
        const sym = decode(lencode);
        if (sym < 16) {
          lengths[i++] = sym;
          continue;
        }
        let repeat: number;
        let value = 0;
        if (sym === 16) {
          if (i === 0) fail("a repeat has nothing to repeat");
          value = lengths[i - 1];
          repeat = 3 + bits(2);
        } else if (sym === 17) repeat = 3 + bits(3);
        else repeat = 11 + bits(7);
        if (i + repeat > nlen + ndist) fail("code lengths run over");
        lengths.fill(value, i, i + repeat);
        i += repeat;
      }
      codes(huffman(lengths, nlen), huffman(lengths.subarray(nlen, nlen + ndist), ndist));
    } else {
      fail("a block has an invalid type");
    }
  }
  if (op !== size) fail("it makes too few bytes");
  return out;
}
