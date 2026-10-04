#!/usr/bin/env python3
"""PRODUCTION DRAFT: current native extraction and full-query command validation.

This draft has not been deployed. The historical retained116 FAIL stays FAIL.
The workflow must pass both this coverage gate and all five security lanes.
"""
import argparse, csv, hashlib, io, json, os, platform, re, shlex, shutil, subprocess, time
from pathlib import Path

SOURCE = None  # Exact checked-out commit, bound anew for each run.
ACTION = '2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2'
CLI_SHA = '938af3639d0709b587251e45d9f8d2bdc3505696'
BUNDLE_URL = 'https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.1/codeql-bundle-linux64.tar.gz'
BUNDLE_SHA = '1d380f79896ededc654c7b21fafb3360136f1aeb678ad4df4df9af3910c6b815'
SDK = {'stplugin.c':'ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d',
       'stplugin.h':'0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b'}
HERE = Path(__file__).resolve().parent
NAMES = ('diagnostics','compilations','includes','files','bodies','includes-absolute','types')
HEADERS = {
 'diagnostics':['file','line','severity','tag','message','translation_unit'],
 'compilations':['file','termination','mode','arguments'],
 'includes':['file','line','include_text','resolved_file'],
 'files':['file'], 'bodies':['file','source_metric','function_definitions','function_bodies'],
 'includes-absolute':['file','line','include_text','resolved_file'],
 'types':['file','owner','slot','declared_type','resolved_type','category','size','unknown']}
INTERNAL = 'r-package/dtatools/src/dtatools-internal.h'
GENERAL = 'r-package/dtatools/src/numeric-arithmetic-general.h'
PAYLOAD = 'r-package/dtatools/src/numeric-payload.c'
DECLARATION_HEADER = 'r-package/dtatools/src/probe-bracket-live-cache.h'
FIELDS = {
 'numeric_data':{'values':('pointer',8),'length':('integral',8),'kind':('integral',4),
   'temporal':('integral',4),'format_version':('integral',4),'missing_count':('integral',8),
   'native_owner':('pointer',8),'scalar_values':('pointer',8),'scalar_start':('integral',8),
   'scalar_end':('integral',8),'domain_flags':('integral',4)},
 'numeric_reader':{'value':('pointer',8),'storage':('pointer',8),'real_values':('pointer',8),
   'integer_values':('pointer',8),'type':('integral',4)},
 'arithmetic_general_output':{'kind':('integral',4),'raw':('pointer',8),'real':('pointer',8),
   'minimum':('floating',8),'maximum':('floating',8),'magnitude':('integral',8),
   'fractional':('integral',4),'missing_count':('integral',8)}}

def need(value,message):
    if not value: raise ValueError(message)
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text())
def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def integer(value):
    need(isinstance(value,str) and re.fullmatch('0|[1-9][0-9]*',value), 'Invalid nonnegative count')
    return int(value)
def metadata_binding(text,root,head):
    for pattern,expected in [(r'^buildMode:\s*(\S+)\s*$','manual'),
        (r'^finalised:\s*(\S+)\s*$','true'),
        (r'^sourceLocationPrefix:\s*(\S+)\s*$',str(root)),
        (r'^  sha:\s*(\S+)\s*$',head),(r'^  cliVersion:\s*(\S+)\s*$','2.27.1')]:
        need(re.findall(pattern,text,re.M)==[expected],'Wrong or ambiguous database metadata: '+pattern)
def tables_at(folder):
    result={}
    for name in NAMES:
        reader=csv.DictReader(io.StringIO((folder/(name+'.csv')).read_text()),strict=True)
        need(reader.fieldnames == HEADERS[name], 'Wrong table columns: '+name)
        result[name]=list(reader)
        need(all(set(r)==set(HEADERS[name]) and all(isinstance(v,str) for v in r.values()) for r in result[name]), 'Malformed table: '+name)
    return result

