"""Private actual-Rust API and search-work gate, independent of timing."""
import argparse, csv, hashlib, io, json, os, re, shutil, subprocess, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = Path('<private-work>/dta-retained-uniform-locator')
PROBE = Path('<private-work>/dta-retained-span-evidence/rust-red-bound/retained_span_probe.rs')
TRACE = Path('<private-work>/dta-retained-span-evidence/poll-v2-green-final')
SOURCE = 'r-package/dtatools/src/rust/src/owned_numeric.rs'

def need(x, message):
    if not x:
        raise RuntimeError(message)

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def inventory(root):
    return {str(p.relative_to(root)): sha(p) for p in root.rglob('*') if p.is_file()}

p = argparse.ArgumentParser()
p.add_argument('--commit', required=True)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--expect', choices=('red', 'green'), required=True)
a = p.parse_args()
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
root = out / 'source'
root.mkdir()
env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
commit = subprocess.check_output(['git', '--no-replace-objects', 'rev-parse', a.commit + '^{commit}'], cwd=REPO, env=env, text=True).strip()
archive = subprocess.check_output(['git', '--no-replace-objects', 'archive', commit, 'r-package/dtatools/src/rust', 'r-package/dtatools/src/dta-tools'], cwd=REPO, env=env)
with tarfile.open(fileobj=io.BytesIO(archive)) as t:
    t.extractall(root, filter='data')
original = inventory(root)
path = root / SOURCE
source = path.read_text()
anchor = 'static LIVE_NATIVE_BYTES:'
need(source.count(anchor) == 1, 'counter insertion anchor')
source = source.replace(anchor, 'thread_local! { static CHUNK_SEARCH_COMPARISONS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }\n' + anchor)
pattern = r'\.partition_point\(\|chunk\| chunk\.end <= (start|index)\)'
source, count = re.subn(pattern, lambda m: '.partition_point(|chunk| { CHUNK_SEARCH_COMPARISONS.with(|count| count.set(count.get() + 1)); chunk.end <= ' + m[1] + ' })', source)
need(count == (3 if a.expect == 'red' else 1), 'unexpected search instrumentation count')
source += '\n#[cfg(test)]\n#[path = "retained_span_probe.rs"]\nmod retained_span_probe;\n'
path.write_text(source)
shutil.copyfile(PROBE, path.with_name('retained_span_probe.rs'))
before = inventory(root)
compiler = Path(shutil.which('rustc')).resolve()
cargo = Path(shutil.which('cargo')).resolve()
tools = {str(t): sha(t) for t in (compiler, cargo)}
controller = sha(__file__)
probe_hash = sha(PROBE)
trace_receipt = json.loads((TRACE / 'receipt.json').read_text())
need(trace_receipt['commit'] == 'e1b0278b1403b4d8fc2d9a2dfc0c4ddaa7cde3a2' and trace_receipt['exit_code'] == 0 and trace_receipt['cases'] == 18 and trace_receipt['semantic_failures'] == 0 and trace_receipt['work_failures'] == 0, 'C trace qualification')
trace_binding = {name: sha(TRACE / name) for name in ('receipt.json', 'work-count.csv')}
need(trace_binding['work-count.csv'] == trace_receipt['artifact_sha256']['work-count.csv'], 'C trace CSV binding')
sysroot = Path(subprocess.check_output([str(compiler), '--print', 'sysroot'], cwd=root, env=env, text=True).strip())
selected_rustc = (sysroot / 'bin/rustc').resolve(strict=True)
rustc_version = subprocess.check_output([str(selected_rustc), '--version', '--verbose'], cwd=root, env=env, text=True)
tools[str(selected_rustc)] = sha(selected_rustc)
need(not env.get('RUSTC_WRAPPER') and not env.get('RUSTC_WORKSPACE_WRAPPER'), 'private probe requires direct compiler execution')
env['RUSTC'] = str(selected_rustc)
env['CARGO_TARGET_DIR'] = str(HERE / 'rust-target')
command = [str(cargo), 'test', '--offline', '--locked', '--manifest-path', 'r-package/dtatools/src/rust/Cargo.toml', '--no-run', '--message-format=json']
r = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True)
(out / 'build.jsonl').write_text(r.stdout)
(out / 'build.log').write_text(r.stderr)
need(r.returncode == 0, 'Rust probe compile failed')
records = [json.loads(line) for line in r.stdout.splitlines() if line.startswith('{')]
binaries = [Path(x['executable']) for x in records if x.get('reason') == 'compiler-artifact' and x.get('executable') and x['target']['name'] == 'dtatools_r' and x['profile']['test']]
need(len(binaries) == 1, 'ambiguous probe executable')
binary = binaries[0]
binary_hash = sha(binary)
env['DTATOOLS_SPAN_PROBE_OUTPUT'] = str(out / 'work-count.csv')
env['DTATOOLS_REQUIRE_UNIFORM_LOOKUP'] = '1'
run_command = [str(binary), '--exact', 'owned_numeric::retained_span_probe::retained_span_work_probe', '--nocapture', '--test-threads=1']
r = subprocess.run(run_command, cwd=root, env=env, capture_output=True, text=True)
(out / 'run.log').write_text(r.stdout + r.stderr)
failures = 10 if a.expect == 'red' else 0
need(r.returncode == (101 if failures else 0) and f'11367 API checks passed, {failures} uniform search-work failures' in r.stdout + r.stderr, 'semantic/work gate')
with (out / 'work-count.csv').open() as f:
    rows = list(csv.DictReader(f))
need(len(rows) == 12 and len({tuple(x[k] for k in ('length', 'long_chunk', 'float_chunk', 'reverse')) for x in rows}) == 12, 'complete Rust geometry')
with (TRACE / 'work-count.csv').open() as f:
    crows = list(csv.DictReader(f))
need(len(crows) == 18, 'complete C geometry')
for c in crows:
    matches = [x for x in rows if all(x[k] == c[k] for k in ('length', 'long_chunk', 'float_chunk', 'reverse'))]
    need(len(matches) == 1 and all(matches[0][k] == c[k] for k in ('span_calls', 'span_trace')), 'C/Rust request trace')
need(before == inventory(root) and sha(binary) == binary_hash and sha(__file__) == controller and sha(PROBE) == probe_hash and tools == {str(t): sha(t) for t in (compiler, cargo, selected_rustc)}, 'source/build/tools changed')
need(trace_binding == {name: sha(TRACE / name) for name in trace_binding}, 'C trace receipt/CSV changed')
receipt = dict(status='EXPECTED_RED' if failures else 'PASS', commit=commit, original_source=original, instrumented_source=before, instrumented_searches=count, controller_sha256=controller, probe_sha256=probe_hash, compiler_hashes=tools, selected_rustc=str(selected_rustc), rustc_version=rustc_version, binary_sha256=binary_hash, build_command=command, build_rustc_environment=env['RUSTC'], run_command=run_command, exit_code=r.returncode, api_checks=11367, uniform_work_failures=failures, geometries=12, c_header_cases=18, c_header_binding=trace_binding, artifacts={p.name: sha(p) for p in out.iterdir() if p.is_file()}, scope='Untimed real Rust owner and exported APIs, private predicate instrumentation, immutable source export; original C request traces unchanged. No public-R or reader timing claim.')
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ('status', 'commit', 'api_checks', 'uniform_work_failures', 'geometries', 'c_header_cases')}))
