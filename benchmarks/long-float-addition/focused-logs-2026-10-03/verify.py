"""Verify the additive historical focused logs; runs no package tests or timings."""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / 'evidence'
NAMES = {
    'baseline-focused-v1', 'candidate-focused-v1',
    'all-missing-baseline-focused-v1', 'all-missing-candidate-focused-v1',
    'publication-focused-v1',
}

def require(value, message):
    if not value:
        raise RuntimeError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

supplement = json.loads((HERE / 'supplement.json').read_text())
require(sha(EVIDENCE / 'publication-manifest.json') == supplement['original_publication_manifest_sha256'], 'Historical manifest changed')
require(sha(EVIDENCE / 'publication-source-map.json') == supplement['original_source_map_sha256'], 'Historical source map changed')
manifest = json.loads((EVIDENCE / 'publication-manifest.json').read_text())
source_map = {item['artifact']: item for item in json.loads((EVIDENCE / 'publication-source-map.json').read_text())}
records = supplement['logs']
require(len(records) == 5 and {item['log'] for item in records} == {name + '.log' for name in NAMES}, 'Incomplete or duplicate log set')
for item in records:
    name = item['log'][:-4]
    completion = 'focused/' + name + '/completion.json'
    require(item['completion'] == completion, 'Unexpected completion path')
    path = EVIDENCE / completion
    require(sha(path) == manifest[completion] == item['published_completion_sha256'] == source_map[completion]['published_sha256'], 'Published completion changed')
    require(item['original_completion_sha256'] == source_map[completion]['source_sha256'], 'Original completion identity changed')
    original = json.loads(path.read_text())
    require(original['status'] == 'PASS' and original['before_after_equal'] is True, 'Historical focused gate failed')
    require(sha(HERE / item['log']) == item['published_log_sha256'] == item['original_log_sha256'] == original['artifacts']['focused.log'], 'Historical log bytes changed')
    lines = (HERE / item['log']).read_text().splitlines()
    require(len(lines) == 3 and lines[0].split() == ['passed', 'failed', 'error', 'skipped', 'warning'], 'Unexpected log schema')
    require(re.fullmatch(r'\s*[0-9]+(?:\s+[0-9]+){4}\s*', lines[1]) is not None, 'Non-numeric log counts')
    values = [int(value) for value in lines[1].split()]
    require(values[1:] == [0] * 4 and [values[0], values[1], values[4]] == [original['totals'][key] for key in ('passed', 'failed', 'warning')], 'Historical counts disagree')
    require(lines[2].strip() == 'Test blocks: ' + str(original['blocks']), 'Historical block count disagrees')
    require(item['source_commit'] == original['source_commit'] and item['test_source_head'] == original['test_source_head'] and item['blocks'] == original['blocks'] and item['passed'] == values[0], 'Supplement source or counts disagree')
print('PASS: five historical focused logs match unchanged completion records')
