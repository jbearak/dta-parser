# Plan: read fixed-width text files through SAS setup files (historical NSFG)

Status: approved by Sonnet 5.5 (three rounds) and GPT-6.1 Terra (five
rounds); implemented. Extended to the 2002 to 2017-2019 setups (see
[Later cycles](#later-cycles-2002-to-2017-2019)).

## Problem

The National Survey of Family Growth (NSFG) cycles of 1973, 1976, 1982,
1988 and 1995 are published by CDC as fixed-width ASCII data (`.dat`)
with a SAS setup file (`.sas`) per file. CDC publishes no Stata
dictionary, SPSS syntax or `.dta` for them. The user wants to read them
into R, Python and Julia with this library, and, where the setup file
turns survey codes such as 98 "DK" into missing values, to be able to
keep those codes as R's labelled missing values (haven's tagged NA,
which dtaparser already reads `.a` to `.z` into) instead of a bare
`NA`.

The other open-source tools do not cover this today (limits, not bugs;
recorded in `docs/other-readers.md`):

- ReadStat's command line (1.1.9) reads text data with a `.sas` command
  file, but stops on CDC's files as published (on `libname "...";`,
  then on an unnamed `DATA ;`), and has no record-type selection.
- R's asciiSetupReader 3.0.0 reads the 1995 pregnancy file, but reads
  the 1988 files (fixed records with no line breaks) as one row and the
  1976 file (two record types in one file) as one column.

## What CDC's setup files contain

Surveyed in the nine files at
`ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NSFG/sas/`
(`1973FemRespSetup`, `1976FemRespSetup`, `1976PregSetup`,
`1982FemRespSetup`, `1982PregSetup`, `1988FemRespSetup`,
`1988PregSetup`, `1995FemPregFile`, `1995FemRespSetup`; 55,741 lines,
CRLF, tabs as whitespace, keywords in either case):

| statement | forms seen |
|---|---|
| comments | `/* ... */`, including inside `INPUT` (`/*blank 10383-10866*/`); `* ... ;` statements; a stray `*/` with no opener after a `*` comment (1973, 1976FemResp, 1988Preg) |
| `libname "data-file-path";` | placeholder, every file |
| `PROC FORMAT; VALUE name k='label' ... ;` | 7,306 VALUE statements; integer keys, two negative (`-1=`); labels single-quoted with `''` for `'`, may hold `;` and `"`; once no space between a label and the next key (1973 `24='(20) Subfecund'33='(30) Fecund'`) |
| `run;` | at the end, and between `PROC FORMAT` and `DATA` in 1995FemResp |
| `DATA ;` | unnamed |
| `INFILE "c:\temp\x.dat" [missover] [recfm=f] lrecl=N;` | `recfm=f` only in 1988 |
| `INPUT name start[-end] ...;` | column input; one `$` (1973 `temp_NLAMOUNT $ 653-656`); no implied decimals, pointers or informats. Overlapping columns are common (`rec_type 6` and `MARSTAT 6`). The same name twice: 1982FemResp (`FMARITAL 1041` twice; `AGEREMAR` at 1265-1267 and 1284-1287) and 1995FemResp (`FILLER` about 20 times) |
| record-type selection | `INPUT rec_type 6 @; if rec_type<5 then delete; else input ... ;` with `<`, `>`, `=`; 1976 and 1982, both files each |
| `LABEL` | `name = 'text'`; `name ="text"` (all of 1995FemPregFile; two in 1988FemResp holding `'`); `name 'text'` with no `=` (three in 1995FemResp); `FILLER` labelled many times; `INTENT` and `DISFIRST` labelled twice with different text (1982FemResp) |
| missing-value recodes | `IF (X = 98 OR X = 99) THEN X = .;` with 1 to 3 codes: 54 variables in 1973, 363 in 1976FemResp, 49 in 1976Preg, 126 in 1988Preg |
| `FORMAT name fmt. ...;` | |
| other data-step code | 1973 only: `if int_id=3882 then temp_NLAMOUNT='0000';` and `H_FINC_NLAMOUNT=input(temp_NLAMOUNT, 4.);`. Record 3882 holds `OOO0` (letter O) in columns 653-656; 7,986 other records are blank there |

