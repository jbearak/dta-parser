# Text encodings

From release 118 (Stata 14), every string in a `.dta` file is UTF-8:
names, labels, value labels, notes and data. dta-parser reads it as
UTF-8 and ignores any encoding option. Bytes that are not valid UTF-8
become U+FFFD (�) instead of stopping the read.

Before 118, a file stores one byte per character and does not say which
character set it used. Stata used the computer's code page, which for
English and Western European text was usually Windows-1252 or Latin-1,
its near twin. So dta-parser decodes older
files as **Windows-1252 by default**, as haven does. You can choose:

| encoding | name to pass | use it when |
|---|---|---|
| Windows-1252 | `"windows-1252"` (the default) | almost always |
| Latin-1 | `"latin1"` | you want byte-for-byte agreement with pandas, which assumes Latin-1 |
| UTF-8 | `"utf-8"` | the file was written by a tool that put UTF-8 into an old release |

Windows-1252 and Latin-1 differ only for bytes 0x80 to 0x9F: Windows-1252
maps them to curly quotes, dashes, `€` and a few letters; Latin-1 maps
them to control characters that almost never appear in real text. If
you see `â€™` where an apostrophe should be, the file holds UTF-8 and
needs `"utf-8"`. Other code pages (Cyrillic, Greek, East Asian) are not
supported; read such a file with ReadStat-based tools, which use iconv.

The option goes to the read call:

| language | option |
|---|---|
| R | `read_dta(path, encoding = "latin1")` |
| Python | `dta_parser.read_dta(path, encoding="latin1")` |
| Julia | `read_dta(path; encoding="latin1")` |
| TypeScript | `openDtaFile(path, { encoding: "latin1" })` |

After reading, text is the language's ordinary string type (UTF-8 in R,
Julia and Python's `str`; UTF-16 in JavaScript). Writing always produces
release 118, so every string goes back as UTF-8: an old file read and
written once is converted. In R, strings you write must be valid UTF-8;
`enc2utf8()` converts a string in the native encoding.

Which encoding was used for a file is in the metadata: Python
`df.attrs["dta"]["encoding"]`, Julia `metadata(t, "encoding")`,
TypeScript `reader.info.encoding`.
