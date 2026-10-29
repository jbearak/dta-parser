# Memory and speed

Measured numbers are in [bench/RESULTS.md](../../bench/RESULTS.md),
for every language against the other open-source readers. This page
explains what costs time and memory, so you can predict it for your
files.

## How a read works

A `.dta` file stores its rows one after another, each holding every
variable. dta-parser reads the rows in chunks of about 8 MiB, decodes
the selected variables of each chunk straight into the columns it
returns, and drops the chunk. Memory while reading is the result plus
that chunk, plus the index of strL positions when a strL column is
selected.

What follows from that:

- **Selecting columns** saves memory and the work of building the
  unselected columns, but every byte of row data still passes through:
  the variables you skip sit between the ones you keep.
- **A row window** (`skip` and `n_max`, or `start` and `count`) reads
  only those rows: the reader computes where row `skip` starts and seeks
  there, so 1,000 rows from the end of a large file cost the same as
  1,000 from the start.
- **Metadata only** (`read_meta`, or opening a file in TypeScript) reads
  the header, the variable descriptors, and then jumps to the value
  labels; it never reads the rows.
- **Files over 4 GiB** read the same way; nothing is mapped into memory
  whole.

## Where each language spends

**R.** Numbers go into double vectors with no copy beyond the chunk.
Strings are the expensive part of any R reader, because R makes a
global, cached string object per value. dtatools reads string columns
*packed*: it keeps the bytes from the file and makes R strings only
when a value is used. Printing or slicing a few rows stays cheap; the
first operation over every value of a column (`==`, `unique()`,
sorting) pays for making them. A column with few distinct values is
kept as those values plus a code per row, so R makes one string per
distinct value. [ADR 0010](../adr/0010-packed-strings-in-r.md) and
[ADR 0011](../adr/0011-dictionary-strings-in-r.md) explain why.

**Python.** The extension fills numpy arrays that Python allocated, in
their storage width (an `int8` column takes one byte per row), and
builds Python strings in Rust. A `StataArray` costs one extra byte per
row for its codes. Python strings cost about 50 bytes each plus the
text, which dominates for string-heavy files.

**Julia.** The C library hands each chunk to Julia, which copies it into
vectors allocated once for the whole result. A `DtaColumn` costs one
extra byte per row for its codes.

**TypeScript.** The core runs as WebAssembly inside the package. Each
call into it decodes at most 64 MiB, so a large read is a loop of
bounded calls, and `openDtaFile` reads the file through `fs.readSync`
only as far as asked. Numeric columns are `Float64Array`s (8 bytes per
row whatever the storage type) plus a `Uint8Array` of codes.

## Writing

Writers stream: the core builds about 8 MiB of rows at a time from your
columns and writes them, so writing needs little memory beyond the data
you already hold. Each distinct strL text is stored once.

## Tips for large files

- Read the metadata first to see the row count and variables.
- Select the columns you need; read in row windows if the result would
  not fit in memory.
- In R, avoid touching every value of a string column you do not need.
- In Python, `dates=False` skips the date conversion pass.
