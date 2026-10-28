# Text in files before release 118 is read as Windows-1252

Releases before 118 do not say how their text is encoded. We decode it as
Windows-1252 by default, as haven (through ReadStat) does, so `read_dta`
agrees with haven. Latin-1 and UTF-8 are options. pandas assumes Latin-1.
The two differ only for bytes 0x80 to 0x9F, which Latin-1 maps to control
characters that hardly ever appear in real text, whereas Windows-1252 maps
them to curly quotes, dashes and the euro sign. Release 118 and later are
always UTF-8. Invalid UTF-8 there is replaced with U+FFFD rather than being
an error.
