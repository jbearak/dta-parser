#!/usr/bin/env python3
"""Package already audited reciprocal evidence, with no timing or test execution.

The private originals remain unchanged. Archived scripts are snapshots with
redacted paths. Original and published hashes are recorded separately.
"""
from pathlib import Path
import csv
import hashlib
import json
import re
import sys

WORK = Path(__file__).resolve().parent
DESIGN = Path('<design>')
BASELINE = Path('<baseline-build>')
REPO = Path('<source-repository>')
BASE = '7003eba901671797ee91fffc97f08e28a1f7f515'
MEASURED = 'f219bf72bbc882cc4c090ded870470ab9c5e2099'
FINAL = '50e448283231cde1432fa6b30d5d3f6bd0441618'
RECORDER_REPO = Path('<private-work>/dta-long-float-add-blocks')
CONTROLLERS = {'controller': WORK/'controller/run.py', 'worker': WORK/'controller/worker.R',
 'validation': WORK/'controller/core.py', 'protocol_tests': WORK/'controller/test-run.py',
 'build_validation': RECORDER_REPO/'benchmarks/native-operations/run.py',
 'build_recorder': RECORDER_REPO/'benchmarks/r-file-readers/record-builds.py',
 'build_recorder_parent': RECORDER_REPO/'benchmarks/io-optimization/record-builds.py'}


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bound(path, expected):
    require(sha(path) == expected, 'Changed bound artifact: ' + str(path))


