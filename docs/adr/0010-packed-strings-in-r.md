# read_dta returns string columns packed, making R strings on use

Making an R string means hashing it into R's global string cache, and
R's collector then traces it. For 10M distinct values that cost 4.9 s,
nine tenths of a full read of the benchmark file, and no eager route
got under 2.3 s, more than the npm package's whole read. pandas and npm
are fast here because Python and V8 strings are neither interned nor
traced one by one; R has no such string.

So each string column `read_dta` returns is an ALTREP character vector
that holds the column's UTF-8 bytes and end offsets in two R vectors,
and makes an R string only when R asks for that element, caching it.
Anything that needs the whole vector as a C array (`Dataptr`) makes the
rest and drops the bytes. Base R's `as.character(1:n)`, vroom and arrow
return lazy character vectors in the same way.

The cost moves rather than vanishes. Reading is about ten times faster,
and slicing, `head()` and filtering on other columns make only the
strings they keep. But the first operation over every value of a
high-cardinality column (`==`, `unique`, sorting, grouping) pays about
what the read used to. The benchmarks therefore report a read followed
by a comparison over every string beside the plain read, because the
other tools pay their string cost inside the read.

Considered and rejected:

- **Eager, tuned:** pre-growing R's heap needs startup settings; R has
  no API for it, and even a grown heap leaves 2.3 s.
- **A string class of our own** (not `character`): every R function
  would need methods for it.
- **Lazy only above some size:** two code paths, and small columns cost
  little either way.
- **Making the strings in hash order** when the whole column is
  needed, so R's string table is filled bucket by bucket: making them
  took 2.5 s instead of 4.1 s, but the strings then lie in memory out of
  row order, and the collection right after took 3.3 s instead of
  0.45 s, and every later full collection 1.2 s instead of 0.3 s.
- **A `Serialized_state` method:** it would make `.rds` files need
  dtatools to load; without one they hold plain character vectors.

`save_dta` still reads a packed column through its strings, making them.
Writing the packed bytes directly is possible if a workload needs it.

Since ADR 0016, the bridge and the packed string columns live in
dtaparser, which dtatools imports.
