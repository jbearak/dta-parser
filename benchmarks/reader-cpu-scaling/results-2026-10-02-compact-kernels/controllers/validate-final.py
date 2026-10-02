from pathlib import Path
import csv,hashlib,json,subprocess,importlib.util
from datetime import datetime,timezone
r=Path('<compact-work>');repo=Path('<repository>')
old=Path('<scalar-work>');b=r/'candidate-kernel-float'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())
def number(value):return {'TRUE':1,'FALSE':0}.get(value, float(value) if value not in ('TRUE','FALSE') else 0)
rows=list(csv.DictReader((r/'full-tests.csv').open()))
counts={key:sum(int(number(row[key])) for row in rows) for key in ('passed','failed','error','warning','skipped')}
assert counts['failed']==counts['error']==counts['skipped']==0
previous=list(csv.DictReader((old/'full-tests.csv').open()))
def warnings(rows):return sorted((x['file'],x['test'],int(float(x['warning']))) for x in rows if int(float(x['warning'])))
assert warnings(rows)==warnings(previous)
source_files=[p for p in (b/'source').rglob('*') if p.is_file()]
assert len(source_files)==449
assert all((repo/'r-package/dtatools'/p.relative_to(b/'source')).read_bytes()==p.read_bytes() for p in source_files)
rust=[p for p in source_files if str(p.relative_to(b/'source')).startswith(('src/rust/','src/dta-tools/'))]
assert all((old/'candidate-combined/source'/p.relative_to(b/'source')).read_bytes()==p.read_bytes() for p in rust)
spec=importlib.util.spec_from_file_location('records',repo/'benchmarks/r-file-readers/record-builds.py');records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
receipt,patch,receipt_hash=records.verified_receipt(b,'candidate')
a=r/'acceptance';completion=read(a/'completion.json')
assert completion['observations']==504 and completion['processes']==252 and not completion['parity_failures']
assert read(a/'provenance-before.json')==read(a/'provenance-after.json')
assert 'GREEN' in (r/'accepted-repro.log').read_text()
assert all(row['exact']=='TRUE' and row['lazy']=='TRUE' for row in csv.DictReader((r/'block-boundary.csv').open()))
assert subprocess.run(['git','diff','--check'],cwd=repo).returncode==0
parity=list(csv.DictReader((a/'parity.csv').open()))
result=dict(validated_utc=datetime.now(timezone.utc).isoformat(),accepted_build_receipt_sha256=receipt_hash,accepted_library_sha256=receipt['installed_inventory']['libs/dtatools.so'],production_source_files=len(source_files),production_source_matches_accepted_build=True,full_r_suite={**counts,'tests':len(rows),'warnings_match_previous_by_test_and_count':True,'results_sha256':sha(r/'full-tests.csv'),'log_sha256':sha(r/'full-tests.log')},acceptance=completion,parity={metric:dict(largest_paired_ratio=max(float(x['paired_ratio']) for x in parity if x['metric']==metric),largest_upper95=max(float(x['upper95']) for x in parity if x['metric']==metric)) for metric in ('cpu','wall')},original_parity_repro='GREEN',block_boundary_cases=20,build_test_or_profile_overlapped_timing=False,git_diff_check_exit_code=0,rust_sources_unchanged_from_previously_validated_candidate=True,rust_source_files_compared=len(rust),not_rerun=['R CMD check','full cross-language conformance','Rust tests/Clippy/format: sources unchanged from preceding accepted build'],benchmark_qualification='Native reductions exact against ordinary doubles; public results follow existing Stata storage policy, including float scalar rounding.')
(r/'final-validation.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps(result,indent=2))
