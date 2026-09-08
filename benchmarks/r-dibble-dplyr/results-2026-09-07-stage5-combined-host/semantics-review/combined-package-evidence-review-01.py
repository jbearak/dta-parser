from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re, subprocess, tarfile

root=Path('/private/tmp/dta-direct-stage5-validation/implementation')
folder=root/'package-combined-01';repo=Path('/private/tmp/dta-direct-stage5');review=Path(__file__).parent
source='a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9'
def git(*args):return subprocess.check_output(['git',*args],cwd=repo)
def ident(p):
 p=Path(p);q=p.resolve(strict=True);s=q.stat();h=hashlib.sha256()
 with q.open('rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return dict(path=str(p),resolved=str(q),bytes=s.st_size,mode=oct(s.st_mode&0o777),sha256=h.hexdigest())
receipt=ident(folder/'receipt.json');assert receipt['sha256']=='a015a466e8de2d0314bf28b49eb29a5533b423e17de4839944aa3f43297a892d'
r=json.loads((folder/'receipt.json').read_text());m=json.loads((folder/'manifest.json').read_text());b=json.loads((folder/'inputs-before.json').read_text());e=json.loads((folder/'execution-result.json').read_text())
assert r['status']==e['status']=='complete' and not r['changed_inputs'] and not e['changed_inputs']
assert r['source_sha']==r['runner_sha']==b['source_sha']==b['runner_sha']==source
assert r['manifest']==ident(folder/'manifest.json')
for row in m['products']:assert ident(row['path'])==row,row['path']
assert len({x['path'] for x in m['products']})==len(m['products'])
assert {x['path'] for x in m['products']}=={str(p) for p in folder.rglob('*') if p.is_file()}-{str(folder/'manifest.json'),str(folder/'receipt.json')}
for row in b['inputs']:assert ident(row['path'])==row,row['path']
assert len(e['records'])==16 and all(x['exit_code']==0 for x in e['records'])
archive=json.loads((folder/'built-source-before-checks.json').read_text());assert ident(archive['path'])==archive
for command in e['records']:
 if command['label'] in ['archive','check','binary']:assert archive['path'] in command['command']
driver=folder/'source/benchmarks/r-dibble-dplyr/run-expression-checks.py'
assert driver.read_bytes()==git('show',source+':benchmarks/r-dibble-dplyr/run-expression-checks.py')
assert driver.read_bytes()==git('show','57309d40433a92d99849fefa155ae7b22b86b337:benchmarks/r-dibble-dplyr/run-expression-checks.py')
notice=git('show',source+':r-package/dtatools/inst/NOTICE');news=git('show',source+':r-package/dtatools/NEWS.md')
binary=folder/'binary/dtatools_0.7.1.tgz'
with tarfile.open(archive['path'],'r:*') as tar:
 assert tar.extractfile('dtatools/inst/NOTICE').read()==notice
 assert tar.extractfile('dtatools/NEWS.md').read()==news
 for rel in ['R/output-container.R','R/dibble-expressions.R','src/init.c','tests/testthat/helper-generation-interrupt.R','tests/testthat/test-dibble-expressions.R','tests/testthat/test-mutate-data.R']:
  assert tar.extractfile('dtatools/'+rel).read()==git('show',source+':r-package/dtatools/'+rel)
with tarfile.open(binary,'r:*') as tar:
 assert tar.extractfile('dtatools/NOTICE').read()==notice
 assert tar.extractfile('dtatools/NEWS.md').read()==news
for installed in [folder/'dtatools.Rcheck/dtatools',folder/'binary/library/dtatools']:
 assert (installed/'NOTICE').read_bytes()==notice and (installed/'NEWS.md').read_bytes()==news
def sections(path):
 text=path.read_text();blocks=re.split(r'(?=^\* checking )',text,flags=re.M)
 selected=[x for x in blocks if re.match(r'^\* checking .* \.\.\. (WARNING|NOTE)\n',x)]
 cleaned=[]
 for block in selected:
  block=block.replace(str(path.parent),'<RCHECK>')
  block=re.sub(r'rust/target/[0-9a-f]+','rust/target/<HASH>',block)
  block=re.sub(r'zstd-sys-[0-9a-f]+','zstd-sys-<HASH>',block)
  # Compiler/SDK informational lines may follow an installation warning.
  block=re.sub(r'^\* used (C compiler|SDK):.*\n','',block,flags=re.M)
  cleaned.append(block)
 return cleaned
current=folder/'dtatools.Rcheck/00check.log';previous=root/'package-final-02/dtatools.Rcheck/00check.log'
check=current.read_text();assert 'Status: 3 WARNINGs, 2 NOTEs' in check and '* checking tests ... OK' in check and 'Problems with news' not in check and 'No news entries found' not in check
assert sections(current)==sections(previous)
rout=(folder/'dtatools.Rcheck/tests/testthat.Rout').read_text()
assert '[ FAIL 0 | WARN 4 | SKIP 0 | PASS 16750 ]' in rout
result=dict(utc=datetime.now(timezone.utc).isoformat(),status='combined_exact_host_package_gate_evidence_clear',source=source,runner=source,package_tree='b08c77d91bdce67032f13aced90c29d068d6e95a',reviewer_script=ident(__file__),receipt=receipt,manifest=ident(folder/'manifest.json'),products=len(m['products']),product_bytes=sum(x['bytes'] for x in m['products']),bound_inputs=len(b['inputs']),input_bytes=sum(x['bytes'] for x in b['inputs']),command_exits={x['label']:x['exit_code'] for x in e['records']},consumed_source_archive=archive,binary_archive=ident(binary),rcheck=dict(log=ident(current),baseline_comparison=ident(previous),warnings=3,notes=2,normalized_warning_note_sections_match=True,test_passes=16750,test_failures=0,test_skips=0,test_warnings=4,news_parser_subnote_absent=True),assessment='All16 package commands passed on exact a2 sources and runner, including archive/vendor tests, interoperability, corpus framework, pinned roxygen, conformance, source build/archive, R CMD check and binary build. All completed products and declared inputs are unchanged. The built source archive was bound before its three consuming commands by the unchanged previously reviewed guard. Actual source archive code/test bytes match a2. Source/binary/check-installed/binary-installed NOTICE and NEWS match exact source bytes. The current Rcheck retains the same three warning and two note sections as package-final-02 after normalizing output/build paths, with no NEWS parser sub-note. Its retained testthat output has16750 passes, no failures/skips and four known warnings.',limits=['The warning categories remain recorded: macOS link deployment version, vendored GNU Makefiles and Rust abort entry point; notes cover vendored CITATION and generated flag_check.c newline. They are not relabeled as zero-warning checks.','This gate uses host R4.6.1 with --no-manual. It does not replace minimum-runtime or Windows checks, pending native allocation/readiness qualification, performance/memory/write-cost acceptance or external CI/review/merge.','All outputs retain a2 source and runner identities. The later ea031 progress-only correction has the same package tree.','No package command, test or benchmark was rerun. Archives were read without extraction and retained manifests, input files and current Rcheck output were independently audited.'])
with (review/'combined-package-evidence-review-01.json').open('x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
print(json.dumps(dict(status=result['status'],products=result['products'],inputs=result['bound_inputs'],commands=16,rcheck_passes=16750,warnings=3,notes=2)))
