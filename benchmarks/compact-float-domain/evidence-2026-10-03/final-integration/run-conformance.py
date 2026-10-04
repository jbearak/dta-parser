from pathlib import Path
import hashlib,json,os,shutil,subprocess
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent
REPO=Path('<final_repository>')
EXPORT=HERE/'conformance-export'
COMMIT='3eadb244253fb817d5773b01b11cb36c284f3a1d'
def need(ok,message):
    if not ok: raise RuntimeError(message)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
EXPORT.mkdir(exist_ok=False)
git_env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
archive=subprocess.Popen(['git','--no-replace-objects','archive',COMMIT],cwd=REPO,env=git_env,stdout=subprocess.PIPE)
extract=subprocess.run(['tar','-x','-C',str(EXPORT)],stdin=archive.stdout)
archive.stdout.close()
archive_status=archive.wait()
need(archive_status==0 and extract.returncode==0,'Immutable export failed')
original=(EXPORT/'scripts/conformance.sh').read_text()
old="trap 'rm -rf \"$temporary\"' EXIT HUP INT TERM"
new="trap 'cp -R \"$temporary\" "+str(HERE/'conformance-preserved')+"; rm -rf \"$temporary\"' EXIT HUP INT TERM"
need(original.count(old)==1,'Conformance preservation seam is not unique')
wrapper=HERE/'conformance-gate.sh';wrapper.write_text(original.replace(old,new))
validator=HERE/'validate-conformance-archive.py'
shutil.copyfile('<private-work>/dta-compact-materialization-evidence/validate-conformance-archive.py',validator)
overrides={'DTA_REQUIRE_R_CONFORMANCE':'1','R_ENVIRON_USER':'/dev/null','R_PROFILE_USER':'/dev/null','CARGO_TARGET_DIR':'<private-work>/dta-native-comparison-followup/target'}
env={k:v for k,v in os.environ.items() if not k.startswith('GIT_')};env.update(overrides)
controller_sha=sha(Path(__file__))
command={'controller_sha256':controller_sha,'commit':COMMIT,'command':['sh',str(wrapper)],'cwd':str(EXPORT),'environment':overrides,'original_script_sha256':sha(EXPORT/'scripts/conformance.sh'),'wrapper_sha256':sha(wrapper),'validator_sha256':sha(validator),'only_wrapper_change':'Preserve temporary source archive and complete check outputs before original cleanup.','started_utc':datetime.now(timezone.utc).isoformat()}
(HERE/'conformance-command.json').write_text(json.dumps(command,indent=2)+'\n')
with (HERE/'conformance.log').open('wb') as log: result=subprocess.run(command['command'],cwd=EXPORT,env=env,stdout=log,stderr=subprocess.STDOUT)
command.update(exit_code=result.returncode,finished_utc=datetime.now(timezone.utc).isoformat())
(HERE/'conformance-command.json').write_text(json.dumps(command,indent=2)+'\n')
if result.returncode: raise RuntimeError('Required conformance failed; retained original log and temporary tree')
archives=list((HERE/'conformance-preserved').glob('dtatools_*.tar.gz'))
need(len(archives)==1,'Retained source archive is absent or ambiguous')
shutil.copyfile(archives[0],HERE/'conformance.tar.gz')
subprocess.run(['python3',str(validator),str(REPO),str(EXPORT/'r-package/dtatools'),str(HERE/'conformance'),COMMIT],cwd=EXPORT,env=env,check=True)
need(sha(Path(__file__))==controller_sha,'Conformance controller changed during execution')
print('Combined required conformance and immutable archive binding PASS')
