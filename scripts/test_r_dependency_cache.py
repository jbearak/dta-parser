"""Exercise cross-tag dependency cache selection without GitHub or R builds."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('restore_r_dependencies', Path(__file__).with_name('restore-r-dependencies.py'))
CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CACHE)
REPO = {'id': 7, 'default_branch': 'main'}


def artifact(number, date='2026-10-04T01:00:00Z', name='r-runtime-v1-test'):
    return {'id': number, 'name': name, 'expired': False, 'created_at': date,
            'workflow_run': {'id': number, 'repository_id': 7, 'head_repository_id': 7,
                             'head_sha': 'a' * 40}}


def run(number, branch='main'):
    return {'id': number, 'path': CACHE.WORKFLOW, 'repository': {'id': 7},
            'head_repository': {'id': 7}, 'head_sha': 'a' * 40,
            'event': 'workflow_dispatch', 'pull_requests': [], 'head_branch': branch,
            'status': 'completed', 'conclusion': 'success'}


class DependencyCacheTests(unittest.TestCase):
    def test_default_branch_and_verified_release_tags_are_trusted(self):
        self.assertTrue(CACHE.trusted_run(run(1), artifact(1), REPO, lambda _: None))
        tagged = run(1, 'v0.11.3')
        tagged['event'] = 'release'
        self.assertTrue(CACHE.trusted_run(tagged, artifact(1), REPO, lambda _: 'a' * 40))
        self.assertFalse(CACHE.trusted_run(tagged, artifact(1), REPO, lambda _: 'b' * 40))

    def test_untrusted_workflow_source_head_and_outcomes_are_rejected(self):
        mutations = [
            {'path': '.github/workflows/ci.yml'}, {'repository': {'id': 8}},
            {'head_repository': {'id': 8}}, {'head_sha': 'b' * 40}, {'id': 2},
            {'event': 'pull_request'}, {'event': 'pull_request_target'},
            {'pull_requests': [{'number': 1}]}, {'head_branch': 'codex/change'},
            {'status': 'in_progress'}, {'conclusion': 'failure'},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                donor = run(1)
                donor.update(mutation)
                self.assertFalse(CACHE.trusted_run(donor, artifact(1), REPO, lambda _: 'a' * 40))
        for field in ['repository_id', 'head_repository_id', 'head_sha']:
            bad = artifact(1)
            bad['workflow_run'][field] = 8
            self.assertFalse(CACHE.trusted_run(run(1), bad, REPO, lambda _: None))

    def test_newest_exact_nonexpired_trusted_artifact_wins(self):
        old, latest, wrong = artifact(1), artifact(2, '2026-10-04T02:00:00Z'), artifact(3, name='other')
        expired = artifact(4, '2026-10-04T04:00:00Z')
        expired['expired'] = True
        untrusted = artifact(5, '2026-10-04T05:00:00Z')
        def api(endpoint):
            if endpoint == 'repos/owner/repo':
                return REPO
            if '/artifacts?' in endpoint:
                self.assertIn('name=r-runtime-v1-test', endpoint)
                return {'total_count': 5, 'artifacts': [old, latest, wrong, expired, untrusted]}
            donor = run(int(endpoint.rsplit('/', 1)[-1]))
            if donor['id'] == 5:
                donor['event'] = 'pull_request'
            return donor
        with patch.object(CACHE, 'api', side_effect=api):
            self.assertEqual(CACHE.select_artifact('owner/repo', 'r-runtime-v1-test'), latest)

    def test_zero_artifacts_is_a_real_cache_miss(self):
        with patch.object(CACHE, 'api', side_effect=[REPO, {'total_count': 0, 'artifacts': []}]):
            self.assertIsNone(CACHE.select_artifact('owner/repo', 'r-runtime-v1-test'))

    def test_filtered_pagination_finds_the_later_page(self):
        expired = artifact(1)
        expired['expired'] = True
        response = [REPO, {'total_count': 101, 'artifacts': [expired] * 100},
                    {'total_count': 101, 'artifacts': [artifact(2)]}, run(2)]
        with patch.object(CACHE, 'api', side_effect=response) as request:
            self.assertEqual(CACHE.select_artifact('owner/repo', 'r-runtime-v1-test')['id'], 2)
            self.assertIn('page=2', request.call_args_list[2].args[0])

    def test_annotated_tag_is_resolved_before_reusing_a_release_cache(self):
        response = [REPO, {'total_count': 1, 'artifacts': [artifact(1)]}, run(1, 'v0.11.3'),
                    {'object': {'type': 'tag', 'sha': 'b' * 40}},
                    {'object': {'type': 'commit', 'sha': 'a' * 40}}]
        with patch.object(CACHE, 'api', side_effect=response) as request:
            self.assertEqual(CACHE.select_artifact('owner/repo', 'r-runtime-v1-test')['id'], 1)
            self.assertEqual(request.call_args_list[3].args[0], 'repos/owner/repo/git/ref/tags/v0.11.3')

    def test_api_and_download_failures_are_not_cache_misses(self):
        with patch.object(CACHE, 'api', side_effect=RuntimeError('permission denied')):
            with self.assertRaisesRegex(RuntimeError, 'permission denied'):
                CACHE.select_artifact('owner/repo', 'r-runtime-v1-test')
        with tempfile.TemporaryDirectory() as directory, patch.object(CACHE, 'select_artifact', return_value=artifact(1)), patch.object(CACHE, 'gh', side_effect=RuntimeError('download failed')):
            with self.assertRaisesRegex(RuntimeError, 'download failed'):
                CACHE.restore('r-runtime-v1-test', Path(directory), 'owner/repo')

    def test_download_is_bound_to_exact_name_run_repo_and_fresh_library(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / 'library'
            def download(*args):
                self.assertEqual(args, ('run', 'download', '1', '--repo', 'owner/repo', '--name', 'r-runtime-v1-test', '--dir', str(library)))
                (library / 'rlang').mkdir()
                (library / 'rlang/DESCRIPTION').write_text('Package: rlang\nVersion: 1.2.0\n')
            with patch.object(CACHE, 'select_artifact', return_value=artifact(1)), patch.object(CACHE, 'gh', side_effect=download):
                self.assertEqual(CACHE.restore('r-runtime-v1-test', library, 'owner/repo')['id'], 1)
            with self.assertRaisesRegex(ValueError, 'fresh empty'):
                CACHE.restore('r-runtime-v1-test', library, 'owner/repo')

    def test_cached_dtatools_renames_links_and_nonpackages_are_rejected(self):
        cases = [('dtatools', 'dtatools'), ('alias', 'dtatools'), ('alias', 'rlang')]
        for directory_name, package_name in cases:
            with self.subTest(case=directory_name), tempfile.TemporaryDirectory() as directory:
                package = Path(directory) / directory_name
                package.mkdir()
                (package / 'DESCRIPTION').write_text(f'Package: {package_name}\n')
                with self.assertRaises(ValueError):
                    CACHE.validate_library(Path(directory))
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'rlang').symlink_to('/tmp', target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'link or special'):
                CACHE.validate_library(Path(directory))
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'unexpected.txt').write_text('not a package')
            with self.assertRaisesRegex(ValueError, 'non-package'):
                CACHE.validate_library(Path(directory))

    def test_failure_text_redacts_the_token(self):
        failure = subprocess.CompletedProcess(['gh'], 1, '', 'failed with secret-token')
        with patch.dict(CACHE.os.environ, {'GH_TOKEN': 'secret-token'}), patch.object(CACHE.subprocess, 'run', return_value=failure):
            with self.assertRaisesRegex(RuntimeError, r'failed with \[redacted\]'):
                CACHE.gh('api', 'repos/owner/repo')


if __name__ == '__main__':
    unittest.main()
