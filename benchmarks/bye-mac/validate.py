#!/usr/bin/env python3
"""Destructive fixtures are isolated; benchmark models and releases are untouched."""
import json
import argparse
import os
import subprocess
import threading
import time
import urllib.request
from pathlib import Path
import benchmark as b

OUT=b.ROOT/'docs/verification/bye-local-validation-2026-10-11'


def main():
    if OUT.exists(): raise ValueError('Refusing to overwrite validation results')
    OUT.mkdir(parents=True)
    results=[]
    runtime=b.WORK/('llama-'+b.MANIFEST['runtime']['tag'])
    invalid=b.WORK/'invalid.gguf'; invalid.write_bytes(b'GGUF'+b'\0'*64)
    for key in ['lfm','qwen','smol']:
        app=b.WORK/(key+'.app'); tool=app/'Contents/MacOS/runtime/llama-completion'
        prompt=json.loads((b.ROOT/'docs/verification/bye-local-2026-10-11'/f'round1-{key}-2048/repeated_positives.json').read_text())['prompt']
        prompt_file=OUT/(key+'-prompt.txt'); prompt_file.write_text(prompt)
        empty=b.WORK/('empty-home-'+key); empty.mkdir(exist_ok=True)
        env={**os.environ,'HOME':str(empty),'XDG_CACHE_HOME':str(empty/'cache'),'HF_HOME':str(empty/'hf')}
        env={k:v for k,v in env.items() if not k.startswith(('LLAMA_','DYLD_'))}
        # Enforce offline inference at the OS boundary, rather than relying on runtime flags alone.
        args=['/usr/bin/sandbox-exec','-p','(version 1) (allow default) (deny network*)',str(tool),
              '-m',str(app/'Contents/Resources/model.gguf'),'-f',str(prompt_file),'-n','64','-c','2048',
              '-t','4','-ngl','99','--temp','0','--offline','--no-display-prompt','-lv','4']
        start=time.perf_counter()
        p=subprocess.run(args,capture_output=True,env=env,timeout=120)
        (OUT/(key+'-offline.stdout')).write_bytes(p.stdout)
        (OUT/(key+'-offline.stderr')).write_bytes(p.stderr)
        b.save(OUT/(key+'-offline.json'),dict(command=args,status=p.returncode,stdout=p.stdout.decode('utf-8','replace'),stderr=p.stderr.decode('utf-8','replace'),seconds=time.perf_counter()-start))
        results.append(dict(model=key,test='offline_empty_cache_network_denied',passed=p.returncode==0 and bool(p.stdout.strip())))
        for name,path in [('missing',b.WORK/'does-not-exist.gguf'),('corrupt',invalid)]:
            p=subprocess.run([str(tool),'-m',str(path),'-p','test','-n','1','--offline','-lv','4'],capture_output=True,text=True,errors='replace',timeout=30)
            b.save(OUT/(key+'-'+name+'.json'),dict(status=p.returncode,stdout=p.stdout,stderr=p.stderr))
            results.append(dict(model=key,test=name+'_weights',passed=p.returncode!=0))
        server=b.Server(key,2048,OUT/('cancel-'+key))
        try:
            prompt,count=server.prompt(dict(course='ETH 014',reviews=[dict(id='a',course='ETH 014',text='The explanations were clear. '*30)]))
            started=threading.Event(); cancel=threading.Event(); state={}
            def stream():
                req=urllib.request.Request(f'http://127.0.0.1:{server.port}/completion',json.dumps(dict(prompt=prompt,n_predict=1000,ignore_eos=True,temperature=0,cache_prompt=False,stream=True)).encode(),{'Content-Type':'application/json'})
                try:
                    with urllib.request.urlopen(req,timeout=60) as response:
                        for line in response:
                            if line.startswith(b'data: '): started.set()
                            if cancel.is_set(): break
                except Exception as error: state['stream_error']=repr(error)
            worker=threading.Thread(target=stream); worker.start()
            active=started.wait(15); start=time.perf_counter()
            # Close the active streaming client before stopping the HTTP helper.
            # Its shutdown otherwise waits on an outstanding streaming request.
            cancel.set(); worker.join(15); server.close()
            state.update(first_event_received=active,cancel_seconds=time.perf_counter()-start,
                         host_exited=server.host.poll() is not None,worker_finished=not worker.is_alive(),
                         discarded_partial_output=True)
            try: os.kill(server.pids['runtime'],0); state['runtime_exited']=False
            except ProcessLookupError: state['runtime_exited']=True
            b.save(OUT/(key+'-cancellation.json'),state)
            results.append(dict(model=key,test='terminate_active_inference',passed=active and state['host_exited'] and state['runtime_exited'] and state['worker_finished']))
        finally: server.close()
    invalid.unlink()
    b.save(OUT/'results.json',results)
    print(json.dumps(results,indent=2))
    if not all(r['passed'] for r in results): raise SystemExit(1)


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,default=OUT)
    OUT=parser.parse_args().output.resolve(); main()
