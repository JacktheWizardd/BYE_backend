import contextlib,io,json,tempfile,unittest
from pathlib import Path
import review

class ReviewTests(unittest.TestCase):
 def write(self,root,name,value):
  path=root/name;path.write_text(json.dumps(value)+'\n')
 def fixture(self,root,technical=False):
  self.write(root,'selected-cases.json',{'cases':[{'name':'fixture','partition':'development','reviews':[{'id':'a','text':'Clear explanations'},{'id':'b','text':'Explanations clear'}]}]})
  self.write(root,'development-expected-facts.json',{'cases':[{'case':'fixture','themes':[{'text':'clear explanations','review_ids':['a','b']}]}]})
  self.write(root,'heldout-expected-facts.json',{'cases':[]})
  packet={'blind_id':'blind','raw_sha256':'raw','evidence_sha256':'evidence','eligible_priority_themes':[{'text':'clear explanations'}],'displayed':{'positives':[],'concerns':[]},'raw_output':'{"positives":[],"concerns":[]}','expected':{},'structural_errors':[]}
  self.write(root,'semantic-review-packets.json',[packet])
  key={'blind_id':'blind','path':'trial','variant':'variant','context':2048,'mode':'direct','output_limit':256,'case':'fixture','partition':'development','raw_sha256':'raw'}
  self.write(root,'semantic-review-key.json',[] if technical else [key])
  self.write(root,'technical-quality-failures.json',[key] if technical else [])
  judgment={'blind_id':'blind','raw_sha256':'raw','evidence_sha256':'evidence','raw_invented_claims':0,'displayed_invented_claims':0,'wrong_course_claims':0,'sentiment_reversals':0,'unsupported_corroboration':0,'covered_themes':1,'raw_readability':4,'displayed_readability':4,'abstention_pass':None,'disagreement_pass':None,'notes':'fixture'}
  self.write(root,'semantic-judgments.jsonl',judgment)
 def aggregate(self,root):
  with contextlib.redirect_stdout(io.StringIO()):review.aggregate(root)
  return json.loads((root/'quality-summary.json').read_text())[0]
 def test_empty_display_cannot_inherit_raw_theme_coverage(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);self.fixture(root);result=self.aggregate(root)
   self.assertEqual(result['reviewed_subset_coverage']['development']['displayed_coverage'],0)
   self.assertEqual(result['empty_theme_bearing_displays'],1)
   self.assertEqual(result['release_recommendation'],'none for this configuration')
 def test_technical_only_configuration_is_reported_as_failure(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);self.fixture(root,technical=True);result=self.aggregate(root)
   self.assertEqual(result['technical_failures'],1)
   self.assertEqual(result['reviewed_subset_coverage']['development']['eligible_theme_occurrences'],1)
   self.assertEqual(result['reviewed_subset_coverage']['development']['displayed_coverage'],0)
   self.assertEqual(result['release_recommendation'],'none for this configuration')
 def test_display_detail_hash_mismatch_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);self.fixture(root)
   self.write(root,'semantic-judgment-display-details.json',{'details':[{'blind_id':'blind','raw_sha256':'different','evidence_sha256':'evidence'}]})
   with self.assertRaisesRegex(ValueError,'Display-detail hash mismatch'):self.aggregate(root)
 def test_heldout_schema_conversion_preserves_disagreements(self):
  original={'expected_facts':[{'claim':'clear lectures','review_ids':['a','b'],'status':'recurring_positive'},{'claim':'opposing accounts','review_ids':['c','d'],'status':'conflict'}]}
  converted=review.normalized_annotation(original)
  self.assertEqual(len(converted['themes']),1)
  self.assertEqual(converted['expected_facts'],original['expected_facts'])
  self.assertNotIn('themes',original)

class AnalysisTests(unittest.TestCase):
 def test_first_summary_text_excludes_syntax_and_reasoning(self):
  import analyze
  events=[{'arrival_s':.1,'event':{'content':'<think>draft</think>{"overview": "'}},{'arrival_s':.2,'event':{'content':'Clear explanations'}}]
  self.assertEqual(analyze.first_summary_text({'stream_events':events}),.2)
 def test_unfinished_reasoning_has_no_answer_text_arrival(self):
  import analyze
  self.assertIsNone(analyze.first_summary_text({'stream_events':[{'arrival_s':.1,'event':{'content':'<think>{"overview":"draft'}}]}))