def qualify(tables,scope,pre,build):
    root=Path(pre['root']); rinclude=Path(pre['r_include'])
    active={r['path'] for r in scope['active_translation_units']}
    headers={r['path'] for r in scope['active_headers']}
    historical={r['path'] for k in ['historical_prior_main_43','historical_new_117'] for r in scope[k]}
    need(active and headers and len(historical)==160,'Wrong current/historical manual scope')
    issues=[]
    def check(ok,message):
        if not ok: issues.append(message)
    def absolute(value):
        return str(Path(value) if Path(value).is_absolute() else root/value)
    originals={str(root/p) for p in active}; current_headers={str(root/p) for p in headers}
    history={str(root/p) for p in historical}
    body={}
    for row in tables['bodies']:
        path=absolute(row['file']);need(path not in body,'Duplicate File/body record')
        integer(row['function_bodies']);integer(row['function_definitions']);body[path]=row
    strict_file_rows=[absolute(r['file']) for r in tables['files']]
    need(len(strict_file_rows)==len(set(strict_file_rows)), 'Duplicate File metric record')
    strict_files=set(strict_file_rows)
    for path in sorted(originals|current_headers):
        check(path in strict_files,'Missing active file metric: '+path)
        if path != str(root/DECLARATION_HEADER):
            check(path in body and integer(body[path]['function_bodies'])>0,'No original-path function body: '+path)
    check(not history.intersection(body),'Historical file entities present: '+str(sorted(history.intersection(body))))
    external={r['path'] for r in build['external_compilation']}
    need(build['external_compilation']==[{'path':str(Path(pre['work'])/'stata-sdk/stplugin.c'),
        'sha256':SDK['stplugin.c'],'role':'Pinned SDK support; outside current active translation-unit set'}],'Unexpected declared external compilation')
    compilations={};external_compilations=[];unexpected_compilations=[]
    for row in tables['compilations']:
        path=absolute(row['file'])
        check(row['termination']=='normal' and row['mode']=='other','Not normal manual compilation: '+path)
        if path in originals:
            compilations.setdefault(path,[]).append(row)
            check(not any(h in row['arguments'] for h in history),'Historical input in compiler args: '+path)
        elif path in external:external_compilations.append(row)
        else:unexpected_compilations.append(row)
    check(set(compilations)==originals,'Active compilation set incomplete')
    check({absolute(r['file']) for r in external_compilations}==external,'SDK compilation set incomplete')
    check(not unexpected_compilations,'Unexpected traced compilation: '+str([r['file'] for r in unexpected_compilations]))
    errors=[]
    relevant=originals|current_headers|{r['path'] for r in build['generated_header_maps']}
    for row in tables['diagnostics']:
        if integer(row['severity'])>=3 and (absolute(row['translation_unit']) in originals or absolute(row['file']) in relevant): errors.append(row)
    check(not errors,'Recorded extraction errors in active source/header contexts: '+str(len(errors)))
    graph={};unresolved={}
    for row in tables['includes-absolute']:
        source=absolute(row['file']); target=row['resolved_file']
        if target: graph.setdefault(source,set()).add(absolute(target))
        else: unresolved.setdefault(source,[]).append(row)
    reached={}
    for source in sorted(originals):
        seen=set();pending=[source]
        while pending:
            path=pending.pop()
            if path in seen:continue
            seen.add(path);pending.extend(graph.get(path,set())-seen)
        reached[source]=seen
        check(not seen&history,'Historical include reachable from active TU: '+source)
        check(not any(p in unresolved for p in seen),'Unresolved include reachable from active TU: '+source)
        relative=str(Path(source).relative_to(root))
        uses_r=(relative.startswith('r-package/dtatools/src/') or relative.startswith('r-package/dtatools/tests/testthat/fixtures/') or relative=='benchmarks/compact-materialization/probe.c')
        if uses_r:check(str(rinclude/'Rinternals.h') in seen,'Actual bound Rinternals not reached: '+source)
    required_type_rows=[]
    def witness(file,owner,slot,category,size=None):
        candidates=[r for r in tables['types'] if r['file']==file and r['owner']==owner and r['slot']==slot]
        check(bool(candidates),'Missing type witness: '+owner+'/'+slot+' at '+file)
        for r in candidates:
            check(r['category']==category and r['unknown']=='no' and (int(r['size'])>0 if size is None else int(r['size'])==size),'Invalid type witness: '+owner+'/'+slot)
        required_type_rows.extend(candidates)
    witness(str(rinclude/'Rinternals.h'),'SEXP','typedef','pointer',8)
    witness(str(rinclude/'Rinternals.h'),'R_xlen_t','typedef','integral',8)
    declaration=str(root/DECLARATION_HEADER)
    witness(declaration,'dtatools_bracket_live_cache','typedef','class',48)
    for field in ['snapshots','tables','live','namespaces','primitives','length_method']:
        witness(declaration,'dtatools_bracket_live_cache','field:'+field,'pointer',8)
    for name in ['dtatools_probe_bracket_live_cache_init','dtatools_probe_bracket_live_cache_check']:
        witness(declaration,name,'declaration-return','integral',4)
        for index in [0,1]:witness(declaration,name,'declaration-parameter:'+str(index),'pointer',8)
    check(any(declaration in paths for paths in reached.values()),'Declaration-only header not reached from active compilation')
    for name,fields in FIELDS.items():
        file=str(root/(GENERAL if name=='arithmetic_general_output' else INTERNAL))
        witness(file,name,'typedef','class')
        found={r['slot'].removeprefix('field:') for r in tables['types'] if r['file']==file and r['owner']==name and r['slot'].startswith('field:')}
        check(found==set(fields),'Descriptor field set differs: '+name)
        for field,(category,size) in fields.items():witness(file,name,'field:'+field,category,size)
    for file,name,category,size in [(PAYLOAD,'numeric_length','integral',8),(PAYLOAD,'numeric_payload_root','pointer',8),(INTERNAL,'numeric_strict_modern_float','integral',4)]:
        witness(str(root/file),name,'return',category,size)
        witness(str(root/file),name,'parameter:0','pointer',8)
    return {'status':'PASS_MANUAL_ACTIVE_EXTRACTION' if not issues else 'FAIL_MANUAL_ACTIVE_EXTRACTION',
      'issues':issues,'active_translation_units':len(active),'active_headers':len(headers),'historical_snapshot_paths':160,
      'historical_retained116_verdict':'FAIL_UNCHANGED_NOT_REPLACED', 'security_acceptance':False,
      'active_body_records':{p:body.get(p) for p in sorted(originals|current_headers)},
      'compilations':compilations,'external_compilations':external_compilations,'unexpected_compilations':unexpected_compilations,
      'declaration_only_header':DECLARATION_HEADER,'error_facts':errors,'type_witnesses':required_type_rows,
      'per_tu_reachable_includes':{p:sorted(v) for p,v in reached.items()},
      'limits':['This new active-source diagnostic is distinct from the failed116-file historical contract.',
       'Include edges are context-insensitive; per-TU reachability conservatively combines recorded edges and does not prove every preprocessor branch.',
       'Selected types and nonzero body counts are explicit extraction witnesses, not full semantic equivalence.',
       'Linux LP64 and current R headers only; Windows- and Apple-specific bodies are not qualified.']}

