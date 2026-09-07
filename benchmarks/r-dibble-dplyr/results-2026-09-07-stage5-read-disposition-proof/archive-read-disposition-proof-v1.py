"""Copy the bounded read-disposition proof selection without rerunning it."""
from pathlib import Path, PurePosixPath
import hashlib,json,shutil,sys
ROOT=Path(__file__).resolve().parent
SELECTION=ROOT/'read-disposition-proof-selection-v2.json'
PINS={'01':'9d16c8eba32b12afc87c11d9680bb25182e7591e2b5964accef95e833c950f46','02':'6a206719d9c1b7f0cffc1bd8e19847dd0bdd3570558f2781a3ee1f413a5d964a'}

def identity(path):
    if path.is_symlink() or not path.is_file():raise ValueError('Expected regular file: '+str(path))
    data=path.read_bytes()
    return dict(bytes=len(data),mode=oct(path.stat().st_mode & 0o777),sha256=hashlib.sha256(data).hexdigest())

def check(path,expected):
    observed=identity(path)
    if any(observed[k]!=expected[k] for k in observed):raise ValueError('Changed selected file: '+str(path))

def write(path,value):
    with path.open('x') as stream:stream.write(json.dumps(value,indent=2)+'\n')

def main():
    if len(sys.argv)!=2:raise ValueError('Expected fresh destination')
    target=Path(sys.argv[1])
    if target.exists() or target.is_symlink():raise ValueError('Fresh destination required')
    selection_id=identity(SELECTION)
    if selection_id['sha256']!='0aced557afaadc3b00fbe869b8717a04f505dba6b673ae967b7ab00efe01a2bc':raise ValueError('Unexpected selection')
    selection=json.loads(SELECTION.read_text());check(SELECTION,selection_id)
    if len(selection['files'])!=26:raise ValueError('Unexpected record count')
    for version,pin in PINS.items():
        receipt=ROOT/'root-expression-performance'/('read-disposition-verification-'+version)/'completed-receipt.json'
        if identity(receipt)['sha256']!=pin:raise ValueError('Unexpected receipt')
        completed=json.loads(receipt.read_text())
        if completed.get('accepted') is not True or completed.get('changed_inputs'):raise ValueError('Unaccepted derivation')
        manifest=Path(completed['manifest']['path']);check(manifest,completed['manifest'])
        for row in json.loads(manifest.read_text())['products']:check(Path(row['path']),row)
    rows=[dict(source=x['source'],path=x['relative_path'],**{k:x[k] for k in ('bytes','mode','sha256')}) for x in selection['files']]
    for source,path in [(Path(__file__).resolve(),'archive-read-disposition-proof-v1.py'),(SELECTION,'selection.json'),(ROOT/'read-disposition-proof-README-v1.md','README.md')]:rows.append(dict(source=str(source),path=path,**identity(source)))
    seen=set()
    for row in rows:
        path=PurePosixPath(row['path'])
        if not row['path'] or path.is_absolute() or '..' in path.parts or str(path)!=row['path'] or row['path'] in seen or row['path'] in ('inclusion-manifest.json','inclusion-receipt.json'):raise ValueError('Invalid member path')
        seen.add(row['path']);check(Path(row['source']),row)
    target.mkdir(parents=True)
    for row in rows:
        destination=target/row['path'];destination.parent.mkdir(parents=True,exist_ok=True)
        check(Path(row['source']),row);shutil.copy2(row['source'],destination);check(destination,row)
    for row in rows:check(Path(row['source']),row);check(target/row['path'],row)
    check(SELECTION,selection_id)
    write(target/'inclusion-manifest.json',dict(files=rows,scope='Selected original bytes/modes and archive wrappers. Idle-file consistency and retained receipt/products only; no experiment rerun, full original-input revalidation, complete replay or concurrent-mutation guarantee.'))
    write(target/'inclusion-receipt.json',dict(files=len(rows),manifest=identity(target/'inclusion-manifest.json')))
    print(json.dumps(dict(physical_files=len(rows)+2,copied_bytes=sum(x['bytes'] for x in rows),receipt=identity(target/'inclusion-receipt.json'))))

if __name__=='__main__':main()
