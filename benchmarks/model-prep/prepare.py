#!/usr/bin/env python3
"""Download a pinned BYE candidate set; never loads models or accesses PCC/RMP."""
import argparse, csv, datetime, hashlib, json, os, re, shutil, struct, subprocess, time
from pathlib import Path
from urllib.parse import quote, urlparse

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
WEIGHTS=ROOT/'.build/bye-candidates-2026-10-11'
LOGS=ROOT/'.local-docs/model-prep-2026-10-11'
MANIFEST=HERE/'manifest.json'
FORMATS={0:'B',1:'b',2:'H',3:'h',4:'I',5:'i',6:'f',7:'?',10:'Q',11:'q',12:'d'}

def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(path,value):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(4*1024*1024),b''):h.update(block)
    return h.hexdigest()
def exact(f,n):
    data=f.read(n)
    if len(data)!=n:raise ValueError('Truncated GGUF metadata')
    return data
def number(f,fmt):return struct.unpack('<'+fmt,exact(f,struct.calcsize('<'+fmt)))[0]
def string(f,keep=True):
    n=number(f,'Q')
    if n>128*1024*1024 or f.tell()+n>os.fstat(f.fileno()).st_size:raise ValueError('Invalid GGUF string extent')
    if keep:return exact(f,n).decode('utf-8')
    f.seek(n,1)
def value(f,kind,keep=True,depth=0):
    if depth>3:raise ValueError('Excessively nested metadata')
    if kind in FORMATS:return number(f,FORMATS[kind])
    if kind==8:return string(f,keep)
    if kind!=9:raise ValueError('Unknown GGUF value type '+str(kind))
    element=number(f,'I');count=number(f,'Q')
    if count>50000000:raise ValueError('Invalid GGUF array count')
    if element in FORMATS:
        extent=struct.calcsize('<'+FORMATS[element])*count
        if f.tell()+extent>os.fstat(f.fileno()).st_size:raise ValueError('Truncated GGUF array')
        f.seek(extent,1)
    else:
        for _ in range(count):value(f,element,False,depth+1)
    return {'element_type':element,'count':count}
def inspect_gguf(path):
    with path.open('rb') as f:
        if exact(f,4)!=b'GGUF':raise ValueError('Not a GGUF file')
        version=number(f,'I')
        if version not in [2,3]:raise ValueError('Unsupported GGUF version')
        tensors=number(f,'Q');count=number(f,'Q')
        if count>100000 or tensors>100000:raise ValueError('Unreasonable GGUF header counts')
        metadata={};arrays={}
        for _ in range(count):
            key=string(f);kind=number(f,'I')
            if key in metadata or key in arrays:raise ValueError('Duplicate GGUF metadata key')
            item=value(f,kind)
            (arrays if kind==9 else metadata)[key]=item
        for _ in range(tensors):
            string(f,False);dimensions=number(f,'I')
            if not 1<=dimensions<=4:raise ValueError('Invalid tensor dimensions')
            for _ in range(dimensions):number(f,'Q')
            number(f,'I');number(f,'Q')
        alignment=metadata.get('general.alignment',32)
        if not isinstance(alignment,int) or alignment<1 or alignment>65536:raise ValueError('Invalid alignment')
        data_offset=(f.tell()+alignment-1)//alignment*alignment
        if data_offset>path.stat().st_size:raise ValueError('Truncated tensor directory')
    for key in ['general.architecture','general.file_type','tokenizer.ggml.model']:
        if key not in metadata:raise ValueError('Missing required metadata: '+key)
    return {'gguf_version':version,'tensor_count':tensors,'tensor_data_offset':data_offset,
            'scalars':metadata,'arrays':arrays,'scope':'Header/metadata inspection only; tensor contents and runtime compatibility are not certified.'}

def integrity(path,spec,retired=()):
    if path.is_symlink():raise ValueError('Refusing symlink: '+str(path))
    if path.stat().st_size!=spec['bytes']:raise ValueError('Size mismatch')
    digest=sha(path)
    if digest!=spec['sha256']:raise ValueError('SHA-256 mismatch')
    if digest in retired:raise ValueError('Matches a retired checkpoint')
    return digest

class Recorder:
    def __init__(self,directory):
        self.directory=directory;directory.mkdir(parents=True,exist_ok=True)
        self.log=(directory/'events.jsonl').open('a')
    def event(self,event,**fields):
        self.log.write(json.dumps(dict(utc=now(),event=event,**fields),ensure_ascii=False)+'\n');self.log.flush()

