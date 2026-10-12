import hashlib, json, struct, tempfile, unittest
from pathlib import Path
import prepare
from unittest.mock import patch
from types import SimpleNamespace

def fixture():
    def string(text):
        data=text.encode();return struct.pack('<Q',len(data))+data
    data=b'GGUF'+struct.pack('<IQQ',3,0,4)
    for key,item in [('general.architecture','llama'),('tokenizer.ggml.model','gpt2'),('tokenizer.chat_template','{{ messages }}')]:
        data+=string(key)+struct.pack('<I',8)+string(item)
    data+=string('general.file_type')+struct.pack('<II',4,15)
    return data+b'\0'*((-len(data))%32)

class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.base=Path(self.temp.name)
        self.recorder=prepare.Recorder(self.base/'logs');self.path=self.base/'model.gguf';self.data=fixture()
        self.spec={'bytes':len(self.data),'sha256':hashlib.sha256(self.data).hexdigest()}
    def tearDown(self):self.recorder.log.close();self.temp.cleanup()
    def fetch(self,url,path,recorder,resume=False):path.write_bytes(self.data)
    def test_success_and_metadata_without_inference(self):
        prepare.download(self.spec,'fixture',self.path,self.recorder,fetch=self.fetch)
        result=prepare.inspect_gguf(self.path)
        self.assertEqual(result['scalars']['general.architecture'],'llama')
        self.assertEqual(result['scalars']['tokenizer.chat_template'],'{{ messages }}')
        self.assertFalse(self.path.with_suffix('.gguf.part').exists())
    def test_interruption_preserves_partial_and_resumes(self):
        def interrupt(url,path,recorder,resume=False):path.write_bytes(self.data[:17]);raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):prepare.download(self.spec,'fixture',self.path,self.recorder,fetch=interrupt)
        self.assertFalse(self.path.exists())
        def resume(url,path,recorder,resume=False):
            self.assertTrue(resume);self.assertEqual(path.read_bytes(),self.data[:17])
            with path.open('ab') as f:f.write(self.data[17:])
        prepare.download(self.spec,'fixture',self.path,self.recorder,fetch=resume)
        self.assertEqual(self.path.read_bytes(),self.data)
    def test_hash_mismatch_not_promoted(self):
        wrong=dict(self.spec,sha256='0'*64)
        with self.assertRaisesRegex(ValueError,'SHA-256'):prepare.download(wrong,'fixture',self.path,self.recorder,fetch=self.fetch)
        self.assertFalse(self.path.exists());self.assertTrue(self.path.with_suffix('.gguf.part').exists())
    def test_truncated_file_and_header_rejected(self):
        self.path.write_bytes(self.data[:30])
        with self.assertRaisesRegex(ValueError,'Size mismatch'):prepare.integrity(self.path,self.spec)
        with self.assertRaisesRegex(ValueError,'Truncated|extent'):prepare.inspect_gguf(self.path)
    def test_existing_verified_file_never_fetched_again(self):
        self.path.write_bytes(self.data)
        def forbidden(*args,**kwargs):self.fail('Existing verified file must not be downloaded')
        prepare.download(self.spec,'fixture',self.path,self.recorder,fetch=forbidden)
        self.assertEqual(self.path.read_bytes(),self.data)
    def test_existing_wrong_file_is_preserved(self):
        self.path.write_bytes(b'keep this')
        with self.assertRaises(ValueError):prepare.download(self.spec,'fixture',self.path,self.recorder,fetch=self.fetch)
        self.assertEqual(self.path.read_bytes(),b'keep this')
    def test_retired_digest_rejected(self):
        self.path.write_bytes(self.data)
        with self.assertRaisesRegex(ValueError,'retired'):prepare.integrity(self.path,self.spec,[self.spec['sha256']])
    def test_manifest_is_exactly_the_authorized_set(self):
        manifest=json.loads(prepare.MANIFEST.read_text());files=[f for m in manifest['models'] for f in m['files']]
        self.assertEqual(len(manifest['models']),9);self.assertEqual(len(files),12)
        self.assertEqual(sum(f['bytes'] for f in files),11949057632)
    def test_curl_resumes_with_tls_verification_and_at_most_two_retries(self):
        partial=self.path.with_suffix('.gguf.part');partial.write_bytes(b'partial')
        failed=SimpleNamespace(returncode=28,stdout='{}',stderr='timeout')
        with patch.object(prepare.subprocess,'run',return_value=failed) as run,patch.object(prepare.time,'sleep'):
            with self.assertRaises(RuntimeError):prepare.curl('https://huggingface.co/fixture',partial,self.recorder,resume=True)
        self.assertEqual(run.call_count,3)
        argv=run.call_args.args[0]
        self.assertEqual(argv[:2],['/usr/bin/curl','-q'])
        self.assertEqual(argv[argv.index('--continue-at')+1],'-')
        self.assertNotIn('--insecure',argv);self.assertNotIn('-k',argv)
    def test_network_destinations_outside_model_and_license_hosts_are_refused(self):
        with patch.object(prepare.subprocess,'run') as run:
            with self.assertRaisesRegex(ValueError,'allowlist'):prepare.curl('https://www.ratemyprofessors.com/graphql',self.path,self.recorder)
            with self.assertRaisesRegex(ValueError,'allowlist'):prepare.curl('https://prod-apiweb.pasadena.edu/api/getClassScheduleTerms',self.path,self.recorder)
            run.assert_not_called()

if __name__=='__main__':unittest.main()
