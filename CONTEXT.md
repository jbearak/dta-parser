# dta-parser

dta-parser provides TypeScript and R libraries that read Stata DTA files without collapsing labels, display formats, long strings, or Stata missing codes.

## R package language

**Default Stata reader**:
The R package's intended role for DTA imports, including in projects that use haven for file writing or other statistical formats.
_Avoid_: Large-file fallback, Haven replacement

**Haven-compatible read**:
A DTA read that accepts haven's common read arguments and returns equivalent values, labels, dates, and missing codes for valid supported inputs. It does not promise identical validation or encoding behavior.
_Avoid_: Drop-in replacement

**Tag-preserving recode**:
A recode that changes matched values while retaining each unmatched system or extended missing code.
_Avoid_: Missing-value-safe recode

**Label-aware tabulation**:
A frequency table that uses Stata value labels and, when requested, keeps system missing, extended missing codes, and R `NaN` as distinct categories.
_Avoid_: Safe tabulation