def command_from_log(path, command):
    text=path.read_text()
    lines=text.splitlines()
    need(lines and '] This is codeql ' in lines[0], 'Missing actual command line')
    argv=shlex.split(lines[0].split('] This is codeql ',1)[1])
    need(argv[:2]==command.split(), 'Wrong logged command')
    return argv,text

def security_binding(db,init):
    """Verify the actual full evaluator invocation and all unchanged query outputs."""
    expected=init['queries'];need(len(expected)==61, 'Wrong initialized query count')
    for name,row in expected.items():
        source=Path(row['source'])
        need(sha(source)==row['sha256'] and sha(source.with_suffix('.qlx'))==row['compiled_sha256'], 'Official query changed: '+name)
    results={}
    for path in sorted(db.rglob('*.bqrs')):
        relative=path.relative_to(db).as_posix()
        matches=[q for q in expected if relative.endswith('/'+q.removeprefix('codeql/cpp-queries/')[:-3]+'.bqrs')]
        need('/results/codeql/cpp-queries/' in '/'+relative and len(matches)==1, 'Unknown security result: '+relative)
        query=matches[0];need(query not in results,'Duplicate security result')
        results[query]={'path':relative,'sha256':sha(path)}
    need(set(results)==set(expected),'Incomplete default security query results')
    return dict(security_command_binding(db,expected,db/'cpp/log'),results=results)

