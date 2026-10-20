import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from tools.record_demo import main


class RecordingRecoveryTest(unittest.TestCase):
    def test_reconciliation_recovery_never_invokes_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dataset = root/'dataset'
            dataset.mkdir()
            (dataset/'manifest.json').write_text(json.dumps(dict(run_id='run',sha256='hash',event_count=1)))
            receipt = root/'receipt.json'
            receipt.write_text(json.dumps(dict(status='ACKNOWLEDGED',run_id='run',sha256='hash',acknowledged_records=1)))
            args = ['record_demo.py','--dataset',str(dataset),'--out',str(root/'evidence'),'--reconcile-only','--publish-receipt',str(receipt)]
            with patch('sys.argv',args), patch('tools.record_demo.subprocess.run',return_value=subprocess.CompletedProcess([],0,'verified\n','')) as run:
                self.assertEqual(main(),0)
            commands = [call.args[0] for call in run.call_args_list]
            self.assertFalse(any('publish' in command for command in commands))
            self.assertTrue(any('reconcile' in command for command in commands))
            self.assertIn('stop',commands[-1])
            self.assertIn('publication skipped',(root/'evidence'/'demo.cast').read_text())
