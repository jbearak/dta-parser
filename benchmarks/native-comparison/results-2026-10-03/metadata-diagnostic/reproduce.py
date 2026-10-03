#!/usr/bin/env python3
"""Source-bound metadata prefix/full reproduction. Do not run during timing.

Creates a private test mirror; changes only diagnostic stack capture, leaving
all original expectations intact. --instrument none is the unchanged control.
No caller-owned source or installed library is edited.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
TARGET='test-metadata-execution-profile.R'

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def require(condition,message):
    if not condition:raise RuntimeError(message)

def instrument(original):
    edits=[
      ('        helper_calls <- 0L\n        if (is.null(transform)) {',
       '        helper_calls <- 0L\n        probe_events <- list()\n        probe_record <- NULL\n        if (is.null(transform)) {'),
      ('        trace(wrapper, tracer = function() calls <<- calls + 1L,',
       '        trace(wrapper, tracer = function() {\n            calls <<- calls + 1L\n            if (identical(wrapper, "is.null")) {\n                probe_index <- calls\n                probe_events[[probe_index]] <<- sys.calls()\n            }\n        },'),
      ('        on.exit(untrace(wrapper, where = baseenv()), add = TRUE)',
       '        on.exit(untrace(wrapper, where = baseenv()), add = TRUE)\n        on.exit({\n            if (identical(wrapper, "is.null") && !is.null(probe_record)) {\n                .GlobalEnv$.metadata_probe_records[[helper]] <- probe_record\n                saveRDS(probe_record, file.path(getOption("metadata.probe.output"),\n                    paste0("calls-", helper, ".rds")))\n            }\n        }, add = TRUE)'),
      ('        run(lhs)\n        expected <- c(calls, helper_calls)',
       '        probe_events <- list()\n        run(lhs)\n        expected <- c(calls, helper_calls)\n        probe_lhs <- probe_events'),
      ('        run(rhs)\n        observed <- c(calls, helper_calls)',
       '        probe_events <- list()\n        run(rhs)\n        observed <- c(calls, helper_calls)\n        if (identical(wrapper, "is.null")) probe_record <- list(\n            helper=helper, wrapper=wrapper, expected=expected, observed=observed,\n            lhs=probe_lhs, rhs=probe_events, mismatch=!identical(observed, expected))')]
    result=original
    for old,new in edits:
        require(result.count(old)==1,'Instrument seam changed')
        result=result.replace(old,new)
    assertion='        expect_identical(observed, expected, info = paste(helper, wrapper))'
    require(original.count(assertion)==result.count(assertion)==1,'Original assertion changed')
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True,help='Package root from retained conformance export')
    p.add_argument('--binding',type=Path,required=True)
    p.add_argument('--build',type=Path,required=True)
    p.add_argument('--receipt-name',default='build-receipt.json')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--mode',choices=['focus','suspects','prefix','full'],default='prefix')
    p.add_argument('--runner',choices=['dir','check'],default='check')
    p.add_argument('--instrument',choices=['stacks','none'],default='stacks')
    p.add_argument('--only-files',nargs='*',help='Optional fixed subset for later bisection; must include target')
    args=p.parse_args()
    source=args.source.resolve();build=args.build.resolve();output=args.output.resolve()
    binding=json.loads(args.binding.read_text());receipt=json.loads((build/args.receipt_name).read_text())
    library=Path(receipt.get('library',str(build/'library'))).resolve()
    launcher=str(Path(shutil.which('Rscript')).resolve())
    def bindings():
        # Verify the retained conformance source and the actual installed tree.
        # This executes only when this script is released, never during preparation.
        for relative,expected in binding['source_inventory'].items():
            require(sha(source/relative)==expected,'Conformance source mismatch: '+relative)
        installed=receipt['installed_inventory']
        actual_installed={str(f.relative_to(library/'dtatools')) for f in (library/'dtatools').rglob('*') if f.is_file()}
        require(actual_installed==set(installed),'Installed file inventory changed')
        for relative,expected in installed.items():
            require(sha(library/'dtatools'/relative)==expected,'Installed mismatch: '+relative)
        rhome=Path(subprocess.check_output([launcher,'--vanilla','-e','cat(R.home())'],text=True).strip())
        runtime=sha(rhome/'bin/exec/R')
        require(runtime==receipt['toolchain']['R_runtime_sha256'],'Worker/build runtime mismatch')
        return dict(binding_sha256=sha(args.binding),receipt_sha256=sha(build/args.receipt_name),
            launcher=launcher,launcher_sha256=sha(launcher),runtime_sha256=runtime,
            controller_sha256=sha(__file__),worker_sha256=sha(HERE/'reproduce.R'),
            verified_source_files=len(binding['source_inventory']),verified_installed_files=len(installed))
    before=bindings()
    output.mkdir(parents=True,exist_ok=False)
    (output/'before.json').write_text(json.dumps(before,indent=2)+'\n')
    package=output/'package';tests=package/'tests';testdir=tests/'testthat'
    testdir.mkdir(parents=True)
    # Mirror only the recorded archive files: added helpers/tests cannot execute.
    for relative in binding['source_inventory']:
        if relative=='tests/testthat/'+TARGET:continue
        destination=package/relative
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.symlink_to(source/relative)
    original=(source/'tests/testthat'/TARGET).read_text()
    target=instrument(original) if args.instrument=='stacks' else original
    (testdir/TARGET).write_text(target)
    config=dict(library=str(library),output=str(output),test_directory=str(testdir),
        source_binding=before,mode=args.mode,runner=args.runner,instrument=args.instrument,only_files=args.only_files)
    (output/'config.json').write_text(json.dumps(config,indent=2)+'\n')
    env=dict(os.environ,R_ENVIRON_USER='/dev/null',R_PROFILE_USER='/dev/null')
    with (output/'run.log').open('w') as log:
        completed=subprocess.run([launcher,'--vanilla',str(HERE/'reproduce.R'),str(output/'config.json')],
            cwd=tests,env=env,stdout=log,stderr=subprocess.STDOUT)
    after=bindings();require(before==after,'Source/runtime/controller changed during reproduction')
    (output/'after.json').write_text(json.dumps(after,indent=2)+'\n')
    result=dict(exit_code=completed.returncode,source_before_after_equal=True,
        original_target_sha256=hashlib.sha256(original.encode()).hexdigest(),
        executed_target_sha256=sha(testdir/TARGET),instrument=args.instrument,
        original_assertion_preserved=True)
    (output/'completion.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    raise SystemExit(completed.returncode)

if __name__=='__main__':main()