Variable labels run to 200 characters (275 over 80; see "Long variable
labels").

The data files: 1973, 1976, 1982 and 1995 have one record per CRLF line,
every line the same length (1973's lines are 2,023 bytes against
`lrecl=787`; 1976's are 1,000 against 872 and 896). 1988's two files
have no line breaks: exactly 8,450 and 15,759 records of `lrecl=3553`.
1976 and 1982 hold respondent and pregnancy records in one file, told
apart by a record-type column.

## Design

### Overview

A new module in the core, `crates/dta/src/fixed_width.rs`, parses a SAS
setup file and a fixed-width data file and writes a release 118 `.dta`
through the existing writer. Each language reads that file back with its
existing `read_dta`. So one parser serves R, Python and Julia, and every
read option, type rule and missing-value representation they already
have applies unchanged (ADR 0018).

```rust
pub enum Recodes { Setup, Tagged, None }

pub struct FixedWidthWarning { pub kind: WarningKind, pub message: String }
pub enum WarningKind { SkippedStatement, SkippedValueLabel, UnknownName,
                       DuplicateName, NotANumber, ShortRecords, NoRecords,
                       LabelCut, LabelQuotes }

/// Read `data` as `setups` describe and write it as release 118 to `out`.
pub fn fixed_width_to_dta(setups: &[&[u8]], data: &[u8], recodes: Recodes,
                          commented_formats: bool, out: impl Write)
                          -> Result<Vec<FixedWidthWarning>>
```

The core keeps doing no I/O of its own; bindings read both files into
memory (the largest, 1995FemResp, is 142 MB) and give the writer a
buffered file. Each file's text (the setup file; the data file's string
fields) is read as UTF-8 when the whole file is valid UTF-8 and as
windows-1252 otherwise (all nine files are ASCII), so there is no
encoding option; a UTF-8 character cut by a column boundary becomes
U+FFFD. String columns are decoded into owned text before writing (one
string variable in the nine files).

### Parsing the setup file

A tokenizer that knows SAS comments (`/* */` anywhere, including inside
statements; `*` at the start of a statement, up to `;`), single- and
double-quoted strings with doubled quotes, and splits statements at `;`
outside quotes. Tabs and CR are whitespace. Keywords and variable names
match case-insensitively; names keep the case of their first `INPUT`
spec.

Statements:

- `PROC FORMAT;` then `VALUE [$]name key='label' ...;` until `DATA`,
  `RUN` or another `PROC`. Keys must be integers (optionally negative);
  a range (`1-5=`), `LOW`, `HIGH`, `OTHER` or non-integer key skips that
  entry with a warning. A `$` (character) format is skipped with a
  warning: Stata labels only numbers. A repeated key: the last wins.
- `DATA [name];` begins the data step.
- `INFILE "path" options;` reads `LRECL=n` and `RECFM=F|V`; `MISSOVER`
  needs nothing (short lines read as blank). Other options are ignored.
  The path is ignored; the caller names the data file.
- `INPUT` column specs: `name [$] start[-end]`. Anything else in an
  `INPUT` (pointers, informats, implied decimals, list input) is an
  error naming the setup line.
- **Repeated names** follow SAS: the variable has one column in the
  result, at the position of its first spec, and each record's value is
  read by its last spec. A name given as `$` in one spec and numeric in
  another is an error. One warning per repeated name.
- Record-type selection: `INPUT v cols @; IF v op n THEN DELETE; ELSE
  INPUT specs;` with `op` one of `=`, `^=`, `~=`, `<`, `<=`, `>`, `>=`
  or `EQ`, `NE`, `LT`, `LE`, `GT`, `GE`. A record for which the
  condition holds is dropped. `v` stays a variable, as in SAS. A
  variable a selection reads may not be assigned by any statement (an
  error), which is stricter than SAS needs and enough for the nine
  files.
- `LABEL name [=] 'text' ...;`, single- or double-quoted; the last label
  of a name wins.
- `FORMAT name fmt. ...;` attaches the value-label set `fmt` when a
  `VALUE` defined it; other formats (SAS built-ins) are ignored. The
  last format of a name wins.
- `LIBNAME`, `RUN`, `OPTIONS`, `TITLE`, `FILENAME` are ignored.
- **Data-step assignments**, executed in setup order for each kept
  record. Two forms only, which cover every assignment in the nine
  files:
  - `IF cond THEN name = constant;` where `cond` is comparisons
    `v op n` joined by `OR` and `AND` (`AND` binds tighter), with
    parentheses, and `constant` is a number, `.`, `.A` to `.Z` (or
    `.a`), or a quoted string for a `$` variable.
  - `name = INPUT(strvar, w.);` makes a new numeric variable from the
    first `w` characters of `strvar`'s trimmed value, parsed as a
    numeric field is (below). New variables go after the `INPUT`
    variables, in order of appearance.
  A **missing-value recode** is the first form when `cond` compares only
  `name` itself, by `=`, joined by `OR`, and the constant is a missing
  value. The `recodes` option (below) governs recodes; every other
  assignment always applies.
  **Order.** A variable's value at a statement is its field (or its
  `INPUT(...)` result) with the earlier statements that assign it
  applied in order. A condition may name only `INPUT` variables that no
  earlier statement assigns, apart from `name` itself; `INPUT(strvar,
  w.)` reads `strvar` after every statement that assigns it, which must
  all come earlier. Otherwise the setup is an error ("unsupported
  data-step order"). So each variable can be computed on its own, row
  by row. The 1973 pair (`IF int_id=3882 THEN temp_NLAMOUNT='0000';`
  then `H_FINC_NLAMOUNT=input(temp_NLAMOUNT, 4.);`) meets the rule.
- Any other statement in the data step is skipped with a warning quoting
  it. A name in `LABEL`, `FORMAT` or `IF` that no `INPUT` or assignment
  defines is a warning.
- **Comparisons with missing values** follow SAS: a missing value is
  less than every number, and `.` < `.a` < ... < `.z`. So a blank
  `rec_type` meets `rec_type<5` and not `rec_type>0`.

### Records and fields

- `RECFM=F` with `LRECL=n`: records are consecutive `n`-byte slices; a
  shorter last slice is an error naming the byte count.
- Otherwise records are lines split at `\n`, with a trailing `\r`
  dropped; a final line without `\n` counts; an empty final line does
  not. With `LRECL`, bytes past it are not read (SAS's behaviour; 1973
  and 1976). Columns past the end of a line read as blank.
- A warning when any kept record is shorter than the last column the
  `INPUT` reads (capped at `LRECL`): "N records are shorter than column
  C; is this the data file the setup describes?". A warning when no
  record is kept.
- Numeric field: trimmed of blanks. Empty, or `.`, is `.`. Otherwise
  parsed as a decimal number (sign, digits, point, exponent). A field
  that is not a number is `.`; one warning per variable gives the count
  and the first record's number in the data file (1973's `OOO0` is fixed by the setup's
  own assignment before `INPUT(...)` reads it).
