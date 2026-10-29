# strLs: long strings and binary values

Release 117 added the *strL* storage type for text longer than the 2045
bytes a `str2045` holds. A strL value lives outside the rows, in a strL
section near the end of the file; the row holds only a reference to it
(8 bytes). Several rows may refer to the same stored value, so a long
text repeated in a million rows is stored once.

Each stored value is marked as text or as binary. Text is a string in
the file's encoding (UTF-8 from release 118). Binary is any sequence of
bytes, such as an image or a compressed document, and may contain zero
bytes. One strL column can mix the two.

## Reading

dta-parser resolves every reference while reading, so a strL column
comes back as an ordinary string column. Nothing about strLs needs
handling in your code unless a column holds binary values:

| language | text strL | binary strL |
|---|---|---|
| R | character | an error naming the column ("holds binary strLs, which dtatools does not read"); skip the column with `col_select` |
| Python | `str` (or `object` on pandas 2.2) | the column becomes `object`, holding `bytes` for binary values and `str` for text ones |
| Julia | `String` | `Vector{UInt8}` elements; the column's element type widens to hold both |
| TypeScript | `string` | `Uint8Array` elements |

Reading a strL column costs a pass over the strL section to build an
index of where each value starts, before the first row is read. If you
select no strL column, the section is not read at all.

## Writing

dta-parser writes text longer than 2045 bytes as a strL, and stores each
distinct text once. Shorter text is a fixed-width `strN`, where N is the
longest value in bytes.

Binary values are written as binary strLs in Python (`bytes` values)
and Julia (`Vector{UInt8}` values). The R and TypeScript writers take
text only.

A text strL keeps its strL storage on a round trip in Python and Julia
even when every value is short, because the storage type is kept from
the read. In R and TypeScript, short text is written as `strN`.
