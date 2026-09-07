import pathlib, subprocess, json, os, hashlib, datetime, time
root = pathlib.Path('/private/tmp/dta-direct-stage4')
validation = pathlib.Path('/private/tmp/dta-direct-stage4-validation')
source = validation / 'source-c8ca0a4'
lib = validation / 'candidate-c8ca0a4-library'
sha = 'c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe'
out = validation / 'native-c8ca0a4'
out.mkdir()
manifest = json.loads((validation / 'source-c8ca0a4-manifest.json').read_text())
records = []
def guard_source():
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() != sha:
        raise RuntimeError('Qualification checkout revision changed')
    for name, item in manifest['entries'].items():
        path = source / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256'] or (path.stat().st_mode & 0o777) != int(item['mode'], 8):
            raise RuntimeError('Archived source bytes/mode changed: ' + name)
    for revision in ['ec10a6ac34602f3bd691e8043019c1b479babda4', sha]:
        blob = subprocess.check_output(['git', 'show', revision + ':benchmarks/r-reference-mutation/run.R'], cwd=root)
        if hashlib.sha256(blob).hexdigest() != '31a103ea84e9415d42b0074f01ee13dc1c85a985842ce024c477e1532d1f4ee8':
            raise RuntimeError('Original native runner changed')
    for name in ['benchmarks/r-reference-mutation/owned-atoms.R', 'benchmarks/r-dibble-dplyr/helpers.R']:
        if (root/name).read_bytes() != (source/name).read_bytes():
            raise RuntimeError('Current native runner dependency differs from exact source')

def run(name, command, cwd=source, env=None):
    started = datetime.datetime.now(datetime.timezone.utc).isoformat(); begin = time.monotonic()
    path = out / (name + '.log')
    with path.open('x') as log: result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    records.append(dict(name=name, command=command, cwd=str(cwd), started=started, seconds=time.monotonic()-begin, exit_code=result.returncode, log=str(path)))
    with (out / 'commands.json').open('w') as report: json.dump(records, report, indent=2)
    print(name, result.returncode, flush=True)
    if result.returncode: raise RuntimeError('Native qualification failed: ' + name)
guard = 'source("benchmarks/r-dibble-dplyr/helpers.R"); lib <- "' + str(lib) + '"; sha <- "' + sha + '"; validate_benchmark_install(lib,sha); .libPaths(c(lib,.libPaths())); library(dtatools); package <- normalizePath(file.path(lib,"dtatools")); dll <- normalizePath(file.path(package,"libs",paste0("dtatools",.Platform$dynlib.ext))); stopifnot(identical(normalizePath(find.package("dtatools")),package), identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),dll)); cat("source",sha,"\npackage",package,"\ndll",dll,"\nDLL MD5",tools::md5sum(dll),"\n"); validate_benchmark_install(lib,sha)'
guard_source()
run('identity-before', ['Rscript','--vanilla','-e',guard])
env = os.environ.copy()
env.update(DTATOOLS_BENCHMARK_CHILD='1', DTATOOLS_BENCHMARK_LIBRARY=str(lib), DTATOOLS_BENCHMARK_SHA=sha, DTATOOLS_BENCHMARK_STATE='clean')
run('original-native', ['Rscript','--vanilla',str(source/'benchmarks/r-reference-mutation/run.R'),'--markdown='+str(out/'original-native.md')], env=env)
atom_out = out / 'atoms'; atom_out.mkdir()
run('native-atoms', ['Rscript','--vanilla','benchmarks/r-reference-mutation/owned-atoms.R',str(lib),sha,str(atom_out)], cwd=root)
run('rename-allocation', ['Rscript','--vanilla','benchmarks/r-dibble-dplyr/check-rename-allocation.R',str(lib)])
run('identity-after', ['Rscript','--vanilla','-e',guard])
guard_source()
record = dict(source_sha=sha, source_tree=manifest['source_tree'], package_tree=manifest['package_tree'], library=str(lib), archive_sha256=manifest['archive_sha256'], archived_files_checked_before_and_after=len(manifest['files']), runner_hashes={name: manifest['files'][name] for name in ['benchmarks/r-reference-mutation/run.R','benchmarks/r-reference-mutation/owned-atoms.R','benchmarks/r-dibble-dplyr/helpers.R','benchmarks/r-dibble-dplyr/check-rename-allocation.R']}, commands=records)
with (out/'qualification.json').open('x') as report: json.dump(record,report,indent=2)
record['driver_sha256'] = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
record['logs'] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(out.glob('*.log'))}
with (out/'complete-qualification.json').open('x') as report: json.dump(record,report,indent=2)
print('Exact archived-source native qualification complete.', flush=True)
