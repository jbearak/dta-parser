from pathlib import Path
import json,shutil,subprocess,hashlib,time
base=Path('<work>/combined-v1')
out=Path('<work>/finalizer-checkpoint')
record=json.loads((base/'record.json').read_text())
(out/'src').mkdir(parents=True,exist_ok=False)
for p in (base/'src').iterdir():
    if p.name in ('numeric-payload.o','dtatools.so'): continue
    dest=out/'src'/p.name
    if p.name in ('numeric-payload.c','numeric-arithmetic-integer.h'):
        shutil.copy2(p,dest)
    else: dest.symlink_to(p,target_is_directory=p.is_dir())
shutil.copytree(base/'library',out/'library',symlinks=True)
p=out/'src/numeric-arithmetic-integer.h'
s=p.read_text(); needle='        arithmetic_integer_preflight(left, right, length, operation, &plan);\n'
assert s.count(needle)==1
s=s.replace(needle,needle+'        R_gc(); /* PRIVATE exact-window finalizer stress, never production. */\n')
p.write_text(s)
for kind in ('compile','link'):
    with (out/(kind+'.log')).open('w') as stream:
        r=subprocess.run(record[kind+'_arguments'],cwd=out/'src',stdout=stream,stderr=subprocess.STDOUT)
    assert r.returncode==0,(kind,r.returncode)
shutil.copy2(out/'src/dtatools.so',out/'library/dtatools/libs/dtatools.so')
record['purpose']='Private exact-window finalizer checkpoint; simulates immediate-finalizer R build, not observed default R allocation behavior.'
record['base']=str(base)
record['changed_header_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
record['dll_sha256']=hashlib.sha256((out/'library/dtatools/libs/dtatools.so').read_bytes()).hexdigest()
(out/'record.json').write_text(json.dumps(record,indent=2)+'\n')
print(out)