def read(path):
    return json.loads(path.read_text())


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def identities(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key in ('USER', 'LOGNAME'):
                require(isinstance(item, dict) and set(item) == {'value', 'sha256'} and
                        all(isinstance(v, str) for v in item.values()), 'Unexpected identity schema')
                item['value'] = item['sha256'] = '<private>'
            else:
                identities(item)
    elif isinstance(value, list):
        for item in value:
            identities(item)


def focused(path):
    rows = list(csv.DictReader(path.open()))
    require(len(rows) == 31, 'Incomplete focused matrix')
    passed = 0
    for row in rows:
        for key in ('passed', 'failed', 'warning'):
            require(re.fullmatch(r'[0-9]+', row[key]) is not None, 'Invalid test count')
        require(row['failed'] == row['warning'] == '0' and
                row['error'] == row['skipped'] == 'FALSE', 'Failed focused test')
        passed += int(row['passed'])
    require(passed == 32173, 'Wrong focused assertion count')


def main():
    output = Path(sys.argv[1]).resolve()
    require(not output.exists(), 'Publication destination exists')
    audit = read(WORK/'independent-audit.json')
    require(audit['status'] == 'PASS' and audit['observations'] == 216 and
            audit['qualification_observations'] == 36 and audit['summaries'] == 9 and
            audit['source_commits'] == {'baseline': BASE, 'candidate': MEASURED},
            'Independent timing audit does not match this stage')
    bound(WORK/'independent-audit.py', audit['audit_sha256'])
    for relative, expected in audit['artifact_sha256'].items():
        bound(WORK/relative, expected)
    for stage, observations in (('screen-v1', 216), ('qualification-v1', 36)):
        before, after = (read(WORK/stage/('provenance-'+side+'.json')) for side in ('before','after'))
        require(before == after, 'Changed measured identities')
        complete = read(WORK/stage/'completion.json')
        require(complete['observations'] == observations and complete['exact_results'] is True and
                complete['provenance_unchanged'] is True, 'Incomplete stage')
        for name, expected in complete['artifacts'].items():
            bound(WORK/stage/name, expected)
        require({role:b['receipt']['base_commit'] for role,b in before['builds'].items()} ==
                {'baseline':BASE,'candidate':MEASURED}, 'Wrong measured source pair')
        require(set(before['controllers']) == set(CONTROLLERS), 'Unknown controller dependency')
        for name, expected in before['controllers'].items():
            bound(CONTROLLERS[name], expected)
        for role, build in (('baseline',BASELINE),('candidate',WORK/'candidate')):
            b = before['builds'][role]
            bound(build/'build-receipt.json', b['receipt_sha256'])
            bound(build/'input-record.json', b['receipt']['input_record_sha256'])
            bound(build/'source.patch', b['receipt']['source_patch_sha256'])
    qualification = read(WORK/'focused-qualification.json')
    require(qualification['status'] == 'PASS' and qualification['runtime_source_commit'] == MEASURED and
            qualification['test_source_commit'] == FINAL and
            qualification['arithmetic_runtime_unchanged_after_build'] is True, 'Wrong focused qualification')
    for role, stem in (('baseline','baseline-focused-final'),('candidate','focused-final')):
        record = qualification['focused'][role]
        require(record['assertions'] == 32173 and record['blocks'] == 31, 'Wrong focused record')
        for suffix in ('csv','log'):
            bound(WORK/(stem+'.'+suffix), record[suffix+'_sha256'])
        focused(WORK/(stem+'.csv'))
    bound(WORK/'focused-source.R', qualification['focused_controller_sha256'])
    bound(WORK/'candidate/build-receipt.json', qualification['build_receipt_sha256'])
    bound(WORK/'candidate/library/dtatools/libs/dtatools.so', qualification['installed_dll_sha256'])
    for relative, expected in qualification['test_files'].items():
        bound(REPO/'r-package/dtatools'/relative, expected)
    archive = read(WORK/'conformance.json')
    require(archive['source_commit'] == FINAL and all(archive[key] is True for key in (
        'checked_source_matches_clean_export','clean_export_matches_source_commit',
        'exact_packaged_source_inventory','expected_hashes_from_committed_blobs',
        'repository_environment_overrides_removed','required_conformance_passed')), 'Archive gate failed')
    bound(WORK/'conformance.tar.gz', archive['source_archive_sha256'])
    full = read(WORK/'conformance-suite-binding.json')
    require(full['status'] == 'PASS' and full['source_commit'] == FINAL and
            full['counts']['failed'] == full['counts']['skipped'] == 0 and
            full['counts']['passed'] > 100000, 'Full archived suite gate failed')
    for filename, expected in full['artifact_sha256'].items():
        bound(WORK/filename, expected)
    stages = [
        ('baseline-semantic-v1','baseline-probe-source',BASE,'PASS',0),
        ('baseline-red-v1','baseline-probe-source',BASE,'EXPECTED_RED',12),
        ('candidate-structural-v1','candidate-strict-probe-source','528494baebc0285bb5d6216323c87784bfc599e9','PASS',0),
        ('candidate-release-v1','release-probe-source',MEASURED,'PASS',0)]
    for stage, controller, commit, status, failures in stages:
        path = DESIGN/stage
        bound(path/'receipt.json', qualification['structural_records'][stage])
        receipt = read(path/'receipt.json')
        require(receipt['commit'] == commit and receipt['status'] == status and
                receipt['matrix_cases'] == 1484 and receipt['semantic_failures'] == 0 and
                receipt['work_failures'] == failures and receipt['source_before_after_equal'] is True,
                'Wrong structural stage')
        for name, expected in receipt['artifact_sha256'].items():
            bound(path/name, expected)
        bound(DESIGN/controller/'work-count.py', receipt['controller_sha256'])
        bound(DESIGN/controller/'work-count.c', receipt['probe_sha256'])
    codegen = qualification['codegen']
    for name, key in (('command.json','command_sha256'),('producer.txt','object_disassembly_sha256'),
                      ('installed-producer.txt','installed_disassembly_sha256'),('remarks.log','remarks_sha256')):
        bound(DESIGN/'codegen-v1'/name, codegen[key])
    excerpts = read(WORK/'codegen-excerpts/binding.json')
    for name, expected in excerpts['originals'].items():
        bound(DESIGN/'codegen-v1'/name, expected)
    for name, record in excerpts['excerpts'].items():
        bound(WORK/'codegen-excerpts'/name, record['sha256'])

    pending, mapping = {}, []
    replacements = sorted([(str(WORK),'<work>'),(str(DESIGN),'<design>'),
        (str(BASELINE),'<baseline-build>'),(str(REPO),'<source-repository>'),
        (str(Path.home()),'<user>')], key=lambda x:len(x[0]), reverse=True)
    def queue(source, relative):
        original = source.read_bytes()
        text = original.decode()
        if source.suffix == '.json':
            value = json.loads(text); identities(value); text = encoded(value).decode()
        for old,new in replacements: text = text.replace(old,new)
        text = re.sub(r'/(?:private/)?tmp/([^/\s\"\'<>]+)',r'<private-work>/\1',text)
        text = re.sub(r'/(?:private/)?var/folders/[^\s\"\'<>]+','<temporary>',text)
        # These generic prefixes occur in this validator's own privacy patterns.
        scan = text.replace('/(?:Users|home|private/tmp|tmp)/','<path-pattern>')
        require(not re.search(r'/(?:Users|home|private/tmp|tmp)/',scan), 'Unmapped private path: '+relative)
        require(relative not in pending,'Repeated destination')
        public = text.encode(); pending[relative] = public
        mapping.append({'artifact':relative,'source_sha256':hashlib.sha256(original).hexdigest(),
            'published_sha256':hashlib.sha256(public).hexdigest(),
            'transformation':'none' if original==public else 'private paths/identity redaction or JSON formatting'})
    for stage in ('screen-v1','qualification-v1'):
        for path in sorted((WORK/stage).iterdir()):
            if path.suffix in ('.csv','.json','.patch'): queue(path,stage+'/'+path.name)
    for key in ('build_validation','build_recorder','build_recorder_parent'):
        queue(CONTROLLERS[key], 'controller/recorders/'+key+'.py')
    for path in sorted((WORK/'controller').iterdir()):
        if path.suffix in ('.py','.R'): queue(path,'controller/'+path.name)
    for name in ('independent-audit.py','independent-audit.json','focused-qualification.json',
                 'focused-final.csv','baseline-focused-final.csv','focused-source.R',
                 'conformance.json','conformance.log','conformance-command.json',
                 'conformance-suite-binding.json','conformance-testthat.Rout',
                 'run-conformance.py','conformance-gate.sh','bind-conformance-suite.py','validate-conformance-archive.py'):
        queue(WORK/name,name)
    for role, build in (('baseline',BASELINE),('candidate',WORK/'candidate')):
        for name in ('build-receipt.json','input-record.json','source.patch'):
            queue(build/name,'builds/'+role+'/'+name)
    for stage, controller, *_ in stages:
        for name in ('receipt.json','work-count.csv','work-count.log','source.patch'):
            queue(DESIGN/stage/name,'structural/'+stage+'/'+name)
    for controller in sorted({s[1] for s in stages}):
        for name in ('work-count.py','work-count.c'):
            queue(DESIGN/controller/name,'structural/'+controller+'/'+name)
    for path in sorted((WORK/'codegen-excerpts').iterdir()):
        queue(path,'codegen/'+path.name)
    queue(DESIGN/'codegen-v1/command.json','codegen/command.json')
    queue(Path(__file__),'publish.py')
    pending['publication-source-map.json'] = encoded(mapping)
    pending['publication-manifest.json'] = encoded({name:hashlib.sha256(data).hexdigest() for name,data in sorted(pending.items())})
    output.mkdir(parents=True)
    for name,data in pending.items():
        target=output/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    print('Published',len(pending),'artifacts; original records unchanged')

if __name__ == '__main__': main()
