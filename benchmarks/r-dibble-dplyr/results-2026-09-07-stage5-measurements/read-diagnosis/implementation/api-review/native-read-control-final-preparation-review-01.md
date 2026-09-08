# Native read control final preparation review

Clear for the future coordinated control run. The accepted-build rebinding finding is fixed in read-control-v2.py: receipt and manifest identities are frozen before parsing, parsed bytes must match them, accepted product/build-input records are preserved, runtime identities must match those exact records, and both sets are guarded before launch and in finally. The eight retained helper guard tests pass with four bound inputs and three products (receipt f2963685ea6aa2c2c9c17b258c8087fa6101a9d971fa93c2e3bb0e48cb8d8471).

The final v5 build receipt a90771dd5c644160a2afe0bcce66f9bbf8d381ffe1d0987b5e1470125624cd74 matches all eight products and 192 compile inputs. Fifty-eight preparation inputs include the compiler, explicit linker, resolved MacOSX26.5 SDK settings, libSystem stubs and compiler runtime archive. All 135 dependency entries from discovery match the actual compilation dependency file and the precompile inventory. Both commands pass without build/discovery diagnostics. The precise registration-cast warning exception accommodates R's registered-call function pointer representation; other enabled warnings remain errors.

Read-only Mach-O inspection shows only the DLL install name and /usr/lib/libSystem.B.dylib, with unresolved public R API symbols and dyld_stub_binder. No second libR is linked. The C and R source hashes are unchanged from the original reviewed control: rooted nonescaping public API loops bounded to one million values, ordinary/package-owned empty and NA checks, separate untimed native visits, four public/native operations, and value/metadata/backing/native-counter guards. No R or native control timing was executed by this reviewer. Runtime success, actual loaded namespace/DLL coverage and final raw outputs still require their own completed-run audit.

All four failed builders and their products remain attributed to their failures: missing SDK headers, deprecated linker-path flag, registration cast warning, and missing libSystem linkage. V1 failed discovery before persisting its five in-memory input records; its narrower retained evidence is commands/error/products/receipt, not a complete pre-input inventory. V2-v4 retain 140 compile inputs and six preparation inputs. No history was relabeled or overwritten.

The first independent final-build checker assumed the libSystem alias appeared in the resolved-path set. It actually resolves to libSystem.B.tbd. The preserved -02 checker corrects that alias expectation and passes; -01 source/failure remains a reviewer artifact. This changed no build or runtime evidence.

Full compiler/OS/dylib/Python closures remain excluded. Guard tests exercise artifact-binding helpers rather than an end-to-end R run. Native pointer/per-element comparisons cannot establish an exclusive internal cause for base anyNA timing. No performance acceptance or irreducibility claim follows from preparation.

Artifacts:

- audit-native-read-control-final-preparation-02.py: 1f0432c3dd008100ade8dc207cce57ffff58ee310186eb6f87daab10cf68bd26
- audit-native-read-control-final-preparation-02.json: 2fa3b4fe50048b73830aa41484e37a2c21c7536287b0f35fde3313a614903623
