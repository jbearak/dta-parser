"""Read-only Stage 4 downstream parity against an unchanged historical fixture state.

This uses an isolated package library. It does not activate or edit renv and
cannot replace the final epic's merged-main renv install/test/restore check.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    with path.open('x') as file:
        json.dump(value, file, indent=2)
        file.write('\n')


require(len(sys.argv) == 4, 'Usage: check-fertility-candidate.py SOURCE_SHA LIBRARY NEW_OUTPUT_DIRECTORY')
source_sha = sys.argv[1]
library, output = map(lambda x: Path(x).resolve(), sys.argv[2:])
require(re.fullmatch('[0-9a-f]{40}', source_sha) is not None, 'Expected full package source SHA')
require(library.is_dir(), 'Missing candidate library')
require(not output.exists(), f'Refusing to replace evidence: {output}')
dlls = [path for path in (library / 'dtatools/libs').glob('dtatools.*')
        if path.suffix in {'.so', '.dll', '.dylib'} and path.is_file()]
require(len(dlls) == 1, 'Expected one installed candidate native library')
dll = dlls[0]
dll_md5 = hashlib.md5(dll.read_bytes()).hexdigest()
repo = Path('/Users/jmb/repos/fertility_surveys')
package_repo = Path('/private/tmp/dta-direct-stage4')
prior = Path('/private/tmp/dta-direct-stage3-validation/resume-audit')
helper_relative = 'benchmarks/r-dibble-dplyr/helpers.R'
helper = package_repo / helper_relative
helper_revision = 'ec10a6ac34602f3bd691e8043019c1b479babda4'
helper_bytes = subprocess.check_output(['git', 'show', helper_revision + ':' + helper_relative], cwd=package_repo)
require(helper.read_bytes() == helper_bytes, 'Shared installation guard differs from committed source')
script = Path(__file__).resolve()
script_hash = digest(script)
baseline_log = prior / 'fertility-stage2-baseline.log'
baseline_state = prior / 'fertility-before-exact-45f2ba4.json'
baseline_bytes = baseline_log.read_bytes()
baseline_expected_state = json.loads(baseline_state.read_text())
# This historical record contains a comparison annotation in addition to the
# downstream state. Verify that annotation explicitly before comparing state.
baseline_annotation = baseline_expected_state.pop('prior_baseline_comparison')
require(baseline_annotation == {'file_changes': [], 'state_changes': {}},
        'Historical downstream state was not identical to its retained baseline')
require(set(baseline_expected_state) ==
        {'head', 'branch', 'status', 'diff_sha256', 'files', 'integration_output'},
        'Unexpected historical downstream state schema')
inputs = {str(path): digest(path) for path in [helper, script, baseline_log, baseline_state, dll]}
git_env = os.environ.copy()
git_env['GIT_OPTIONAL_LOCKS'] = '0'


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo, env=git_env)


def snapshot():
    names = git('ls-files', '--cached', '--others', '--exclude-standard', '-z').decode().split('\0')
    files = {name: digest(repo / name) for name in sorted(set(names)) if name and (repo / name).is_file()}
    stat = (repo / 'output/mics.dta').stat()
    return {'head': git('rev-parse', 'HEAD').decode().strip(),
            'branch': git('branch', '--show-current').decode().strip(),
            'status': git('status', '--porcelain').decode(),
            'diff_sha256': hashlib.sha256(git('diff', '--binary', 'HEAD')).hexdigest(),
            'files': files,
            'integration_output': {'output/mics.dta': {'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns}}}


before = snapshot()
require(before == baseline_expected_state,
        'Downstream changed since retained baseline; establish a fresh same-state baseline before comparison')
output.mkdir(parents=True)
dump(output / 'before.json', before)
dump(output / 'input-identities.json', {'inputs': inputs, 'helper_revision': helper_revision,
                                      'baseline_comparison_annotation': baseline_annotation,
                                      'source_sha': source_sha, 'library': str(library)})
code = '''lib <- Sys.getenv('DTA_QUALIFICATION_LIBRARY')
sha <- Sys.getenv('DTA_QUALIFICATION_SOURCE')
source(Sys.getenv('DTA_QUALIFICATION_HELPER'))
validate_benchmark_install(lib, sha)
.libPaths(c(lib, .libPaths()))
library(dtatools, lib.loc = lib)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'), 'path')),
                    normalizePath(file.path(lib, 'dtatools'))),
          identical(normalizePath(getLoadedDLLs()[['dtatools']][['path']]),
                    normalizePath(file.path(lib, 'dtatools', 'libs', paste0('dtatools', .Platform$dynlib.ext)))))
cat(sprintf('Exact source %s\\nDLL_md5 %s\\n', sha,
            unname(tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]))))
testthat::set_max_fails(Inf)
source('checks/run_testthat.R')
'''
with (output / 'driver.R').open('x') as file:
    file.write(code)
env = os.environ.copy()
env.update({'R_LIBS': str(library), 'DTA_QUALIFICATION_LIBRARY': str(library),
            'DTA_QUALIFICATION_SOURCE': source_sha, 'DTA_QUALIFICATION_HELPER': str(helper),
            'FERTILITY_SURVEYS_BACKEND': 'r'})
# No trailing R arguments: the downstream runner interprets them as a test file.
try:
    with (output / 'test.log').open('xb') as file:
        result = subprocess.run(['Rscript', '--vanilla', str(output / 'driver.R')], cwd=repo,
                                env=env, stdout=file, stderr=subprocess.STDOUT)
finally:
    after = snapshot()
    dump(output / 'after.json', after)
post = "source(Sys.getenv('DTA_QUALIFICATION_HELPER')); validate_benchmark_install(Sys.getenv('DTA_QUALIFICATION_LIBRARY'), Sys.getenv('DTA_QUALIFICATION_SOURCE')); cat('Exact package provenance and installed-file hashes preserved after downstream run\\n')"
with (output / 'post-install-guard.log').open('xb') as file:
    post_result = subprocess.run(['Rscript', '--vanilla', '-e', post], cwd=repo, env=env,
                                 stdout=file, stderr=subprocess.STDOUT)
actual = (output / 'test.log').read_bytes()
marker = b'backend: r'
actual_suffix = actual[actual.index(marker):] if marker in actual else None
baseline_suffix = baseline_bytes[baseline_bytes.index(marker):]
expected_prefix = f'Exact source {source_sha}\nDLL_md5 {dll_md5}\n'.encode()
actual_prefix = actual[:actual.index(marker)] if marker in actual else None
pattern = rb'r backend: (\d+) tests, (\d+) failed or errored, (\d+) skipped'
actual_counts = re.findall(pattern, actual)
baseline_counts = re.findall(pattern, baseline_bytes)
require(len(baseline_counts) == 1, 'Ambiguous retained baseline summary')
metrics = [int(x) for x in actual_counts[0]] if len(actual_counts) == 1 else None
baseline_metrics = [int(x) for x in baseline_counts[0]]
verification = {'source_sha': source_sha, 'baseline_source_sha': 'fd069a36832ed7c1bdedeed52a4281ecabb36e25',
                'library': str(library), 'test_exit_code': result.returncode,
                'post_install_guard_exit_code': post_result.returncode,
                'tests_failed_blocks_skips': metrics, 'baseline_tests_failed_blocks_skips': baseline_metrics,
                'complete_test_log_matches_baseline': actual_suffix == baseline_suffix,
                'prefix_matches_exact_identity_header': actual_prefix == expected_prefix,
                'column_reallocation_warning_present': b'Column reallocation' in actual,
                'source_file_count': len(before['files']), 'downstream_state_unchanged': before == after,
                'input_files_unchanged': all(digest(Path(path)) == sha for path, sha in inputs.items()),
                'driver_sha256': script_hash,
                'files': {p.name: digest(p) for p in sorted(output.iterdir()) if p.is_file()},
                'scope': 'Isolated-library R shadow-backend parity only; no renv activation/install/restore or source modification'}
dump(output / 'verification.json', verification)
require(verification['downstream_state_unchanged'], 'Downstream state changed; inspect before/after records')
require(verification['input_files_unchanged'], 'Validation inputs changed during run')
require(post_result.returncode == 0, 'Post-run package provenance failed')
require(not verification['column_reallocation_warning_present'],
        'Column reallocation warning found in complete downstream log')
require(verification['prefix_matches_exact_identity_header'],
        'Unexpected output before downstream test marker; inspect complete log')
require(metrics == baseline_metrics and actual_suffix == baseline_suffix,
        'Downstream differs from retained baseline; inspect complete logs')
require(result.returncode == (1 if baseline_metrics[1] else 0), 'Unexpected downstream process status')
print(json.dumps(verification, indent=2))
