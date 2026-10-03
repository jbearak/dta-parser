#!/usr/bin/env python3
"""Merge independently prepared completed sections, retaining the pending gate.

Run only after the timing hold ends. This does not publish or approve evidence.
"""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
GROUPS = {'decisions', 'audits', 'timings', 'qualifications', 'structural',
          'codegen', 'focused', 'historical_full_suite', 'integration', 'archive', 'final34'}
PARTS = ('publication-config-completed-stages.json',
         'publication-config-auxiliary.json', 'publication-config-integration.json')


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def main():
    merged = dict(schema_version=1, ready=False, pins={}, roots={},
                  groups={group: [] for group in sorted(GROUPS)}, files=[])
    for name in PARTS:
        part = json.loads((HERE / name).read_text())
        need(part['ready'] is False, 'Partial configuration must not independently authorize publication')
        need(set(part['groups']) <= GROUPS, 'Unknown evidence group')
        for key, value in part['pins'].items():
            if value == 'PENDING_FINAL_COMBINED_COMMIT' and key == 'integrated':
                continue
            need(re.fullmatch('[0-9a-f]{40}', value), 'Unfrozen source pin')
            need(key not in merged['pins'] or merged['pins'][key] == value,
                 'Conflicting source pin: ' + key)
            merged['pins'][key] = value
        for key, value in part['roots'].items():
            need(key not in merged['roots'] or merged['roots'][key] == value,
                 'Conflicting artifact root: ' + key)
            merged['roots'][key] = value
        for group, entries in part['groups'].items():
            merged['groups'][group].extend(entries)
        merged['files'].extend(part['files'])
    need(set(merged['pins']) == {'baseline', 'rejected', 'corrected', 'integrated'},
         'Incomplete source pins')
    need(all(merged['groups'][g] for g in GROUPS - {'final34'}), 'Incomplete completed groups')
    need(not merged['groups']['final34'], 'Final acceptance must be added after its separate review')
    (HERE / 'publication-config-pending-final34.json').write_text(
        json.dumps(merged, indent=2, sort_keys=True) + '\n')
    print('Prepared combined configuration; final34 and publication approval remain pending')


if __name__ == '__main__':
    main()