- String field (`$`): leading and trailing blanks trimmed.

### Storage types

After the statements are applied (so types depend on the `recodes`
mode: 98 recoded away may leave a byte), one row-by-row pass over the
kept records finds, per numeric variable, whether every value is an
integer and its range. The smallest Stata type that holds the values is
used: byte (-127 to 100), int (-32,767 to 32,740), long (-2,147,483,647
to 2,147,483,620), else double. A variable with no non-missing value is
byte. Strings are strN sized by the writer. Display formats are the
writer's defaults.

The writer's `Values::Numbers` fill computes each value again from the
data (field, then statements), so the values are never held as a second
copy; only the start, end and number of each kept record (24 bytes a
record) are stored.

### Long variable labels

The writer rejects variable labels over 80 characters, and 275 labels
in these files are longer (83 in 1976FemResp, 21 in 1982FemResp, 9 in
1982Preg, 140 in 1988FemResp, 18 in 1988Preg, 4 in 1995FemResp).
Release 118's field holds 320 bytes, and every reader of ours reads all
of it (`header.rs`). `WriteOptions` gets a hidden field,
`long_variable_labels` (default false), passed through to
`check_metadata`; when true a variable label may have up to 320
characters and 320 bytes. The converter sets it: the temporary file is
read back by our own readers and never given to Stata. A label over 320
bytes is cut at a character boundary with a warning.

