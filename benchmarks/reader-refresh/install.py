#!/usr/bin/env python3
"""Install an experimental reader and bind its source tree to installed files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

source, library, record = [Path(value).resolve() for value in sys.argv[1:]]
library.mkdir(parents=True, exist_ok=False)
record.parent.mkdir(parents=True, exist_ok=True)

def git(*args):
    return subprocess.check_output(['git', *args], cwd=source, text=True).strip()

def clean():
    subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--', 'r-package/dtatools'],
                   cwd=source, check=True, stdout=subprocess.DEVNULL)

clean()
commit = git('rev-parse', 'HEAD')
tree = git('rev-parse', 'HEAD:r-package/dtatools')
log = record.with_suffix('.log')
env = {k: v for k, v in os.environ.items()
       if not k.startswith(('DTATOOLS_EXPERIMENT_', 'DTA_READ_PERF_'))}
command = ['R', 'CMD', 'INSTALL', '--preclean', '--install-tests',
           '--library=' + str(library), str(source / 'r-package/dtatools')]
with log.open('w') as stream:
    subprocess.run(command, env=env, cwd=source, stdout=stream,
                   stderr=subprocess.STDOUT, check=True)
clean()
assert git('rev-parse', 'HEAD') == commit, 'source commit changed during installation'
package = library / 'dtatools'
installed = {}
for path in sorted(package.rglob('*')):
    if path.is_file():
        installed[str(path.relative_to(package))] = hashlib.sha256(path.read_bytes()).hexdigest()
record.write_text(json.dumps(dict(source_commit=commit, package_tree=tree,
    installed=installed, command=command,
    install_log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()), indent=2) + '\n')
print(json.dumps(dict(source_commit=commit, library=str(library), record=str(record))))
