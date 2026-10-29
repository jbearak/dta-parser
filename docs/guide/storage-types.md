# Storage types

Each Stata variable has a *storage type* that fixes how its values sit
in the file. There are five numeric types and two kinds of string.

| type | holds | values that are numbers | reserved for missing values |
|---|---|---|---|
| byte | 1-byte integer | −127 to 100 | 101 to 127 |
| int | 2-byte integer | −32,767 to 32,740 | 32,741 to 32,767 |
| long | 4-byte integer | −2,147,483,647 to 2,147,483,620 | 2,147,483,621 to 2,147,483,647 |
| float | 4-byte IEEE float | about ±1.7 × 10^38, 7 significant digits | a range of large positive values; 27 of them, spaced apart, are `.` to `.z` |
| double | 8-byte IEEE float | about ±8.98 × 10^307 | a range of large positive values; 27 of them, spaced apart, are `.` to `.z` |
| str1 to str2045 | fixed-width text, that many bytes | | |
| strL | text or binary of any length, stored once per distinct value | | |

The integer ranges stop short of the type's limits because Stata keeps
the largest 27 values of each type for the missing values `.` and `.a`
to `.z` (see [Missing values](missing-values.md)). Before release 113
only the largest value is reserved, for `.`.

String widths count bytes, not characters. In release 118 text is
UTF-8, so `str10` holds ten ASCII letters but only five letters such as
`é` that take two bytes. Releases before 117 stop at `str244` and have no
strL. See [strLs](strls.md).

## What each language reads them as

| storage | R | Python (no missing) | Python (only `.` missing) | Python (any `.a` to `.z`) | Julia (no missing) | Julia (any missing) | TypeScript |
|---|---|---|---|---|---|---|---|
| byte | `dta_num` (double) | `int8` | `float32` | `StataArray` | `Vector{Int8}` | `DtaColumn{Int8}` | `Float64Array` |
| int | `dta_num` | `int16` | `float32` | `StataArray` | `Vector{Int16}` | `DtaColumn{Int16}` | `Float64Array` |
| long | `dta_num` | `int32` | `float64` | `StataArray` | `Vector{Int32}` | `DtaColumn{Int32}` | `Float64Array` |
| float | `dta_num` | `float32` | `float32` | `StataArray` | `Vector{Float32}` | `DtaColumn{Float32}` | `Float64Array` |
| double | `dta_num` | `float64` | `float64` | `StataArray` | `Vector{Float64}` | `DtaColumn{Float64}` | `Float64Array` |
| strN, strL | character | text (`str` on pandas 3, `object` on 2.2) | | | `Vector{String}` | | `string[]` |
| strL holding binary | an error | `object` of `bytes` | | | `Vector{UInt8}` elements | | `Uint8Array` elements |

Every value converts exactly. A byte or int with `.` becomes `float32` in
Python because `float32` holds every integer of those types; a long
needs `float64`. In R every numeric column is a double vector (R
integers have only one `NA`, so they could not hold `.a` to `.z`), and
the column's `storage` attribute keeps the type from the file, so
writing it back uses the same type.

## Which storage type a write uses

When you write a column that came from a read, dta-parser keeps its
storage type if every value still fits it. Otherwise it picks a type
from the values:

| values | storage |
|---|---|
| logicals / booleans | byte |
| integers | the smallest of byte, int, long that holds every value (with the ranges above); else double |
| integers beyond ±2^53 | an error: a double cannot hold them exactly |
| 32-bit floats | float |
| 64-bit floats | double |
| text | strN, with N the longest value in bytes, up to 2045; longer text makes the column a strL |
| binary (Python `bytes`, Julia `Vector{UInt8}`) | strL |

R and TypeScript differ in one way: they do not shrink integers. In R
an integer column is long and a double column is double unless its
`storage` attribute says otherwise; in TypeScript a numeric column is
double unless you set `type`. A value outside the chosen type's range is
an error in every language, and integer types never truncate. Float
storage is the exception: a double written as float is rounded to the
nearest float, as any 4-byte float would hold it, so `0.1` reads back as
`0.10000000149011612`. Choose float only for values that are floats
already (or where 7 significant digits are enough).

Fixed-width string columns are written as wide as their longest value
needs, not as wide as they were read: a `str100` column whose values
are all short comes back narrower. In R and TypeScript a text strL short
enough for a fixed-width string is written as one (see
[strLs](strls.md)).
