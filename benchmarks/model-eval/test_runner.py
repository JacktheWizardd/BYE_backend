import importlib.util,json,socket,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('evaluation',Path(__file__).with_name('run.py'));r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class RunnerTests(unittest.TestCase):
 def setUp(self):
  self.case={'name':'test','course':'ETH 014','partition':'synthetic','reviews':[{'id':'a','course':'ETH014','text':'Clear explanations.'},{'id':'b','course':'ETH014','text':'Explanations were clear.'}]}
  self.output={'overview':'Clear explanations.','positives':[{'text':'clear explanations','reviewIDs':['a','b']}],'concerns':[]}
 def test_twelve_variants_and_totals(self):
  a=r.artifacts();self.assertEqual(len(a),12);self.assertEqual(len(set(x['variant'] for x in a)),12);self.assertEqual(sum(x['bytes'] for x in a),11949057632)
 def test_integrity_mismatch(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'model';p.write_bytes(b'wrong')
   with self.assertRaises(ValueError):r.verify_artifact({'path':str(p),'bytes':5,'sha256':'bad'})
 def test_valid_json(self):self.assertEqual(r.structural(json.dumps(self.output),self.case,'direct')[1],[])
 def test_malformed_json(self):self.assertTrue(r.structural('{',self.case,'direct')[1])
 def test_wrong_ids(self):
  self.output['positives'][0]['reviewIDs']=['a','missing'];self.assertIn('invalid citations',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_duplicate_id(self):
  self.output['positives'][0]['reviewIDs']=['a','a'];self.assertIn('not two distinct IDs',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_duplicate_content_distinct_ids(self):
  self.case['reviews'][1]['text']=self.case['reviews'][0]['text'];self.assertIn('duplicate corroboration',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_course_alias_not_guessed(self):
  self.case['reviews'][1]['course']='ETH016';self.assertIn('wrong-course citation',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_honors_not_equivalent(self):self.assertNotEqual(r.canonical('PSYC002H'),r.canonical('PSYC002'))
 def test_schema_empty_source_has_no_fake_valid_id(self):self.assertEqual(r.point_schema([])['properties']['reviewIDs']['items']['enum'],['NO_SOURCE'])
 def test_templates_no_special_addition(self):
  with patch.object(r,'rpc',side_effect=[{'prompt':'<s>text'},{'tokens':[1,2]}]) as mocked:
   s=object.__new__(r.Server);s.port=1
   self.assertEqual(s.render(self.case)[1],[1,2]);self.assertFalse(mocked.call_args.args[2]['add_special']);self.assertTrue(mocked.call_args.args[2]['parse_special'])
 def test_overflow_rejected_before_inference(self):
  with tempfile.TemporaryDirectory() as d:
   s=object.__new__(r.Server);s.run=Path(d);s.a={'variant':'test'};s.ctx=2;s.inflight=False;s.first_inference=True;s.load_s=0
   with patch.object(s,'render',return_value=('prompt',[1,2],{})),patch.object(r.urllib.request,'urlopen') as http:
    v=s.generate(self.case,'direct',Path(d)/'result.json');self.assertIn('context_overflow_rejected',v['error']);http.assert_not_called()
 def test_timeout_preserves_raw_checkpoint(self):
  with tempfile.TemporaryDirectory() as d:
   s=object.__new__(r.Server);s.run=Path(d);s.a={'variant':'test'};s.ctx=2048;s.inflight=False;s.first_inference=True;s.load_s=0;s.port=1
   with patch.object(s,'render',return_value=('prompt',[1,2],{})),patch.object(r.urllib.request,'urlopen',side_effect=TimeoutError('deadline')):
    p=Path(d)/'result.json';v=s.generate(self.case,'direct',p);self.assertIn('deadline',v['error']);self.assertTrue(p.exists());self.assertFalse(s.inflight)
 def test_checkpoint_recovery_does_not_repeat_completed_trial(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'result.json';r.save(p,{'complete':True})
   self.assertEqual(r.pipeline(None,self.case,'direct',p),{'complete':True})
 def test_one_model_guard(self):
  with patch.object(r.Server,'active',object()):
   with self.assertRaises(RuntimeError):r.Server(None,None,None,None)
 def test_one_request_guard(self):
  s=object.__new__(r.Server);s.inflight=True
  with self.assertRaises(RuntimeError):s.generate(self.case,'direct',Path('/not-written'))
 def test_reduction_keeps_original_ledger(self):self.assertIn('SOURCE LEDGER',r.messages(self.case,'reduce',{})[-1]['content'])
 def test_no_download_code_or_external_network_path(self):
  source=Path(r.__file__).read_text();self.assertNotIn('huggingface.co/',source);self.assertIn('(deny network*)',r.POLICY)
 def test_compact_contract(self):
  self.output['positives'][0]['text']='word '*11
  self.assertIn('point compact contract',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_overview_contract(self):
  self.output['overview']='word '*25
  self.assertIn('overview compact contract',r.structural(json.dumps(self.output),self.case,'direct')[1])
 def test_cancellation_closes_only_owned_process(self):
  from unittest.mock import Mock
  s=object.__new__(r.Server);s.host=Mock();s.host.poll.return_value=None;s.sampler=Mock();s.samplefile=None;s.logfile=None;s.run=Path('/unused');s.a={'variant':'fixture'};s.dir=Path('/fixture')
  with patch.object(r.Server,'active',s),patch.object(r,'event'):
   s.close();s.host.terminate.assert_called_once();s.sampler.terminate.assert_called_once();self.assertIsNone(r.Server.active)
 def test_completed_stage_is_not_overwritten(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'stage.json';value={'variant':'fixture','case':'test','context':2048,'stage':'direct','output_limit':256,'raw_output':'{}','raw_sha256':r.hashlib.sha256(b'{}').hexdigest()};r.save(p,value)
   before=p.read_bytes();s=object.__new__(r.Server);s.a={'variant':'fixture'};s.ctx=2048
   with patch.object(r.urllib.request,'urlopen') as http:self.assertEqual(s.generate(self.case,'direct',p),value);http.assert_not_called()
   self.assertEqual(p.read_bytes(),before)
if __name__=='__main__':unittest.main()
