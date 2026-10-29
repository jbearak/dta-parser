You are checking whether a library's documentation is enough to use it. Your only source on how to use the library is the file /private/tmp/claude-501/judging/round-1/fresh/typescript/docs.md. Do not read the library's source code, tests, or any other file in the repository; do not look anything up online.

The library is not published. Where the docs say to clone https://github.com/jbearak/dta-parser, use the existing checkout at /Users/jmb/repos/dta-parser.new/.claude/worktrees/agent-a2eb7dc5013b84836 instead (do not modify it; build outputs it creates are fine). Keep everything you install inside /private/tmp/claude-501/judging/round-1/fresh/typescript/scratch: make an npm project in /private/tmp/claude-501/judging/round-1/fresh/typescript/scratch and install into its node_modules.

Do these ten tasks in TypeScript (or JavaScript on Node), writing every .dta file you read yourself with the library (never use or look for other .dta files, and never run Stata):
1. Install the package and check that it loads.
2. Write a small table with an integer, a float, a text and a date column; read the whole file back into the usual table type; report what type each column became.
3. Read only two of the columns, in the reverse of file order; report the order you get and what happens if you name a column that is not in the file.
4. Read rows 3 to 5 only, and report what happens when you ask for rows past the end.
5. Get variable labels, the data label, display formats and storage types, and get them without reading the data.
6. Give a column a value label set; read it back, look up the text for one code, and turn the column into the language's categorical/labelled type.
7. Read the date column as a date; then read it with date conversion turned off.
8. Write a table and report which release was written and which storage type each column got; try something the docs say is an error and report the error.
9. Write a variable label, a value label set and a data label, and check them by reading back.
10. Make a numeric column holding ordinary values plus ., .a and .z; tell them apart per value after reading; filter and sort; write back and check the letters survive.

Put your scripts in /private/tmp/claude-501/judging/round-1/fresh/typescript/scratch. Write a report to /private/tmp/claude-501/judging/round-1/fresh/typescript/scratch/report.md: for each task, succeeded / partly / failed, the code you ran, what you saw, and any place the docs were wrong, unclear or missing something (quote the docs). Reply with a ten-line summary: task number, outcome, and the doc problem if any.