def security_command_binding(db,expected,log_dir):
    # Diagnostic helper evaluations use a different output directory and are not
    # mistaken for the one full-suite evaluator command.
    run_logs=list(log_dir.glob('database-run-queries-*.log'))
    need(len(run_logs)==1,'Missing or repeated full database query command')
    run_args,_=command_from_log(run_logs[0],'database run-queries')
    candidates=[]
    for path in log_dir.glob('execute-queries-*.log'):
        argv,text=command_from_log(path,'execute queries')
        if '--output='+str(db/'cpp/results') in argv:candidates.append((path,argv,text))
    need(len(candidates)==1,'Missing or repeated full security evaluator command')
    execute,args,text=candidates[0]
    for argv in [run_args,args]:
        cap=[v for v in argv if v.startswith('--max-disk-cache')]
        need(cap==['--max-disk-cache=32768'],'Requested 32 GiB intermediate cache cap not applied exactly')
    need('path:'+str(db/'cpp/temp/config-queries.qls') in args,'Unexpected evaluated security suite')
    finished=re.findall(r'Evaluation done; writing results to (codeql/cpp-queries/[^\r\n]+)\.bqrs\.',text)
    need(len(finished)==61 and {q+'.ql' for q in finished}==set(expected),'Incomplete evaluator completion ledger')
    need(re.findall(r'Exiting with code ([0-9]+)',text)==['0'],'Security evaluator did not exit successfully')
    return {'status':'PASS_CURRENT_NATIVE_SECURITY_COMMAND', 'queries':61,
      'requested_intermediate_cache_mib':32768,'query_commands':[run_args,args],
      'command_logs':{p.name:sha(p) for p in [run_logs[0],execute]},
      'scope':'Full unchanged C++ default suite. Cache cap is an intermediate evaluator-cache bound, not a whole-job disk or RAM limit. Other language gates remain independent.'}

