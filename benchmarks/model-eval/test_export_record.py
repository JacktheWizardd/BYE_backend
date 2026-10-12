import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import export_record


class PublicRecordTests(unittest.TestCase):
    def fixture(self, root):
        run=root/'private-run'
        run.mkdir()
        stagepath='trials/development-256/round1/model/2048/direct/private-case.final.json'
        stage={'stage':'direct','prompt':'PRIVATE_REVIEW_SENTINEL',
               'raw_output':'PRIVATE_REVIEW_SENTINEL','timings':{'predicted_n':7}}
        row={'variant':'model','case':'PRIVATE_CASE_SENTINEL','partition':'development',
             'context':2048,'mode':'direct','output_limit':256,
             'stages':[stagepath],'total_pipeline_s':1.25,'error':'PRIVATE_ERROR_SENTINEL'}
        files={stagepath:stage,stagepath.replace('.final.json','.json'):row,
               'quality-summary.json':[],'sizes.json':[],'manifest.json':{'models':[]},
               'settings.json':{'threads':4},'semantic-review-packets.json':[],
               'semantic-review-key.json':[]}
        for name,value in files.items():
            path=run/name;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(value))
        (run/'semantic-judgments.jsonl').write_text('')
        (run/'sessions').mkdir()
        return run

    def test_export_omits_real_text_case_names_and_free_form_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);run=self.fixture(root);out=root/'public'
            before={str(p.relative_to(run)):p.read_bytes() for p in run.rglob('*') if p.is_file()}
            with contextlib.redirect_stdout(io.StringIO()):export_record.export(run,out)
            # Provenance retains private relative source paths and hashes, but no contents.
            content=''.join(p.read_text() for p in out.iterdir() if p.name!='provenance.json')
            for sentinel in ['PRIVATE_REVIEW_SENTINEL','PRIVATE_CASE_SENTINEL','PRIVATE_ERROR_SENTINEL']:
                self.assertNotIn(sentinel,content)
            self.assertIn('real-01',content)
            self.assertEqual(before,{str(p.relative_to(run)):p.read_bytes() for p in run.rglob('*') if p.is_file()})

    def test_existing_export_is_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);run=self.fixture(root);out=root/'public';out.mkdir()
            with self.assertRaises(FileExistsError):export_record.export(run,out)
