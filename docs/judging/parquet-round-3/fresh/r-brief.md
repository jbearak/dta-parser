You are checking whether a library's documentation is enough to use it. Your only source on how to use the library is the file /private/tmp/claude-501/gate2/fresh3/r/docs.md. Do not read the library's source code, tests, or any other file in the checkout except to build and install it; do not look anything up online.

The library is not published. Where the docs say to clone https://github.com/jbearak/dta-parser, use the copy at /private/tmp/claude-501/gate2/fresh3/r/checkout instead (do not edit its files; build outputs it creates are fine). Keep everything you install inside /private/tmp/claude-501/gate2/fresh3/r/scratch: install into a private library under /private/tmp/claude-501/gate2/fresh3/r/scratch (for example R_LIBS_USER=/private/tmp/claude-501/gate2/fresh3/r/scratch/lib, with that directory first in .libPaths()); packages already installed on the machine (rlang, tibble, arrow, ...) may be used.

Never run Stata, and never use or look for .dta or Parquet files you did not write yourself. Write every file you read: Parquet files with the library (and, for task 11, with another tool available on this machine), and the .dta file for tasks 6, 9 and 10 with the library's own .dta writer.

Do these eleven tasks in R:
1. Install the package(s) the docs say Parquet needs, and check that they load.
2. Write a small table with an integer, a floating-point, a text, a logical, a date and a timestamp column to Parquet; read the whole file back into the usual table type; report what type each column became.
3. Read only two of the columns, in the reverse of file order; report the order you get and what happens if you name a column that is not in the file.
4. Read rows 3 to 5 only, and report what happens when you ask for rows past the end.
5. Without reading the data, get the column names and types, the row count, the row groups, the compression and the key-value metadata.
6. Write a .dta file with a value-labelled numeric column and variable labels, bring it into Parquet as the docs show, and read the Parquet file: read a column's variable label and value labels, look up the text of one code, and turn the column into the language's categorical type.
7. Write and read back a date, a timestamp without a time zone and a timestamp with one; report what each becomes, the units and the time zone.
8. Write a table with a codec other than the default and a row group size you choose; check both in the file's metadata; try something the docs say is an error and report the error.
9. Write a variable label, value labels and a data label to a Parquet file and check them by reading back.
10. Make a numeric column holding ordinary values plus ., .a and .z (in the .dta file of task 6, or directly as the docs show); write it to Parquet, read it back and tell the three kinds apart per value; report what the docs say other tools see in place of .a to .z.
11. Read a Parquet file written by another tool on this machine (if none is available, say which you looked for); report what the docs say this library does not read.

Put your scripts in /private/tmp/claude-501/gate2/fresh3/r/scratch. Write a report to /private/tmp/claude-501/gate2/fresh3/r/scratch/report.md: for each task, succeeded / partly / failed, the code you ran, what you saw, and any place the docs were wrong, unclear or missing something (quote the docs). Reply with an eleven-line summary: task number, outcome, and the doc problem if any.
