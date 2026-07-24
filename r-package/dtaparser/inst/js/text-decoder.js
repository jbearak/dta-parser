if (typeof TextDecoder === "undefined") {
    globalThis.TextDecoder = class TextDecoder {
        constructor(encoding) {
            this.encoding = String(encoding || "utf-8").toLowerCase();
            if (!["utf-8", "utf8", "windows-1252"].includes(this.encoding)) {
                throw new Error(`Unsupported encoding: ${encoding}`);
            }
        }

        decode(bytes) {
            if (this.encoding === "windows-1252") {
                const replacements = [
                    0x20ac, 0x81, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020,
                    0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8d,
                    0x017d, 0x8f, 0x90, 0x2018, 0x2019, 0x201c, 0x201d,
                    0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a,
                    0x0153, 0x9d, 0x017e, 0x0178
                ];
                let decoded = "";
                for (const byte of bytes) {
                    const codepoint = byte >= 0x80 && byte <= 0x9f
                        ? replacements[byte - 0x80]
                        : byte;
                    decoded += String.fromCodePoint(codepoint);
                }
                return decoded;
            }
            let output = "";
            for (let index = 0; index < bytes.length;) {
                const first = bytes[index++];
                if (first < 0x80) {
                    output += String.fromCharCode(first);
                } else if (first < 0xe0) {
                    const second = bytes[index++] & 0x3f;
                    output += String.fromCharCode(
                        ((first & 0x1f) << 6) | second
                    );
                } else if (first < 0xf0) {
                    const second = bytes[index++] & 0x3f;
                    const third = bytes[index++] & 0x3f;
                    output += String.fromCharCode(
                        ((first & 0x0f) << 12) | (second << 6) | third
                    );
                } else {
                    const second = bytes[index++] & 0x3f;
                    const third = bytes[index++] & 0x3f;
                    const fourth = bytes[index++] & 0x3f;
                    const codepoint = ((first & 0x07) << 18)
                        | (second << 12) | (third << 6) | fourth;
                    output += String.fromCodePoint(codepoint);
                }
            }
            return output;
        }
    };
}
