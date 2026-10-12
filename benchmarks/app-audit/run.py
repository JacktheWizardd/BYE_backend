#!/usr/bin/env python3
"""Build/stage separately, run bounded live audit once, replay offline under OS network denial."""
import argparse, datetime, hashlib, json, os, plistlib, shutil, signal, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.local-docs/app-audit-2026-10-11'
BUILD=ROOT/'.build/app-audit'
APP=BUILD/'BYE Measurement.app'

def save(path,data):path.write_text(json.dumps(data,indent=2)+'\n')
def command(args,log):
    with log.open('w') as f:
        result=subprocess.run(args,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if result.returncode:raise RuntimeError(f'Command failed; inspect {log}')
def stage():
    if (BASE/'build-identity.json').exists():
        archive=BASE/'builds'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        archive.mkdir(parents=True,exist_ok=True)
        for name in ['build-identity.json','build.log','sign.log','sampler-build.log']:
            if (BASE/name).exists():shutil.copy2(BASE/name,archive/name)
    BASE.mkdir(parents=True,exist_ok=True);BUILD.mkdir(parents=True,exist_ok=True)
    command(['./scripts/swift.sh','build','-c','release','-Xswiftc','-DBYE_AUDIT'],BASE/'build.log')
    binary=ROOT/'.build/arm64-apple-macosx/release/Classwise'
    (APP/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(APP/'Contents/Resources').mkdir(exist_ok=True)
    shutil.copy2(binary,APP/'Contents/MacOS/Classwise')
    for name in ['RMPReader.js','THIRD_PARTY_NOTICES.txt']:
        shutil.copy2(ROOT/'Sources/Classwise/Resources'/name,APP/'Contents/Resources'/name)
    plist={'CFBundleName':'BYE Measurement','CFBundleDisplayName':'BYE Measurement',
           'CFBundleIdentifier':'local.bye.performance-audit','CFBundleExecutable':'Classwise','CFBundlePackageType':'APPL',
           'CFBundleShortVersionString':'0.0.1','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True}
    with (APP/'Contents/Info.plist').open('wb') as f:plistlib.dump(plist,f)
    command(['codesign','--force','--deep','--sign','-',str(APP)],BASE/'sign.log')
    command(['xcrun','clang','-O2',str(ROOT/'benchmarks/app-audit/resources.c'),'-o',str(BUILD/'resources')],BASE/'sampler-build.log')
    save(BASE/'build-identity.json',{'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
        'app':str(APP),'build':'release -DBYE_AUDIT','runtime_memory_note':'RSS and physical footprint are separate accounting views.',
        'app_logical_bytes':sum(p.stat().st_size for p in APP.rglob('*') if p.is_file())})
    print('Staged',APP,flush=True)
def run(mode,apple,session_name=None,hold=0,maximum=40,duration=300):
    session=BASE/(session_name or ('live' if mode=='live' else 'offline-1'))
    if (session/'events.jsonl').exists():raise RuntimeError('Refusing to overwrite an existing session')
    session.mkdir(parents=True,exist_ok=True)
    save(session/'resource-format.json',{'version':2,'cpu_unit':'nanoseconds converted from Mach ticks','clock':'mach_absolute_time converted to seconds',
                                       'calibration':json.loads(subprocess.check_output([str(BUILD/'resources')],text=True))})
    if mode=='offline':
        source=BASE/'live'
        for name in ['Reports','http']:
            if (source/name).exists():shutil.copytree(source/name,session/name)
            else:(session/name).mkdir()
        shutil.copy2(source/'collection-plan.json',session/'collection-plan.json')
    args=[str(APP/'Contents/MacOS/Classwise'),'--audit-session',str(session)]
    if mode=='offline':
        args+=['--audit-offline']
        if apple:args+=['--audit-apple']
        policy='(version 1)(allow default)(deny network*)'
        (session/'network.sb').write_text(policy+'\n')
        args=['/usr/bin/sandbox-exec','-p',policy,*args]
    shutil.copy2(BASE/'build-identity.json',session/'build-identity.json')
    save(session/'launch.json',{'argv':args,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                              'network':'bounded allowlist' if mode=='live' else 'OS deny network + recorded response transport'})
    with (session/'app.stdout.log').open('w') as stdout,(session/'app.stderr.log').open('w') as stderr:
        environment=os.environ.copy();environment['BYE_AUDIT_REQUEST_LIMIT']=str(maximum);environment['BYE_AUDIT_DURATION']=str(duration)
        save(session/'policy.json',{'maximum_requests':maximum,'duration_s':duration,'spacing_s':2,'concurrency':1,'retries':0})
        begin=time.monotonic();app=subprocess.Popen(args,cwd=ROOT,stdout=stdout,stderr=stderr,env=environment)
        save(session/'pid.json',{'pid':app.pid,'launch_monotonic_s':begin})
        with (session/'resources.csv').open('w') as resources,(session/'resource-errors.log').open('w') as errors:
            sampler=subprocess.Popen([str(BUILD/'resources'),str(app.pid)],stdout=resources,stderr=errors)
            try:
                last_snapshot=-10
                while time.monotonic()-begin < (390 if mode=='live' else 240):
                    if (session/'complete.json').exists():time.sleep(max(2,hold));break
                    if app.poll() is not None:break
                    if time.monotonic()-last_snapshot>=10:
                        last_snapshot=time.monotonic()
                        result=subprocess.run(['ps','-Ao','pid,ppid,pcpu,rss,comm'],text=True,capture_output=True)
                        with (session/'processes.log').open('a') as f:f.write(f'\nmonotonic_s={time.monotonic()}\n'+result.stdout+result.stderr)
                    time.sleep(0.25)
            finally:
                sampler.terminate();sampler.wait()
                if app.poll() is None:
                    app.terminate()
                    # wait4 reports this application's exit-time max RSS, not other children.
                    _,status,usage=os.wait4(app.pid,0);app.returncode=os.waitstatus_to_exitcode(status)
                    save(session/'exit-resource.json',{'exit_code':app.returncode,'max_rss_bytes':usage.ru_maxrss,
                        'user_cpu_s':usage.ru_utime,'system_cpu_s':usage.ru_stime,'measurement':'macOS wait4 for app process'})
        save(session/'controller.json',{'elapsed_s':time.monotonic()-begin,'exit_code':app.returncode,
                                      'complete_record_present':(session/'complete.json').exists()})
    print('Session finished:',session,flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['stage','live','offline']);parser.add_argument('--apple',action='store_true');parser.add_argument('--session-name');parser.add_argument('--hold-seconds',type=int,default=0);parser.add_argument('--maximum-requests',type=int,default=40);parser.add_argument('--duration',type=int,default=300)
    args=parser.parse_args()
    if args.action=='stage':stage()
    else:run(args.action,args.apple,args.session_name,args.hold_seconds,args.maximum_requests,args.duration)
