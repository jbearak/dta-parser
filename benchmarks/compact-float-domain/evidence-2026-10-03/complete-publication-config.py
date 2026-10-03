#!/usr/bin/env python3
"""Bind the independently replayed final34 sibling bundle and final reports."""
import hashlib,json
from pathlib import Path
E=Path(__file__).resolve().parent
F=Path('<final34_evidence>')
P=Path('<final34_public>')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def need(ok,message):
 if not ok:raise RuntimeError(message)
def key(s):return s.replace('~','~0').replace('/','~1')
def spec(path,root='evidence'):return dict(root=root,path=path)
def bind(path,pointer,out=None,root='evidence'):return dict(file=spec(path,root),digest_pointer=pointer,publish_as=out or path)
def gate(path,expect,bindings,root='evidence',out=None,**kw):
 base={'evidence':E,'final34_evidence':F,'final34_public':P}[root]
 return dict(receipt=spec(path,root),receipt_sha256=sha(base/path),expect=expect,bindings=bindings,publish_as=out or path,**kw)
def extra(config,path,out=None,root='evidence'):
 base={'evidence':E,'final34_evidence':F}[root]
 config['files'].append(dict(file=spec(path,root),publish_as=out or path,sha256=sha(base/path),binding_scope='post-run-publication'))

def main():
 config=json.loads((E/'publication-config-pending-final34.json').read_text())
 need(config['ready'] is False and not config['groups']['final34'],'Expected pending final34 configuration')
 config['roots'].update(final34_evidence=str(F),final34_public=str(P))
 review=json.loads((F/'reader-publication-review.json').read_text())
 need(review['source_commits']==dict(baseline='7003eba901671797ee91fffc97f08e28a1f7f515',candidate=config['pins']['integrated']),'Wrong final panel sources')
 need(review['status']=='PASS' and review['published_artifacts']==69 and review['publication_replay_byte_identical'] is True,'Final panel publication is unqualified')
 config['groups']['final34'].append(gate('reader-publication-review.json',{
  '/status':'PASS','/source_commits/baseline':'7003eba901671797ee91fffc97f08e28a1f7f515','/source_commits/candidate':{'pin':'integrated'},
  '/observations':1224,'/qualification_observations':204,'/summary_rows':68,'/published_artifacts':69,'/source_map_entries':66,
  '/audit_replay_byte_identical':True,'/publication_replay_byte_identical':True,'/full_current_source_installed_runtime_replay':True,
  '/all_description_statistics_and_table_recomputed':True,'/original_public_hash_mapping_verified':True,'/original_whole_artifact_hashes_preserved':True,
  '/direct_identity_values_and_hashes_removed':True},[
  bind('reader-publication-review.py','/reviewer_script_sha256','final34-linkage/reader-publication-review.py','final34_evidence'),
  bind('acceptance-independent-audit.json','/original_audit_sha256','final34-linkage/original-audit.json','final34_evidence'),
  bind('acceptance-independent-audit.py','/auditor_sha256','final34-linkage/original-auditor.py','final34_evidence'),
  bind('publish-final-acceptance.py','/publisher_sha256','final34-linkage/publish-final-acceptance.py','final34_evidence'),
  bind('publication-manifest.json','/public_manifest_sha256','final34-linkage/sibling-publication-manifest.json','final34_public')],root='final34_evidence',out='final34-linkage/reader-publication-review.json'))
 config['groups']['final34'][-1]['bindings'].append(bind('publication-source-map.json','/public_source_map_sha256','final34-linkage/sibling-publication-source-map.json','final34_public'))
 manifest=json.loads((P/'publication-manifest.json').read_text())
 actual={str(p.relative_to(P)) for p in P.rglob('*') if p.is_file()}
 need(actual==set(manifest)|{'publication-manifest.json'} and len(actual)==69,'Incomplete sibling public inventory')
 audit='validation/acceptance-independent-audit.json'
 config['groups']['final34'].append(gate('publication-manifest.json',{
  '/'+key(audit):manifest[audit],'/README.md':manifest['README.md']},[
  bind(audit,'/'+key(audit),'final34-linkage/published-audit.json','final34_public')],root='final34_public',out='final34-linkage/sibling-publication-manifest.json',
  omitted_bindings=[dict(file=spec(name,'final34_public'),digest_pointer='/'+key(name),artifact='sibling-final-acceptance-2026-10-03/'+name,
   reason='Already-redacted artifact is checked here and published byte-for-byte in the separate sibling final-acceptance-2026-10-03 bundle, retaining its own original/public hash map; not copied or redacted a second time in this canonical bundle.') for name in sorted(manifest)]))
 # The root manifest has no parent key. Its complete byte inventory and literal
 # receipt digest are frozen here; publisher scalar omissions validate each child.
 config['groups']['final34'][-1]['expect'].update({'/'+key(name):digest for name,digest in manifest.items()})
 guards=json.loads((E/'publisher-guard-results.json').read_text())
 need(len(guards['commands'])==2,'Incomplete publication guard matrix')
 config['groups']['audits'].append(gate('publisher-guard-results.json',{
  '/status':'PASS','/commands/0/tests':15,'/commands/1/tests':15,'/commands/0/exit_code':0,'/commands/1/exit_code':0},[
  bind(name,'/source_sha256/'+key(name),'publish-canonical.py' if name=='publish-canonical-draft.py' else name) for name in guards['source_sha256']]+[
  bind(row['log'],f'/commands/{i}/log_sha256') for i,row in enumerate(guards['commands'])],
  expected_key_sets={'/source_sha256':sorted(guards['source_sha256'])}))
 for path,out,root in [
  ('report-draft.md','results-2026-10-03.md','evidence'),('evidence-README-draft.md','README.md','evidence'),
  ('architecture-report-draft.md','architecture-report-2026-10-03.md','final34_evidence'),
  ('test-publish-canonical.py',None,'evidence'),('publisher-guard-results.json',None,'evidence'),
  ('build-aux-publication-config.py',None,'evidence'),('merge-publication-config.py',None,'evidence'),
  ('complete-publication-config.py',None,'evidence')]:extra(config,path,out,root)
 need(all(config['groups'].values()),'Incomplete final groups')
 config['ready']=True
 (E/'publication-config-complete.json').write_text(json.dumps(config,indent=2,sort_keys=True)+'\n')
 print('Completed exact final34 linkage; ready for independently replayed private publication')

if __name__=='__main__':main()
