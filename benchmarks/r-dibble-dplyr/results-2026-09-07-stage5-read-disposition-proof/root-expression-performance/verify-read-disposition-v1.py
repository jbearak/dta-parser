"""Bind and verify current read-disposition derivations; no R or benchmark run."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REPO = Path('/private/tmp/dta-direct-stage5')
PREP = Path('/private/tmp/dta-direct-stage5-read-cost-preparation.inputs.json')
NOTE = Path('/private/tmp/dta-direct-stage5-read-cost-preparation.md')
A2 = 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
C8 = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'


def identity(path):
    resolved = path.resolve(strict=True)
    st = resolved.stat()
    return dict(path=str(path), resolved=str(resolved), bytes=st.st_size,
                mode=oct(st.st_mode & 0o777), sha256=hashlib.sha256(resolved.read_bytes()).hexdigest())


def write(path, value):
    with path.open('x') as out:
        out.write(json.dumps(value, indent=2, sort_keys=True) + '\n')


def changes(rows):
    changed = []
    for row in rows:
        try:
            now = identity(Path(row['path']))
        except (OSError, RuntimeError) as error:
            changed.append(dict(path=row['path'], error=str(error)))
        else:
            if now != row:
                changed.append(dict(path=row['path'], current=now))
    return changed


def main():
    output = ROOT / 'read-disposition-verification-01'
    if output.exists() or output.is_symlink():
        raise RuntimeError('Fresh output required')
    output.mkdir()
    before = []
    accepted = False
    error = None
    try:
        prep_id = identity(PREP)
        payload = PREP.read_bytes()
        if hashlib.sha256(payload).hexdigest() != prep_id['sha256'] or identity(PREP) != prep_id:
            raise RuntimeError('Preparation changed during discovery')
        prep = json.loads(payload)
        package_paths = ['r-package/dtatools/src/owned-columns.h',
                         'benchmarks/r-dibble-dplyr/owned-atomic-helpers.R',
                         'benchmarks/r-dibble-dplyr/owned-atomic.R']
        docs = ['docs/research/stage5-base-r-read-costs.md',
                'docs/plans/dibble-result-performance.md',
                'docs/plans/dibble-result-performance-progress.md']
        assessments = ['atomic-read-repeat-v2-root-assessment-01.json',
                       'read-control-v3-root-assessment-01.json',
                       'read-count-control-v1-root-assessment-01.json']
        git = Path(shutil.which('git')).resolve(strict=True)
        paths = {PREP, NOTE, Path(__file__).resolve(), Path(sys.executable).resolve(), git,
                 *(Path(row['path']) for row in prep['inputs']),
                 *(REPO / name for name in package_paths + docs),
                 *(ROOT / name for name in assessments)}
        before = [identity(path) for path in sorted(paths)]
        write(output / 'inputs-before.json', dict(inputs=before,
            scope='Current source/hash and saved-assessment arithmetic verification. No historical runtime reconstruction, new R execution or performance experiment. Completed benchmark/raw audits retain their independent receipts.'))
        if identity(PREP) != prep_id:
            raise RuntimeError('Preparation changed before verification')
        for row in prep['inputs']:
            now = identity(Path(row['path']))
            if now['sha256'] != row['sha256'] or now['bytes'] != row['bytes']:
                raise RuntimeError('Historical preparation input differs: ' + row['path'])
        package_comparisons = []
        for name in package_paths:
            a2 = subprocess.check_output([str(git), 'show', A2 + ':' + name], cwd=REPO)
            c8 = subprocess.check_output([str(git), 'show', C8 + ':' + name], cwd=REPO)
            if a2 != c8 or a2 != (REPO / name).read_bytes():
                raise RuntimeError('Current package source differs from compared source: ' + name)
            package_comparisons.append(dict(path=name, a2=A2, c8=C8,
                sha256=hashlib.sha256(a2).hexdigest(), identical=True))
        cases = json.loads((ROOT / assessments[0]).read_text())['comparisons']
        rows = []
        keys = dict.fromkeys((r['kind'], r['operation']) for r in cases if r['case'] == 'read-repeat')
        for kind, operation in keys:
            repeated = [r for r in cases if r['kind'] == kind and r['operation'] == operation and r['case'] == 'read-repeat' and r['rows'] == 1000000]
            minimum = [r for r in cases if r['kind'] == kind and r['operation'] == operation and r['case'] == 'read-minimum']
            if len(repeated) != 3 or len(minimum) != 1 or not all(r['flag'] for r in repeated + minimum):
                raise RuntimeError('Expected three flagged repeats and one minimum')
            rows.append(dict(kind=kind, operation=operation,
                delta_min_ms=min(r['delta_ms'] for r in repeated),
                delta_max_ms=max(r['delta_ms'] for r in repeated), minimum_delta_ms=minimum[0]['delta_ms']))
        if len(rows) != 12:
            raise RuntimeError('Expected twelve residual reads')
        controls = []
        for name in assessments[1:]:
            source = json.loads((ROOT / name).read_text())['comparisons']
            for operation in ['public_table', 'public_column', 'native_elt', 'native_pointer']:
                matching = [r for r in source if r['rows'] == 1000000 and r['operation'] == operation]
                controls.append(dict(assessment=name, operation=operation,
                    delta_min_ms=min(r['delta_ms'] for r in matching),
                    delta_max_ms=max(r['delta_ms'] for r in matching)))
        write(output / 'derivation.json', dict(package_comparisons=package_comparisons,
            historical_preparation_inputs=27, residual_reads=rows, controls=controls,
            limit='Saved assessments supply arithmetic, not a new raw-sample audit or causal decomposition.'))
        accepted = not changes(before)
        if not accepted:
            raise RuntimeError('Input changed')
    except BaseException as failure:
        error = repr(failure)
        raise
    finally:
        changed = changes(before)
        accepted = accepted and not changed
        write(output / 'execution-result.json', dict(accepted=accepted, changed_inputs=changed, error=error))
        products = [identity(path) for path in sorted(output.iterdir()) if path.is_file()]
        write(output / 'manifest.json', dict(products=products, excluded_self='manifest.json', excluded_receipt='completed-receipt.json'))
        write(output / 'completed-receipt.json', dict(accepted=accepted, changed_inputs=changed, manifest=identity(output / 'manifest.json')))
    if not accepted:
        raise RuntimeError('Current disposition verification not accepted')


if __name__ == '__main__':
    main()
