import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import stable_tools_release as release


class FakeGitHub:
    repository = 'superautoma/Enriquecido'

    def __init__(self):
        self.sha = release.BASELINE_COMMIT
        self.run = {
            'id': 37785000081, 'run_number': 101, 'run_attempt': 1,
            'workflow_id': 7, 'path': release.WORKFLOW,
            'head_repository': {'full_name': self.repository},
            'status': 'completed', 'conclusion': 'success',
            'head_sha': self.sha, 'html_url': 'https://github.com/example/run/101',
        }
        self.steps = list(release.REQUIRED_STEPS)
        self.artifact = {
            'id': 11554577398, 'name': release.ARTIFACT, 'expired': False,
            'workflow_run': {'head_sha': self.sha},
        }
        self.existing_tag = self.sha
        self.posts = []

    def get(self, path):
        if path == 'actions/workflows/build-integrated-quill-apk.yml':
            return {'id': 7}
        if path.startswith('git/tags/'):
            return {'object': {'type': 'commit', 'sha': self.existing_tag}}
        raise AssertionError(path)

    def pages(self, path, field):
        if path == 'actions/workflows/7/runs':
            return iter([self.run])
        if path == 'actions/runs/37785000081/attempts/1/jobs':
            return iter([{'steps': [{'name': s, 'conclusion': 'success'} for s in self.steps]}])
        if path == 'actions/runs/37785000081/artifacts':
            return iter([self.artifact])
        if path == 'releases':
            return iter([])
        raise AssertionError(path)

    def optional(self, path):
        if path.startswith('git/ref/tags/'):
            if self.existing_tag is None:
                return None
            return {'object': {'type': 'tag', 'sha': 'annotated-tag'}}
        if path.startswith('releases/tags/'):
            return None
        raise AssertionError(path)

    def post(self, path, data):
        self.posts.append((path, data))
        raise AssertionError('Unexpected write')


class StableReleaseTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeGitHub()

    def plan(self, **kwargs):
        return release.plan(self.api, kwargs.get('number', '101'),
                            kwargs.get('confirmed', True), kwargs.get('dry_run', False))

    def test_uses_exact_build_commit_and_original_artifact(self):
        result = self.plan()
        self.assertEqual(result['commit'], release.BASELINE_COMMIT)
        self.assertEqual(result['run_id'], 37785000081)
        self.assertEqual(result['tag'], 'gestor-herramientas-v101')
        self.assertEqual(result['artifact_id'], 11554577398)
        self.assertEqual(self.api.posts, [])

    def test_requires_mobile_confirmation_for_writes(self):
        with self.assertRaisesRegex(ValueError, 'confirmar'):
            self.plan(confirmed=False)

    def test_dry_run_needs_no_mobile_confirmation_and_never_writes(self):
        info = self.plan(confirmed=False, dry_run=True)
        self.assertIn('No se han creado', release.publish(self.api, info, None, True))
        self.assertEqual(self.api.posts, [])

    def test_rejects_invalid_and_unknown_numbers(self):
        for number in ['101; echo secret', '0', '0101', '-1', '32']:
            with self.subTest(number=number), self.assertRaises(ValueError):
                self.plan(number=number)

    def test_rejects_failed_or_incomplete_runs(self):
        for field, value in [('conclusion', 'failure'), ('status', 'in_progress')]:
            original = copy.deepcopy(self.api.run)
            self.api.run[field] = value
            with self.assertRaises(ValueError):
                self.plan()
            self.api.run = original

    def test_rejects_other_workflows_and_forks(self):
        for field, value in [('workflow_id', 9), ('path', 'check-herramientas.yml'),
                             ('head_repository', {'full_name': 'attacker/fork'})]:
            original = copy.deepcopy(self.api.run)
            self.api.run[field] = value
            with self.assertRaises(ValueError):
                self.plan()
            self.api.run = original

    def test_requires_signature_and_application_tests(self):
        for step in release.REQUIRED_STEPS:
            with self.subTest(step=step):
                self.api.steps = list(release.REQUIRED_STEPS - {step})
                with self.assertRaises(ValueError):
                    self.plan()

    def test_refuses_expired_original_instead_of_rebuilding(self):
        self.api.artifact['expired'] = True
        with self.assertRaisesRegex(ValueError, 'caducado'):
            self.plan()

    def test_rejects_artifact_from_another_commit(self):
        self.api.artifact['workflow_run']['head_sha'] = 'another-commit'
        with self.assertRaises(ValueError):
            self.plan()

    def test_does_not_move_existing_tag(self):
        self.api.existing_tag = 'another-commit'
        with self.assertRaisesRegex(ValueError, 'otro commit'):
            self.plan()
        self.assertEqual(self.api.posts, [])

    def test_rechecks_tag_before_publishing(self):
        info = self.plan()
        self.api.existing_tag = 'another-commit'
        with self.assertRaisesRegex(ValueError, 'cambiado'):
            release.publish(self.api, info, None, False)
        self.assertEqual(self.api.posts, [])

    def test_checks_http_status_instead_of_treating_auth_error_as_missing(self):
        api = release.GitHub('superautoma/Enriquecido')
        with patch.object(release.subprocess, 'run') as run:
            run.return_value.returncode = 1
            run.return_value.stdout = 'HTTP/2.0 403 Forbidden\n\n{}'
            run.return_value.stderr = 'Resource not accessible by integration'
            with self.assertRaises(RuntimeError):
                api.optional('git/ref/tags/test')
            run.return_value.stdout = 'HTTP/2.0 404 Not Found\n\n{}'
            self.assertIsNone(api.optional('git/ref/tags/test'))

    def test_pagination_continues_until_exact_old_build(self):
        api = release.GitHub('superautoma/Enriquecido')
        with patch.object(api, 'get', side_effect=[{'workflow_runs': list(range(100))},
                                                {'workflow_runs': [101]}]) as get:
            self.assertEqual(list(api.pages('actions/runs', 'workflow_runs'))[-1], 101)
            self.assertIn('page=2', get.call_args.args[0])

    def test_refuses_ambiguous_apk_files(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ['app-release.apk', 'other.apk']:
                (Path(directory) / name).write_bytes(b'test')
            with self.assertRaisesRegex(ValueError, 'una sola APK'):
                release.verify_apk(self.api, self.plan(), directory)

    def test_reads_legacy_signer_output(self):
        digest = 'ab' * 32
        output = f'Signer #1 certificate SHA-256 digest: {digest}\n'
        self.assertEqual(release.signer_digest(output), digest)

    def test_reads_exact_v101_runner_output(self):
        digest = 'b8a1e06c9d9f7e5ea828a47d2d220b024e7fad3d057d167f29e4a18c69070aae'
        output = (
            'V2 Signer: certificate DN: CN=Android Debug, O=Memento Development, C=ES\n'
            f'V2 Signer: certificate SHA-256 digest: {digest}\n'
            'V2 Signer: certificate SHA-1 digest: 12039bb4eb30f75313f6460a8510906b05721b39\n')
        self.assertEqual(release.signer_digest(output), digest)

    def test_reads_signer_certificates_for_sdk_ranges_and_dev_releases(self):
        digest = 'ab' * 32
        output = (
            f'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: {digest}\n'
            f'Signer (minSdkVersion=33 (dev release=true), maxSdkVersion=2147483647) '
            f'certificate SHA-256 digest: {digest.upper()}\n'
            f'Source Stamp Signer certificate SHA-256 digest: {"cd" * 32}\n')
        self.assertEqual(release.signer_digest(output), digest)

    def test_reads_duplicate_digest_without_accepting_different_certificates(self):
        output = f'Signer #1 certificate SHA-256 digest: {"ab" * 32}\n'
        self.assertEqual(release.signer_digest(output * 2), 'ab' * 32)
        with self.assertRaises(RuntimeError):
            release.signer_digest(output + f'Signer #2 certificate SHA-256 digest: {"cd" * 32}\n')

    def test_does_not_accept_stamp_only_or_malformed_certificate(self):
        for output in ['Source Stamp Signer certificate SHA-256 digest: ' + 'ab' * 32,
                       'Signer #1 certificate SHA-256 digest: 1234', 'DOES NOT VERIFY']:
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                release.signer_digest(output)


if __name__ == '__main__':
    unittest.main()