### Missing-value recodes: the `recodes` option

- `"setup"` (default): apply the recodes as the setup writes them: a
  code recoded to `.` becomes `.`; one recoded to `.A` becomes `.a`. In
  R a `.a` stays a tagged NA (ADR 0017); in Python `.` is `NaN` and `.a`
  is `missing.a`; in Julia both are `missing`, with `stata_code` 1 or 2.
- `"tagged"`: keep why a value is missing. Per variable, the codes its
  recodes send to `.` take the letters `.a`, `.b`, ... in the order the
  setup first names them, skipping letters the setup writes itself for
  that variable; letters the setup writes are kept. So 98 and 99
  recoded together become `.a` and `.b`, the mapping CDC's setup header
  suggests. The same letter can mean different things in different
  variables (1988Preg lists `97 Refused, 98 DK, 99 Not ascertained`; a
  lone `9` in 1976 is "Not ascertained"); a letter means what that
  variable's labels say. A variable needing more than 26 letters is an
  error naming it.
- `"none"`: ignore the recodes; the codes stay numbers.

Value labels follow the values. In `"setup"` and `"tagged"` mode a
variable with recodes gets a value-label set without the codes recoded
away; a code recoded to a letter (`.a`, whether the setup wrote it or
`"tagged"` chose it) has its label moved to that letter, and a code
recoded to `.` loses its label (Stata cannot label `.`). A code recoded
to a letter with no label gets its number as label text (`"9"`), so the
code can always be read back. Codes sent to the same letter share it,
their labels joined with `" / "` in code order. So no label names a
value the column can no longer hold, and no letter is unlabelled. A
recoded variable with no `FORMAT` whose letters need labels gets a set
of its own, based on the variable's name.

