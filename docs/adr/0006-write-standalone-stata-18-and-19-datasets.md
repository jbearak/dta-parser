---
status: accepted
---

# Write standalone Stata 18 and 19 datasets

`save_dta()` targets the Stata 18 and 19 applications while writing the ordinary standalone DTA layouts those applications use. Stata 18 targets are limited to 32,767 variables and release 118. Stata 19 targets use release 118 through that limit and release 119 for wider datasets. The writer does not emit legacy releases or the release 120/121 alias-variable layouts. This keeps it within the package's single-dataset model, although the resulting ordinary files may also open in older Stata versions.

The public R function uses a reusable Rust-core writer. Its round-trip promise covers the semantics represented by the R package, including dataset notes, rather than byte identity or source details the reader does not retain. Metadata outside Stata's documented limits fails validation before the destination is created or replaced; the writer does not truncate it.

The R interface uses `save_dta(data, path, version, label, strl_threshold, adjust_tz)`, following the argument shape of haven's `write_dta()`. It defaults to target version 19 and returns `data` invisibly. It accepts only target versions 18 and 19 and local filesystem paths. The Rust core uses a write-specific input model instead of parser output types that can contain projections and stale source offsets. R validates the complete input, writes through a sibling temporary file, and replaces the destination only after the writer closes the completed file.

A local write path whose final component has no extension receives `.dta`, with a warning that reports the actual destination. An extensionless local read path resolves to the corresponding `.dta` path even if an exact extensionless file exists. Explicit extensions remain unchanged, except that the writer rejects compression suffixes it does not implement. URLs, connections, raw inputs, and source objects retain their current read behavior.

Every file uses little-endian byte order and zero-filled padding so output does not depend on the writer's host. R factors export as value-labelled Stata `long` variables whose codes follow factor level order. One warning per `save_dta()` call identifies all converted factor columns because the R factor class and orderedness do not survive re-import.

The writer replaces unrepresentable numeric values with Stata system missing and `NA_character_` with the empty string. It emits at most one warning for each lossy conversion category, with affected columns and replacement counts. It preserves dataset notes but does not expose arbitrary Stata characteristics or use hidden characteristics to repair invalid variable names.

Bare logical, integer, and double columns use Stata `byte`, `long`, and `double` storage respectively; declared `stata.storage` metadata takes precedence. The writer preserves compatible display formats and temporal metadata, infers fixed or long string storage from UTF-8 byte lengths and `strl_threshold`, and rejects unsupported R classes or invalid Stata names rather than reinterpret them.
