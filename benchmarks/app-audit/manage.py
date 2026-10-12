#!/usr/bin/env python3
"""Local evidence preservation, explicit model cleanup, and audit environment capture."""
import argparse, datetime, hashlib, json, os, platform, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()

def inventory():
    paths = []
    for base in [ROOT/'benchmarks/bye-mac', ROOT/'docs/verification', ROOT/'.local-docs/rmp-benchmark-2026-10-11']:
        paths.extend(p for p in base.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    paths.extend(p for p in (ROOT/'dist').rglob('*') if p.is_file())
    for name in ['Classwise', 'BYEAppleAIBeta']:
        paths.extend((Path.home()/f'Library/Application Support/{name}/Reports').glob('*.json'))
    return {str(p): {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in sorted(set(paths))}

def cleanup(out):
    if (out/'cleanup.json').exists(): raise RuntimeError('Cleanup already recorded; refusing to overwrite')
    before = inventory()
    save(out/'retained-evidence-before.json', before)
    targets = [ROOT/'.build/bye-benchmark'/f'{model}.{ext}' for model in ['lfm','qwen','smol'] for ext in ['gguf','app','zip']]
    records = []
    for p in targets:
        if p.is_symlink(): raise RuntimeError('Refusing symlink: '+str(p))
        files = [p] if p.is_file() else sorted(x for x in p.rglob('*') if x.is_file())
        records.append({'path': str(p), 'exists': p.exists(), 'logical_bytes': sum(x.stat().st_size for x in files),
                        'allocated_bytes': sum(x.stat().st_blocks*512 for x in files),
                        'files': [{'path': str(x.relative_to(p)) if x != p else p.name, 'bytes': x.stat().st_size} for x in files],
                        'sha256': sha(p) if p.is_file() else None})
    record = {'started_utc': now(), 'reason': 'User requested removal of three rejected models; preserve all benchmark evidence.',
              'free_bytes_before': shutil.disk_usage(ROOT).free, 'targets': records}
    save(out/'cleanup.json', record)
    for p, row in zip(targets, records):
        if p.is_dir(): shutil.rmtree(p)
        elif p.exists(): p.unlink()
        row.update(removed_utc=now(), outcome='removed' if row['exists'] else 'already_absent', absent=not p.exists())
        save(out/'cleanup.json', record)
    after = inventory()
    save(out/'retained-evidence-after.json', after)
    record.update(finished_utc=now(), retained_evidence_unchanged=before==after,
                  logical_bytes_removed=sum(x['logical_bytes'] for x in records),
                  allocated_bytes_removed=sum(x['allocated_bytes'] for x in records),
                  free_bytes_after=shutil.disk_usage(ROOT).free)
    record['observed_volume_free_delta_bytes'] = record['free_bytes_after']-record['free_bytes_before']
    record['note'] = 'Volume free-space delta includes concurrent activity and APFS accounting; logical/allocated sizes describe deleted paths.'
    save(out/'cleanup.json', record)
    if before != after: raise RuntimeError('Retained evidence changed: inspect inventories')
    print(json.dumps({k:v for k,v in record.items() if k!='targets'}, indent=2))

def environment(out):
    commands = {'hardware':['system_profiler','SPHardwareDataType','SPDisplaysDataType'],
                'macos':['sw_vers'], 'power':['pmset','-g','batt'], 'power_settings':['pmset','-g','custom'],
                'thermal':['pmset','-g','therm'], 'swap':['sysctl','vm.swapusage'],
                'vm':['vm_stat'], 'pressure':['memory_pressure','-Q'],
                'background':['ps','-Ao','pid,ppid,pcpu,rss,comm'],
                'git':['git','-c','core.fsmonitor=false','status','--short']}
    data={'captured_utc':now(),'timezone':'America/Los_Angeles','platform':platform.platform()}
    for key, command in commands.items():
        try: result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True)
        except OSError as error:
            data[key]={'command':command,'unavailable':str(error)}
            continue
        data[key]={'command':command,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr}
    save(out/('environment-'+now().replace(':','-')+'.json'),data)
    print('Environment recorded')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['cleanup','environment']);parser.add_argument('directory',type=Path)
    args=parser.parse_args();args.directory.mkdir(parents=True,exist_ok=True)
    (cleanup if args.action=='cleanup' else environment)(args.directory.resolve())
