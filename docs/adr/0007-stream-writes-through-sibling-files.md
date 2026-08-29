---
status: superseded by ADR-0011
---

# Stream writes through sibling files

`save_dta()` validates and plans the complete input, emits aggregated conversion warnings, and then streams row-major DTA data through a seekable sibling temporary file. The Rust writer retains schema metadata and `strL` deduplication indexes rather than buffering the complete output. It runs serially and polls for R interruption during validation and writing.

The seekable file lets the writer backpatch the DTA section map after recording actual offsets. Closing and atomically renaming a sibling temporary file keeps an existing destination intact after validation, serialization, interruption, or I/O failures reported before replacement. The contract excludes delayed close or writeback failures and crash durability. The R interface replaces regular files, preserves existing permissions where supported, and rejects directories, symbolic links, and other non-regular filesystem entries.