Derived sets are shared when identical. Every `VALUE` name in the setup
is reserved first. Then, in column order, the first variable with a
given set (original or derived) keeps its base name (the format's, or
the variable's when it has none); a different set from the same base
takes the first unreserved name of `<base>_2`, `<base>_3`, ... (the base
shortened so the name fits in 32 characters). Sets no variable uses are
not written.

### Bindings

Each language gets one function, `read_fixed_width`, that converts to a
temporary `.dta` file, reads it with the language's own `read_dta`, and
removes the file:

| language | call |
|---|---|
| R (dtaparser) | `read_fixed_width(file, setup, recodes = c("setup", "tagged", "none"), col_select = NULL, skip = 0, n_max = Inf, factors = recodes != "tagged", warn_extended_missing = TRUE, commented_formats = TRUE)` |
| Python | `dta_parser.read_fixed_width(path, setup, recodes="setup", columns=None, skip=0, n_max=None, commented_formats=True)` |
| Julia | `read_fixed_width(path, setup; recodes=:setup, cols=nothing, skip=0, n_max=nothing, commented_formats=true)` |

`setup` is one path or several (an R character vector, a Python list, a
Julia vector).

- R's `factors` defaults to `FALSE` with `recodes = "tagged"`
  (`recodes <- match.arg(recodes)` runs before `factors` is used), so asking
  for labelled missings gets them: numbers, tagged NAs and a `labels`
  attribute naming both. An explicit `factors = TRUE` is honoured
  (letters become plain `NA` with dtaparser's warning).
- `skip` and `n_max` apply to the converted file: the whole data file is
  converted first. `encoding` and `dates` are not offered: the file is
  release 118 (no encoding choice) and has no date formats.
- Warnings: R raises one classed warning (`dtaparser_fixed_width_warning`)
  with the first 8 messages, each cut to 100 characters, as lines and a
  count of the rest, under R's `warning.length`; Python one
  `warnings.warn` with a `FixedWidthWarning` category (exported and
  documented), same content; Julia one `@warn`, same.
  The full list is the `warnings` attribute (R), `df.attrs["warnings"]`
  (Python) and table metadata `"warnings"` (Julia).
- Errors carry the setup file's line number or the data file's record
  number.
- The temporary file: each binding makes a private temporary directory
  (R `tempfile()` then `dir.create(mode = "0700")`; Python
  `tempfile.TemporaryDirectory`; Julia `mktempdir`), and the binding's
  Rust code creates `data.dta` in it with `create_new` (mode 0600 on
  Unix). The
  directory is removed on success, error and interrupt (`on.exit`,
  the context manager, `try/finally`). It needs disk about the size of
  the result's numbers; memory peaks at the data file plus the record
  offsets plus the string columns' text plus what `read_dta` returns.

Plumbing: R's bridge (`r/dtaparser/src/rust/lib.rs`, with its C entry
in `init.c`) and the Python extension (`python/src/lib.rs`) each get one
function taking the data path, the setup paths, the output path, the
mode and `commented_formats`, and returning the warnings. Julia gets a
C function in `crates/dta-ffi/src/native.rs`, declared in
`crates/dta-ffi/include/dta.h`: `dta_fixed_width_to_dta(data_path,
setup_paths, n_setups, out_path, recodes, commented_formats,
warnings_json_out, err, err_len)` (ABI version 3; it was 2 with one
setup path and no `commented_formats`).
Julia's `lib.jl` looks up every symbol before it checks the ABI version,
so a stale library would fail with a raw `dlsym` error: the ABI version
goes to 2 in `native.rs`, `include/dta.h` and `lib.jl`, and `lib.jl`
checks the version before looking up the other symbols. dtaparser's committed copy of
the core (`r/dtaparser/src/rust/dta`) is refreshed by its `configure`
and committed.

Not in this plan: dtatools (it can read the converted file through
dtaparser later), the npm package, Stata `.dct` dictionaries and SPSS
`.sps` syntax (the parser produces a layout a second front end could
produce too), and a public function that keeps the `.dta` file.

### ADR 0018

"Fixed-width files are read by converting them to a release 118 file":
the choice above, against (a) a column builder per language (three more
code paths for types, labels and letters, which the existing readers
already get right) and (b) reading from memory through a `Reader<Bytes>`
(every binding's reader type is `Reader<FileSource>`; generalising it
touches every read path for a feature that reads each file once). The
cost is one write and one read of a temporary file, measured for the PR.
It records the letter rule of `"tagged"` and the 320-byte labels of the
temporary file.

### Docs

- `CONTEXT.md`: **Setup file** (a SAS program giving each variable's
  columns, label and value labels for a fixed-width file),
  **Missing-value recode** (a setup statement that turns a code into a
  missing value).
- One section on each language page (`docs/r.md`, `docs/python.md`,
  `docs/julia.md`), "Fixed-width files with a SAS setup file", whose
  first block writes a small `.sas` and `.dat`; later blocks read them
  in each `recodes` mode. They run in each language's docs test.
- README: one line in the feature list.
- ADR 0005 and `compat/README.md`: asciiSetupReader as the oracle for
  fixed-width reads, with its limits. `docs/other-readers.md`: the
  ReadStat and asciiSetupReader limits above, as limits.

## Tests

Expected values come from open-source readers (AGENTS.md); none comes
from Stata, its output or its documentation. For setup mode they are
what asciiSetupReader 3.0.0 (MIT) reads. For `"tagged"` mode they are
asciiSetupReader's codes, read through the setup without its recodes,
made into haven tagged NAs in the order asciiSetupReader's
`parse_setup()` lists each variable's recodes, with their labels on the
letters (`compat/fixed_width/expected_fixed_width.R`). What no open-source reader does (the letters of `"tagged"`,
the 1973 assignments, repeated names) is this plan's own behaviour, and
the tests assert it as specified here; the files that behaviour writes
are then read by haven, readstata13, pandas and pyreadstat. No expected
value comes from Stata, its output or its documentation.

1. **Rust** (`crates/dta/tests/fixed_width.rs`), on setups and data
   written in the test, each read back with `Reader`: the tokenizer
   cases in the survey table (CRLF, tabs, `/* */` inside `INPUT`, stray
   `*/`, quoted `;`, `''`, double quotes, `LABEL` without `=`, `run;`
   before `DATA`, lowercase); negative keys; skipped ranges and `$`
   formats with warnings; `$` fields; single columns and ranges;
   overlapping columns; repeated names with the same and different
   columns; record-type selection with each operator and a blank type;
   `RECFM=F` with no line breaks and a short last record; CRLF and LF;
   lines shorter and longer than `LRECL`; the short-record and
   no-record warnings; blank and `.` fields; a non-number field;
   storage-type boundaries (100 byte, 101 int, 32,740 int, 32,741 long,
   1.5 double) and a type that changes with the mode; each `recodes`
   mode; letter order, setup-written letters, two codes to one letter,
   an unlabelled recoded code, more than 26 letters; derived and shared
   sets and their names; the 1973-style override and `INPUT(...)`; an
   unsupported data-step order; a 200-character label; every error.
2. **Oracle fixture** (`compat/fixed_width/`): `make_fixed_width.R`
   writes a synthetic setup in CDC's style (200 rows, 30 variables,
   value labels, recodes, one string, overlapping columns; no
   record-type selection, which the oracle cannot read) and its data
   from a fixed seed; `expected_fixed_width.R` reads it with asciiSetupReader
   and stores values, labels and value labels in
   `compat/expected/fixed_width.json`, with the `"tagged"` values made
   from them with haven. The Rust tests compare setup and tagged mode.
   Committed, so CI needs no R for it.
   **Tagged mode readback**: R's tests convert the same fixture in
   `"tagged"` mode (through the internal `dtaparser:::fixed_width_to_dta`)
   and read the `.dta` with haven (`na_tag()` and `labels`) and
   readstata13; Python's tests read it with pandas and pyreadstat
   (missing codes and value labels), as `python/tests/test_compat.py`
   does. That checks letters, their value labels, a value-label set
   without the recoded codes and a 200-character label with readers
   independent of ours. (The Rust tests cover shared and renamed
   derived sets and 320-byte labels.)
