# Zstandard decoder

`fzstd.ts` derives from the MIT-licensed fzstd decoder by Arjun Barrett:
https://github.com/101arrowz/fzstd/blob/master/src/index.ts

The source snapshot was retrieved on 2026-09-05. `fzstd.LICENSE` preserves the
upstream license. The same license appears in a retained source comment so
bundlers include it in the distributed parser.

Local changes remove the unused streaming API, decode into caller-owned bounded
storage, validate frame content sizes and decoded block bounds, reject external
dictionaries, check match distances, and read up to five bytes for wide offset
bit fields. Caller-owned output also avoids allocating the declared window or coercing large
typed arrays to strings. The adapter validates frame checksums.

The wide-offset interoperability fixture comes from Rust's Zstandard encoder.
Its final batch references data more than 96 MiB earlier. A 26-bit offset field
starts at bit 7 and needs a fifth input byte. Restoring the upstream four-byte
expression corrupts the decoded tail and fails the fixture's content checksum.

The upstream implementation does not use strict TypeScript checking; its
vendored file retains that boundary through `@ts-nocheck`. The adapter and the
rest of the parser compile with strict checking.
