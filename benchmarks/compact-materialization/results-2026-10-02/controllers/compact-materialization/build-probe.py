#!/usr/bin/env python3
"""Compile the one shared DATAPTR_RO probe and record its actual build inputs."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('snapshot', HERE.parent / 'r-file-readers/build-snapshot.py')
SNAPSHOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)
RECORDS = SNAPSHOT.RECORDS


def verify(work):
    receipt_bytes = (work / 'receipt.json').read_bytes()
    receipt = json.loads(receipt_bytes)
    RECORDS.require(receipt['schema'] == 1 and receipt['exit_code'] == 0,
                    'Probe receipt does not identify a successful build')
    RECORDS.require(receipt['source_sha256'] == RECORDS.sha_file(HERE / 'probe.c') ==
                    RECORDS.sha_file(work / 'materialization_probe.c'), 'Probe source changed')
    RECORDS.require(receipt['builder_sha256'] == RECORDS.sha_file(Path(__file__)),
                    'Probe builder changed')
    RECORDS.require(receipt['snapshot_artifacts'] == RECORDS.artifact_hashes(),
                    'Probe toolchain recorder changed')
    for field, name in (('binary_sha256', 'materialization_probe.so'),
                        ('build_log_sha256', 'build.log'),
                        ('input_record_sha256', 'input-record.json'),
                        ('private_record_sha256', 'input-record-private.json')):
        RECORDS.require(receipt[field] == RECORDS.sha_file(work / name), 'Probe build artifact changed')
    inputs = json.loads((work / 'input-record.json').read_text())
    RECORDS.require(inputs['source_sha256'] == receipt['source_sha256'] and
                    inputs['toolchain'] == receipt['toolchain'], 'Probe pre/post binding differs')
    return dict(receipt=receipt, receipt_sha256=RECORDS.sha_bytes(receipt_bytes))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    source = (HERE / 'probe.c').read_bytes()
    (work / 'materialization_probe.c').write_bytes(source)
    env = {key: value for key, value in os.environ.items()
           if key in SNAPSHOT.ENVIRONMENT_KEYS or key.startswith('LC_')}
    env.update(R_ENVIRON_USER='/dev/null', R_PROFILE_USER='/dev/null')
    r = SNAPSHOT.executable('R', env)
    toolchain = SNAPSHOT.toolchain(r, env)
    command = [r, 'CMD', 'SHLIB', '-o', 'materialization_probe.so', 'materialization_probe.c']
    private = dict(command=command, cwd=str(work), environment=env, toolchain=toolchain)
    (work / 'input-record-private.json').write_bytes(RECORDS.json_bytes(private))
    inputs = dict(source_sha256=RECORDS.sha_bytes(source), toolchain=toolchain,
                  command=['<R>', 'CMD', 'SHLIB', '-o', 'materialization_probe.so', 'materialization_probe.c'],
                  environment={key: SNAPSHOT.sanitize(value) for key, value in sorted(env.items())})
    (work / 'input-record.json').write_bytes(RECORDS.json_bytes(inputs))
    with (work / 'build.log').open('wb') as log:
        result = subprocess.run(command, cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
    RECORDS.require(result.returncode == 0, 'Probe compilation failed; inspect build.log')
    RECORDS.require(source == (HERE / 'probe.c').read_bytes() ==
                    (work / 'materialization_probe.c').read_bytes(), 'Probe source changed during build')
    RECORDS.require(toolchain == SNAPSHOT.toolchain(r, env), 'Probe toolchain changed during build')
    receipt = dict(schema=1, exit_code=0, source_sha256=RECORDS.sha_bytes(source), toolchain=toolchain,
        builder_sha256=RECORDS.sha_file(Path(__file__)), snapshot_artifacts=RECORDS.artifact_hashes(),
        binary_sha256=RECORDS.sha_file(work / 'materialization_probe.so'),
        build_log_sha256=RECORDS.sha_file(work / 'build.log'),
        input_record_sha256=RECORDS.sha_file(work / 'input-record.json'),
        private_record_sha256=RECORDS.sha_file(work / 'input-record-private.json'))
    (work / 'receipt.json').write_bytes(RECORDS.json_bytes(receipt))
    verify(work)
    print('Built and verified the shared DATAPTR_RO probe', flush=True)


if __name__ == '__main__':
    main()
