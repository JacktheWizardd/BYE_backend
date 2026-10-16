import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import run

class SelectionTests(unittest.TestCase):
    def test_held_out_never_selected(self):
        cases=run.cases()
        self.assertEqual(len(cases),21)
        self.assertEqual(sum(c['partition']=='development' for c in cases),7)
        self.assertFalse(any(c['partition']=='held_out' for c in cases))

    def test_wrong_artifact_rejected(self):
        with tempfile.TemporaryDirectory() as d,patch.object(run,'WORK',Path(d)):
            p=Path(d)/'models/x/gguf/a.gguf';p.parent.mkdir(parents=True);p.write_bytes(b'wrong')
            with self.assertRaisesRegex(ValueError,'integrity'):
                run.verify(dict(id='x',filename='a.gguf',bytes=5,sha256='bad'))

    def test_complete_review_chunking(self):
        server=run.p.Server({},'unused')
        reviews=[dict(id=str(i),course='ETH014',text='Complete review '+str(i)) for i in range(5)]
        captured=[]
        def render(msgs):
            n=len(json.loads(msgs[1]['content'].split('\n')[-1]))
            return 'prompt',8000 if n>2 else 100
        def generate(msgs):
            captured.append(msgs);return dict(text='Supported summary.',runtime={})
        with patch.object(server,'render',side_effect=render),patch.object(server,'generate',side_effect=generate):
            result=server.summarize(dict(name='long',course='ETH014',reviews=reviews),1)
        self.assertTrue(result['chunked'])
        self.assertEqual([r for m in captured[:-1] for r in json.loads(m[1]['content'].split('\n')[-1])],reviews)

    def test_single_review_overflow_rejected(self):
        server=run.p.Server({},'unused')
        with patch.object(server,'render',return_value=('p',9000)):
            with self.assertRaisesRegex(ValueError,'Single complete review'):
                server.summarize(dict(name='large',course='ETH014',reviews=[dict(id='1',course='ETH014',text='Full text')]),1)

    def test_empty_abstains_without_inference(self):
        server=run.p.Server({},'unused')
        with patch.object(server,'generate',side_effect=AssertionError('No inference')):
            result=server.summarize(dict(name='empty',course='ETH014',reviews=[]),1)
        self.assertTrue(result['abstained'])

if __name__=='__main__':unittest.main()
