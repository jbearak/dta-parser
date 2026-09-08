"""Audit a completed expression matrix without executing benchmark operations."""
from pathlib import Path
import csv
import datetime
import hashlib
import json
import math
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
R_ROOT = Path('/opt/homebrew/Cellar/r/4.6.1/lib/R')
RSCRIPT = Path('/opt/homebrew/Cellar/r/4.6.1/bin/Rscript')


def identity(path):
    target = path.resolve(strict=True)
    stat = target.stat()
    digest = hashlib.sha256()
    with target.open('rb') as stream:
        while block := stream.read(8 * 1024 * 1024):
            digest.update(block)
    return dict(path=str(path), resolved=str(target), bytes=stat.st_size,
                mode=oct(stat.st_mode & 0o777), sha256=digest.hexdigest())


def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def changes(inputs):
    result = []
    for item in inputs:
        try:
            current = identity(Path(item['path']))
        except (OSError, RuntimeError) as error:
            result.append(dict(path=item['path'], error=repr(error)))
        else:
            if current != item:
                result.append(dict(path=item['path'], current=current))
    return result


def main():
    if len(sys.argv) != 3:
        raise RuntimeError('Expected completed run name and fresh audit name')
    name, output_name = sys.argv[1:]
    for value in (name, output_name):
        if Path(value).name != value or value in ('', '.', '..'):
            raise RuntimeError('Names must be direct children')
    run = ROOT / name
    output = ROOT / output_name
    receipt = ROOT / (output_name + '-receipt.json')
    if any(path.exists() or path.is_symlink() for path in (output, receipt)):
        raise RuntimeError('Existing audit destination')
    run_receipt = ROOT / (name + '-receipt.json')
    completed = json.loads(run_receipt.read_text())
    if not completed['accepted'] or completed['returncode'] != 0:
        raise RuntimeError('Measurement receipt is not successful')
    manifest = run / 'manifest.json'
    if identity(manifest) != completed['manifest']:
        raise RuntimeError('Changed completed manifest')
    products = json.loads(manifest.read_text())['products']
    expected_paths = {item['path'] for item in products} | {str(manifest)}
    actual_paths = {str(path) for path in run.iterdir() if path.is_file() or path.is_symlink()}
    if actual_paths != expected_paths or changes(products):
        raise RuntimeError('Changed output inventory or product identity')
    with (run / 'measurements.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 50:
        raise RuntimeError('Incomplete matrix')
    for row in rows:
        for key, value in row.items():
            if key.endswith('_bytes') or key == 'median_ms':
                if not math.isfinite(float(value)) or float(value) < 0:
                    raise RuntimeError('Invalid metric ' + key)
        expected_columns = int(row['columns']) + (row['kind'] in ('grouped', 'by'))
        if int(row['actual_input_columns']) != expected_columns:
            raise RuntimeError('Wrong actual input column count')
    with (run / 'source-states.csv').open() as stream:
        states = list(csv.DictReader(stream))
    for row in states:
        if row['owned'] != 'TRUE' or row['exposed'] != 'FALSE' or int(row['depth']) != 1:
            raise RuntimeError('Invalid source backing state')
        if float(row['bytes']) != int(row['rows']) * 8:
            raise RuntimeError('Wrong source backing size')
    inputs = {Path(item['path']) for item in products} | {
        manifest, run_receipt, Path(__file__).resolve(), ROOT / 'audit-measurement.R',
        Path(sys.executable).resolve(), RSCRIPT}
    inputs.update(path for path in R_ROOT.rglob('*') if path.is_file())
    before = [identity(path) for path in sorted(inputs)]
    command = [str(RSCRIPT), '--vanilla', str(ROOT / 'audit-measurement.R'), str(run)]
    output.mkdir()
    write(output / 'inputs.json', dict(inputs=before, command=command,
        scope='Completed output hashes and raw-sample recalculation. No benchmark workload. '
              'Host R tree and executables are bound; full OS/Python module closure is not frozen.'))
    code = None
    error = None
    changed = []
    try:
        with (output / 'execution.log').open('x') as stream:
            code = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT).returncode
    except BaseException as exception:
        error = repr(exception)
        raise
    finally:
        changed = changes(before)
        write(output / 'result.json', dict(returncode=code, error=error, changed_inputs=changed,
              measurements=len(rows), state_rows=len(states), utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
        output_products = [identity(path) for path in sorted(output.iterdir()) if path.is_file()]
        write(output / 'manifest.json', dict(products=output_products, excluded_self='manifest.json'))
        write(receipt, dict(manifest=identity(output / 'manifest.json'),
              accepted=code == 0 and error is None and not changed))
    if code != 0 or error is not None or changed:
        raise RuntimeError('Audit failed; original records preserved')
    print((output / 'execution.log').read_text())
    print('Audit receipt SHA256', identity(receipt)['sha256'])


if __name__ == '__main__':
    main()
