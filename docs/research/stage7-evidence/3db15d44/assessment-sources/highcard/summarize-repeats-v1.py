"""Summarize three assessed independent-process pairs; no R execution."""
from pathlib import Path
from datetime import datetime
import hashlib
import json

P = Path(__file__).resolve().parent

def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())

plan_path = P / 'repeat-plan-3db15d44-01.json'
assert identity(plan_path)['sha256'] == 'a15fb246eed862dcaa9cfd2948c9bf6dc65766466a29ccec6e6a7f477638f23a'
plan = json.loads(plan_path.read_text())
expected_hashes = ['cb72ebfd86e269a6e511e9dcc28f7c6a1ea8c0c6d43ea7c37d4eb6bef84a820e',
                   'edb866f9f791c129c879b1d73b1e8b187e854068d5303f4110b8d648f0f20e4d']
reports, records, commands = [], [], []
for pair in range(1, 4):
    path = P / ('root-pair-3db15d44-%02d.json' % pair)
    record = identity(path)
    if pair <= 2:
        assert record['sha256'] == expected_hashes[pair - 1]
    report = json.loads(path.read_text())
    assert report['assessor']['sha256'] == '3dbefe88831f75f01b297655427cef4c0739e29b872f13550191444c00db2fd0'
    assert len(report['comparisons']) == 8
    assert sum(len(run['series']) for run in report['runs']) == 12
    assert sum(len(s['raw_times']) for run in report['runs'] for s in run['series']) == 84
    pair_commands = []
    for run in report['runs']:
        command_path = Path(run['directory']) / 'command-result.json'
        selected = next(x for x in run['consumed'] if x['path'] == str(command_path))
        assert identity(command_path) == selected
        command = json.loads(command_path.read_text())
        assert command['returncode'] == 0 and command['error'] is None
        role = 'predecessor' if run['source'] == plan['predecessor'] else 'candidate'
        assert run['source'] == plan[role]
        pair_commands.append(dict(pair=pair, role=role, command=selected,
            started=command['started_utc'], completed=command['completed_utc']))
    pair_commands.sort(key=lambda x: x['started'])
    assert [x['role'] for x in pair_commands] == plan['serial_run_order'][pair - 1]
    assert datetime.fromisoformat(pair_commands[0]['completed']) <= datetime.fromisoformat(pair_commands[1]['started'])
    commands.extend(pair_commands)
    reports.append(report)
    records.append(record)
assert datetime.fromisoformat(plan['created_utc']) < datetime.fromisoformat(commands[0]['started'])
assert all(datetime.fromisoformat(a['completed']) <= datetime.fromisoformat(b['started'])
           for a, b in zip(commands, commands[1:]))

summaries = []
for groups in [1024, 4096]:
    for workload in ['group_nest', 'nest_by']:
        public, safe = [], []
        for report in reports:
            for row in report['comparisons']:
                if (row['groups'], row['workload']) == (groups, workload):
                    (public if row['reference_route'] == 'public' else safe).append(row)
        assert len(public) == len(safe) == 3
        assert all(r['investigation_flag'] and r['schemas_identical'] for r in public)
        assert all(not r['investigation_flag'] and r['schemas_identical'] and r['delta_ms'] < 0 for r in safe)
        assert len({r['after_R_bytes'] for r in public + safe}) == 1
        assert len({r['before_R_bytes'] for r in public}) == 1
        assert len({r['before_R_bytes'] for r in safe}) == 1
        bounds = lambda rows, field: [min(r[field] for r in rows), max(r[field] for r in rows)]
        summaries.append(dict(groups=groups, workload=workload,
            predecessor_public_ms=bounds(public, 'before_ms'), candidate_ms=bounds(public, 'after_ms'),
            public_delta_ms=bounds(public, 'delta_ms'), public_ratio=bounds(public, 'median_ratio'),
            fixed_safe_ms=bounds(safe, 'before_ms'), fixed_safe_delta_ms=bounds(safe, 'delta_ms'),
            fixed_safe_ratio=bounds(safe, 'median_ratio'),
            predecessor_public_R_bytes=public[0]['before_R_bytes'],
            candidate_R_bytes=public[0]['after_R_bytes'], fixed_safe_R_bytes=safe[0]['before_R_bytes'],
            flags_repeated=3, fixed_safe_flags=0, paired_schemas_equal=True))

output = P / 'root-repeat-summary-3db15d44-01.json'
result = dict(assessor=identity(Path(__file__).resolve()), plan=identity(plan_path),
    pair_assessments=records, executed_order=commands, series=36, samples=252,
    profiles=36, cross_source_schema_pairs=24, shape_summaries=summaries,
    scope='Three fresh serial process pairs, alternating run order. Each preceding assessor checks complete raw timings/profiles and schema equality; this summarizer reuses those assessments and checks selected command identities/order and cross-repeat numerical consistency. Four public elapsed flags recur in every pair; all fixed-safe comparisons improve. No significance test, paired individual-sample test, exclusive phase/CPU attribution, RSS/retention result, universal scaling or claim that remaining overhead is unavoidable. Public predecessor has weaker foreign-write isolation; its elapsed/allocated regressions remain reported.')
with output.open('x') as stream:
    json.dump(result, stream, indent=2)
    stream.write('\n')
print(json.dumps(dict(output=identity(output), shape_summaries=summaries), indent=2))
