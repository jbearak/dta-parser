# R package repository

The CRAN-style repository at <https://jbearak.github.io/dta-parser/> hosts the
latest stable `dtatools` release independently of CRAN.

```r
install.packages("dtatools", repos = c(
  dtatools = "https://jbearak.github.io/dta-parser",
  CRAN = "https://cloud.r-project.org"
))
```

Keep CRAN in the repository list so R can install dependencies. To include
dtatools in future `install.packages()` and `update.packages()` calls, add this
to `~/.Rprofile`:

```r
options(repos = c(
  dtatools = "https://jbearak.github.io/dta-parser",
  CRAN = "https://cloud.r-project.org"
))
```

## Available packages

The package requires R >= 4.6.0. v0.8.0 includes source and binaries built with
R 4.6.1. R selects Windows x86_64 and Apple Silicon macOS 14 or later binaries from the
repository's R 4.6 directories. Intel Macs and Linux use source by default.
Source installation needs Cargo and Rust >= 1.98.0, plus the platform's R build
tools. Use `type = "source"` to request source explicitly.

The Linux x86_64 binary is also hosted as a direct download linked from the
repository page. It is an installed package from the GitHub Actions Ubuntu
runner and requires compatible R and system libraries. Download it and use
`R CMD INSTALL /path/to/archive.tar.gz` on a compatible system. It is not
advertised as a portable binary through `install.packages()`.

The source index is at `src/contrib/PACKAGES`. Binary indexes are at
`bin/windows/contrib/4.6/PACKAGES` and
`bin/macosx/sonoma-arm64/contrib/4.6/PACKAGES`, with a matching
`bin/macosx/big-sur-arm64/contrib/4.6/PACKAGES` index for R builds using that path.
Both macOS paths require macOS 14 or later, matching the
[R 4.6 ARM64 distribution](https://cran.r-project.org/bin/macosx/).
Each index also has compressed
`PACKAGES.gz` and `PACKAGES.rds` forms, generated with R's
[`tools::write_PACKAGES()`](https://stat.ethz.ch/R-manual/R-devel/library/tools/html/writePACKAGES.html).

## Publishing

Publish a GitHub release to run **Attach compiled R packages**. That workflow
builds and smoke-tests all three binaries, checks the source archive, and
attaches source and binary archives to the release. Its successful completion
triggers **Publish R package repository**, which downloads the latest stable
release, checks its version and required assets, generates indexes, and deploys
them to GitHub Pages. A failed build leaves the deployed repository intact.

The publishing workflow always selects GitHub's latest stable release, even
when the binary workflow rebuilds an older tag. Prereleases are excluded.
Pages hosts only the latest stable version; older assets stay on GitHub Releases.
Set the intended release as latest when publishing a new stable version.

To republish indexes after replacing release assets, run:

```sh
gh workflow run publish-r-repository.yml --repo jbearak/dta-parser
```

GitHub Pages must use GitHub Actions as its build source. Deployment uses the
repository's `GITHUB_TOKEN` and the `github-pages` environment, with no personal
access token or separate hosting repository. The npm workflow remains separate.

To generate the repository locally with downloaded release assets:

```sh
gh release download v0.8.0 --pattern 'dtatools_*' --dir release-assets
Rscript --vanilla scripts/build-r-repository.R release-assets public 0.8.0
```
