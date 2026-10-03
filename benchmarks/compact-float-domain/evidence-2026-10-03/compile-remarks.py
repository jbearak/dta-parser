"""Compile a private diagnostic object with the actual release flags plus remarks."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = Path('<repository>')
BUILD = HERE / 'candidate-final-v1'
OUT = HERE / 'release-remarks-v1'
PIN = '452ac7232ef6e47c398bcd22c7bb2800b55932c3'
RECORDER = ROOT / 'benchmarks/native-operations/run.py'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

spec = importlib.util.spec_from_file_location('records', RECORDER)
records = importlib.util.module_from_spec(spec)
spec.loader.exec_module(records)
before = records.inventory(BUILD, 'baseline')
require(before['receipt']['base_commit'] == PIN, 'Wrong candidate source')
OUT.mkdir(exist_ok=False)
src = BUILD / 'build/src'
lines = [line for line in (BUILD / 'build.log').read_text().splitlines()
         if ' -c numeric-payload.c -o numeric-payload.o' in line]
require(len(lines) == 1, 'Nonunique actual compile command')
command = shlex.split(lines[0])
command[0] = shutil.which(command[0])
require(command[0] is not None, 'Compiler unavailable')
command[command.index('-o') + 1] = str(OUT / 'numeric-payload-remarks.o')
command += ['-Rpass=loop-vectorize', '-Rpass-missed=loop-vectorize',
            '-Rpass-analysis=loop-vectorize']
inputs = {p.name: sha(p) for p in src.glob('*') if p.suffix in ('.c', '.h')}
tool_sha = sha(command[0])
controller_sha = sha(__file__)
with (OUT / 'remarks.log').open('w') as log:
    result = subprocess.run(command, cwd=src, stdout=log, stderr=subprocess.STDOUT)
require(result.returncode == 0, 'Remark compilation failed')
require(inputs == {name: sha(src / name) for name in inputs}, 'Consumed inputs changed')
require(tool_sha == sha(command[0]) and controller_sha == sha(__file__), 'Compiler/controller changed')
require(before == records.inventory(BUILD, 'baseline'), 'Original build inputs changed')
record = dict(status='PASS', source_commit=PIN, build_receipt_sha256=before['receipt_sha256'],
    controller_sha256=controller_sha, compiler_sha256=tool_sha,
    actual_build_command=lines[0], diagnostic_command=command, cwd=str(src),
    source_sha256=inputs,
    artifacts={p.name: sha(p) for p in OUT.iterdir() if p.is_file()},
    scope='Same release compilation flags with only output path and vectorizer diagnostics changed. This private object is never loaded or timed; installed-DLL extraction is separately bound.')
(OUT / 'binding.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
print('PASS release-flag vectorizer diagnostic binding')
