# Checks

`ci.yml` runs three quick jobs on source and workflow changes: TypeScript
typechecking/tests/build, one stable Rust library check, and Python source,
vendor-integrity and collector guards. It does not install R or Arrow, rebuild
archives, replay benchmark evidence or run a platform/dependency matrix.
New commits cancel obsolete CI runs. Job timeouts are 5, 8 and 3 minutes.

Use fast local tests for the code being changed. After installing a modified R
package once, reuse that installation for the relevant test files, for example:

```sh
Rscript --vanilla -e 'testthat::test_dir("r-package/dtatools/tests/testthat", filter = "compact-float-domain", package = "dtatools", load_package = "installed", stop_on_failure = TRUE)'
```

`full-compatibility.yml` is optional and runs only through **Run workflow**.
Choose one suite for a focused investigation, or explicitly choose `all` for
the full OS, R version and dependency matrix. The default is the short
TypeScript suite. It is not a PR or release requirement. Requested R package
and present suites fail if their declared dependencies cannot be loaded.
Expanded deterministic fuzz tests run inside the Rust suite, sharing its build.

The publishing workflows keep their own short product checks. R releases build
each platform once, reuse compiled runtime dependency libraries across release
tags, and smoke-test the produced binary. They do not install Arrow/test
dependencies or repeat full source/binary suites. Full C++ CodeQL runs locally
only, as described in [the CodeQL instructions](../codeql/README.md).
