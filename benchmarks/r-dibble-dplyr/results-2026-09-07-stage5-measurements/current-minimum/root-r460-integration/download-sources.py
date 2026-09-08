"""Download exact source versions, retaining current-index checks and URLs."""
from pathlib import Path
import concurrent.futures
import datetime
import gzip
import hashlib
import json
import tarfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def write(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')

def dcf(text):
    fields = {}
    key = None
    for line in text.splitlines():
        if line[:1].isspace() and key:
            fields[key] += ' ' + line.strip()
        elif ':' in line:
            key, value = line.split(':', 1)
            fields[key] = value.strip()
    return fields

def fetch(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read(), response.geturl(), dict(response.headers)

def main():
    directory = ROOT / 'source-downloads'
    if directory.exists() or directory.is_symlink():
        raise RuntimeError('Fresh source-downloads directory required')
    plan_path = ROOT / 'dependency-plan.json'
    plan_bytes = plan_path.read_bytes()
    plan = json.loads(plan_bytes)
    directory.mkdir()
    write(directory / 'inputs-before.json', {
        'script_sha256': sha(Path(__file__).read_bytes()),
        'plan_sha256': sha(plan_bytes),
        'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'scope': 'Download source archives only. No installation or runtime compatibility claim.'})
    url = 'https://cloud.r-project.org/src/contrib/PACKAGES.gz'
    data, final_url, headers = fetch(url)
    (directory / 'PACKAGES.gz').write_bytes(data)
    index = {item['Package']: item for item in
             (dcf(block) for block in gzip.decompress(data).decode().split('\n\n'))
             if 'Package' in item}
    write(directory / 'index-receipt.json', {'url': url, 'final_url': final_url,
          'headers': headers, 'bytes': len(data), 'sha256': sha(data)})

    def download(name):
        record = plan['records'][name]
        version = record['version']
        current = index.get(name, {})
        filename = name + '_' + version + '.tar.gz'
        current_match = current.get('Version') == version
        path = filename if current_match else 'Archive/' + name + '/' + filename
        source_url = 'https://cloud.r-project.org/src/contrib/' + path
        body, redirect, response_headers = fetch(source_url)
        archive = directory / filename
        with archive.open('xb') as stream:
            stream.write(body)
        if current_match and hashlib.md5(body).hexdigest() != current.get('MD5sum'):
            raise RuntimeError('Current CRAN index MD5 mismatch: ' + name)
        with tarfile.open(archive) as tar:
            description = tar.extractfile(name + '/DESCRIPTION')
            if description is None:
                raise RuntimeError('Missing source DESCRIPTION: ' + name)
            description_bytes = description.read()
        fields = dcf(description_bytes.decode())
        if fields.get('Package') != name or fields.get('Version') != version:
            raise RuntimeError('Wrong source package/version: ' + name)
        result = {'package': name, 'version': version, 'url': source_url,
                  'final_url': redirect, 'headers': response_headers,
                  'archive': str(archive), 'bytes': len(body), 'sha256': sha(body),
                  'source_description_sha256': sha(description_bytes),
                  'current_index_md5_verified': current_match,
                  'current_index_md5': current.get('MD5sum') if current_match else None}
        write(directory / (name + '-receipt.json'), result)
        print(name + ' ' + version + ' downloaded', flush=True)
        return result

    records = []
    errors = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = {pool.submit(download, name): name for name in plan['install_order']}
        for job in concurrent.futures.as_completed(jobs):
            try:
                records.append(job.result())
            except Exception as error:
                errors.append({'package': jobs[job], 'error': str(error)})
    products = [{'path': str(path), 'bytes': path.stat().st_size,
                 'sha256': sha(path.read_bytes())}
                for path in sorted(directory.iterdir()) if path.is_file()]
    manifest = directory / 'output-manifest.json'
    write(manifest, {'products': products, 'excluded_self': str(manifest)})
    write(ROOT / 'source-downloads-receipt.json', {
        'records': sorted(records, key=lambda item: item['package']), 'errors': errors,
        'manifest_sha256': sha(manifest.read_bytes())})
    if errors:
        raise RuntimeError('Some sources failed; inspect retained receipt')

if __name__ == '__main__':
    main()
