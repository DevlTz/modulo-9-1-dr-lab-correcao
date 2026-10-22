"""Testes locais com falhas injetadas; não substituem integração Docker/PostgreSQL/MinIO."""
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('backup', ROOT / 'backup/backup.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class S3Fake:
    def __init__(self, corrupt=False, mode='COMPLIANCE'):
        self.corrupt = corrupt
        self.mode = mode
        self.data = {}
    def put_object(self, **kw):
        self.data[kw['Key']] = (kw['Body'].read(), kw['ObjectLockRetainUntilDate'])
        return {'VersionId': 'v1'}
    def get_object_retention(self, **kw):
        return {'Retention': {'Mode': self.mode, 'RetainUntilDate': self.data[kw['Key']][1]}}
    def get_object(self, **kw):
        data = self.data[kw['Key']][0]
        return {'Body': io.BytesIO(data + b'corruption' if self.corrupt else data)}


class BackupTests(unittest.TestCase):
    def test_upload_verifies_hash_and_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'dump'; f.write_bytes(b'backup real')
            result = b.put_verified(S3Fake(), f, 'sets/a/loja.dump')
            self.assertEqual(result['version'], 'v1')
            self.assertEqual(result['sha256'], b.hash_file(f).hexdigest())
    def test_corrupt_upload_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'dump'; f.write_bytes(b'backup')
            with self.assertRaisesRegex(RuntimeError, 'SHA-256'):
                b.put_verified(S3Fake(corrupt=True), f, 'test')
    def test_governance_is_not_compliance(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'dump'; f.write_bytes(b'backup')
            with self.assertRaisesRegex(RuntimeError, 'COMPLIANCE'):
                b.put_verified(S3Fake(mode='GOVERNANCE'), f, 'test')
    def test_empty_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / 'dump'; f.touch()
            with self.assertRaisesRegex(RuntimeError, 'vazio'):
                b.put_verified(S3Fake(), f, 'test')
    def test_stale_status_is_unhealthy(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(b, 'ROOT', Path(tmp)):
            b.atomic_json(Path(tmp) / 'status.json', {'id': 'test', 'snapshot_lower_bound':
                (b.now() - dt.timedelta(minutes=6)).isoformat()})
            with self.assertRaisesRegex(RuntimeError, 'fora da meta'):
                b.health()
    def test_failed_dump_never_replaces_good_status(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(b, 'ROOT', Path(tmp)), patch.object(b, 'client', return_value=S3Fake()):
            status = Path(tmp) / 'status.json'; status.write_text('{"id":"previous"}')
            def fail(args, **kwargs):
                if args[0] == 'psql': return 't'
                if args[0] == 'pg_dump': raise subprocess.CalledProcessError(1, args)
                raise AssertionError('Não pode enviar backup após falha do dump.')
            with patch.object(b, 'command', side_effect=fail), self.assertRaises(subprocess.CalledProcessError):
                b.backup_once()
            self.assertEqual(json.loads(status.read_text())['id'], 'previous')
            self.assertFalse(list(Path(tmp).glob('.pending-*')))
    def test_remote_failure_never_publishes_success(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(b, 'ROOT', Path(tmp)), patch.object(b, 'client', return_value=S3Fake(corrupt=True)):
            def generate(args, outfile=None, **kwargs):
                if args[0] == 'psql': return 't'
                if args[0] == 'pg_dump': Path(args[-1]).write_bytes(b'dump')
                elif outfile: Path(outfile).write_text('roles or toc')
            with patch.object(b, 'command', side_effect=generate), self.assertRaisesRegex(RuntimeError, 'SHA-256'):
                b.backup_once()
            self.assertFalse((Path(tmp) / 'status.json').exists())
    def test_manifest_is_published_last(self):
        fake = S3Fake()
        with tempfile.TemporaryDirectory() as tmp, patch.object(b, 'ROOT', Path(tmp)), patch.object(b, 'client', return_value=fake):
            def generate(args, outfile=None, **kwargs):
                if args[0] == 'psql': return 't'
                if args[0] == 'pg_dump': Path(args[-1]).write_bytes(b'dump')
                elif outfile: Path(outfile).write_text('roles or toc')
            with patch.object(b, 'command', side_effect=generate): b.backup_once()
            self.assertTrue(list(fake.data)[-1].endswith('/manifest.json'))
            self.assertTrue((Path(tmp) / 'status.json').exists())


class ArchiveTests(unittest.TestCase):
    def test_atomic_idempotent_and_collision_safe(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); archive = root / 'archive'; archive.mkdir()
            src = root / 'wal'; src.write_bytes(b'WAL original')
            name = '000000010000000000000001'
            env = {**os.environ, 'ARCHIVE_DIR': str(archive)}
            args = ['bash', str(ROOT / 'scripts/archive-wal.sh'), str(src), name]
            subprocess.run(args, env=env, check=True, capture_output=True)
            subprocess.run(args, env=env, check=True, capture_output=True)
            src.write_bytes(b'WAL divergente')
            result = subprocess.run(args, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((archive / name).read_bytes(), b'WAL original')
            self.assertEqual(len(list(archive.iterdir())), 1)
    def test_failed_copy_leaves_no_final_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(['bash', str(ROOT / 'scripts/archive-wal.sh'), '/nonexistent/labwal',
                '000000010000000000000001'], env={**os.environ, 'ARCHIVE_DIR': tmp}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(list(Path(tmp).iterdir()))


DOCKER_STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args=sys.argv[1:]; root=pathlib.Path(os.environ['FAKE_ROOT'])
with (root/'commands.jsonl').open('a') as f: f.write(json.dumps(args)+'\\n')
if args[0]=='inspect':
    print('true' if os.getenv('FENCE_FAIL')=='1' else 'false')
elif 'ps' in args: print('container-id')
elif 'exec' in args:
    query=args[-1]
    if 'pg_promote' in query:
        (root/'promoted').touch(); print('t')
    elif 'pg_is_wal_replay_paused' in query: print('f')
    elif 'pg_is_in_recovery' in query:
        print('f' if (root/'promoted').exists() else 't')
    elif 'COALESCE(pg_last_wal_replay_lsn' in query: print('t')
    elif 'pg_last_wal_receive_lsn' in query: print('0/200|0/200|timestamp')
'''


class FailoverTests(unittest.TestCase):
    def run_case(self, fail):
        tmp = tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        shutil.copytree(ROOT / 'scripts', root / 'scripts')
        (root / 'runtime').mkdir(); (root / 'runtime/active').write_text('pg-primary\n')
        (root / 'bin').mkdir(); stub = root / 'bin/docker'; stub.write_text(DOCKER_STUB); stub.chmod(0o755)
        env = {**os.environ, 'PATH': str(root / 'bin') + ':' + os.environ['PATH'],
               'FAKE_ROOT': str(root), 'FENCE_FAIL': str(int(fail))}
        result = subprocess.run(['bash', str(root / 'scripts/failover.sh'), '--aceitar-perda-potencial'],
                                env=env, capture_output=True, text=True, timeout=15)
        commands = [json.loads(line) for line in (root / 'commands.jsonl').read_text().splitlines()]
        return root, result, commands
    def test_no_promotion_when_fencing_fails(self):
        root, result, commands = self.run_case(True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((root / 'promoted').exists())
        self.assertEqual((root / 'runtime/active').read_text().strip(), 'none')
        self.assertTrue((root / 'runtime/fenced-pg-primary').exists())
    def test_promotion_only_after_fencing(self):
        root, result, commands = self.run_case(False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        inspected = next(i for i,c in enumerate(commands) if c[0] == 'inspect')
        promoted = next(i for i,c in enumerate(commands) if 'pg_promote' in c[-1])
        self.assertLess(inspected, promoted)
        self.assertEqual((root / 'runtime/active').read_text().strip(), 'pg-replica')
        self.assertTrue((root / 'runtime/fenced-pg-primary').exists())


if __name__ == '__main__': unittest.main(verbosity=2)