def curl(url,destination,recorder,resume=False,attempts=3):
    host=urlparse(url).hostname
    if urlparse(url).scheme!='https' or host not in ['huggingface.co','www.apache.org','ai.google.dev','www.llama.com']:
        raise ValueError('Destination outside preparation allowlist')
    destination.parent.mkdir(parents=True,exist_ok=True)
    for attempt in range(attempts):
        args=['/usr/bin/curl','-q','--fail','--location','--silent','--show-error','--proto','=https','--proto-redir','=https',
              '--connect-timeout','20','--max-time','1800' if resume else '60','--speed-limit','1024','--speed-time','90',
              '--output',str(destination),'--write-out','%{json}']
        if resume and destination.exists() and destination.stat().st_size:args+=['--continue-at','-']
        args.append(url);start=time.monotonic()
        recorder.event('transfer_start',argv=args,attempt=attempt+1,bytes_before=destination.stat().st_size if destination.exists() else 0)
        result=subprocess.run(args,text=True,capture_output=True)
        recorder.event('transfer_end',url=url,attempt=attempt+1,exit_code=result.returncode,seconds=time.monotonic()-start,
                       bytes_after=destination.stat().st_size if destination.exists() else 0,stderr=result.stderr,curl_metrics=result.stdout)
        if result.returncode==0:return
        # Permanent failures do not benefit from retries. Preserve all partial files.
        if result.returncode in [22,33,60] or attempt==attempts-1:raise RuntimeError('curl failed '+str(result.returncode)+': '+result.stderr.strip())
        time.sleep(min(2,attempt+1))
    raise RuntimeError('Transfer failed')

def download(spec,url,destination,recorder,retired=(),fetch=curl):
    if destination.exists() or destination.is_symlink():
        digest=integrity(destination,spec,retired)
        recorder.event('existing_verified_file_reused',path=str(destination),sha256=digest)
        return digest
    partial=destination.with_suffix(destination.suffix+'.part')
    if partial.is_symlink():raise ValueError('Refusing partial symlink')
    if not partial.exists() or partial.stat().st_size!=spec['bytes']:
        if partial.exists() and partial.stat().st_size>spec['bytes']:raise ValueError('Oversized partial file; retained for inspection')
        fetch(url,partial,recorder,resume=True)
    digest=integrity(partial,spec,retired)
    if destination.exists():raise RuntimeError('Destination appeared during download; refusing overwrite')
    # Link promotion fails if another writer creates the final file. Both paths are on one volume.
    os.link(partial,destination);partial.unlink()
    recorder.event('download_verified',path=str(destination),bytes=spec['bytes'],sha256=digest)
    return digest

def retained_inventory():
    roots=[ROOT/'benchmarks/bye-mac',ROOT/'docs/verification',ROOT/'dist',ROOT/'.build/bye-benchmark/llama-b11559',
           ROOT/'.local-docs/app-audit-2026-10-11',ROOT/'.local-docs/rmp-benchmark-2026-10-11']
    roots += [Path.home()/f'Library/Application Support/{name}/Reports' for name in ['Classwise','BYEAppleAIBeta']]
    return {str(p):{'bytes':p.stat().st_size,'sha256':sha(p)} for base in roots if base.exists() for p in sorted(base.rglob('*')) if p.is_file() and '__pycache__' not in p.parts}