3. **Bindings**: R (testthat), Python (pytest) and Julia read one small
   fixture in each mode and check types, `NA` positions, letters
   (`haven::na_tag`, `missing.a`, `stata_code`), a column with both
   ordinary labels and recoded values, R's `factors` default per mode,
   a 200-character label, that warnings surface, and that a failed read
   leaves no temporary file.
4. **Docs**: the new sections run in each docs test.
5. **Real NSFG, local only** (`scripts/check-nsfg.R`, given the data and
   setup directories): reads all nine files with dtaparser in setup mode
   and with asciiSetupReader and compares row counts, column names,
   every value, variable labels and value labels. For inputs
   asciiSetupReader cannot read, the script gives it equivalent ones:
   1988's data with a line break after every 3,553 bytes; for 1976 and
   1982 the lines of the wanted record type, with a copy of the setup
   whose selection statement becomes a plain `INPUT rec_type cols` spec
   at the front of the `INPUT`, so both readers return `rec_type`. It
   asserts the kept record counts (1973 9,797; 1976 8,611 respondent and
   23,042 pregnancy; 1982 7,969 and 13,768; 1988 8,450 and 15,759; 1995
   10,847 and 21,332) and the column counts after merging repeated
   names. Known exclusions, listed in the script: 1973's `temp_NLAMOUNT`
   override and `H_FINC_NLAMOUNT` (asciiSetupReader does not run them;
   checked against the setup's own statements instead), and repeated
   names and overlapping columns wherever asciiSetupReader reads them
   differently (each such difference listed, not skipped silently). It also times conversion
   and read for each file. Run for the PR and reported there, not in CI
   (the data is not ours to commit).

## Later cycles (2002 to 2017-2019)

CDC's setups for the 2002, 2006-2010, 2011-2013, 2013-2015, 2015-2017
and 2017-2019 female respondent and pregnancy files use the statements
above, with three differences.

- **Several files.** 2002 splits each setup in three:
  `2002FemPregInput.sas` (`FILENAME`, `libname`, `%LET`, `DATA
  &dataset;`, `INFILE`, `INPUT`, `RUN;`), `2002FemPregVarLabel.sas`
  (`LABEL`, with `/* SECTION B */` comments inside it) and
  `2002FemPregValueLabel.sas` (`PROC FORMAT; VALUE ...; RUN;` then
  `FORMAT ...; RUN;`); the same for FemResp. `setup` takes the files in
  that order. Each file is split into statements on its own (a
  statement may not run from one file into the next) and the
  statements are then read in order as one setup. With several files,
  messages say `file 2 line 8` where one file says `line 8`.
  The `FORMAT` comes after the `RUN` of a `PROC FORMAT` step, outside
  any step. So once a `DATA` statement has been read, a `LABEL` or
  `FORMAT` outside any step (after a `RUN`, not inside `PROC FORMAT` or
  another `PROC`) applies to the DATA step's variables.
- **Commented-out formats.** From 2006-2010 on, the header says that
  "Sections for PROC FORMAT and FORMAT have been commented out": a line
  `/*` before `PROC FORMAT;` and a line `*/` after its last `VALUE` (or
  its `QUIT;`), and the same around `FORMAT ... ;`. CDC does this so
  that SAS users without CDC's format catalog can run the file as
  published; the value labels are all there. With `commented_formats`
  (the default), a block comment that starts between statements is
  read as code when its text, ignoring whitespace, ends in `;`, splits
  into statements without error, and is either `PROC FORMAT ...;`
  followed by one or more `VALUE` statements and at most a final `RUN;`
  or `QUIT;`, or one `FORMAT` statement that names at least one
  variable and format. Any other comment, such as the header that
  mentions `PROC FORMAT` in prose, stays a comment. Turned off, every
  comment is a comment and those files have no value labels.
- **Stray quotes in labels.** The 2006-2010 to 2017-2019 FemResp setups
  have labels with quotes inside them, such as
  `SALMX1 = "FLAG INDICATING WHETHER " SAME AS LAST MONTH" WAS ORIGINAL ANSWER ..."`
  and `STRLOPER = "... OPERATION "IN EFFECT" (RECODE)"` (98 labels in
  each of 2011-2013, 2013-2015 and 2015-2017), and
  `RING = "... RING OR "NuvaRing"?"` (in each from 2006-2010 to
  2017-2019).
  SAS ends the string at the second quote, and so did this reader,
  which then failed on `SAME`. Now, when a label's string is followed
  on its line by words and strings, the last a string, up to the next
  `name =` or the statement's end, the label is the setup's text from
  its first quote to its last, with a warning (`LabelQuotes`) naming
  the line. (ADR 0030 drops the warning.) Words and strings that are all `name 'text'` pairs naming
  variables already defined stay labels without `=` (1995FemResp has
  such labels on lines of their own). Anything else after a label is
  still an error.

Encodings, `INPUT`, `INFILE` and the data files need nothing new
(2006-2010 FemPreg's setup is windows-1252 text; the others are ASCII,
with CRLF lines until 2011-2013 and LF after). The `LENGTH` statement
of 2006-2010 on is skipped with a warning, as before. (ADR 0030 skips
a `LENGTH` for numbers without one.)

## Proof for the PR

CI green (Rust, R, Python, Julia, docs); `scripts/check-nsfg.R` output
for all nine files with timings.
