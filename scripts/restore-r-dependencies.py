#!/usr/bin/env python3
"""Restore one exact runtime-library artifact from a trusted release run.

Usage: restore-r-dependencies.py ARTIFACT_NAME FRESH_LIBRARY
Requires GH_TOKEN, GITHUB_REPOSITORY and Actions:read. GitHub's artifact API
supports an exact name filter: https://docs.github.com/en/rest/actions/artifacts
"""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from urllib.parse import quote, urlencode

WORKFLOW = '.github/workflows/release-r-packages.yml'


def gh(*args):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        message = result.stderr.strip() or 'GitHub CLI failed'
        token = os.environ.get('GH_TOKEN')
        if token:
            message = message.replace(token, '[redacted]')
        raise RuntimeError(message)
    return result.stdout


def api(endpoint):
    return json.loads(gh('api', '-H', 'X-GitHub-Api-Version: 2022-11-28', endpoint))


def trusted_run(run, artifact, repository, tag_commit):
    donor = artifact['workflow_run']
    if (run.get('path', '').split('@', 1)[0] != WORKFLOW
            or run.get('repository', {}).get('id') != repository['id']
            or run.get('head_repository', {}).get('id') != repository['id']
            or donor.get('repository_id') != repository['id']
            or donor.get('head_repository_id') != repository['id']
            or run.get('head_sha') != donor.get('head_sha')
            or run.get('id') != donor.get('id')
            or run.get('event') not in {'release', 'workflow_dispatch'}
            or run.get('pull_requests')
            or run.get('status') != 'completed'
            or run.get('conclusion') != 'success'):
        return False
    branch = run.get('head_branch', '')
    if branch == repository['default_branch']:
        return True
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?', branch):
        return False
    return tag_commit(branch) == run['head_sha']


def select_artifact(repository, name):
    info = api(f'repos/{repository}')
    artifacts = []
    # Names are exact, so even a busy repository normally needs one page.
    # Bound lookup to 1,000 matching artifacts rather than scan its history.
    for page in range(1, 11):
        query = urlencode({'name': name, 'per_page': 100, 'page': page})
        response = api(f'repos/{repository}/actions/artifacts?{query}')
        artifacts.extend(response['artifacts'])
        if len(response['artifacts']) < 100 or len(artifacts) >= response['total_count']:
            break
    candidates = [a for a in artifacts if a['name'] == name and not a['expired']]
    candidates.sort(key=lambda a: (a['created_at'], a['id']), reverse=True)

    def tag_commit(tag):
        obj = api(f'repos/{repository}/git/ref/tags/{quote(tag, safe="")}')['object']
        if obj['type'] == 'tag':
            obj = api(f'repos/{repository}/git/tags/{obj["sha"]}')['object']
        return obj['sha'] if obj['type'] == 'commit' else None

    for artifact in candidates:
        run_id = artifact['workflow_run']['id']
        run = api(f'repos/{repository}/actions/runs/{run_id}')
        if trusted_run(run, artifact, info, tag_commit):
            return artifact
    return None


def validate_library(library):
    for path in library.rglob('*'):
        if not (stat.S_ISREG(path.lstat().st_mode) or stat.S_ISDIR(path.lstat().st_mode)):
            raise ValueError('Dependency cache contains a link or special file')
    for package in library.iterdir():
        description = package / 'DESCRIPTION'
        if not package.is_dir() or not description.is_file():
            raise ValueError('Dependency cache contains a non-package entry')
        match = re.search(r'^Package:\s*([A-Za-z][A-Za-z0-9.]*)\s*$', description.read_text(), re.M)
        if not match or match[1] != package.name or match[1].lower() == 'dtatools':
            raise ValueError('Dependency cache contains an invalid package or dtatools')


def restore(name, library, repository):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{1,200}', name):
        raise ValueError('Invalid exact artifact name')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('GITHUB_REPOSITORY must identify one repository')
    if library.is_symlink() or (library.exists() and (not library.is_dir() or any(library.iterdir()))):
        raise ValueError('Dependency cache destination must be a fresh empty library')
    library.mkdir(parents=True, exist_ok=True)
    artifact = select_artifact(repository, name)
    if artifact is None:
        return None
    gh('run', 'download', str(artifact['workflow_run']['id']), '--repo', repository,
       '--name', name, '--dir', str(library))
    validate_library(library)
    if not any(library.iterdir()):
        raise ValueError('Chosen dependency artifact is empty')
    return artifact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact_name')
    parser.add_argument('library', type=Path)
    args = parser.parse_args()
    if not os.environ.get('GH_TOKEN'):
        raise ValueError('GH_TOKEN is required for dependency artifact lookup')
    artifact = restore(args.artifact_name, args.library.absolute(), os.environ.get('GITHUB_REPOSITORY', ''))
    hit = artifact is not None
    outputs = {'cache_hit': str(hit).lower(), 'donor_run': str(artifact['workflow_run']['id']) if hit else ''}
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            for name, value in outputs.items():
                output.write(f'{name}={value}\n')
    print(f"R runtime dependency cache: {'restored run ' + outputs['donor_run'] if hit else 'none'}")


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f'R dependency restore failed: {error}', file=sys.stderr)
        sys.exit(1)
