#!/usr/bin/env python3
"""Read-only background workload observations. Never launches/stops another app."""
import argparse,json,os,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--run',type=Path,required=True);p.add_argument('--controller-pid',type=int);args=p.parse_args();run=args.run
if args.controller_pid:controller=args.controller_pid
else:
 sessions=sorted((run/'sessions').glob('*/pids.json'),key=lambda p:p.stat().st_mtime)
 host=json.loads(sessions[-1].read_text())['host']
 parent=subprocess.run(['ps','-o','ppid=','-p',str(host)],capture_output=True,text=True,check=True)
 controller=int(parent.stdout.strip())
(run/'observer-identity.json').write_text(json.dumps({'observer_pid':os.getpid(),'controller_pid':controller,'interval_s':5,'cpu_percent_is_os_recent_activity_estimate':True,'external_app_presence_does_not_prove_inference':True},indent=2))
with (run/'background-processes.jsonl').open('a') as f:
 while True:
  try:os.kill(controller,0)
  except ProcessLookupError:break
  observed=subprocess.run(['ps','-Ao','pid,ppid,pcpu,rss,comm'],text=True,capture_output=True)
  own={controller,os.getpid()};rows=[]
  for line in observed.stdout.splitlines()[1:]:
   parts=line.strip().split(None,4)
   if len(parts)==5:
    try:rows.append({'pid':int(parts[0]),'ppid':int(parts[1]),'cpu_percent':float(parts[2]),'rss_kib':int(parts[3]),'command':parts[4]})
    except ValueError:pass
  for _ in range(8):own.update(v['pid'] for v in rows if v['ppid'] in own)
  candidates=[v for v in rows if v['pid'] not in own and any(s in v['command'].lower() for s in ('llama','ollama','mlx','lm studio','classwise','foundationmodel'))]
  f.write(json.dumps({'monotonic_s':time.monotonic(),'controller_pid':controller,'owned_pids':sorted(own),'external_inference_candidates':candidates,'ps_exit':observed.returncode,'other_cpu_busy':[v for v in rows if v['pid'] not in own and v['cpu_percent']>=25]})+'\n');f.flush()
  time.sleep(5)
