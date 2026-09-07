import pathlib, subprocess, json, os, hashlib, datetime, time
root = pathlib.Path('/private/tmp/dta-direct-stage4')
validation = pathlib.Path('/private/tmp/dta-direct-stage4-validation')
source = validation / 'source-976cc40'
lib = validation / 'candidate-976cc40-library'
sha = '976cc403f21b9adbb454d39c9c3447717b67c29f'
out = validation / 'native-976cc40'
out.mkdir()
manifest = json.loads((validation / 'source-976cc40-manifest.json').read_text())
records = []
def guard_source():
    mismatches = [name for name, digest in manifest['files'].items() if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest]
    if mismatches: raise RuntimeError('Archived source changed: ' + repr(mismatches))
    before = subprocess.check_output(['git', 'rev-parse', 'ec10a6ac34602f3bd691e8043019c1b479babda4:benchmarks/r-reference-mutation/run.R'], cwd=root)
    after = subprocess.check_output(['git', 'rev-parse', sha + ':benchmarks/r-reference-mutation/run.R'], cwd=root)
    if before != after: raise RuntimeError('Original native runner changed')
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
print('Exact archived-source native qualification complete.', flush=True)
