from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,difflib
root=Path('/private/tmp/dta-direct-stage5-validation/root-expression-performance');review=Path(__file__).parent
names=['atomic-read-setup-probe-v1.R','atomic-read-setup-probe-v1.py']
def identity(p):
 q=p.resolve(strict=True);s=q.stat();return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=hashlib.sha256(q.read_bytes()).hexdigest())
r=(root/names[0]).read_text();python=(root/names[1]).read_text();compile(python,str(root/names[1]),'exec')
assert r.count('if (setup == "rename")')==1 and 'invisible(dplyr::rename(atomic_fixture(kind, 4L), changed = c01))' in r
assert r.index('if (setup == "rename")')<r.index('data <- atomic_fixture(kind, rows, columns)')
assert 'bench::mark' not in r and 'system.time' not in r and 'system_time' not in r
assert r.index('file.path(output, "fork-metrics.csv")')<r.index('atomic_selector_gate(fork$metrics, kind, mode)')
assert r.index('file.path(output, "fork-states.rds")')<r.index('atomic_selector_gate(fork$metrics, kind, mode)')
assert r.index('file.path(output, "namespaces.tsv")')<r.index('atomic_selector_gate(fork$metrics, kind, mode)')
parent=review/'atomic-read-repeat-preparation-review-01.json';previous=json.loads(parent.read_text())
for x in previous['sources']+previous['helpers']:assert identity(Path(x['path']))==x
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='allocation_only_setup_probe_source_clear',reviewer_script=identity(Path(__file__)),sources=[identity(root/n) for n in names],prior_review=identity(parent),python_diff=''.join(difflib.unified_diff((root/'atomic-read-repeat-v1.py').read_text().splitlines(True),python.splitlines(True))),assessment='Actual first-case probe is clear as a controlled setup diagnosis. It keeps declared_character100k8columns, the unchanged atomic helpers/profiler/gate, independent ordinary anyNA oracle, original DTA/Arrow setup, source checks and scalar-state save. Both fresh-process modes omit bench timing; one extra checked anyNA is common. The sole conditional difference is one unprofiled rename on an independent4row default16column fixture before measured data exists. First actual result and profiled result stay alive through the selector. Fork allocation/scan metrics and source/result state plus namespace paths are saved before the unchanged gate, so a reproduced failure remains inspectable. Python alters only mode/script/environment/scope strings from the previously cleared driver; exact source/library/runtime bindings and failure receipts remain.',limits=['Preparation review only. No R command, profiler, fixture constructor, benchmark or probe was executed by reviewer. Root owns any quiet execution.','Cold must reproduce the same allocation-gate failure in this common timing-omitted minimization before the warm contrast is interpreted. A cold/warm difference supports the effect of this complete4row rename setup; it does not distinguish internal JIT, dispatch, metadata or other subcomponents without further evidence.','Unchanged atomic_profile returns summary metrics and discards raw Rprofmem events. The records must not be presented as allocation-stack evidence. Namespace coverage is retained before gate but automatic success-only coverage qualification remains false on an expected failure.','No production or old driver/evidence mutation. The original failing read record and passing full-matrix records remain separate. No performance or overall acceptance claim.'])
with (review/'atomic-read-setup-preparation-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(result['status'])
