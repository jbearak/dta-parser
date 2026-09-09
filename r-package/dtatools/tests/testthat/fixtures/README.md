# Ordinary dplyr group fixtures

`dplyr-groups.rds` contains a finite registry of ordinary grouped and rowwise frames produced by real dplyr. It lets native dtatools tests run when dplyr is physically absent. The optional tests retain their live dplyr calls and dynamic comparisons.

The inputs are synthetic cases from this package's tests and the repository's `auto_v118.dta`. The registry contains no code or data from other repositories. `inst/NOTICE` records the upstream test adaptations.

Each entry records the original plain input specification, column structure, actual grouping metadata, and any expected operation results. Specifications retain raw double payloads, character bytes and encodings, attributes, factor levels, row names and column order. Group records retain ordered keys, memberships, the integer `.rows` prototype and `.drop`. Small cases check literal memberships and selected key positions. Factor expansion and row-operation expectations come from real dplyr. The large ASCII case checks arithmetic memberships.

The helper rereads the RDS for every lookup. A test needing a dibble calls `as_dibble(entry$data)` and assigns `reserve_columns()` where necessary. Serialization supplies semantic input; it does not prove ownership or later-write isolation. Tests of ownership, foreign writes and callbacks construct fresh columns locally. They compute the plain specification before capture or arming callbacks. `.group_fixture_attach()` checks that specification and the new frame's structure without reading its column payloads. Its optional groups override requires reviewed correspondence to the safe input. Deliberately malformed metadata is applied afterward.

Complex legacy-locale fixtures use `LC_COLLATE=C`, and their consumers set the same locale. Present tests also compare the original ambient-locale dplyr behavior. A separate native string-order test uses a base R expectation in the current locale.

To regenerate, install the intended dtatools candidate and dplyr 1.2.1 or later into the selected R library, then run the producer in a fresh process from the repository root. Both output paths must be new:

```sh
Rscript --vanilla scripts/prepare-dplyr-group-fixtures.R \
  "$PWD" /tmp/dplyr-groups-new.rds /tmp/dplyr-groups-provenance-new.R \
  /path/to/selected/library/dtatools
```

Review the producer and consumer changes together. Record the producer/helper and repository input hashes, the installed package identity, R version, selected libraries, command, status and output hashes. The producer writes package paths, versions, namespace/DLL observations and session information to the separate provenance file. Replace the committed RDS only after successful generation, then run the fixture consumers in a fresh process whose visible libraries contain no dplyr. Keep failed generation attempts separately.

The committed registry has 133 cases. It was generated with R 4.6.1, dplyr 1.2.1, tibble 3.3.1, vctrs 0.7.3 and dtatools source `10736b58a1a7eaea77bfb5b9d542b33a079c8bd1`, package tree `5f48073adecd21e5720021c451739142ac4ee89a`. Generation returned zero and its bound inputs were unchanged. Its SHA256 identities are:

| Artifact | SHA256 |
| --- | --- |
| Producer | `da1dfc1c8977c51520a674b5b0b016f32436446e670384d01cd01a03eb7a22bc` |
| Helper | `f5df3c768932a1f55cdf8aa42c908a0d982773bc5209a84c8f3c2af394fc7a36` |
| Repository auto fixture | `cb1b1668a946288ef312d06f90f62da2ac550b8a7ef8b0e95d7b3ac7ada80a4c` |
| Registry | `dc503758cc22ce467b0693a607cd435e98c79643037f507c735c7f9214a97121` |