class Collector:
    def __init__(self,args):
        self.root=args.root.resolve();self.work=args.work.resolve();self.db=args.database.resolve();self.cli=args.codeql.resolve()
        self.out=self.work/'extraction';self.temp=Path(os.environ['RUNNER_TEMP']);self.action_temp=Path(os.environ.get('CODEQL_ACTION_TEMP',str(self.temp)))
        self.out.mkdir(parents=True,exist_ok=True)
    def git(self,*args):return subprocess.check_output(['git','--no-replace-objects',*args],cwd=self.root,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')})
    def run(self,name,argv):
        prefix=self.out/'commands'/name;prefix.parent.mkdir(exist_ok=True);need(not prefix.with_suffix('.json').exists(),'Command evidence already exists')
        t=time.time();r=subprocess.run([str(v) for v in argv],cwd=self.root,capture_output=True)
        for kind,raw in [('stdout',r.stdout),('stderr',r.stderr)]:prefix.with_suffix('.'+kind).write_bytes(raw)
        save(prefix.with_suffix('.json'),{'argv':[str(v) for v in argv],'cwd':str(self.root),'returncode':r.returncode,'before':t,'after':time.time(),**{k+'_sha256':sha(prefix.with_suffix('.'+k)) for k in ['stdout','stderr']}})
        need(r.returncode==0,'Command failed: '+name);return r.stdout.decode()
    def facts(self):
        return {'image_os':os.environ.get('ImageOS'),'image_version':os.environ.get('ImageVersion'),'architecture':platform.machine(),'os_release':Path('/etc/os-release').read_text(),'disk':dict(zip(['total','used','free'],shutil.disk_usage(self.root)))}
    def sources(self):
        scope=read(self.work/'active-scope.json');pre=read(self.work/'prebuild.json')
        need(sha(self.work/'active-scope.json')==pre['scope_sha256'], 'Run-bound source scope changed')
        need(scope['source_policy_sha256']==sha(HERE/'native-source-scope.json'), 'Source classification policy changed')
        need(scope['source']==pre['source']==SOURCE and pre['root']==str(self.root),'Wrong source/root')
        need(pre['head']==self.git('rev-parse','HEAD').decode().strip(),'Head changed')
        for group in ['active_translation_units','active_headers','historical_prior_main_43','historical_new_117']:
            for r in scope[group]:
                p=self.root/r['path'];need(p.is_file() and not p.is_symlink() and sha(p)==r['sha256'],'Scoped source changed')
                need(hashlib.sha256(self.git('show',SOURCE+':'+r['path'])).hexdigest()==r['sha256'],'Scoped Git source mismatch')
        for name,h in pre['source_sha256'].items():
            need(sha(self.root/name)==h and hashlib.sha256(self.git('show',SOURCE+':'+name)).hexdigest()==h,'Build input changed: '+name)
        return scope,pre
    def controller_hashes(self):
        workflow=self.root/'.github/workflows/codeql.yml'
        if not workflow.exists():workflow=HERE/'codeql.yml'
        paths=[HERE/'collector.py',HERE/'build.py',HERE/'native-source-scope.json',HERE/'expected-query-names.json',HERE/'cpp.yml']+[HERE/'queries'/(n+'.ql') for n in NAMES]+[HERE/'queries/qlpack.yml']
        return {**{str(p.relative_to(HERE)):sha(p) for p in paths},'workflow':sha(workflow)}
    def external_binding(self,pre):
        bundle=read(self.work/'bundle.json');archive=self.work/'official-codeql-bundle.tar.gz'
        need(set(bundle)=={'url','sha256','bytes'} and bundle['url']==BUNDLE_URL and bundle['sha256']==BUNDLE_SHA,'Wrong official bundle receipt')
        need(archive.is_file() and archive.stat().st_size==bundle['bytes'] and sha(archive)==BUNDLE_SHA,'Official bundle bytes changed')
        include=Path(pre['r_include']);actual={str(p.relative_to(include)):sha(p) for p in sorted(include.rglob('*.h')) if p.is_file()}
        need(actual==pre['r_headers_sha256'] and {'R.h','Rinternals.h','Rversion.h','R_ext/Altrep.h'}<=set(actual),'Actual R headers changed')
        need(set(pre['sdk'])==set(SDK),'Wrong SDK inventory')
        for name,digest in SDK.items():
            row=pre['sdk'][name];path=self.work/'stata-sdk'/name
            need(row['url']=='https://www.stata.com/plugins/'+name and row['sha256']==digest and path.stat().st_size==row['bytes'] and sha(path)==digest,'Actual SDK input changed')
        return {'bundle_receipt_sha256':sha(self.work/'bundle.json'),'bundle_sha256':BUNDLE_SHA,'r_headers_sha256':actual,'sdk':pre['sdk']}
    def initialized(self):
        scope,pre=self.sources();need(not (self.out/'initialized.json').exists(),'Already initialized');external=self.external_binding(pre)
        version=json.loads(self.run('codeql-version',[self.cli,'version','--format=json']))
        need(version['version']=='2.27.1' and version['sha']==CLI_SHA,'Wrong CLI')
        config=self.action_temp/'config';generated=self.action_temp/'user-config.yaml';suite=self.db/'cpp/temp/config-queries.qls'
        state=read(config);expected={'name':'Current maintained C sources with actual build inputs'}
        need(state['languages']==['cpp'] and state['buildMode']=='manual' and state['overlayDatabaseMode']=='none','Wrong manual mode')
        need(state['analysisKinds']==['code-scanning'] and state['extraQueryExclusions']==[],'Query filters changed')
        need(state['originalUserInput']==state['computedConfig']==expected,'Unexpected config/path/model settings')
        need(Path(state['codeQLCmd']).resolve()==self.cli and Path(state['dbLocation']).resolve()==self.db,'Wrong DB/CLI')
        resolved=json.loads(self.run('resolve-default-suite-only',[self.cli,'resolve','queries','--format=json',suite]));queries={}
        for value in resolved:
            marker='/qlpacks/codeql/cpp-queries/1.9.0/';need(marker in value,'Wrong query pack');name='codeql/cpp-queries/'+value.split(marker,1)[1]
            need(name not in queries,'Duplicate query');p=Path(value);queries[name]={'source':str(p),'sha256':sha(p),'compiled_sha256':sha(p.with_suffix('.qlx'))}
        need(set(queries)==set(read(HERE/'expected-query-names.json')) and len(queries)==61,'Default suite changed')
        for source,name in [(config,'action-config.json'),(generated,'generated-config.yml'),(suite,'generated-suite.qls')]:shutil.copyfile(source,self.out/name)
        shutil.copyfile(self.work/'active-scope.json',self.out/'active-scope.json')
        shutil.copyfile(HERE/'native-source-scope.json',self.out/'native-source-scope.json')
        save(self.out/'initialized.json',{'source':SOURCE,'head':pre['head'],'action':ACTION,'cli':str(self.cli),'cli_sha256':sha(self.cli),'cli_version':version,'db':str(self.db),'prebuild_sha256':sha(self.work/'prebuild.json'),'external_inputs':external,'controllers':self.controller_hashes(),'queries':queries,'configs':{n:sha(self.out/n) for n in ['action-config.json','generated-config.yml','generated-suite.qls']},'environment':self.facts(),'security_queries_evaluated':0})
    def build_binding(self,scope,pre):
        build=read(self.work/'build.json');need(build['source']==SOURCE and build['head']==pre['head'] and build['prebuild_sha256']==sha(self.work/'prebuild.json'),'Build receipt mismatch')
        expected={r['path']:r['sha256'] for r in scope['active_translation_units']}
        units=build['translation_units'];need(len(units)==len(expected) and {r['path']:r['sha256'] for r in units}==expected,'Incomplete build ledger')
        for r in units:
            need(r['original_source']==str(self.root/r['path']),'Compiled copy substituted for original source')
            command=self.work/'commands'/(r['command_id']+'.json');c=read(command);need(c['returncode']==0,'Failed compiler group')
            for suffix in ['stdout','stderr']:need(sha(command.with_suffix('.'+suffix))==c[suffix+'_sha256'],'Compiler evidence changed')
            need(r['original_source'] in r['compiler_command'] or str(Path(r['original_source']).relative_to(Path(r['cwd']))) in r['compiler_command'],'Original source absent from compiler argv')
            if 'driver_receipt' in r:need(sha(r['driver_receipt'])==r['driver_receipt_sha256'],'Driver receipt changed')
        for r in build['generated_header_maps']:
            need(sha(r['path'])==r['sha256'],'Derived current header changed')
            if r['mapping_kind']=='byte-identical-current-header':need(r['source_path'] in pre['source_sha256'] and r['sha256']==pre['source_sha256'][r['source_path']],'False identity mapping')
            else:need(r['mapping_kind']=='instrumented-or-extracted-current-source' and r['source_inputs'],'Unbound derived mapping')
            for name,digest in r['source_inputs'].items():
                path='r-package/dtatools/src/'+name
                need(path in pre['source_sha256'] and pre['source_sha256'][path]==digest,'Derived mapping source changed: '+name)
            need(r['driver_receipt'] in {u.get('driver_receipt') for u in units},'Unbound header driver receipt')
        need(build['rust_archive_before_after_equal'] and build['original_source_before_after_equal'],'Build mutability gate failed')
        need(sha(pre['rust_archive'])==pre['rust_archive_sha256'] and sha(pre['makevars'])==pre['makevars_sha256'],'Build support changed')
        return build
    def collect(self):
        scope,pre=self.sources();init=read(self.out/'initialized.json');build=self.build_binding(scope,pre)
        need(init['controllers']==self.controller_hashes() and init['cli_sha256']==sha(self.cli),'Controller or CLI changed')
        need(init['external_inputs']==self.external_binding(pre),'External inputs changed since initialization')
        for live,name in [(self.action_temp/'config','action-config.json'),(self.action_temp/'user-config.yaml','generated-config.yml'),(self.db/'cpp/temp/config-queries.qls','generated-suite.qls')]:need(sha(live)==init['configs'][name],'Effective configuration changed')
        security=security_binding(self.db,init)
        need(os.environ.get('ANALYSIS_STEP_OUTCOME')=='success', 'Official security analysis did not succeed')
        save(self.out/'security-analysis.json',security)
        metadata=self.db/'cpp/codeql-database.yml';text=metadata.read_text()
        metadata_binding(text,self.root,pre['head'])
        shutil.copyfile(metadata,self.out/'codeql-database.yml');qout=self.out/'queries';qout.mkdir()
        evidence={}
        for name in NAMES:
            source=HERE/'queries'/(name+'.ql');bqrs=qout/(name+'.bqrs');csvfile=qout/(name+'.csv')
            self.run(name+'-query',[self.cli,'query','run','--database='+str(self.db/'cpp'),'--search-path='+str(self.cli.parent/'qlpacks'),'--threads=2','--ram=3072','--max-disk-cache=1024','--common-caches='+str(self.work/'query-cache'),'--output='+str(bqrs),source])
            self.run(name+'-decode',[self.cli,'bqrs','decode','--format=csv','--result-set=#select','--output='+str(csvfile),bqrs])
            evidence[name]={'query_sha256':sha(source),'bqrs_sha256':sha(bqrs),'csv_sha256':sha(csvfile)}
        need(security_binding(self.db,init)==security, 'Security results/commands changed during coverage collection');self.sources()
        need(self.controller_hashes()==init['controllers'] and sha(self.cli)==init['cli_sha256'],'Controller or CLI changed during query collection')
        need(init['external_inputs']==self.external_binding(pre),'External inputs changed during collection')
        verdict=qualify(tables_at(qout),scope,pre,build)
        save(self.out/'collection.json',{'source':SOURCE,'head':pre['head'],'status':'COLLECTED','security_queries_evaluated':61,'security_analysis_sha256':sha(self.out/'security-analysis.json'),'tables':evidence,'verdict':verdict,'build_sha256':sha(self.work/'build.json'),'controllers_after':self.controller_hashes(),'environment_after':self.facts()})
        need(verdict['status']=='PASS_MANUAL_ACTIVE_EXTRACTION','Manual active-source qualification failed; tables/verdict preserved')
    def finish(self):
        for source,name in [(self.db/'log','cluster-log'),(self.db/'cpp/log','cpp-log'),(self.db/'cpp/diagnostic','cpp-diagnostic'),(self.work/'commands','build-commands')]:
            if source.exists():
                need(not any(p.is_symlink() for p in source.rglob('*')),'Symlink in retained logs');shutil.copytree(source,self.out/'raw'/name,dirs_exist_ok=True)
        for name in ['prebuild.json','build.json','bundle.json']:
            if (self.work/name).is_file():shutil.copyfile(self.work/name,self.out/name)
        retained={};omitted={}
        def retain(path,expected=None,required_text=True):
            path=Path(path)
            need(path.is_file() and not path.is_symlink(),'Missing or symlink evidence child: '+str(path))
            digest=sha(path);need(expected is None or digest==expected,'Evidence child changed: '+str(path))
            try:relative=path.relative_to(self.work)
            except ValueError:relative=Path('configured-package')/path.name
            destination=self.out/'build-inputs'/relative
            raw=path.read_bytes()
            try:raw.decode('utf-8');need(b'\0' not in raw,'NUL in text evidence')
            except (UnicodeDecodeError,ValueError):
                need(not required_text,'Nontext required evidence: '+str(path))
                omitted[str(path)]={'sha256':digest,'bytes':len(raw),'reason':'Binary build artifact; excluded from uploaded text diagnostic'};return
            destination.parent.mkdir(parents=True,exist_ok=True)
            if destination.exists():need(sha(destination)==digest,'Retention destination collision')
            else:destination.write_bytes(raw)
            retained[str(path)]={'sha256':digest,'published_path':str(destination.relative_to(self.out))}
        if (self.work/'prebuild.json').is_file():
            pre=read(self.work/'prebuild.json')
            retain(pre['makevars'],pre['makevars_sha256'])
            for name,row in pre['sdk'].items():retain(self.work/'stata-sdk'/name,row['sha256'])
            for path,expected,reason in [(Path(pre['rust_archive']),pre['rust_archive_sha256'],'Prebuilt Rust static archive'),
                (self.work/'official-codeql-bundle.tar.gz',BUNDLE_SHA,'Official CodeQL bundle')]:
                if path.is_file():
                    need(sha(path)==expected,'Omitted artifact changed')
                    omitted[str(path)]={'sha256':expected,'bytes':path.stat().st_size,'reason':reason}
        if (self.work/'build.json').is_file():
            build=read(self.work/'build.json')
            for row in build['generated_header_maps']:retain(row['path'],row['sha256'])
            for row in build['translation_units']:
                if 'driver_receipt' not in row:continue
                receipt=Path(row['driver_receipt']);retain(receipt,row['driver_receipt_sha256'])
                for name,digest in read(receipt).get('artifact_sha256',{}).items():
                    child=Path(name);need(not child.is_absolute() and '..' not in child.parts,'Unsafe driver artifact path')
                    retain(receipt.parent/child,digest,required_text=False)
        save(self.out/'retained-build-inputs.json',{'retained':retained,'omitted':omitted,
             'limits':'External R header bytes are hash-bound before and after extraction; the full include tree is not uploaded. Full database/source archive and package shared objects are not retained.'})
        save(self.out/'final-resources.json',{'facts':self.facts(),'observed_job_status':os.environ.get('OBSERVED_JOB_STATUS'),'analysis_step_outcome':os.environ.get('ANALYSIS_STEP_OUTCOME'),'security_acceptance':'Determined by the complete five-language workflow and this coverage job; this manifest alone is not acceptance'})
        files={str(p.relative_to(self.out)):sha(p) for p in sorted(self.out.rglob('*')) if p.is_file() and p != self.out/'final-manifest.json'}
        save(self.out/'final-manifest.json',{'status':'RETAINED_CURRENT_NATIVE_SECURITY_VALIDATION','artifacts':files,'omitted':['Rust archive, full CodeQL database/source archive, downloaded bundle; their recorded hashes/identities remain distinct from retained artifact bytes.']})

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('phase',choices=['initialized','collect','finish'])
    for n in ['root','work','database','codeql']:p.add_argument('--'+n,type=Path,required=True)
    args=p.parse_args()
    SOURCE=subprocess.check_output(['git','--no-replace-objects','rev-parse','HEAD'],cwd=args.root,env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}).decode().strip()
    need(re.fullmatch(r'[0-9a-f]{40}',SOURCE), 'Invalid current source commit')
    getattr(Collector(args),args.phase)()
