# `dtatools` name availability

Checked on 2026-08-28 against the official registry and hosting services.

## Recommendation

Use these names:

| Public surface | Name | Finding |
| --- | --- | --- |
| CRAN | `dtatools` | No current or archived collision found. |
| crates.io | `dta-tools` | No crate record found. |
| npm | `@jbearak/dta-tools` | No package record found in the existing `@jbearak` scope. |
| GitHub | `jbearak/dta-tools` | No repository visible to the authenticated owner account. |

All four names appear available. None of these checks reserves a name. Publication, CRAN review, or a repository rename still has to succeed, and another party could claim an unscoped name first.

## Registry checks

### R and CRAN

The proposed R package name is `dtatools`. CRAN's official [active package index](https://cran.r-project.org/src/contrib/PACKAGES.gz) contained no exact or case-only match. The candidate [package page](https://cran.r-project.org/web/packages/dtatools/index.html) and [archive directory](https://cran.r-project.org/src/contrib/Archive/dtatools/) both returned HTTP 404. The archive index also contained no case-only match.

Result: no current or previously archived CRAN package named `dtatools` was found. The name appears available for a new submission, subject to CRAN's normal review.

### Rust and crates.io

The proposed Rust package name is `dta-tools`. The [crates.io API](https://crates.io/api/v1/crates/dta-tools) returned HTTP 404 with `crate dta-tools does not exist`. The API also returned 404 for `dta_tools`. That second check matters because [crates.io prevents names that differ only by hyphen and underscore](https://doc.rust-lang.org/cargo/reference/registry-index.html#name-restrictions).

Result: no conflicting crates.io record was found. The crate is only a prospective publication target today. Its [manifest](../../r-package/dtatools/src/dta-tools/Cargo.toml) sets `publish = false`.

### TypeScript and npm

The convention-matching npm name is `@jbearak/dta-tools`. The existing [npm package record](https://registry.npmjs.org/%40jbearak%2Fdta-parser/latest) establishes the `@jbearak/` owner scope, and the repository's [package manifest](../../typescript/dta-tools/package.json) retains the scoped, hyphenated form. [npm scopes](https://docs.npmjs.com/about-scopes/) are owner namespaces.

The official [registry endpoint for `@jbearak/dta-tools`](https://registry.npmjs.org/%40jbearak%2Fdta-tools) returned HTTP 404. The unscoped `dta-tools` and `dtatools` forms also returned 404, but neither matches the repository's established npm convention.

Result: `@jbearak/dta-tools` appears available and is the recommended TypeScript package name.

### GitHub repository

An authenticated owner-visible request to the [GitHub repository endpoint](https://api.github.com/repos/jbearak/dta-tools) returned HTTP 404. Exact-name repositories exist under other owners, as shown by the [GitHub repository search API](https://api.github.com/search/repositories?q=dta-tools%20in%3Aname&per_page=100), but they do not occupy the owner-scoped `jbearak/dta-tools` path.

Result: the `jbearak/dta-tools` repository path appears available. This is independent of the crates.io package name. Creating one does not reserve the other.

## Publication surfaces found in this repository

The repository's [`publish.yml`](../../.github/workflows/publish.yml) targets npm. It distributes compiled R packages as GitHub Release assets through [`release-r-packages.yml`](../../.github/workflows/release-r-packages.yml). GitHub Releases inherit the repository path and do not introduce another package name to reserve. No CRAN or crates.io publication workflow is present, but both names were checked because the rename proposal identifies them as possible public package targets.
