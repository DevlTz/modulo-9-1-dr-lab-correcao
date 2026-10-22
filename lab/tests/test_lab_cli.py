"""Compatibilidade com o lab.sh original; Docker e incidentes são simulados."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
STUB='''#!/usr/bin/env python3
import json, os, pathlib, sys
root=pathlib.Path(os.environ['FAKE_ROOT'])
with (root/'commands.jsonl').open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if os.getenv('UP_FAIL')=='1' and 'up' in sys.argv: sys.exit(17)
'''

class LabCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        shutil.copytree(ROOT/'scripts',self.root/'scripts')
        shutil.copytree(ROOT/'initdb',self.root/'initdb')
        shutil.copy2(ROOT/'lab.sh',self.root/'lab.sh')
        (self.root/'bin').mkdir(); (self.root/'incidentes').mkdir()
        stub=self.root/'bin/docker'; stub.write_text(STUB); stub.chmod(0o755)
        self.env={**os.environ,'PATH':str(self.root/'bin')+':'+os.environ['PATH'],'FAKE_ROOT':str(self.root)}
    def run_cli(self,*args):
        return subprocess.run(['bash',str(self.root/'lab.sh'),*args],cwd='/tmp',env=self.env,
                              capture_output=True,text=True,timeout=10)
    def commands(self):
        f=self.root/'commands.jsonl'
        return [json.loads(s) for s in f.read_text().splitlines()] if f.exists() else []
    def script(self,path,text):
        f=self.root/path; f.write_text('#!/bin/bash\n'+text+'\n'); f.chmod(0o755)
    def test_subir_keeps_single_up_and_no_build_or_restore(self):
        r=self.run_cli('subir'); self.assertEqual(r.returncode,0,r.stderr)
        c=self.commands()
        self.assertEqual([a for a in c if 'up' in a],[['compose','up','-d']])
        self.assertFalse(any('build' in a or 'run' in a for a in c))
        self.assertIn('Rode ./lab.sh checar',r.stdout)
    def test_original_lab_works_without_preparation_hook(self):
        (self.root/'scripts/prepare.sh').unlink()
        r=self.run_cli('subir'); self.assertEqual(r.returncode,0)
        self.assertEqual(self.commands(),[['compose','up','-d']])
    def test_baixar_keeps_down_without_volume_deletion(self):
        r=self.run_cli('baixar'); self.assertEqual(r.returncode,0)
        self.assertEqual(self.commands(),[['compose','down']])
    def test_checar_preserves_existing_checagem_script_and_exit_status(self):
        self.script('scripts/checagem.sh','echo CHECAGEM_ORIGINAL; exit 13')
        r=self.run_cli('checar')
        self.assertEqual(r.returncode,13); self.assertIn('CHECAGEM_ORIGINAL',r.stdout)
    def test_failed_up_does_not_announce_success(self):
        self.env['UP_FAIL']='1'; r=self.run_cli('subir')
        self.assertEqual(r.returncode,17); self.assertNotIn('Subindo.',r.stdout)
    def test_incident_failure_does_not_announce_success(self):
        self.script('incidentes/1-provocar.sh','echo FALHA; exit 23')
        r=self.run_cli('incidente','iniciar','1')
        self.assertEqual(r.returncode,23); self.assertNotIn('Falha provocada.',r.stdout)
        self.assertIn('FALHA',(self.root/'evidencias/incidente1.log').read_text())
    def test_repeated_incident_preserves_log(self):
        self.script('incidentes/1-provocar.sh','echo PROVOCADO')
        self.assertEqual(self.run_cli('incidente','iniciar','1').returncode,0)
        self.assertEqual(self.run_cli('incidente','marcar','1','evidência anterior').returncode,0)
        self.assertEqual(self.run_cli('incidente','iniciar','1').returncode,0)
        log=(self.root/'evidencias/incidente1.log').read_text()
        self.assertEqual(log.count('T0 '),2); self.assertIn('evidência anterior',log)
    def test_recovery_uses_latest_t0(self):
        (self.root/'evidencias').mkdir()
        (self.root/'evidencias/incidente1.log').write_text('T0 1 rodada antiga\nT0 '+str(int(time.time()))+' rodada atual\n')
        r=self.run_cli('incidente','recuperado','1')
        self.assertEqual(r.returncode,0); self.assertIn('MTTR=00:00:',r.stdout)
    def test_revert_failure_does_not_run_check_or_claim_normal(self):
        self.script('incidentes/2-reverter.sh','exit 29')
        self.script('scripts/checagem.sh','echo CHECOU')
        r=self.run_cli('incidente','reverter','2')
        self.assertEqual(r.returncode,29)
        self.assertNotIn('CHECOU',r.stdout); self.assertNotIn('Ambiente de volta',r.stdout)
    def test_revert_runs_original_check(self):
        self.script('incidentes/2-reverter.sh','echo REVERTIDO')
        self.script('scripts/checagem.sh','echo CHECOU')
        r=self.run_cli('incidente','reverter','2')
        self.assertEqual(r.returncode,0)
        self.assertIn('CHECOU',r.stdout); self.assertIn('Ambiente de volta',r.stdout)
    def test_new_command_preserves_arguments(self):
        self.script('scripts/rejoin.sh','printf "ARG=%s\\n" "$@"; exit 7')
        r=self.run_cli('reintegrar','pg-primary','--descartar-dados-do-no')
        self.assertEqual(r.returncode,7)
        self.assertIn('ARG=pg-primary',r.stdout); self.assertIn('ARG=--descartar-dados-do-no',r.stdout)
    def test_unknown_command_returns_error(self):
        self.assertNotEqual(self.run_cli('apagar-tudo').returncode,0)
        self.assertFalse(self.commands())

if __name__=='__main__': unittest.main(verbosity=2)
