#!/usr/bin/env python3
"""Replay historical diagnostics only through an explicit installation guard."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
HELPERS = {
    'owned-double-helpers.R': 'a6c5a83561a03401258aa5f0ebbd8dc494a1f8ac46fdc3f1d9fdd19c3dfd53c2',
    'helpers.R': '38be0d6709ba66af9307446c58dce5c6c953e3390da1c3d90258b8c727cf7219',
    'owned-atomic-helpers.R': '4ea65133046e058f2bdf071417ed3c701a6ae98ec600e842dd14fde95ffa4ba1',
}
DIAGNOSTICS = {
    'aggregate': ('aggregate-read-diagnosis.R', 'd8ba0529cf4dda5be0b7121d36725250e1456d3a5886881c237fdd99ff1263df'),
    'accessor': ('atomic-accessor-diagnosis.R', '3cd9a01421fa636e3bf59f9ab277af387878c4f592ee036bdcc5736cac84a120'),
}
R_PREFLIGHT = r'''
args <- commandArgs(TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
expected <- normalizePath(file.path(lib, "dtatools"), mustWork = TRUE)
source(Sys.getenv("DTA_REVIEW_HELPER"))
validate_benchmark_install(lib, Sys.getenv("DTA_REVIEW_SOURCE"))
library(dtatools, lib.loc = lib)
stopifnot(identical(normalizePath(find.package("dtatools"), mustWork = TRUE), expected),
          identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"), mustWork = TRUE), expected))
dll <- normalizePath(getLoadedDLLs()[["dtatools"]][["path"]], mustWork = TRUE)
stopifnot(startsWith(dll, paste0(expected, .Platform$file.sep)))
cat("GUARDED REPLAY", Sys.getenv("DTA_REVIEW_SOURCE"), expected, "\n")
print(tools::md5sum(dll))
if (Sys.getenv("DTA_REVIEW_CHECK_ONLY") != "1") source(Sys.getenv("DTA_REVIEW_SCRIPT"), local = new.env(parent = .GlobalEnv))
validate_benchmark_install(lib, Sys.getenv("DTA_REVIEW_SOURCE"))
stopifnot(identical(normalizePath(find.package("dtatools"), mustWork = TRUE), expected),
          identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]], mustWork = TRUE), dll))
'''


def require(condition, message):
    """Reject an invalid input before creating outputs or executing diagnostics."""
    if not condition:
        raise RuntimeError(message)


def sha(data):
    """Hash exact bytes without text or newline normalization."""
    return hashlib.sha256(data).hexdigest()


def diagnose(args):
    """Run an unchanged historical diagnostic through an explicit library guard."""
    require(re.fullmatch('[0-9a-f]{40}', args.source) is not None, 'Expected source must be a full SHA')
    library = args.library.resolve(strict=True)
    require((library / 'dtatools' / 'DESCRIPTION').is_file(), 'Requested library has no dtatools installation')
    repository = args.repository.resolve(strict=True)
    helper_root = repository / 'benchmarks/r-dibble-dplyr'
    inputs = {helper_root / name: expected for name, expected in HELPERS.items()}
    name, expected = DIAGNOSTICS[args.kind]
    script = HERE / 'diagnosis' / name
    inputs[script] = expected
    for path, expected in inputs.items():
        require(sha(path.read_bytes()) == expected, 'Changed diagnostic dependency: ' + str(path))
    require((args.kind == 'accessor') == (args.csv is not None), 'Only accessor requires --csv')
    if args.csv is not None:
        args.csv = args.csv.absolute()
        require(not args.csv.exists() and not args.csv.is_symlink(), 'CSV output already exists')
        require(args.csv.parent.is_dir(), 'CSV parent directory is missing')
    env = os.environ.copy()
    env.update(DTA_REVIEW_HELPER=str(helper_root / 'helpers.R'), DTA_REVIEW_SOURCE=args.source,
               DTA_REVIEW_SCRIPT=str(script), DTA_REVIEW_CHECK_ONLY='1' if args.check_only else '0')
    arguments = [str(library), 'guarded-replay-' + args.source]
    if args.csv is not None:
        arguments.append(str(args.csv))
    child = subprocess.run(['Rscript', '--vanilla', '-e', R_PREFLIGHT, *arguments],
                           cwd=repository, env=env)
    for path, expected in inputs.items():
        require(sha(path.read_bytes()) == expected, 'Diagnostic dependency changed during execution')
    require(child.returncode == 0, 'Guarded diagnostic failed')


def main():
    """Expose guarded diagnostics with explicit source and output arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    command = sub.add_parser('diagnose')
    command.add_argument('kind', choices=DIAGNOSTICS)
    command.add_argument('--library', type=Path, required=True)
    command.add_argument('--source', required=True)
    command.add_argument('--repository', type=Path, required=True)
    command.add_argument('--csv', type=Path)
    command.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    diagnose(args)



if __name__ == '__main__':
    main()
