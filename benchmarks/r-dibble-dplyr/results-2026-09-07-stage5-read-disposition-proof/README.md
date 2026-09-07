# Read-cost disposition derivation records

These plain records support the Stage 5 read-cost research note and its plan
updates. They retain two bounded derivation checks, their 41-input records,
outputs and receipts, both versions of the prose, and the independent reviews.
The corrected prose is committed at `e23d9571af4c20e07901c7bb9499c626e3f342df`.
No package code or benchmark changed during this documentation work.

The first prose version needed two wording corrections: the ALTREP setter
registers a coercion method, and the 50 series/350 samples are per source.
Its original verification records remain intact. Both prose snapshots were
copied after their corresponding derivation checks and compared with the
original input identities. They preserve those bytes for later reading; they
do not reconstruct a pre-consumption binding for the snapshot operation.
Reviewer scripts and reports likewise retain their actual observation scope.

[selection.json](selection.json) lists the 26 original records.
[inclusion-manifest.json](inclusion-manifest.json) also binds this description,
the selection and the copy recipe. The copy checks retained receipt/product
chains and selected byte/mode consistency. It does not rerun the derivations or
revalidate their full original runtime inputs.

The separate measurement archive retains the primary-source preparation note,
identities and URLs, plus saved benchmark assessments. Actual external R source
copies, installed libraries and runtime/build trees are omitted. Absolute paths
identify the original environment. This is a selective archive, not a standalone
replay bundle. Historical plan-status statements describe their saved versions.
