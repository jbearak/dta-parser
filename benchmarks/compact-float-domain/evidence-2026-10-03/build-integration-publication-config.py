#!/usr/bin/env python3
"""Private final integration/archive config draft; execute only after CPU hold.

This constructs a separate incomplete config. It does not run a checker,
publisher, compiler, R process, or performance measurement. The Rust command
record remains explicitly a post-run launch supplement. Historical timing
sources are not rebound to this combined source.
"""
import hashlib
import json
from pathlib import Path

E = Path(__file__).resolve().parent
FINAL = Path('<final_repository>')
RECORDER = Path('<recorder_repository>')
SOURCE = '3eadb244253fb817d5773b01b11cb36c284f3a1d'
PACKAGE_SOURCE = '754b38ce8f81707506ecac9016167fb66d60487f'
EXPECTED_BINDER = '5eb474653fec303354e1962449ce7f3e7ae1f4fe20de57b09a742fa55431f779'
EXPECTED_BINDING = 'cac859d7c15ec5e320c572f164e9d57f0229eba0b471e9b0bba79303c79d7568'
EMPTY = hashlib.sha256(b'').hexdigest()


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def load(name):
    return json.loads((E/name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ptr(name):
    return name.replace('~', '~0').replace('/', '~1')


def spec(name, root='evidence'):
    return dict(root=root, path=name)


def binding(name, pointer, root='evidence', publish=None):
    return dict(file=spec(name, root), digest_pointer=pointer, publish_as=publish or name)


def omitted(name, pointer, reason, root='evidence', artifact=None):
    return dict(file=spec(name, root), digest_pointer=pointer,
                artifact=artifact or name, reason=reason)


def gate(name, expected, bindings, **extra):
    return dict(receipt=spec(name), receipt_sha256=sha(E/name),
                publish_as=name, expect=expected, bindings=bindings, **extra)


def all_omitted(pointer, names, root, directory, reason):
    return dict(digest_pointer=pointer, expected_names=sorted(names), root=root,
                directory=directory, publish_prefix='omitted/'+directory,
                omit={name: reason for name in names})


def main():
    config = load('publication-config-draft.json')
    need(config['ready'] is False and all(not v for v in config['groups'].values()),
         'Expected the empty private draft')
    config['pins']['integrated'] = SOURCE
    config['roots']['final_repository'] = str(FINAL)
    config['roots']['recorder_repository'] = str(RECORDER)
    groups = config['groups']

    review = load('final-integration/root-independent-review.json')
    need(review['source_commit'] == SOURCE and review['status'] == 'PASS' and
         review['integration_binding_sha256'] == EXPECTED_BINDING and
         review['binder_sha256'] == EXPECTED_BINDER,
         'Unexpected independent final integration record')
    need(sha(E/'final-integration/integration-binding.json') == EXPECTED_BINDING and
         sha(E/'final-integration/bind-integration.py') == EXPECTED_BINDER,
         'Independently reviewed integration bytes changed')
    integrated = load('final-integration/integration-binding.json')
    need(integrated['source_commit'] == SOURCE and
         integrated['package_source_commit'] == PACKAGE_SOURCE,
         'Wrong final integration source')
    groups['integration'].append(gate('final-integration/root-independent-review.json', {
        '/status': 'PASS', '/source_commit': {'pin': 'integrated'},
        '/byte_identical_integration_receipt': True, '/replay_mode': 'python3 -O',
        '/focused/passed': 38954, '/focused/blocks': 47,
        '/archive/passed': 111083, '/archive/source_files': 354,
    }, [binding('final-integration/integration-binding.json', '/integration_binding_sha256'),
        binding('final-integration/bind-integration.py', '/binder_sha256')]))

    artifacts = integrated['artifact_sha256']
    binary_artifacts = {'final-integration/conformance.tar.gz'} | {
        'final-'+kind+'-structural-v1/work-count' for kind in ['canonical','unknown','polling','integer']}
    need(binary_artifacts <= set(artifacts), 'Missing declared archive/probe binaries')
    bindings, omissions = [], []
    for name in sorted(artifacts):
        pointer = '/artifact_sha256/'+ptr(name)
        if name.startswith(str(FINAL)+'/'):
            rel = name[len(str(FINAL))+1:]
            bindings.append(binding(rel,pointer,'final_repository','final-repository/'+rel))
        elif name.startswith(str(RECORDER)+'/'):
            rel = name[len(str(RECORDER))+1:]
            bindings.append(binding(rel,pointer,'recorder_repository','final-recorder/'+rel))
        else:
            need(not Path(name).is_absolute() and '..' not in Path(name).parts,
                 'Unmapped integration artifact path')
            if name in binary_artifacts:
                omissions.append(omitted(name,pointer,
                    'Hash-bound executable or immutable source archive omitted from the public text bundle; source, command, receipt and complete textual results are published.'))
            else:
                bindings.append(binding(name,pointer))
    groups['integration'].append(gate('final-integration/integration-binding.json', {
        '/status': 'PASS', '/source_commit': {'pin':'integrated'},
        '/package_source_commit': PACKAGE_SOURCE,
        '/component_sources/base': {'pin':'baseline'},
        '/component_sources/canonical': {'pin':'corrected'},
        '/component_sources/adaptive': 'd98495c25598098e3d00131a666a34bc47fc90c8',
        '/component_sources/locator': '0f9a13c6deed3c97f8e67b5c165218b1bb54a5f2',
        '/exact_component_union': True, '/parent_manifest_obligations_preserved': True,
        '/focused': dict(blocks=47,passed=38954,failed=0,error=0,skipped=0,warnings=0),
        '/rust': dict(passed=71,failed=0,ignored=0,launch_binding='post-run supplement'),
        '/guards': dict(commands=16,failed=0),
        '/archive/passed':111083, '/archive/failed':0, '/archive/skipped':0,
        '/archive/warnings':7, '/archive/source_files':354, '/archive/buildignore_exclusions':20,
    }, bindings, omitted_bindings=omissions,
        expected_key_sets={'/artifact_sha256': sorted(artifacts)},
        collections=[
            all_omitted('/source_inventory',integrated['source_inventory'],'final_repository',
                'r-package/dtatools','Full immutable package tree omitted from text evidence. The exact inventory is retained; selected consumed source files and probe copies are separately published.'),
            all_omitted('/installed_inventory',integrated['installed_inventory'],'evidence',
                'final-combined-build/library/dtatools','Installed package, binary fixtures and DLL omitted from text evidence. Exact installed hashes remain in the bound build and integration records.')]))

    # The parent's complete artifact map includes these records; each gate also
    # checks its own admitted outcomes and directly binds every recorded child.
    done = load('final-focused-v1/completion.json')
    focused_names = ['after.json','before.json','command.json','focused.csv','focused.log','test-source.patch']
    groups['integration'].append(gate('final-focused-v1/completion.json', {
        '/status':'PASS','/source_commit':{'pin':'integrated'},
        '/test_source_head':{'pin':'integrated'},'/before_after_equal':True,
        '/blocks':47,'/totals':dict(failed=0,passed=38954,warning=0),
        '/artifacts/before.json':done['artifacts']['after.json'],
    }, [binding('final-focused-v1/focused.csv','/artifacts/focused.csv')],
        collections=[dict(digest_pointer='/artifacts',expected_names=focused_names,
            root='evidence',directory='final-focused-v1',publish_prefix='final-focused-v1')]))

    build = load('final-combined-build/build-receipt.json')
    dependencies = {'builder':'benchmarks/r-file-readers/build-snapshot.py',
                    'recorder':'benchmarks/r-file-readers/record-builds.py',
                    'existing_recorder_helpers':'benchmarks/io-optimization/record-builds.py'}
    groups['integration'].append(gate('final-combined-build/build-receipt.json', {
        '/base_commit':{'pin':'integrated'},'/variant':'baseline','/exit_code':0,
        '/pre_post_source_equal':True,'/source_patch_sha256':EMPTY,
    }, [binding('final-combined-build/'+name,'/'+field) for name,field in [
        ('input-record.json','input_record_sha256'),('source.patch','source_patch_sha256'),
        ('build.log','build_log_sha256')]] + [
        binding(path,'/artifact_sha256/'+key,'recorder_repository','final-recorder/'+path)
        for key,path in dependencies.items()],
        expected_key_sets={'/artifact_sha256':sorted(dependencies)},
        collections=[
            all_omitted('/source_inventory',build['source_inventory'],'evidence',
                'final-combined-build/source','Full clean build source copy omitted; immutable commit, complete source inventory and selected source files are published.'),
            all_omitted('/installed_inventory',build['installed_inventory'],'evidence',
                'final-combined-build/library/dtatools','Installed binary package omitted; exact receipt/inventory retained.')]))

    for kind, folder, count in [('canonical','compact-float-domain',162),
            ('unknown','long-float-addition',162),('polling','retained-arithmetic-polling',18),
            ('integer','integer-reciprocal',64)]:
        directory = 'final-'+kind+'-structural-v1'
        receipt = load(directory+'/receipt.json')
        expected = {'/commit':{'pin':'integrated'},'/require_proved':True,'/exit_code':0}
        if kind == 'integer':
            expected.update({'/working_tree_status':'','/source_patch_sha256':EMPTY})
        else:
            expected.update({'/source_before_after_equal':True,'/cases':count,
                             '/semantic_failures':0,'/work_failures':0})
        controls = [binding('benchmarks/'+folder+'/work-count.'+ext,'/'+key,
                    'final_repository','final-repository/benchmarks/'+folder+'/work-count.'+ext)
                    for ext,key in [('py','controller_sha256'),('c','probe_sha256')]]
        if kind == 'polling':
            controls.append(binding('benchmarks/'+folder+'/cadence.h','/cadence_sha256',
                'final_repository','final-repository/benchmarks/'+folder+'/cadence.h'))
        groups['integration'].append(gate(directory+'/receipt.json', expected, controls,
            collections=[dict(digest_pointer='/artifact_sha256',
                expected_names=sorted(receipt['artifact_sha256']),root='evidence',
                directory=directory,publish_prefix=directory,
                omit={'work-count':'Compiled structural-probe binary omitted; actual input source, command, compiler digest and full CSV/log remain published.'}),
                all_omitted('/source_sha256',receipt['source_sha256'],'final_repository',
                    'r-package/dtatools/src','Uninstrumented source files are already pinned by the complete final source inventory; instrumented copies used by this probe are separately published.')]))

    guards = load('final-integration/guards.json')
    guard_bindings = [binding('final-integration/run-guards.py','/runner_sha256')]
    guard_bindings += [binding(name,'/files/'+ptr(name),'final_repository','final-repository/'+name)
                       for name in sorted(guards['files'])]
    guard_bindings += [binding('final-integration/'+row['log'],f'/commands/{i}/log_sha256')
                       for i,row in enumerate(guards['commands'])]
    need(len(guards['commands']) == 16 and len(guards['files']) == 8,'Guard matrix changed')
    groups['integration'].append(gate('final-integration/guards.json', {
        '/status':'PASS','/source_commit':{'pin':'integrated'},
        **{f'/commands/{i}/returncode':0 for i in range(16)},
    },guard_bindings,expected_key_sets={'/files':sorted(guards['files'])}))
    groups['integration'].append(gate('final-integration/rust-command.json', {
        '/status':'PASS','/source_commit':{'pin':'integrated'},
        '/passed':71,'/failed':0,'/ignored':0,
        '/scope':'Post-run launch supplement records the actual completed command and source commit; log counts are rechecked. Not a contemporaneous compiler/runtime inventory.',
    },[binding('final-integration/rust.log','/log_sha256')]))

    archive = load('final-integration/conformance.json')
    groups['archive'].append(gate('final-integration/conformance.json', {
        '/source_commit':{'pin':'integrated'},
        **{'/'+flag:True for flag in ['checked_source_matches_clean_export',
          'clean_export_matches_source_commit','exact_packaged_source_inventory',
          'expected_hashes_from_committed_blobs','repository_environment_overrides_removed',
          'required_conformance_passed']},
    },[binding('final-integration/conformance-export/r-package/dtatools/.Rbuildignore',
               '/buildignore_sha256','evidence','final-integration/buildignore')],
        omitted_bindings=[omitted('final-integration/conformance.tar.gz',
            '/source_archive_sha256','Retained immutable source archive omitted from the text bundle; full committed-file inventory, conformance command/log and archive validation remain published.')],
        collections=[all_omitted('/verified_files',archive['verified_files'],'evidence',
            'final-integration/conformance-export/r-package/dtatools',
            'Full validated package-source export omitted from the text bundle; the exact archive inventory and commit identity are retained.')]))
    groups['archive'].append(gate('final-integration/conformance-command.json', {
        '/commit':{'pin':'integrated'},'/exit_code':0,
        '/only_wrapper_change':'Preserve temporary source archive and complete check outputs before original cleanup.',
    },[binding('final-integration/'+name,'/'+field) for name,field in [
        ('run-conformance.py','controller_sha256'),('conformance-gate.sh','wrapper_sha256'),
        ('validate-conformance-archive.py','validator_sha256')]] + [
        binding('scripts/conformance.sh','/original_script_sha256','final_repository',
                'final-repository/scripts/conformance.sh')]))
    config['files']=[dict(file=spec(Path(__file__).name),publish_as=Path(__file__).name,
                         sha256=sha(Path(__file__)),binding_scope='post-run-publication')]
    need(config['ready'] is False and not groups['final34'], 'Premature publication readiness')
    output=E/'publication-config-integration.json'
    output.write_text(json.dumps(config,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(status='DRAFT',ready=False,source_commit=SOURCE,
                         groups={k:len(v) for k,v in groups.items()})))


if __name__=='__main__':
    main()