def fetch_documents(model,recorder):
    folder=recorder.directory/'documents'/model['id'];notes=[];license_files=[]
    for role,repo,revision in [('publisher',model['repository'],model['revision']),('upstream',model['upstream'],model['upstream_metadata_revision'])]:
        api=folder/(role+'-metadata.json')
        try:
            curl('https://huggingface.co/api/models/'+repo+'/revision/'+revision+'?blobs=true',api,recorder)
            data=json.loads(api.read_text())
            if data['sha']!=revision:raise ValueError('Metadata revision differs from manifest')
            wanted=['README.md','LICENSE','LICENSE.txt','NOTICE','NOTICE.txt','USE_POLICY.md','config.json','tokenizer_config.json','chat_template.jinja','generation_config.json']
            available={f['rfilename'] for f in data['siblings']}
            for filename in wanted:
                if filename not in available:continue
                dest=folder/role/filename
                try:
                    curl('https://huggingface.co/'+repo+'/resolve/'+revision+'/'+quote(filename),dest,recorder)
                    if filename.startswith('LICENSE'):license_files.append(str(dest))
                except Exception as e:notes.append(role+'/'+filename+': '+str(e))
            notes.append(role+' available license/notice files: '+', '.join(sorted(f for f in available if 'LICENSE' in f or 'NOTICE' in f)))
        except Exception as e:notes.append(role+' metadata: '+str(e))
    sources=[]
    if model['license']=='Apache-2.0':sources=[('Apache-2.0.txt','https://www.apache.org/licenses/LICENSE-2.0.txt')]
    if model['license']=='Gemma-Terms':sources=[('Gemma-Terms.html','https://ai.google.dev/gemma/terms'),('Gemma-Prohibited-Use.html','https://ai.google.dev/gemma/prohibited_use_policy')]
    if model['license']=='Llama-3.2-Community':sources=[('Llama-License.txt','https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/raw/'+model['upstream_metadata_revision']+'/LICENSE.txt'),('Llama-Use-Policy.md','https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/raw/'+model['upstream_metadata_revision']+'/USE_POLICY.md')]
    for name,url in sources:
        dest=folder/name
        try:curl(url,dest,recorder);license_files.append(str(dest))
        except Exception as e:notes.append(name+': '+str(e))
    documents={str(p.relative_to(folder)):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in folder.rglob('*') if p.is_file()}
    result={'license':model['license'],'obligations':model['redistribution_obligations'],'documents':documents,'notes':notes,
            'license_material_saved':bool(license_files),'production_release_eligibility':'Not certified by download or metadata inspection.'}
    save(folder/'index.json',result);return result

