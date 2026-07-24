# dtaparser

`dtaparser` is an experimental R interface to the TypeScript dta-parser. It
runs the browser bundle inside a persistent in-process V8 context, so measured
reads do not include Node/Bun subprocess startup.

```r
data <- dtaparser::read_dta("data/example.dta")
dtaparser::dta_missing_tags(data$possibly_missing)
```

Install from the repository root after building the bundled JavaScript:

```sh
npm run build:r-package
R CMD INSTALL r-package/dtaparser
```

The function uses the same argument names as `haven::read_dta()` and returns a
tibble. The package is intended for integration and performance experiments.
It retains extended Stata missing tags in a
`dta_missing_tags` column attribute rather than using haven's tagged-NA bit
encoding.
