"""Review exact helper guards without launching production drivers or R."""
import ast
import datetime
import hashlib
import json
from pathlib import Path

root = Path('/private/tmp/dta-direct-stage5-validation')
out = root / 'implementation/api-review/driver-guard-review-02'
if out.exists():
    raise RuntimeError('Fresh output required')
out.mkdir()
paths = [root / 'root-expression-performance' / n for n in
         ['qualify-v14.py', 'measure.py', 'memory.py']]
paths += [root / 'root-r460-integration' / n for n in
          ['install-candidate-v3.py', 'check-candidate-v3.py']]
records = []
for path in paths:
    contents = path.read_bytes()
    parsed = ast.parse(contents, filename=str(path))
    helpers = [node for node in parsed.body if isinstance(node, ast.FunctionDef)
               and node.name in ['sha', 'record', 'identity', 'input_changes']]
    names = {node.name for node in helpers}
    if 'input_changes' not in names or not names.intersection({'identity', 'record'}):
        raise RuntimeError('Expected actual identity and changes helpers')
    namespace = {'Path': Path, 'hashlib': hashlib}
    exec(compile(ast.Module(body=helpers, type_ignores=[]), str(path), 'exec'), namespace)
    directory = out / path.stem
    directory.mkdir()
    fixture = directory / 'input.txt'
    fixture.write_text('original\n')
    identify = namespace.get('record', namespace.get('identity'))
    before = [identify(fixture)]
    if namespace['input_changes'](before):
        raise RuntimeError('False positive on unchanged input')
    fixture.write_text('changed\n')
    changed = namespace['input_changes'](before)
    if len(changed) != 1 or 'current' not in changed[0]:
        raise RuntimeError('Content change not retained')
    fixture.unlink()
    missing = namespace['input_changes'](before)
    if len(missing) != 1 or 'error' not in missing[0]:
        raise RuntimeError('Missing input not retained')
    fixture.symlink_to(directory / 'absent')
    broken = namespace['input_changes'](before)
    if len(broken) != 1 or 'error' not in broken[0]:
        raise RuntimeError('Broken symlink not retained')
    fixture.unlink()
    if path.read_bytes() != contents:
        raise RuntimeError('Driver changed during review')
    records.append(dict(source=str(path), sha256=hashlib.sha256(contents).hexdigest(),
                        bytes=len(contents), unchanged=True, changed_content=changed,
                        deleted_input=missing, broken_symlink=broken))
result = dict(time_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              python_optimization=__debug__ is False,
              method='Exact parsed helper functions executed without launching driver main or R. Tests missing/changed/broken input collection, not every driver failure path.',
              previous_attempt='01 stopped in reviewer harness because check-candidate uses inline hashing rather than a separate sha helper. Four preceding drivers had passed; no result file was written. No driver defect was found.',
              runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), results=records)
(out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(dict(drivers=len(records), all_passed=True, result=str(out / 'result.json'))))
