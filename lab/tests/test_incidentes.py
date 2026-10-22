"""Testes dos limites dos incidentes; nenhuma chamada ao Docker real."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DOCKER = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ['TEST_LAB_ROOT'])
args = sys.argv[1:]
with (root/'calls.jsonl').open('a') as f:
    f.write(json.dumps(args)+'\n')
if 'exec' in args and 'psql' in args:
    query = args[-1]
    if 'pg_is_in_recovery' in query:
        print('t' if 'pg-replica' in args else 'f')
    elif 'pg_stat_wal_receiver' in query:
        print('streaming')
if 'run' in args and '-c' in args:
    command = args[args.index('-c')+1]
    command = command.replace('/backups', str(root/'backups'))
    sys.exit(subprocess.run(['sh', '-c', command]).returncode)
'''

class IncidentTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in ('scripts', 'incidentes'):
            shutil.copytree(ROOT/name, self.root/name)
        shutil.copy2(ROOT/'lab.sh', self.root/'lab.sh')
        (self.root/'runtime').mkdir()
        (self.root/'runtime/active').write_text('pg-primary\n')
        (self.root/'bin').mkdir()
        stub = self.root/'bin/docker'
        stub.write_text(DOCKER); stub.chmod(0o755)
        self.env = {**os.environ, 'TEST_LAB_ROOT':str(self.root),
                    'PATH':str(self.root/'bin')+':'+os.environ['PATH']}
    def run_script(self, name, *args):
        return subprocess.run(['bash', str(self.root/name), *args],
                              cwd='/tmp', env=self.env, capture_output=True,
                              text=True, timeout=10)
    def calls(self):
        p=self.root/'calls.jsonl'
        return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
    def test_incident3_refuses_to_stop_promoted_replica(self):
        (self.root/'runtime/active').write_text('pg-replica\n')
        r=self.run_script('incidentes/3-provocar.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.calls())
    def test_incident1_refuses_inverted_roles(self):
        (self.root/'runtime/active').write_text('pg-replica\n')
        r=self.run_script('incidentes/1-provocar.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.calls())
    def test_revert1_requires_explicit_discard_after_promotion(self):
        (self.root/'runtime/active').write_text('pg-replica\n')
        r=self.run_script('incidentes/1-reverter.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('--descartar-dados-do-no',r.stderr)
        self.assertFalse(self.calls())
    def test_wrapper_forwards_discard_to_rejoin(self):
        (self.root/'runtime/active').write_text('pg-replica\n')
        (self.root/'scripts/rejoin.sh').write_text('printf "%s\\n" "$@" > rejoin-args.txt\n')
        (self.root/'scripts/checagem.sh').write_text('exit 0\n')
        r=self.run_script('lab.sh','incidente','reverter','1','--descartar-dados-do-no')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual((self.root/'rejoin-args.txt').read_text().splitlines(),
                         ['pg-primary','--descartar-dados-do-no'])
    def test_local_loss_targets_completed_dumps_only(self):
        folder=self.root/'backups/complete/sample'
        folder.mkdir(parents=True)
        (folder/'loja.dump').write_text('dump')
        (folder/'manifest.json').write_text('{}')
        (self.root/'backups/status.json').write_text('{}')
        (self.root/'unrelated.dump').write_text('keep')
        r=self.run_script('incidentes/2-provocar.sh')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertFalse((folder/'loja.dump').exists())
        self.assertFalse((self.root/'backups/status.json').exists())
        self.assertTrue((folder/'manifest.json').exists())
        self.assertTrue((self.root/'unrelated.dump').exists())
        self.assertFalse(any('up' in c for c in self.calls()))
    def test_no_dump_fails_and_resumes_backup(self):
        (self.root/'backups/complete').mkdir(parents=True)
        r=self.run_script('incidentes/2-provocar.sh')
        self.assertNotEqual(r.returncode,0)
        self.assertNotIn('Dumps locais removidos.',r.stdout)
        self.assertTrue(any(c[-4:]==['up','-d','--no-deps','backup'] for c in self.calls()))
    def test_check_wrapper_preserves_failure_in_log(self):
        (self.root/'scripts/check.sh').write_text('echo SEM_STREAMING; exit 19\n')
        r=self.run_script('scripts/checagem.sh')
        self.assertEqual(r.returncode,19)
        logs=list((self.root/'evidencias').glob('checagem_*.txt'))
        self.assertEqual(len(logs),1)
        self.assertIn('SEM_STREAMING',logs[0].read_text())

if __name__ == '__main__':
    unittest.main()
