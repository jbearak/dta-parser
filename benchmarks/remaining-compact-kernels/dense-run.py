#!/usr/bin/env python3
"""Six paired fresh-process dense public-operation rounds; no concurrent workers."""
import argparse,csv,datetime,hashlib,json,statistics,subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent

def require(value,message):
    if not value: raise RuntimeError(message)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def namespace_dll(library):
    files=list((library/'dtatools/libs').rglob('dtatools.so'))
    require(len(files)==1,'Expected exactly one qualified dtatools shared library')
    return files[0]

def validate(rows,round_number,representations):
    require(len(rows)==len(representations),'Incomplete dense round')
    by={row['representation']:row for row in rows}
    require(set(by)==set(representations),'Missing or duplicate representation')
    positions=set()
    for representation,row in by.items():
        require(row['round']==str(round_number) and row['phase']=='measure' and row['rows']=='1000000' and row['pattern']=='random_half' and row['operation']=='reciprocal','Unexpected benchmark coordinate')
        repetitions=int(row['repetitions']);expected_native=0 if representation=='ordinary_double' else repetitions
        require(repetitions>0 and float(row['cpu'])>0 and float(row['wall'])>0 and int(row['native_calls'])==expected_native,'Invalid timed/native record')
        require(row['input_missing']=='500000' and row['zero_observed']=='48','Fixture missing/zero counts changed')
        require(row['input_hash']=='b6b60ef8bb430be90e7239dd64b807cda383733b1048ca6748094e19e1003f06' and row['rank_hash']=='6d001f63d9ce5612a17ed6ff62e0d269d6d862dde318265b90a63af3b92b0706','Original frozen fixture bits/ranks changed')
        require(row['compact_before']==row['compact_after'] and row['materialized_before']==row['materialized_after'] and row['retained_before']==row['retained_after'] and row['chunks_before']==row['chunks_after'],'Source state changed')
        require(row['mutation_checked']==('FALSE' if representation=='ordinary_double' else 'TRUE'),'Cache mutation qualification changed')
        require(row['result_storage']=={'compact':'float','typed_double':'double','ordinary_double':''}[representation],'Result storage changed')
        require(int(row['result_missing'])==(500000 if representation=='ordinary_double' else 500048),'Result missing policy changed')
        positions.add(int(row['position']))
        for field in ('input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash','cleared_hash'):
            require(len(row[field])==64,'Missing qualification digest: '+field)
    require(positions==set(range(1,len(representations)+1)),'Representation positions incomplete')
    return by

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--baseline-library',type=Path,required=True);parser.add_argument('--candidate-library',type=Path,required=True)
    parser.add_argument('--worker',type=Path,default=HERE/'dense-worker.R');parser.add_argument('--include-bare',action='store_true',default=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--baseline-receipt',type=Path);parser.add_argument('--candidate-receipt',type=Path)
    args=parser.parse_args();output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    libraries={'baseline':args.baseline_library.resolve(),'candidate':args.candidate_library.resolve()}
    dlls={role:namespace_dll(library) for role,library in libraries.items()}
    worker=args.worker.resolve();before={'worker':sha(worker),'dlls':{role:sha(path) for role,path in dlls.items()},'controller':sha(Path(__file__))}
    before['build_receipts']={role:sha(path) for role,path in (('baseline',args.baseline_receipt),('candidate',args.candidate_receipt)) if path is not None}
    representations=('compact','typed_double','ordinary_double') if args.include_bare else ('compact','typed_double')
    rounds=[];commands=[];all_rows=[]
    for round_number in range(1,7):
        build_order=('baseline','candidate') if round_number%2 else ('candidate','baseline');observations={}
        for build_position,role in enumerate(build_order,1):
            csv_path=output/f'{role}-round{round_number}.csv';log_path=output/f'{role}-round{round_number}.log'
            command=['Rscript',str(worker),str(libraries[role]),str(round_number),str(csv_path)]
            started=datetime.datetime.now(datetime.timezone.utc).isoformat()
            with log_path.open('w') as log:
                process=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,cwd=HERE)
            commands.append({'round':round_number,'role':role,'position':build_position,'command':command,'cwd':str(HERE),'started_utc':started,'exit_code':process.returncode})
            require(process.returncode==0,'Exact worker qualification/timing failed: '+str(log_path))
            with csv_path.open(newline='') as stream:rows=list(csv.DictReader(stream))
            observations[role]=validate(rows,round_number,representations)
            for row in rows:all_rows.append({'build':role,'build_position':build_position,**row})
            require(sha(worker)==before['worker'] and all(sha(dlls[name])==before['dlls'][name] for name in libraries),'Consumed worker/shared library changed')
        baseline,candidate=observations['baseline'],observations['candidate']
        for representation in representations:
            for field in ('position','input_hash','rank_hash','result_hash','missing_hash','metadata_hash','result_metadata_hash','cleared_hash','result_storage','input_missing','zero_observed','result_missing','compact_before','compact_after','materialized_before','materialized_after','retained_before','retained_after','chunks_before','chunks_after'):
                require(baseline[representation][field]==candidate[representation][field],f'Paired semantic/state difference: {representation} {field}')
        cpu={role:{representation:float(row['cpu'])/int(row['repetitions']) for representation,row in data.items()} for role,data in observations.items()}
        item={'round':round_number,'build_order':list(build_order),'cpu_ms':{role:{representation:value*1000 for representation,value in values.items()} for role,values in cpu.items()},
              'baseline_compact_to_typed_cpu':cpu['baseline']['compact']/cpu['baseline']['typed_double'],'candidate_compact_to_typed_cpu':cpu['candidate']['compact']/cpu['candidate']['typed_double'],
              'paired_compact_speedup':cpu['baseline']['compact']/cpu['candidate']['compact'],'paired_typed_control_speedup':cpu['baseline']['typed_double']/cpu['candidate']['typed_double']}
        if args.include_bare:
            item.update(baseline_compact_to_ordinary_cpu=cpu['baseline']['compact']/cpu['baseline']['ordinary_double'],candidate_compact_to_ordinary_cpu=cpu['candidate']['compact']/cpu['candidate']['ordinary_double'],paired_ordinary_control_speedup=cpu['baseline']['ordinary_double']/cpu['candidate']['ordinary_double'])
        rounds.append(item)
    counts={(role,representation):[int(row['position']) for row in all_rows if row['build']==role and row['representation']==representation] for role in libraries for representation in representations}
    for key,positions in counts.items():
        require(all(positions.count(position)==6//len(representations) for position in range(1,len(representations)+1)),'Unbalanced representation positions: '+str(key))
    require(sha(Path(__file__))==before['controller'],'Controller changed during experiment')
    with (output/'raw.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(all_rows[0]));writer.writeheader();writer.writerows(all_rows)
    summary={'status':'PASS','paired_rounds':6,'timed_observations':len(all_rows),'representations':representations,'before':before,'libraries':{key:str(value) for key,value in libraries.items()},'worker':str(worker),'rounds':rounds,
             'medians':{name:statistics.median(item[name] for item in rounds) for name in rounds[0] if name.endswith('_cpu') or name.endswith('_speedup')},
             'commands':commands,'artifact_sha256':{path.name:sha(path) for path in output.iterdir() if path.is_file()},
             'scope':'Original random_half million-row dense reciprocal input, exact public operation and per-process oracle/cache/native-entry qualifications. Six alternating build pairs in fresh R processes; balanced representation positions. CPU measured only in worker adaptive loops. Unchanged typed control drift reported. No reader, arbitrary-import or universal parity claim.'}
    if args.include_bare:
        summary['scope']+=' Bare R comparison uses its own base division oracle: zero denominators remain Inf, while typed package operations normalize them to missing. Bare output does not run package mutation/cache qualification.'
    (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({'status':'PASS','timed_observations':len(all_rows),'medians':summary['medians']},indent=2))
if __name__=='__main__':main()
