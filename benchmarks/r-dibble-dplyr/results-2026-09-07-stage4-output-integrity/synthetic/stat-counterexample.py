"""Demonstrate the historical stat-only gap using an exclusive tiny fixture.

This never opens the real fertility output or runs R. It changes eight synthetic
bytes, restores their mtime, and compares the old metadata predicate with SHA256.
"""
from pathlib import Path
import hashlib,json,os
root=Path('/private/tmp/dta-direct-stage4-validation/review-fix-final-review/output-integrity/stat-counterexample')
root.mkdir()
fixture=root/'fixture.bin'
fixture.write_bytes(b'original')
saved=fixture.stat()
before={'size':saved.st_size,'mtime_ns':saved.st_mtime_ns,'sha256':hashlib.sha256(fixture.read_bytes()).hexdigest()}
fixture.write_bytes(b'modified')
os.utime(fixture,ns=(saved.st_atime_ns,saved.st_mtime_ns))
after_stat=fixture.stat()
after={'size':after_stat.st_size,'mtime_ns':after_stat.st_mtime_ns,'sha256':hashlib.sha256(fixture.read_bytes()).hexdigest()}
old_accept=all(before[x]==after[x] for x in ['size','mtime_ns'])
new_accept=before['sha256']==after['sha256']
if not old_accept or new_accept:
    raise RuntimeError('Counterexample did not demonstrate the expected gap')
result={'before':before,'after':after,'stat_only_would_accept':old_accept,'digest_equality_would_accept':new_accept,
        'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'scope':'Eight-byte synthetic fixture only; no real output, fertility project, package, R, benchmark or historical evidence was accessed or changed.'}
with (root/'result.json').open('x') as f:json.dump(result,f,indent=2);f.write('\n')
print(json.dumps(result,indent=2))