def reports(run,rows,document_status):
    save(run/'inventory.json',rows)
    with (run/'inventory.csv').open('w',newline='') as f:
        fields=['model','filename','path','status','bytes','sha256','publisher_repository','publisher_revision','upstream','upstream_metadata_revision','conversion_source_revision','architecture','file_type','tokenizer','context_limits','template_sha256','license','obligations','unresolved']
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
    lines=['# BYE candidate download inventory — October 11, 2026','','This preparation workflow performed no model inference, loading, or benchmark and made no PCC/RMP requests.','',
           '| Model / file | Status | Bytes | Architecture | License |','|---|---|---:|---|---|']
    lines += [f"| {r['model']} / {r['filename']} | {r['status']} | {r['bytes']:,} | {r['architecture']} | {r['license']} |" for r in rows]
    lines += ['',f"Verified weights: {sum(r['status']=='verified' for r in rows)}/{len(rows)}; total expected weight bytes: {sum(r['bytes'] for r in rows):,}.",'',
              'Every artifact has a pinned publisher revision and SHA-256. Upstream metadata revision is recorded separately from the unknown/unverified conversion-source revision. Embedded templates are preserved verbatim beside each GGUF metadata JSON.',
              '', '## License obligations and unresolved issues','']
    for mid,doc in document_status.items():lines += ['- '+mid+': '+doc['obligations']+' Saved license material: '+str(doc['license_material_saved'])+'. Notes: '+'; '.join(doc['notes'])]
    for r in rows:
        if r['unresolved']:lines += ['- '+r['filename']+': '+r['unresolved']]
    lines += ['', 'Missing/gated documents are not a waiver of license obligations. Publication eligibility remains unconfirmed. Runtime compatibility, actual staged-app size, summary quality, speed, memory and energy remain pending task 2. Installed app bytes must stay strictly below 1,500,000,000; weights alone do not prove fit. No production integration or publishing was performed.']
    (run/'REPORT.md').write_text('\n'.join(lines)+'\n')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--documents-only',action='store_true');args=parser.parse_args()
    manifest=json.loads(MANIFEST.read_text());models=manifest['models']
    if len(models)!=9 or sum(len(m['files']) for m in models)!=12:raise ValueError('Unexpected candidate set')
    retired_manifest=json.loads((ROOT/'benchmarks/bye-mac/manifest.json').read_text());retired={m['sha256'] for m in retired_manifest['models']}
    for m in models:
        for rev in [m['revision'],m['upstream_metadata_revision']]:
            if not re.fullmatch('[a-f0-9]{40}',rev):raise ValueError('Unpinned revision')
        for f in m['files']:
            if Path(f['filename']).name!=f['filename'] or f['sha256'] in retired:raise ValueError('Unsafe/retired candidate')
    WEIGHTS.mkdir(parents=True,exist_ok=True);LOGS.mkdir(parents=True,exist_ok=True)
    lock=WEIGHTS/'.preparation.lock'
    try:fd=os.open(lock,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError:raise RuntimeError('Preparation lock exists; inspect recorded PID before recovery')
    os.write(fd,str(os.getpid()).encode());os.close(fd)
    run=LOGS/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ');recorder=Recorder(run)
    try:
        shutil.copy2(MANIFEST,run/'manifest.json')
        needed=sum(f['bytes'] for m in models for f in m['files'] if not (WEIGHTS/m['id']/f['filename']).exists())+2*1024**3
        if shutil.disk_usage(WEIGHTS).free<needed:raise RuntimeError('Insufficient free space for weights plus 2 GiB headroom')
        before=retained_inventory();save(run/'retained-before.json',before)
        recorder.event('preparation_start',weights=str(WEIGHTS),manifest_sha256=sha(MANIFEST),runtime=retired_manifest['runtime'],inference=False)
        rows=[];docs={}
        for model in models:
            print('Preparing '+model['name'],flush=True)
            docs[model['id']]=fetch_documents(model,recorder)
            if args.documents_only:continue
            for spec in model['files']:
                path=WEIGHTS/model['id']/spec['filename']
                row=dict(model=model['name'],filename=spec['filename'],path=str(path),status='failed',bytes=spec['bytes'],sha256=spec['sha256'],
                         publisher_repository=model['repository'],publisher_revision=model['revision'],upstream=model['upstream'],upstream_metadata_revision=model['upstream_metadata_revision'],
                         conversion_source_revision=model['conversion_source_revision'],architecture='',file_type='',tokenizer='',context_limits='',template_sha256='',license=model['license'],obligations=model['redistribution_obligations'],unresolved='')
                print('Downloading '+spec['filename'],flush=True)
                try:
                    url='https://huggingface.co/'+model['repository']+'/resolve/'+model['revision']+'/'+quote(spec['filename'])
                    download(spec,url,path,recorder,retired)
                    meta=inspect_gguf(path);save(run/'gguf-metadata'/(spec['filename']+'.json'),meta)
                    scalar=meta['scalars'];templates={k:v for k,v in scalar.items() if k.startswith('tokenizer.chat_template') and isinstance(v,str)}
                    if not templates:row['unresolved']='No embedded chat template; task 2 must establish correct prompting.'
                    hashes={}
                    for key,template in templates.items():
                        out=run/'chat-templates'/(spec['filename']+'.'+key+'.jinja');out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(template.encode('utf-8'));hashes[key]=sha(out)
                    row.update(status='verified',architecture=scalar['general.architecture'],file_type=scalar['general.file_type'],tokenizer=scalar['tokenizer.ggml.model'],
                               context_limits=json.dumps({k:v for k,v in scalar.items() if k.endswith('context_length')}),template_sha256=json.dumps(hashes))
                except Exception as e:row['unresolved']=str(e);recorder.event('artifact_failure',filename=spec['filename'],error=str(e))
                rows.append(row);reports(run,rows,docs)
                print(spec['filename']+': '+row['status']+(' — '+row['unresolved'] if row['unresolved'] else ''),flush=True)
        changes=[name for name,meta in before.items() if not Path(name).is_file() or Path(name).stat().st_size!=meta['bytes'] or sha(Path(name))!=meta['sha256']]
        absent=all(not (ROOT/'.build/bye-benchmark'/f'{model}.{ext}').exists() for model in ['lfm','qwen','smol'] for ext in ['gguf','app','zip'])
        save(run/'preservation.json',{'checked_utc':now(),'original_files':len(before),'changed_paths':changes,'retired_paths_absent':absent})
        reports(run,rows,docs)
        recorder.event('preparation_complete',verified=sum(r['status']=='verified' for r in rows),expected=12,retained_changes=changes,retired_paths_absent=absent)
        save(LOGS/'latest.json',{'directory':str(run),'finished_utc':now()})
        print('Report: '+str(run/'REPORT.md'),flush=True)
        return 0 if not changes and absent and (args.documents_only or len(rows)==12 and all(r['status']=='verified' for r in rows)) else 1
    finally:
        recorder.log.close();lock.unlink(missing_ok=True)

if __name__=='__main__':raise SystemExit(main())
