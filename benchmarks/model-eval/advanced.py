"""Additional offline resource, reasoning, failure, cancellation, and real SwiftUI checks."""
import collections,csv,hashlib,json,os,plistlib,shutil,signal,socket,statistics,subprocess,threading,time,urllib.request
from pathlib import Path
SOURCE_TEXT=Path(__file__).read_text()
SOURCE_SHA256=hashlib.sha256(SOURCE_TEXT.encode()).hexdigest()

def record_source(r,run,phase):
 path=run/'advanced-source'/f'{SOURCE_SHA256}.py';path.parent.mkdir(exist_ok=True)
 if not path.exists():path.write_text(SOURCE_TEXT)
 r.event(run,'advanced_source_used',phase=phase,sha256=SOURCE_SHA256,path=str(path.relative_to(run)))

def reasoning_answer(r,s,case,path,intermediate=None):
 if path.exists():return r.load(path)
 if s.inflight:raise RuntimeError('Concurrent reasoning request forbidden')
 s.inflight=True;begin=time.monotonic();events=[];text='';first=None;first_answer=None;stage='reduce' if intermediate is not None else 'direct'
 row={'variant':s.a['variant'],'case':case['name'],'partition':case['partition'],'context':s.ctx,'stage':stage,'output_limit':1024,'decoding_mode':'unconstrained reasoning supplement; no JSON grammar','started_monotonic_s':begin,'started_utc':r.stamp(),'load_s':s.load_s}
 try:
  prompt,tokens,preflight=s.render(case,stage,intermediate);row.update(prompt=prompt,prompt_tokens=len(tokens),prompt_token_ids=tokens,**preflight)
  if len(tokens)+1024>s.ctx:raise ValueError('context_overflow_rejected')
  body={'prompt':prompt,'n_predict':1024,'temperature':0,'seed':42,'top_k':1,'top_p':1,'min_p':0,'repeat_penalty':1,'cache_prompt':False,'stream':True}
  row['request']=body;start=time.monotonic();row['inference_start_monotonic_s']=start
  request=urllib.request.Request(f'http://127.0.0.1:{s.port}/completion',json.dumps(body).encode(),{'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=180) as response:
   for line in response:
    if time.monotonic()-start>180:raise TimeoutError('absolute reasoning deadline')
    if not line.startswith(b'data: '):continue
    raw=line[6:].strip()
    if raw==b'[DONE]':continue
    value=json.loads(raw);events.append({'arrival_s':time.monotonic()-start,'event':value});content=value.get('content','')
    if content:
     if first is None:first=time.monotonic()-start
     text+=content
     if first_answer is None and '</think>' in text and text.split('</think>',1)[1].strip():first_answer=time.monotonic()-start
  row.update(generation_request_s=time.monotonic()-start,first_generated_content_s=first,first_visible_answer_s=first_answer if '<think>' in text else first,timings=events[-1]['event'].get('timings') if events else None,stop=events[-1]['event'] if events else {})
 except Exception as error:row['error']=repr(error)
 finally:
  answer=text.split('</think>',1)[1].strip() if '</think>' in text else ('' if '<think>' in text else text.strip())
  if answer.startswith('```'):
   answer=answer.split('\n',1)[-1];answer=answer.rsplit('```',1)[0].strip()
  row.update(raw_output=text,answer_content=answer,raw_sha256=hashlib.sha256(text.encode()).hexdigest(),answer_sha256=hashlib.sha256(answer.encode()).hexdigest(),reasoning_observed='<think>' in text,stream_events=events,total_stage_s=time.monotonic()-begin,ended_monotonic_s=time.monotonic())
  row['parsed_output'],row['structural_errors']=r.structural(answer,case,stage)
  if row['parsed_output'] is not None:
   inp=path.with_suffix('.validation-input.json');out=path.with_suffix('.validation.json');r.save(inp,{'text':answer,'reviews':case['reviews'],'course':case['course']});result=r.command([r.WORK/'BYEEvalHost','--validate',inp,out]);row['display_validation']=r.load(out) if out.exists() else result
  r.save(path,row);s.inflight=False;s.first_inference=False
 return row

def reasoning_trials(r,run):
 record_source(r,run,'reasoning')
 variants=[a for a in r.artifacts() if a['id']=='lfm25-thinking']
 cases=r.load(run/'selected-cases.json')['cases']
 r.save(run/'reasoning-decision.json',{'basis':'LFM Thinking has no enable_thinking template switch. Baseline JSON grammar constrains its format; this separately labeled trial removes the grammar to observe natural reasoning. No claim that a parser flag disables model thinking.','variants':[a['variant'] for a in variants],'total_generation_limit':1024,'no_extra_context_substitution':True,'not_identical_budget_to_baseline':True})
 compatible={v['variant'] for v in r.load(run/'compatibility.json') if v['supported']}
 for a in variants:
  if a['variant'] not in compatible:continue
  for rnd in range(3):
   for ctx in [2048,4096]:
    jobs=[(c,m,run/'reasoning'/f'round{rnd+1}'/a['variant']/str(ctx)/m/(c['name']+'.json')) for c in cases for m in ['direct','extract']]
    if all(p.exists() for c,m,p in jobs):continue
    with r.server(run,a,ctx,r.session_label(run,f'reasoning-r{rnd+1}-{a["variant"]}-{ctx}')) as server:
     for c,mode,target in jobs:
      if target.exists():continue
      target.parent.mkdir(parents=True,exist_ok=True);begin=time.monotonic();intermediate=None;stages=[]
      if mode=='extract':
       extracted=server.generate(c,'extract',target.with_suffix('.extract.json'),512);stages.append(str(target.with_suffix('.extract.json').relative_to(run)))
       if extracted.get('error') or extracted['structural_errors']:
        r.save(target,{'variant':a['variant'],'case':c['name'],'partition':c['partition'],'context':ctx,'mode':mode,'output_limit':1024,'error':'extraction_failed','stages':stages});continue
       intermediate=extracted['parsed_output']
      final=reasoning_answer(r,server,c,target.with_suffix('.final.json'),intermediate);stages.append(str(target.with_suffix('.final.json').relative_to(run)))
      row={k:v for k,v in final.items() if k not in ('prompt','prompt_token_ids','request','stream_events')};row.update(mode=mode,stages=stages,total_pipeline_s=time.monotonic()-begin,evidence_sha256=r.digest(c['reviews']));r.save(target,row)
      if final.get('error') and not wait_idle(server)['idle']:raise RuntimeError('Reasoning timeout left active slot')
    print('Unconstrained reasoning supplement',a['variant'],rnd+1,ctx,flush=True)

def energy_trials(r,run):
 record_source(r,run,'energy')
 compatible={v['variant'] for v in r.load(run/'compatibility.json') if v['supported']}
 variants=[a for a in r.artifacts() if a['variant'] in compatible]
 cases=[c for c in r.load(run/'selected-cases.json')['cases'] if c['partition']=='synthetic'][:5]
 probe=r.command(['/usr/bin/powermetrics','-n','1','-i','100','--samplers','cpu_power,gpu_power'],timeout=10)
 r.save(run/'energy-instrumentation.json',{'probe':probe,'energy_joules_available':probe.get('exit_code')==0,'attribution':'system-wide instrumentation, not uniquely BYE; idle comparison required','cpu_time_is_not_energy':True})
 for rnd in range(3):
  for a in variants[rnd*4:]+variants[:rnd*4]:
   out=run/'energy'/f'round{rnd+1}'/a['variant'];target=out/'workload.json'
   if target.exists():continue
   out.mkdir(parents=True,exist_ok=True)
   with r.server(run,a,2048,r.session_label(run,f'energy-r{rnd+1}-{a["variant"]}')) as s:
    power=None;powerlog=None
    if probe.get('exit_code')==0:
     powerlog=(out/'powermetrics.log').open('w');power=subprocess.Popen(['/usr/bin/powermetrics','-i','1000','--samplers','cpu_power,gpu_power'],stdout=powerlog,stderr=powerlog)
    idle_start=time.monotonic();time.sleep(3);idle_end=time.monotonic()
    begin=time.monotonic();rows=[r.pipeline(s,c,'direct',out/(c['name']+'.json')) for c in cases];end=time.monotonic()
    if power:power.terminate();power.wait(timeout=5);powerlog.close()
    r.save(target,{'variant':a['variant'],'round':rnd+1,'case_names':[c['name'] for c in cases],'idle_start_s':idle_start,'idle_end_s':idle_end,'work_start_s':begin,'work_end_s':end,'workload_s':end-begin,'summary_attempts':len(rows),'failures':sum(bool(v.get('error')) for v in rows),'structural_failures':sum(bool(v.get('structural_errors')) for v in rows),'joules_per_attempt':None,'energy_note':'Unavailable unless integrated system power counters in saved log support calculation; CPU time is only activity. Costs are per attempt, not certified successful summaries.','resources':str((s.dir/'resources.csv').relative_to(run))})
   print('Fixed workload',rnd+1,a['variant'],flush=True)

def wait_idle(s,timeout=15):
 begin=time.monotonic();last=None
 while time.monotonic()-begin<timeout:
  try:
   last=__import__('run').rpc(s.port,'/slots',timeout=1)
   if isinstance(last,list) and not any(slot.get('is_processing') for slot in last):return {'idle':True,'seconds':time.monotonic()-begin,'slots':last}
  except Exception as e:last=repr(e)
  time.sleep(.05)
 return {'idle':False,'seconds':time.monotonic()-begin,'slots':last}

def cancellation(r,s,case,out,phase):
 prompt,tokens,preflight=s.render(case,'direct')
 body={'prompt':prompt,'n_predict':1024,'temperature':0,'seed':42,'cache_prompt':False,'stream':True}
 if len(tokens)+1024>s.ctx:
  # Failure test uses a documented smaller output reservation instead of input truncation.
  body['n_predict']=min(512,s.ctx-len(tokens))
 stream=[];log_path=s.dir/'server.log';log_offset=log_path.stat().st_size
 state={'phase_requested':phase,'prompt_tokens':len(tokens),'request':body,'started_s':time.monotonic()};opened=threading.Event();token=threading.Event();stop=threading.Event();holder={}
 def worker():
  try:
   req=urllib.request.Request(f'http://127.0.0.1:{s.port}/completion',json.dumps(body).encode(),{'Content-Type':'application/json'})
   with urllib.request.urlopen(req,timeout=180) as response:
    holder['response']=response;opened.set()
    for line in response:
     stream.append({'arrival_s':time.monotonic(),'line':line.decode('utf-8',errors='replace')})
     if line.startswith(b'data: '):
      try:
       if json.loads(line[6:]).get('content'):token.set()
      except (ValueError,AttributeError):pass
     if stop.is_set():break
  except Exception as e:state['stream_end']=repr(e)
  finally:state['worker_finished_s']=time.monotonic()
 thread=threading.Thread(target=worker,daemon=True);thread.start()
 opened.wait(20)
 if phase=='generation':token.wait(30)
 else:time.sleep(.02)
 state['first_content_observed_before_cancel']=token.is_set();begin=time.monotonic();stop.set()
 response=holder.get('response')
 if response:
  try:response.fp.raw._sock.shutdown(socket.SHUT_RDWR)
  except Exception as e:state['shutdown_error']=repr(e)
 thread.join(15);state.update(cancel_s=time.monotonic()-begin,worker_finished=not thread.is_alive(),runtime_idle=wait_idle(s),phase_proven='generation' if token.is_set() else 'response opened before observed first content; prompt phase not independently proven')
 state.update(cancel_requested_s=begin,recovery_observed_s=time.monotonic())
 with log_path.open('rb') as log:
  log.seek(log_offset);state['runtime_operation_log']=log.read().decode('utf-8',errors='replace')
 releases=__import__('re').findall(r'stop processing[^\n]*n_(?:past|tokens)\s*=\s*(\d+)',state['runtime_operation_log'])
 state['release_context_tokens']=int(releases[-1]) if releases else None
 if releases and not token.is_set() and 0<int(releases[-1])<len(tokens):state['phase_proven']='prompt evaluation inferred from nonzero partial-prompt release context; no internal phase timestamp'
 state['recovery_sample_window_start_s']=time.monotonic();time.sleep(1)
 state['recovery_sample_window_end_s']=time.monotonic()
 state['raw_stream']=stream
 r.save(out,state)
 if thread.is_alive() or not state['runtime_idle']['idle']:raise RuntimeError('Cancellation did not release runtime')

def stage_native_ui(r,run):
 if r.Server.active is not None:raise RuntimeError('Cannot compile while inference is active')
 core_identity={}
 for source in (r.ROOT/'Sources/ClasswiseCore').glob('*.swift'):
  frozen=run/'tool-source'/source.name
  core_identity[source.name]={'baseline_sha256':r.sha(frozen),'native_sha256':r.sha(source)}
 r.save(run/'native-validator-identity.json',core_identity)
 if any(v['baseline_sha256']!=v['native_sha256'] for v in core_identity.values()):raise RuntimeError('ClasswiseCore changed after baseline; native validator comparison would differ')
 root=r.WORK/'native-ui';root.mkdir(exist_ok=True)
 source_inputs=list((r.ROOT/'Sources').rglob('*.swift'))+[r.ROOT/'Package.swift',r.ROOT/'scripts/swift.sh']
 source_before={str(p.relative_to(r.ROOT)):r.sha(p) for p in source_inputs}
 result=r.command([r.ROOT/'scripts/swift.sh','build','-c','release','--scratch-path',root/'swift-build','-Xswiftc','-DBYE_MODEL_EVAL'],timeout=600)
 attempts=list(run.glob('native-ui-build-attempt*.json'))
 r.save(run/f'native-ui-build-attempt{len(attempts)+1}.json',result)
 r.save(run/'native-ui-build.json',result)
 if result.get('exit_code')!=0:raise RuntimeError('Native UI build failed')
 if source_before!={str(p.relative_to(r.ROOT)):r.sha(p) for p in source_inputs}:raise RuntimeError('Native source changed during compilation')
 snapshot=run/'native-build-source'/r.digest(source_before)
 for p in source_inputs:
  destination=snapshot/p.relative_to(r.ROOT);destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,destination)
 r.save(snapshot/'source-hashes.json',source_before)
 r.save(run/'native-build-source-hashes.json',{'source_hashes':source_before,'snapshot':str(snapshot.relative_to(run))})
 binaries=list((root/'swift-build').glob('*/release/Classwise'))
 if len(binaries)!=1:raise RuntimeError('Ambiguous native UI product')
 for name in ['sampler','BYEEvalHost']:shutil.copy2(r.WORK/name,root/name)
 source=run/'native-ui-source';source.mkdir(exist_ok=True)
 for path in (r.ROOT/'Sources/Classwise').glob('*.swift'):shutil.copy2(path,source/path.name)
 r.save(run/'native-ui-build-identity.json',{'utc':r.stamp(),'binary_sha256':r.sha(binaries[0]),'source_hashes':{p.name:r.sha(p) for p in source.glob('*.swift')},'original_staging_apps_unchanged':True})
 sizes=[]
 for a in r.artifacts():
  app=root/'apps'/(a['variant']+'.app');app.parent.mkdir(exist_ok=True)
  if not app.exists():
   result=r.command(['/bin/cp','-cR',r.WORK/'apps'/(a['variant']+'.app'),app],timeout=120)
   if result.get('exit_code')!=0:raise RuntimeError('APFS native app clone failed: '+str(result))
   shutil.copy2(binaries[0],app/'Contents/MacOS/ClasswiseMeasurement')
   if r.sha(app/'Contents/MacOS/ClasswiseMeasurement')!=r.sha(binaries[0]):raise ValueError('Native binary copy changed')
   info=r.load_plist(app/'Contents/Info.plist');info['CFBundleExecutable']='ClasswiseMeasurement';info['CFBundleName']='BYE Offline Model Measurement'
   with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(info,f)
   signed=r.command(['codesign','--force','--deep','--sign','-',app]);r.save(run/'staging'/(a['variant']+'-native-sign.json'),signed)
   if signed.get('exit_code')!=0:raise RuntimeError('Native app signing failed')
   r.save(run/'staging'/(a['variant']+'-native-identity.json'),{'unsigned_build_sha256':r.sha(binaries[0]),'signed_binary_sha256':r.sha(app/'Contents/MacOS/ClasswiseMeasurement'),'note':'Ad-hoc signing may change Mach-O signature bytes.'})
  if r.sha(app/'Contents/Resources/model.gguf')!=a['sha256']:raise ValueError('Native bundled weights changed')
  identity=r.load(run/'staging'/(a['variant']+'-native-identity.json'))
  if identity['unsigned_build_sha256']!=r.sha(binaries[0]) or identity['signed_binary_sha256']!=r.sha(app/'Contents/MacOS/ClasswiseMeasurement'):raise ValueError('Native binary identity changed')
  archive=root/'archives'/(a['variant']+'.zip');archive.parent.mkdir(exist_ok=True)
  if not archive.exists():
   result=r.command(['ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive],timeout=300)
   if result.get('exit_code')!=0:raise RuntimeError('Native archive failed')
  files=[p for p in app.rglob('*') if p.is_file() or p.is_symlink()]
  tree=[]
  for path in files:
   entry={'path':str(path.relative_to(app)),'logical_bytes':path.lstat().st_size}
   if path.is_symlink():entry['symlink_target']=os.readlink(path)
   else:entry['sha256']=a['sha256'] if path==app/'Contents/Resources/model.gguf' else r.sha(path)
   tree.append(entry)
  r.save(run/'staging'/(a['variant']+'-native-tree.json'),{'utc':r.stamp(),'files':tree,'model_sha_verified_immediately_before_inventory':True,'note':'Signed component bytes may differ from unsigned runtime/build source signatures.'})
  size=sum(p.lstat().st_size for p in files)
  sizes.append({'variant':a['variant'],'app':str(app),'installed_logical_bytes':size,'allocated_bytes':sum(p.lstat().st_blocks*512 for p in files),'sizing_definition':'Regular-file logical bytes plus symlink entry bytes; no duplicated symlink targets or filesystem metadata. Allocated blocks may share APFS extents.','archive_bytes':archive.stat().st_size,'archive_sha256':r.sha(archive),'below_mandatory_limit':size<1500000000,'same_bundle_hosts_ui_runtime_weights':True})
  r.save(run/'native-ui-sizes.json',sizes)
 return root

def native_trials(r,run):
 record_source(r,run,'native')
 original_work=r.WORK
 native_root=stage_native_ui(r,run)
 r.WORK=native_root
 compatible={v['variant'] for v in r.load(run/'compatibility.json') if v['supported']}
 cases=[c for c in r.load(run/'selected-cases.json')['cases'] if c['name'] in ['repeated_positives','mixed_sentiment']]
 for a in r.artifacts():
  if a['variant'] not in compatible:continue
  directory=run/'native'/a['variant']
  if (directory/'result.json').exists():continue
  try:_native_one(r,run,a,cases,directory)
  except Exception as e:
   directory.mkdir(parents=True,exist_ok=True)
   r.save(directory/'result.json',{'variant':a['variant'],'error':repr(e),'native_complete':False})
   r.event(run,'native_variant_failure',variant=a['variant'],error=repr(e))
  print('Native app and failure checks',a['variant'],flush=True)
 r.WORK=original_work

def _native_one(r,run,a,cases,directory):
 directory.mkdir(parents=True,exist_ok=True);start=time.monotonic();app=None;sampler=None
 r.save(directory/'environment-before.json',r.environment())
 try:
  with r.server(run,a,2048,r.session_label(run,'native-'+a['variant'])) as s:
   r.save(directory/'native-config.json',{'controller_prelaunch_monotonic_s':time.monotonic(),'bundled_stack_start_monotonic_s':s.started,'port':s.port,'identity':r.digest([a['sha256'],'b11559',r.sha(run/'prompt-freeze.json'),'direct',2048,'exact-course-independent-evidence-v1']),'instructions':r.INSTRUCTIONS,'context':2048,'cases':cases})
   argv=['/usr/bin/sandbox-exec','-p',r.POLICY,str(s.app/'Contents/MacOS/ClasswiseMeasurement'),'--model-eval-session',str(directory)]
   env={k:v for k,v in os.environ.items() if not k.startswith(('LLAMA_','DYLD_')) and not k.lower().endswith('proxy')};env.update(HF_HOME=str(directory/'empty-hf'),XDG_CACHE_HOME=str(directory/'empty-xdg'),LLAMA_CACHE=str(directory/'empty-llama'))
   with (directory/'app.log').open('w') as log,(directory/'app-resources.csv').open('w') as resources:
    app=subprocess.Popen(argv,stdout=log,stderr=log,env=env,start_new_session=True)
    sampler=subprocess.Popen([str(r.WORK/'sampler'),str(app.pid)],stdout=resources,stderr=subprocess.DEVNULL)
    deadline=time.monotonic()+240
    while app.poll() is None and not (directory/'native-complete.json').exists() and time.monotonic()<deadline:time.sleep(.1)
    completed=(directory/'native-complete.json').exists()
    initial_idle=wait_idle(s)
    r.save(directory/'post-ui-runtime-idle.json',initial_idle)
    if not initial_idle['idle']:raise RuntimeError('Native UI left an active inference request')
    cancellation(r,s,r.load(run/'selected-cases.json')['near']['2048'][0],directory/'cancel-prompt.json','prompt')
    cancellation(r,s,cases[0],directory/'cancel-generation.json','generation')
    overflow={**cases[0],'name':'overflow','reviews':cases[0]['reviews']*1000}
    row=s.generate(overflow,'direct',directory/'overflow.json')
    r.save(directory/'overflow-check.json',{'rejected':'context_overflow_rejected' in row.get('error',''),'error':row.get('error')})
    malformed=directory/'malformed.gguf';malformed.write_bytes(b'GGUFbad');tests=[]
    for path in [directory/'missing.gguf',malformed]:
     result=r.command(['/usr/bin/sandbox-exec','-p',r.POLICY,str(s.app/'Contents/MacOS/runtime/llama-cli'),'-m',str(path),'-p','test','-n','1','--offline'],timeout=30)
     tests.append({'path':str(path),'passed':result.get('exit_code') not in (None,0),'result':result})
    r.save(directory/'weight-failure-tests.json',tests)
    idle_start=time.monotonic();time.sleep(30);unload_start=time.monotonic()
    # Graceful unload while the real native UI stays alive, so recovery remains measurable.
    s.close();time.sleep(2)
    r.save(directory/'idle-unload.json',{'idle_start_s':idle_start,'unload_start_s':unload_start,'unload_end_s':time.monotonic(),'controller_policy_s':30,'helper_exited':s.host.poll() is not None,'production_provider_unloading_not_implemented':True})
    sampler.terminate();sampler.wait();sampler=None
    if app.poll() is None:app.terminate();app.wait(timeout=10)
   # Separate fresh process for helper-crash propagation; never overlaps the unloaded helper.
   with r.server(run,a,2048,r.session_label(run,'helper-crash-'+a['variant'])) as crash:
    failed_ui=directory/'helper-crash-ui';failed_ui.mkdir()
    r.save(failed_ui/'native-config.json',{'controller_prelaunch_monotonic_s':time.monotonic(),'port':crash.port,'identity':r.digest([a['sha256'],'helper-crash-fixture']),'instructions':r.INSTRUCTIONS,'context':2048,'cases':cases})
    failure_argv=['/usr/bin/sandbox-exec','-p',r.POLICY,str(crash.app/'Contents/MacOS/ClasswiseMeasurement'),'--model-eval-session',str(failed_ui)]
    with (failed_ui/'app.log').open('w') as log:
     failure_app=subprocess.Popen(failure_argv,stdout=log,stderr=log,env=env,start_new_session=True)
     try:
      deadline=time.monotonic()+15;events=failed_ui/'native-events.jsonl'
      while failure_app.poll() is None and time.monotonic()<deadline:
       if events.exists() and 'native_inference_started' in events.read_text():break
       time.sleep(.02)
      helper=crash.pids['runtime'];os.kill(helper,signal.SIGKILL);crash.host.wait(timeout=10)
      deadline=time.monotonic()+30
      while failure_app.poll() is None and not (failed_ui/'native-complete.json').exists() and time.monotonic()<deadline:time.sleep(.1)
      observed=[json.loads(line) for line in events.read_text().splitlines() if line.strip()] if events.exists() else []
      visible_errors=[v for v in observed if v['kind']=='summary_state_observed' and v.get('error')]
      r.save(directory/'helper-failure.json',{'helper_pid':helper,'signal':signal.SIGKILL,'host_exit':crash.host.returncode,'host_propagated_failure':crash.host.returncode!=0,'native_ui_observed_error':bool(visible_errors),'native_ui_error_events':visible_errors,'failure_ui_completed':(failed_ui/'native-complete.json').exists()})
     finally:
      if failure_app.poll() is None:failure_app.terminate()
      try:failure_app.wait(timeout=10)
      except subprocess.TimeoutExpired:os.killpg(failure_app.pid,signal.SIGKILL);failure_app.wait()
   r.save(directory/'environment-after.json',r.environment())
   r.save(directory/'result.json',{'variant':a['variant'],'native_complete':completed,'exit_code':app.returncode,'argv':argv,'started_s':start,'finished_s':time.monotonic(),'app_runtime_footprint_note':'App, host and helper samples separate; overlap is possible.'})
 finally:
  if sampler:sampler.terminate();sampler.wait()
  if app and app.poll() is None:
   app.terminate()
   try:app.wait(timeout=10)
   except subprocess.TimeoutExpired:os.killpg(app.pid,signal.SIGKILL);app.wait()

def verify_preservation(r,run):
 before=r.load(run/'preservation-before.json');after={};changed=[]
 for path,expected in before.items():
  p=Path(path);actual=r.sha(p) if p.exists() else None;after[path]=actual
  if actual!=expected:changed.append({'path':path,'before':expected,'after':actual})
 r.save(run/'preservation-after.json',after);r.save(run/'preservation-check.json',{'checked_utc':r.stamp(),'files':len(before),'unchanged':not changed,'changed':changed,'mutable_user_caches_not_read_or_written':True})
 if changed:raise RuntimeError('Immutable evidence changed; inspect preservation-check.json')
 r.save(run/'final-weight-integrity.json',[r.verify_artifact(a) for a in r.artifacts()])
 r.save(run/'retired-checkpoint-status.json',{'utc':r.stamp(),'paths':[{'path':str(r.ROOT/'.build/bye-benchmark'/(name+extension)),'exists':(r.ROOT/'.build/bye-benchmark'/(name+extension)).exists()} for name in ['lfm','qwen','smol'] for extension in ['.gguf','.app','.zip']],'no_deletions_performed_in_task2':True})

def summarize_resources(r,run):
 peaks=[]
 for path in (run/'sessions').glob('*/resources.csv'):
  with path.open() as f:rows=list(csv.DictReader(f))
  if not rows:continue
  peak={'session':path.parent.name,'sample_interval_ms':100,'sampled_rss_peak_bytes':max(int(v['rss_bytes']) for v in rows),'sampled_footprint_peak_bytes':max(int(v['physical_footprint_bytes']) for v in rows),'lifetime_footprint_peak_bytes':max(int(v['lifetime_peak_footprint_bytes']) for v in rows),'cpu_s':(int(rows[-1]['cpu_ns'])-int(rows[0]['cpu_ns']))/1e9,'sampled_seconds':float(rows[-1]['monotonic_s'])-float(rows[0]['monotonic_s'])}
  exitfile=path.parent/'pids.json.exit.json'
  if exitfile.exists():peak.update(r.load(exitfile))
  log=(path.parent/'server.log').read_text(errors='replace')
  peak['allocation_lines']=[x for x in log.splitlines() if __import__('re').search(r'buffer size|KV.*size|compute.*size|load time',x,__import__('re').I)]
  peaks.append(peak)
 r.save(run/'memory-and-cpu.json',peaks)
 return peaks
