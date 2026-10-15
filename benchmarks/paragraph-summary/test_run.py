import contextlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run


class EvidenceTests(unittest.TestCase):
    def test_exact_course_preserves_alias_and_honors_boundaries(self):
        case = dict(course='PSYC 002', reviews=[
            dict(id='yes', course='PSYC002', text='Helpful lectures.'),
            dict(id='alias', course='PSYCH002', text='Clear lectures.'),
            dict(id='honors', course='PSYC002H', text='Easy exams.')])
        selected = run.evidence(case)
        self.assertEqual([r['id'] for r in selected['reviews']], ['yes'])
        self.assertEqual(selected['excluded_ids'], ['alias', 'honors'])

    def test_duplicate_ids_do_not_inflate_evidence(self):
        case = dict(course='ETH 014', reviews=[
            dict(id='one', course='ETH014', text='Textbook was expensive!'),
            dict(id='copy', course='ETH014', text='textbook was expensive.'),
            dict(id='two', course='ETH014', text='Clear explanations.')])
        selected = run.evidence(case)
        self.assertEqual(len(selected['reviews']), 2)
        self.assertEqual(selected['duplicate_groups'], [['one', 'copy']])

    def test_unparseable_course_fails_closed(self):
        self.assertEqual(run.evidence(dict(course='English', reviews=[
            dict(id='one', course='English', text='Great examples.')]))['reviews'], [])

    def test_empty_evidence_abstains_without_inference(self):
        server = run.Server({}, 'unused')
        with patch.object(server, 'generate', side_effect=AssertionError('inference forbidden')):
            result = server.summarize(dict(name='empty', course='ETH014', reviews=[]), 0)
        self.assertTrue(result['abstained'])
        self.assertIn('insufficient', result['text'])

    def test_source_ids_and_full_text_survive_selection(self):
        text = 'Homework was not excessive. ' * 1000
        selected = run.evidence(dict(course='ETH014', reviews=[dict(id='one', course='ETH014', text=text)]))
        self.assertEqual(selected['reviews'][0]['text'], text)
        self.assertEqual(selected['reviews'][0]['id'], 'one')

    def test_chunking_preserves_complete_reviews(self):
        server = run.Server({}, 'unused')
        reviews = [dict(id=str(i), course='ETH014', text='full review ' + str(i)) for i in range(4)]
        captured = []
        def render(msgs):
            payload = json.loads(msgs[1]['content'].split('\n')[-1])
            return 'prompt', 8000 if len(payload) > 2 else 100
        def generate(msgs):
            captured.append(msgs)
            return dict(text='A supported paragraph.', runtime={})
        with patch.object(server, 'render', side_effect=render), patch.object(server, 'generate', side_effect=generate):
            result = server.summarize(dict(name='long', course='ETH014', reviews=reviews), 0)
        self.assertTrue(result['chunked'])
        chunks = [json.loads(m[1]['content'].split('\n')[-1]) for m in captured[:-1]]
        self.assertEqual([r for c in chunks for r in c], reviews)

    def test_one_oversized_review_rejected_without_truncation(self):
        server = run.Server({}, 'unused')
        with patch.object(server, 'render', return_value=('prompt', 9000)):
            with self.assertRaisesRegex(ValueError, 'Single complete review'):
                server.summarize(dict(name='large', course='ETH014', reviews=[dict(id='1', course='ETH014', text='complete')]), 0)


class IntegrityTests(unittest.TestCase):
    def test_hash_mismatch_keeps_partial(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'WORK', Path(directory)):
            p = Path(directory) / 'models/test.gguf.part'
            p.parent.mkdir()
            p.write_bytes(b'wrong')
            with self.assertRaises(ValueError):
                run.verify(dict(filename='test.gguf', bytes=5, sha256='bad'))
            self.assertTrue(p.exists())
            self.assertFalse(p.with_suffix('').exists())

    def test_verified_partial_is_promoted(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'WORK', Path(directory)):
            p = Path(directory) / 'models/test.gguf.part'
            p.parent.mkdir()
            p.write_bytes(b'model')
            final = run.verify(dict(filename='test.gguf', bytes=5, sha256=run.sha(p)))
            self.assertEqual(final.read_bytes(), b'model')
            self.assertFalse(p.exists())

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'WORK', Path(directory)):
            p = Path(directory) / 'models/test.gguf'
            p.parent.mkdir()
            target = Path(directory) / 'target'
            target.write_bytes(b'model')
            p.symlink_to(target)
            with self.assertRaises(ValueError):
                run.verify(dict(filename='test.gguf', bytes=5, sha256=run.sha(target)))


class QualityGateTests(unittest.TestCase):
    def setup_rows(self, directory):
        folder = Path(directory) / 'screen-v0/model'
        decisions = {}
        for i in range(21):
            name = str(i)
            text = 'Supported short paragraph.'
            evidence = dict(reviews=[])
            run.save(folder / (name + '.json'), dict(case=name, output_hash=run.digest(text), evidence_hash=run.digest(evidence),
                evidence=evidence, prompt_hash=run.digest(run.PROMPTS[0]), text=text, structural_errors=[]))
            decisions[name] = dict(output_hash=run.digest(text), evidence_hash=run.digest(evidence), safe=True,
                disagreements_preserved=True, covered_priority_facts=1, eligible_priority_facts=1)
        run.save(folder / 'review/decisions.json', decisions)
        return folder, decisions

    def test_pending_reviews_cannot_measure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            with self.assertRaises(FileNotFoundError):
                run.reviewed('model', 0)

    def test_stale_hash_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            folder, decisions = self.setup_rows(directory)
            decisions['0']['output_hash'] = 'old'
            run.save(folder / 'review/decisions.json', decisions)
            with self.assertRaisesRegex(ValueError, 'Stale judgment'):
                run.reviewed('model', 0)

    def test_unsafe_output_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            folder, decisions = self.setup_rows(directory)
            decisions['0']['safe'] = False
            run.save(folder / 'review/decisions.json', decisions)
            with self.assertRaisesRegex(ValueError, 'quality screening'):
                run.reviewed('model', 0)

    def test_low_coverage_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            folder, decisions = self.setup_rows(directory)
            for decision in decisions.values():
                decision['covered_priority_facts'] = 0
            run.save(folder / 'review/decisions.json', decisions)
            with self.assertRaisesRegex(ValueError, '80%'):
                run.reviewed('model', 0)

    def test_changed_prompt_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            self.setup_rows(directory)
            with patch.object(run, 'PROMPTS', ['Changed prompt', 'Other prompt']):
                with self.assertRaisesRegex(ValueError, 'Prompt changed'):
                    run.reviewed('model', 0)

    def test_long_paragraph_rejected_even_with_positive_judgment(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            folder, decisions = self.setup_rows(directory)
            path = folder / '0.json'
            row = run.load(path)
            row['text'] = 'word ' * 121
            row['output_hash'] = run.digest(row['text'])
            decisions['0']['output_hash'] = row['output_hash']
            run.save(folder / 'review/decisions.json', decisions)
            run.save(path, row)
            with self.assertRaisesRegex(ValueError, 'format failed'):
                run.reviewed('model', 0)

    def test_changed_payload_cannot_reuse_hash_fields(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(run, 'BASE', Path(directory)):
            folder, _ = self.setup_rows(directory)
            path = folder / '0.json'
            row = run.load(path)
            row['text'] = 'Unreviewed replacement.'
            run.save(path, row)
            with self.assertRaisesRegex(ValueError, 'changed after source review'):
                run.reviewed('model', 0)


if __name__ == '__main__':
    unittest.main()
