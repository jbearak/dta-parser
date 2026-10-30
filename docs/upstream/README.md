# Upstream bug reports (drafts)

Drafts of reports for bugs our tests found in other libraries (the
`KNOWN` list in `crates/dta/tests/compat.rs`, and
[compat/README.md](../../compat/README.md)). **None has been filed.** Each was
reproduced on 2026-10-29 with haven 2.5.5, readstata13 0.11.0, pandas
3.1.0 and pyreadstat 1.3.7, and checked against the project's current
development branch. The reproductions make their own data, so they
don't depend on this repository's fixtures.

| Bug | Reproduced | Belongs to | Upstream status | Draft |
|---|---|---|---|---|
| haven misreads value labels in releases 104, 105 and 108 | yes | ReadStat (vendored by haven) | fixed in ReadStat `dev` (69d8f91) and haven `main` | [haven NEWS note](haven-news-stata-fixes.md) (optional) |
| haven drops trailing blanks from `str#` values | yes | ReadStat (vendored by haven) | fixed in ReadStat `dev` (725bb90) and haven `main` | same |
| haven writes (and reads) 119 strL references with the 118 layout | yes | ReadStat (vendored by haven) | fixed in ReadStat `dev` (69d8f91) and haven `main` | same |
| readstata13 reads an empty strL as `NA` | yes | readstata13 | open, no existing issue | [new issue](readstata13-empty-strl.md) |
| pandas decodes text before 118 as Latin-1, not Windows-1252 | yes | pandas | open, no existing issue | [new issue](pandas-stata-windows-1252.md) |

The three haven bugs are in the ReadStat code that haven 2.5.5 bundles.
ReadStat's `dev` branch fixed them in September 2026, and haven `main`
(66a332a, built and run here) includes those fixes, though they are not
yet in a CRAN release. So no bug report is needed; the draft only asks
haven to mention them in NEWS.

Every bug reproduced, so none was dropped.
