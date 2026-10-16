"""Download publisher weights and pinned GGUF artifacts; never reads review data."""
import argparse
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote
from common import BASE, WORK, MODELS, save, load, sha

USE_XET=False
USE_RANGES=False

def ranged_transfer(url,path,total):
    """Resume a preserved prefix; verify each bounded byte range before assembly."""
    offset=path.stat().st_size if path.exists() else 0
    if offset>total:raise ValueError('Partial exceeds publisher size')
    pieces=path.parent/(path.name+'.ranges');pieces.mkdir(parents=True,exist_ok=True)
    ranges=[(start,min(start+64*1024*1024,total)-1) for start in range(offset,total,64*1024*1024)]
    def piece(bounds):
        start,end=bounds;target=pieces/f'{start}-{end}'
        if target.exists() and target.stat().st_size==end-start+1:return target
        result=subprocess.run(['/usr/bin/curl','-q','--fail','--location','--silent','--show-error',
            '--proto','=https','--proto-redir','=https','--connect-timeout','20','--max-time','240',
            '--speed-limit','65536','--speed-time','30','--retry','2','--retry-all-errors',
            '--range',f'{start}-{end}',url,'-o',str(target)],capture_output=True,text=True)
        if result.returncode or target.stat().st_size!=end-start+1:raise RuntimeError('Range failed: '+result.stderr)
        print('verified range length',start,end,flush=True)
        return target
    with ThreadPoolExecutor(max_workers=4) as pool:
        files=list(pool.map(piece,ranges))
    with path.open('ab') as output:
        for item in files:
            with item.open('rb') as stream:
                import shutil
                shutil.copyfileobj(stream,output)
    if path.stat().st_size!=total:raise ValueError('Range assembly size mismatch')

def transfer(url, path):
    if not url.startswith('https://huggingface.co/'):
        raise ValueError('Only Hugging Face preparation URLs allowed')
    path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(['/usr/bin/curl', '-q', '--fail', '--location', '--silent', '--show-error',
        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '20', '--max-time', '2400',
        '--speed-limit', '65536', '--speed-time', '30',
        '--retry', '2', '--retry-all-errors', '--retry-delay', '2', '--continue-at', '-', url, '-o', str(path)], capture_output=True, text=True)
    save(path.with_suffix(path.suffix+'.transfer.json'),dict(url=url,returncode=result.returncode,stderr=result.stderr,
        bytes=path.stat().st_size if path.exists() else 0))
    if result.returncode:
        raise RuntimeError(result.stderr)

def metadata(repo, folder):
    path = folder / 'metadata.json'
    if not path.exists():
        transfer('https://huggingface.co/api/models/' + repo + '?blobs=true', path)
    return load(path)

def fetch_file(repo, revision, item, folder):
    name = item['rfilename']; dest = folder / name
    if not dest.exists():
        if USE_XET and item['size']>100_000_000:
            os.environ['HF_XET_HIGH_PERFORMANCE']='1'
            from huggingface_hub import hf_hub_download
            hf_hub_download(repo_id=repo,revision=revision,filename=name,local_dir=folder)
        else:
            partial = dest.with_suffix(dest.suffix + '.part')
            url='https://huggingface.co/' + repo + '/resolve/' + revision + '/' + quote(name)
            if USE_RANGES and item['size']>100_000_000:ranged_transfer(url,partial,item['size'])
            else:transfer(url, partial)
            partial.replace(dest)
    digest = sha(dest)
    expected = item.get('lfs', {}).get('sha256')
    if dest.stat().st_size != item['size'] or (expected and digest != expected):
        raise ValueError('Artifact integrity failed: ' + name)
    return dict(filename=name, bytes=dest.stat().st_size, sha256=digest, publisher_sha256=expected)

def main():
    global USE_XET,USE_RANGES
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['metadata','download']);parser.add_argument('--model',choices=MODELS);parser.add_argument('--xet',action='store_true');parser.add_argument('--ranges',action='store_true')
    args=parser.parse_args()
    USE_XET=args.xet
    USE_RANGES=args.ranges
    for model, (native_repo, gguf_repo) in MODELS.items():
        if args.model and model != args.model: continue
        specs = {}
        for kind, repo in [('native',native_repo),('gguf',gguf_repo)]:
            folder=BASE/'documents'/model/kind
            data=metadata(repo,folder)
            files=data['siblings']
            docs=[f for f in files if f['rfilename'] in ['README.md','LICENSE','LICENSE.txt','NOTICE','NOTICE.txt','config.json','generation_config.json','tokenizer_config.json']]
            inventory=[fetch_file(repo,data['sha'],f,folder) for f in docs]
            if kind=='native':
                artifacts=[f for f in files if f['rfilename'].endswith('.safetensors') or f['rfilename'] in ['model.safetensors.index.json','config.json','generation_config.json','tokenizer.json','tokenizer_config.json','special_tokens_map.json','vocab.json','merges.txt','chat_template.jinja','preprocessor_config.json','processor_config.json']]
            else:
                artifacts=[f for f in files if f['rfilename'].lower().endswith('q8_0.gguf') and 'mmproj' not in f['rfilename'].lower()]
                if len(artifacts)!=1:raise ValueError('Expected exactly one Q8_0: '+str([f['rfilename'] for f in artifacts]))
            specs[kind]=dict(repository=repo,revision=data['sha'],license=data.get('cardData',{}).get('license'),
                artifacts=artifacts,artifact_bytes=sum(f['size'] for f in artifacts),documents=inventory)
            if args.action=='download':
                target=WORK/'models'/model/kind
                specs[kind]['verified']=[fetch_file(repo,data['sha'],f,target) for f in artifacts]
            print(model,kind,data['sha'],specs[kind]['artifact_bytes'],flush=True)
        save(BASE/'artifacts'/(model+'.json'),specs)

if __name__=='__main__':main()
