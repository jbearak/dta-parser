from pathlib import Path
import contextlib, copy, importlib.util, io, json, sys, tarfile, tempfile

source=Path(__file__).with_name('prepare-evidence-v2.py')
spec=importlib.util.spec_from_file_location('evidence',source)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
row=dict(path='/private/tmp/example.txt',resolved='/private/tmp/example.txt',bytes=0,mode='0o644',sha256='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',member='records/example.txt')
cases=[]
def case(name,fn,reject):
    error=None
    try: fn()
    except RuntimeError as exc: error=str(exc)
    if (error is not None)!=reject:raise RuntimeError('Wrong guard outcome: '+name)
    cases.append(dict(name=name,rejected=reject,error=error))
def changed(**kw):
    r=copy.deepcopy(row);r.update(kw);return [r]
case('valid complete identity',lambda:m.validate([row]),False)
case('duplicate path and member',lambda:m.validate([row,row]),True)
case('missing digest',lambda:m.validate([{k:v for k,v in row.items() if k!='sha256'}]),True)
case('malformed digest',lambda:m.validate(changed(sha256='123')),True)
case('wrong member',lambda:m.validate(changed(member='records/other.txt')),True)
case('escaping source',lambda:m.validate(changed(path='/private/tmp/../escape.txt')),True)
case('boolean bytes',lambda:m.validate(changed(bytes=True)),True)
case('empty selection',lambda:m.validate([]),True)
with tempfile.TemporaryDirectory(prefix='stage8-evidence-guard-',dir='/private/tmp') as d:
    p=Path(d)/'target';p.write_text('test');link=Path(d)/'link';link.symlink_to(p)
    case('symlink input rejected',lambda:m.fact(link),True)
with tempfile.TemporaryDirectory(prefix='stage8-evidence-build-',dir='/private/tmp') as td:
    base=Path(td);payload=base/'script.R';payload.write_bytes(b'print(1)\n');payload.chmod(0o755)
    empty=base/'empty.txt';empty.write_bytes(b'')
    def setup(name):
        rows=[]
        for f in [empty,payload]:
            row=m.fact(f);row['member']=m.member(row['path']);rows.append(row)
        rows.sort(key=lambda x:x['member'])
        m.SELECTION=base/(name+'-selection.json');m.OUTPUT=base/name
        m.SELECTION.write_text(json.dumps(dict(files=rows,count=2,bytes=sum(r['bytes'] for r in rows))))
        return rows
    def invoke():
        with contextlib.redirect_stdout(io.StringIO()):m.build()
    rows=setup('valid')
    case('archive round trip',invoke,False)
    with tarfile.open(m.OUTPUT/'records.tar.gz','r:gz') as t:
        members=t.getmembers()
        if [x.name for x in members]!=[r['member'] for r in rows]:raise RuntimeError('Unexpected archive members')
        if [(x.mode,t.extractfile(x).read()) for x in members]!=[(0o644,b''),(0o755,b'print(1)\n')]:raise RuntimeError('Archive payload/mode mismatch')
    if (m.OUTPUT/'selection.json').read_bytes()!=m.SELECTION.read_bytes():raise RuntimeError('Selection transport mismatch')
    if json.loads(m.OUTPUT.with_name(m.OUTPUT.name+'-build-attempt.json').read_text())['status']!='complete':raise RuntimeError('Success attempt missing')
    setup('changed-source');payload.write_bytes(b'changed')
    case('changed source fails and preserves attempt',invoke,True)
    attempt=json.loads(m.OUTPUT.with_name(m.OUTPUT.name+'-build-attempt.json').read_text())
    if attempt['status']!='failed' or (m.OUTPUT/'transport-result.json').exists() or not (m.OUTPUT/'records.tar.gz').exists():raise RuntimeError('Failed copy retention mismatch')
    payload.write_bytes(b'print(1)\n');setup('changed-selection')
    original=m.gzip.GzipFile
    def changing_gzip(*args,**kwargs):
        m.SELECTION.write_bytes(m.SELECTION.read_bytes()+b'\n')
        return original(*args,**kwargs)
    m.gzip.GzipFile=changing_gzip
    try:case('selection change during build rejected',invoke,True)
    finally:m.gzip.GzipFile=original
    attempt=json.loads(m.OUTPUT.with_name(m.OUTPUT.name+'-build-attempt.json').read_text())
    if attempt['status']!='failed' or (m.OUTPUT/'transport-result.json').exists():raise RuntimeError('Changed selection accepted')
print(json.dumps(dict(argv=sys.orig_argv,optimize=sys.flags.optimize,cases=cases,status='pass')))
