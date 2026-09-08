"""Run three paired pipeline repeats sequentially in a coordinated quiet window."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
PYTHON = Path('/Users/jmb/.pyenv/versions/3.14.7/bin/python3.14')
SOURCES = [
    ('baseline', 'f622f1ddba04b2bb7ac07415faccf2b417aab0e6',
     '/private/tmp/dta-direct-stage5-validation/root-baseline-f622f1d/library'),
    ('candidate', 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9',
     '/private/tmp/dta-direct-stage5-validation/implementation/candidate-combined-01/library'),
]

def identity(path):
    target = path.resolve(strict=True)
    return dict(path=str(path), resolved=str(target),
        sha256=hashlib.sha256(target.read_bytes()).hexdigest())

def write(path, data):
    with path.open('x') as stream:
        json.dump(data, stream, indent=2)
        stream.write('\n')

def main():
    output = ROOT / 'pipeline-repeats-a2d8b6a-01'
    if output.exists() or output.is_symlink():
        raise RuntimeError('Fresh output required')
    commands = []
    for repeat in range(1, 4):
        for mode, source, library in SOURCES:
            name = f'{mode}-pipeline-repeat-{repeat:02d}'
            for path in (ROOT / name, ROOT / (name + '-receipt.json')):
                if path.exists() or path.is_symlink():
                    raise RuntimeError('Existing child output: ' + str(path))
            commands.append([str(PYTHON), str(ROOT / 'pipeline-repeat-v1.py'),
                             source, library, name, 'pipeline_repeat'])
    inputs = [identity(path) for path in [Path(__file__).resolve(),
        Path(sys.executable).resolve(), PYTHON, ROOT / 'pipeline-repeat-v1.py',
        ROOT / 'pipeline-repeat-v1.R']]
    output.mkdir()
    write(output / 'plan.json', dict(inputs=inputs, commands=commands,
        environment_overrides={'DTA_EXPRESSION_ITERATIONS': '7'},
        scope='Sequential orchestration only. Each child independently binds its actual R/library/corpus inputs and products. Requires externally coordinated quiet.'))
    environment = dict(os.environ)
    environment['DTA_EXPRESSION_ITERATIONS'] = '7'
    results = []
    failure = None
    try:
        for command in commands:
            for item in inputs:
                if identity(Path(item['path'])) != item:
                    raise RuntimeError('Changed orchestration input')
            code = subprocess.run(command, env=environment, cwd=ROOT).returncode
            results.append(dict(command=command, returncode=code))
            if code:
                raise RuntimeError('Repeat failed; child records preserved')
    except BaseException as error:
        failure = repr(error)
        raise
    finally:
        changed = []
        for item in inputs:
            try:
                if identity(Path(item['path'])) != item:
                    changed.append(item['path'])
            except (OSError, RuntimeError) as error:
                changed.append(dict(path=item['path'], error=str(error)))
        write(output / 'result.json', dict(commands=results, failure=failure,
            changed_inputs=changed, complete=len(results) == 6 and failure is None and not changed))
        write(output / 'receipt.json', dict(plan=identity(output / 'plan.json'),
                                           result=identity(output / 'result.json')))
    if changed:
        raise RuntimeError('Orchestration input changed')

if __name__ == '__main__':
    main()
