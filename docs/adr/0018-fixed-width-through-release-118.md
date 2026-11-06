# Fixed-width files are read by converting them to a release 118 file

CDC publishes the National Survey of Family Growth, from the 1973 cycle
to 2017-2019, as fixed-width text with a SAS setup for each file (plan
0009; the 2002 to 2017-2019 setups were added later, under "Later
cycles"). The core parses the setup and the data and writes a release
118 file through the existing writer; R, Python and Julia then read
that file with their own `read_dta` and remove it. So one parser serves
three languages, and each language's types, value labels and
representation of `.a` to `.z` (haven's tagged NAs, `StataArray`,
`DtaColumn`) apply unchanged.

The file is temporary and only our readers read it, so the converter's
writer allows variable labels of up to 320 characters (the field's size
in release 118) instead of Stata's 80: CDC's female respondent and
pregnancy setups have 1,407 longer labels, up to 200 characters (275
from 1973 to 1995, 1,132 from 2002 to 2017-2019).

With `recodes = "tagged"`, the codes a variable's recodes send to `.`
take the letters `.a`, `.b`, ... in the order the setup names them,
skipping letters the setup writes itself, and each code's value label
moves to its letter. So `.a` means what that variable's labels say: 98
"DK" in one variable, 97 "Refused" in another.

## Considered options

- **A column builder in each language.** Three more code paths for
  storage types, value labels and letters, which the existing readers
  already get right.
- **Reading the converted bytes from memory** through a `Reader<Bytes>`.
  Every binding's reader type is `Reader<FileSource>`; generalising it
  touches every read path for a feature that reads each file once.
- **One letter per code across the file** (98 always `.a`). Codes mean
  different things in different variables (9 is "Not ascertained" in
  one, a real answer in another), and a variable's labels say what its
  letters mean either way.

## Consequences

- A read writes and reads one temporary file. For the largest NSFG
  file, 1995's female respondents (10,847 rows, 5,754 columns, 142 MB
  of text), R's `read_fixed_width`, conversion and read together,
  takes 1.5 seconds, most of it parsing. Disk use is about the size of
  the numbers.
- Options of `read_dta` that a release 118 file makes moot (`encoding`,
  `dates`) are not offered.
- The converter does not run SAS: it reads the statements CDC's setups
  use (plan 0009 lists them) and warns about the rest. The setups from
  2002 on need three more things, and it does them: it reads a setup
  split over several files (2002's three); it reads the `PROC FORMAT`
  step and `FORMAT` statement that 2006-2010 to 2017-2019 wrap in block
  comments as code, unless `commented_formats` is off; and it reads
  labels with stray quotes inside them from the first quote to the
  last (ADR 0030).
