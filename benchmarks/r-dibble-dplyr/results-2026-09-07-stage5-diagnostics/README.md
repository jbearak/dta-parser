# Stage 5 implementation diagnostics

This selective archive preserves 174 observed files from implementation and
review, including failed attempts. The [inclusion manifest](inclusion-manifest.json)
maps each copy to its recorded source path, size, SHA-256 and mode at inclusion. Its
[receipt](inclusion-receipt.json) binds the completed manifest. The
[copy recipe](archive-diagnostics.py) checks both source and destination bytes.
This README and the two inclusion records are new; copied records are unchanged.

The preserved recipe follows file symlinks through `is_file()`, content reads
and `copy2()`, and checks only a lexical path relative to `origin`. It did not
reject symlinks or verify resolved-source containment. Its hashes and modes
identify the copied content at the listed paths; they do not establish that
every historical source was a non-symlink file physically beneath `origin`.
The recipe's records contain no resolved-source inventory. This limitation
cannot be repaired retrospectively by editing the executed recipe or inspecting
today's source tree. The recipe remains a historical copy record.

The development logs are diagnostics, not exact-source acceptance. They used
installed native code with working R overrides. Their working source was not
frozen for every attempt. The retained development scripts are the bytes
observed at inclusion and do not retroactively bind earlier executions.
Attempt 06 failed because its older installed namespace lacked new internal
functions used by the tests. Attempt 07 used the newer installed namespace and
passed with the four established warnings.

`candidate-27d700d` and `candidate-985e26b` preserve preliminary exact Git-archive
install records. The first installed focused attempt exposed warning-history
and metadata assumptions subsequently fixed. `focused-985e26b-01` passed 7,608
assertions, then its namespace reporter failed on the base namespace. Its
overall failure remains recorded. No later reporter fix changes that result.

`candidate-final-01` and `focused-final-01` use source `90375ec`, whose package
tree is `f6331813d211255b4c949e04f34ce74537b142e2`. The focused run passed 7,619
assertions with no failures or skips and four established warnings. A later
self-audit added an explicit Python executable binding to the installer and
check runner. These earlier records keep their original input scope. Fresh
source `4427a9b` installation and broad qualification are separate evidence.
The additive [focused Rscript provenance note](review-fixes/focused-rscript-provenance.json)
identifies the two Rscript candidates already present in the focused run's
original input inventory and the preceding preflight's runtime version. The
test launcher used the bare command `Rscript` without retaining a tool-name mapping or `PATH`.
Those candidate identities do not establish the executable selected at process
launch; that historical identity remains unresolved. The original command and
records are preserved, and no new run supplies a replacement historical identity.

The two review directories retain reproductions, comparisons and review
checkpoints selected when this archive was made. Source review is clean through
`4900dc8`. Selected preliminary runtime/performance driver findings and one
completed full-test output audit are included. Later driver fixes and final
qualification audits remain separate records. These checkpoints do not claim
final measured
acceptance or completion of external review and CI.

The preserved [installed API runner](api-review/run-installed-api-985e26b.py)
enumerated installed package files before execution, then re-read only the
paths in its [initial input record](api-review/installed-api-985e26b-output/inputs-before.json).
Its [empty change list](api-review/installed-api-985e26b-output/result.json)
covers byte/size comparisons for those entries. Added files are outside that
check; no complete post-run path set was retained for comparison. The recorded
success remains a bounded API and NOTICE-distribution result. It does not
certify unchanged membership of the installed package tree.

Source tarballs, expanded Git exports, installed libraries and build trees are
omitted from this readable archive. Their original identities remain in each
run's input and output indexes. Git source is identified by exact repository
commits; installed packages require rebuilding from those sources and the
recorded dependencies. The indexes are evidence inventories, not a standalone
replay bundle. Full OS, SDK and Python runtime closures were not frozen. Original
absolute-path scripts must not be run against this archive in place.

The [preparation archive](../results-2026-09-07-stage5-preparation/README.md)
preserves the helper proof and minimum-version research separately. Adapted
production source is attributed in the [installed NOTICE](../../../r-package/dtatools/inst/NOTICE).
Stage 5 acceptance, stages 6 through 9, the twelve open base-R read costs and the
three Stage 6 filter flags remain subject to their recorded gates.
