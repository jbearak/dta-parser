import csv
import importlib.util
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

ROOT = Path(os.environ['DTATOOLS_DECODE_WORK'])
OLD = Path(os.environ['DTATOOLS_PREVIOUS_READER_WORK'])
REPO = Path(os.environ['DTATOOLS_REPO'])
spec = importlib.util.spec_from_file_location('reader_benchmark', REPO/'benchmarks/r-file-readers/run.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
output = ROOT/'final-sweep'
output.mkdir()
private = output/'private-jobs'
private.mkdir()
library = OLD/'candidate-final-v2/library'
expected = json.loads((OLD/'bindings-final-v2/build-bindings.json').read_text())['libraries']['candidate']
fixture = next(x for x in json.loads((OLD/'controls.json').read_text())['reads'] if x['id']=='india')
known = json.loads((OLD/'final-large/provenance-before.json').read_text())['inputs']['india']
rscript = str(Path(shutil.which('Rscript')).resolve())
settings = [(kind,threads) for kind in ('dta','arrow') for threads in (1,2,4,8,12,16,0)]

def bindings():
    value=dict(installed=bench.inventory(library),inputs={kind:dict(sha256=bench.sha(fixture[kind]),bytes=Path(fixture[kind]).stat().st_size) for kind in ('dta','arrow')},
        runtime=bench.runtime(rscript,library),rscript_sha256=bench.sha(rscript),
        workers={name:bench.sha(REPO/'benchmarks/r-file-readers'/name) for name in ('worker.R','common.R','runtime.R')},
        controller_sha256=bench.sha(Path(__file__)),build_record_sha256=bench.sha(OLD/'bindings-final-v2/build-bindings.json'))
    assert value['installed']==expected and value['inputs']=={kind:known[kind] for kind in ('dta','arrow')}
    return value

before=bindings()
(output/'provenance-before.json').write_text(json.dumps(before,indent=2)+'\n')

def invoke(kind,threads,mode,key):
    command=[rscript,'--vanilla',str(REPO/'benchmarks/r-file-readers/worker.R'),mode,f'dtatools_{kind}_dibble',fixture[kind],str(threads),str(fixture['rows']),str(fixture['columns']),'-']
    log=private/(key+'.log')
    started=time.monotonic()
    with log.open('w') as f:
        child=subprocess.Popen(command,stdout=f,stderr=subprocess.STDOUT,env=bench.environment(library))
        _,status,usage=os.wait4(child.pid,0)
        child.returncode=os.waitstatus_to_exitcode(status)
    if child.returncode: raise RuntimeError('Worker failed: '+key)
    fields=[line.split('\t') for line in log.read_text().splitlines() if line.startswith('QUALIFIED\t' if mode.startswith('qualify') else 'MEASURE\t')]
    assert len(fields)==1
    if mode.startswith('qualify'):return fields[0][1]
    row=bench.validate_record(fields[0],fixture)
    row.update(read_user=float(fields[0][2]),read_system=float(fields[0][3]),process_cpu=usage.ru_utime+usage.ru_stime,process_wall=time.monotonic()-started,maxrss_bytes=usage.ru_maxrss,log_sha256=bench.sha(log))
    return row

signature=None
qualification=[]
for kind,threads in settings:
    actual=invoke(kind,threads,'qualify-signature-read',f'qualify-{kind}-{threads}')
    if signature is None:signature=actual
    assert actual==signature
    qualification.append(dict(kind=kind,threads=threads,datasig=actual))
(output/'qualification.json').write_text(json.dumps(qualification,indent=2)+'\n')
records=[]
for pair,shift in enumerate((0,4,8),1):
    order=settings[shift:]+settings[:shift]
    for flip in (False,True):
        round=2*pair-1+int(flip)
        for position,(kind,threads) in enumerate(list(reversed(order)) if flip else order,1):
            row=invoke(kind,threads,'read',f'{round:02}-{kind}-{threads}')
            row.update(round=round,position=position,kind=kind,threads=threads)
            records.append(row)
            with (output/'raw.jsonl').open('a') as f:f.write(json.dumps(row,sort_keys=True)+'\n')
        print('Completed sweep round',round,flush=True)
summary=[]
for kind,threads in settings:
    rows=[r for r in records if r['kind']==kind and r['threads']==threads]
    summary.append(dict(kind=kind,threads=threads,n=len(rows),**{name:statistics.median(r[name] for r in rows) for name in ('read_wall','read_cpu','read_user','read_system','maxrss_bytes')}))
with (output/'summary.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(summary[0]));w.writeheader();w.writerows(summary)
after=bindings()
assert before==after
(output/'provenance-after.json').write_text(json.dumps(after,indent=2)+'\n')
(output/'protocol.json').write_text(json.dumps(dict(observations=len(records),settings=settings,rounds=6,cache='warm filesystem',output='dibble',dimensions=dict(rows=fixture['rows'],columns=fixture['columns']),order='three rotations each followed by its reverse; settings have balanced precedence',boundaries='read user/system/wall within identical R proc.time interval; qualification occurs only in separate processes',bindings_matched=True),indent=2)+'\n')
(ROOT/'monitor-stop').touch()
print('Completed',len(records),'observations; bindings matched',flush=True)
