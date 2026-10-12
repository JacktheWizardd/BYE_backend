#!/usr/bin/env python3
"""Freeze local evidence and summarize recorded app metrics; never contacts a service."""
import base64, csv, datetime, difflib, hashlib, json, re, statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.local-docs/app-audit-2026-10-11'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value): path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def events(session):return [json.loads(x) for x in (session/'events.jsonl').read_text().splitlines()]
def canonical(label):
    match=re.fullmatch(r'([A-Z]{2,8})\s*([A-Z]?)(\d{1,4})([A-Z]?)',label.upper().strip())
    if not match:return label.upper().strip()
    a,p,n,s=match.groups();return a+p+str(int(n))+s
def stats(values):
    return {'n':len(values),'median':statistics.median(values),'min':min(values),'max':max(values)} if values else None
def csvfile(path,rows):
    if not rows:return
    with path.open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=sorted(set().union(*(r.keys() for r in rows))));writer.writeheader();writer.writerows(rows)

def freeze():
    target=BASE/'dataset';target.mkdir(exist_ok=True)
    if (target/'frozen-corpus.json').exists():return json.loads((target/'frozen-corpus.json').read_text())
    oldpath=ROOT/'.local-docs/rmp-benchmark-2026-10-11/snapshot.json'
    old=json.loads(oldpath.read_text());cases=[]
    for item in old['cases']:
        reviews=[dict(r,id=r['source_id']) for r in item['reviews']]
        cases.append({'name':item['name'],'profile_id':item['profile_id'],'course':item['course'],
                      'partition':'development','source':str(oldpath),'source_sha256':sha(oldpath),
                      'reviews':reviews,'matching_reviews':reviews,'newly_collected':False})
    session=BASE/'live-corrected'
    for file in sorted(session.glob('profile-*.json')):
        frozen=json.loads(file.read_text());profile=frozen['profile'];latestfile=file;latest=frozen
        # Prefer the final raw cache over an early report-open snapshot; never overwrite either.
        for rawfile in (session/'Reports').glob('*.json'):
            raw=json.loads(rawfile.read_text())
            if isinstance(raw,dict) and isinstance(raw.get('profile'),dict) and raw['profile']['id']==profile['id']:
                if len(raw['profile']['reviews'])>=len(profile['reviews']):
                    profile=raw['profile'];latestfile=rawfile;latest=raw
        reviews=profile['reviews'];course=frozen['course']
        matching=[r for r in reviews if canonical(r['course'])==canonical(course)]
        cases.append({'name':'heldout-'+profile['id'],'profile_id':profile['id'],'profile_name':profile['firstName']+' '+profile['lastName'],
                      'course':course,'partition':'held_out','source':str(latestfile),'source_sha256':sha(latestfile),
                      'reviews_complete_flag':latest.get('reviewsComplete',latest.get('reviews_complete')),
                      'review_coverage':profile.get('reviewCoverage'),'reviews':reviews,'matching_reviews':matching,
                      'source_labels':sorted({r['course'] for r in reviews}),'newly_collected':True})
    # Keep connected profiles together when source IDs or substantial review bodies overlap.
    parent=list(range(len(cases)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    def union(a,b):parent[find(a)]=find(b)
    bodies=[];duplicates=[]
    for index,case in enumerate(cases):
        for review in case['reviews']:
            text=' '.join(re.findall(r'\w+',review['text'].lower()))
            bodies.append((index,review['id'],text,set(text.split())))
    for i,(ci,ri,ti,wi) in enumerate(bodies):
        for cj,rj,tj,wj in bodies[:i]:
            if ci==cj and ri==rj:continue
            kind=None;similarity=None
            if ri==rj:kind='same_source_id'
            elif ti==tj and ti:kind='exact_text'
            elif min(len(ti),len(tj))>=80 and min(len(ti),len(tj))/max(len(ti),len(tj))>=0.85:
                if len(wi&wj)/max(1,len(wi|wj))>=0.8:
                    similarity=difflib.SequenceMatcher(None,ti,tj,autojunk=False).ratio()
                    if similarity>=0.92:kind='near_text'
            if kind:
                duplicates.append({'case_a':cases[ci]['name'],'id_a':ri,'case_b':cases[cj]['name'],'id_b':rj,'kind':kind,'similarity':similarity})
                union(ci,cj)
    development_roots={find(i) for i,c in enumerate(cases) if c['partition']=='development'}
    for i,case in enumerate(cases):
        if find(i) in development_roots and case['partition']=='held_out':
            case['partition']='development_overlap';case['partition_reason']='Profile component overlaps prior development evidence.'
    corpus={'frozen_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'cases':cases,
            'policy':'Exact course matching only; no inferred PSYCH/PSYC or honors equivalence. Distinct IDs do not establish distinct authors.',
            'duplicate_policy':'Same IDs/exact bodies; near bodies >=80 characters, token Jaccard >=0.8, SequenceMatcher >=0.92. This heuristic can miss semantic duplicates.',
            'new_cases':sum(c['newly_collected'] for c in cases),
            'new_source_reviews':sum(len(c['reviews']) for c in cases if c['newly_collected']),
            'new_exact_course_reviews':sum(len(c['matching_reviews']) for c in cases if c['newly_collected'])}
    save(target/'duplicates.json',duplicates);save(target/'frozen-corpus.json',corpus)
    save(target/'manifest.json',{'frozen-corpus.json':sha(target/'frozen-corpus.json'),'duplicates.json':sha(target/'duplicates.json')})
    return corpus

def report(corpus):
    sessions={};timings=[];requests=[]
    for name in ['live','live-corrected','offline-1','offline-2']:
        folder=BASE/name
        if not (folder/'events.jsonl').exists():continue
        es=events(folder);starts=[e for e in es if e['event']=='request_start'];ends=[e for e in es if e['event']=='request_end']
        raw=list(csv.DictReader((folder/'resources.csv').open()))
        resources=[{k:float(v) for k,v in r.items()} for r in raw]
        legacy=not (folder/'resource-format.json').exists()
        if legacy:
            calibration=json.loads((BASE/'sampler-clock.json').read_text())
            ratio=calibration['numerator']/calibration['denominator']
            offset=calibration['clock_monotonic_s']-calibration['mach_uptime_s']
            for r in resources:
                r['cpu_ns']*=ratio;r['monotonic_s']-=offset
            csvfile(folder/'resources-calibrated.csv',resources)
        probes=[e['delay_s'] for e in es if e['event']=='main_thread_probe']
        cpu=[]
        for a,b in zip(resources,resources[1:]):
            dt=b['monotonic_s']-a['monotonic_s']
            if dt>0:cpu.append(100*(b['cpu_ns']-a['cpu_ns'])/1e9/dt)
        exitdata=json.loads((folder/'exit-resource.json').read_text()) if (folder/'exit-resource.json').exists() else {}
        state=json.loads((folder/'complete.json').read_text()) if (folder/'complete.json').exists() else {}
        sessions[name]={'requests':len(starts),'responses':len(ends),'http_statuses':sorted({e['status'] for e in ends}),
            'minimum_start_spacing_s':min((b['monotonic_s']-a['monotonic_s'] for a,b in zip(starts,starts[1:])),default=None),
            'overlap_observed':any(b['monotonic_s']<next((e['monotonic_s'] for e in ends if e['request']==a['request']),float('inf')) for a,b in zip(starts,starts[1:])),
            'replay_misses':sum(e['event']=='offline_cache_miss' for e in es),'request_service_s':stats([e['service_s'] for e in ends]),
            'sampled_peak_rss_bytes':int(max((r['rss_bytes'] for r in resources),default=0)),
            'sampled_peak_footprint_bytes':int(max((r['physical_footprint_bytes'] for r in resources),default=0)),
            'lifetime_peak_footprint_bytes':int(max((r['lifetime_peak_footprint_bytes'] for r in resources),default=0)),
            'cpu_percent_one_core':stats(cpu),'main_thread_delay_s':stats(probes),'exit_resource':exitdata,'completion':state,
            'thermal_states':sorted({e['thermal_state'] for e in es if e['event']=='main_thread_probe'})}
        sessions[name]['resource_calibration']='Legacy raw ticks corrected using same-machine timebase; original CSV retained.' if legacy else 'Sampler v2 converts Mach ticks to ns at capture.'
        if resources:
            peak=max(resources,key=lambda r:r['rss_bytes'])
            prior=[e for e in es if e['monotonic_s']<=peak['monotonic_s']]
            sessions[name]['rss_peak_context']={ 'monotonic_s':peak['monotonic_s'],'preceding_events':[e['event'] for e in prior[-5:]] }
            phases={}
            for begin_event,end_event in [('idle_baseline_start','idle_baseline_end'),('recovery_idle_start','recovery_idle_end')]:
                a=next((e['monotonic_s'] for e in es if e['event']==begin_event),None)
                b=next((e['monotonic_s'] for e in es if e['event']==end_event),None)
                if a is not None and b is not None:
                    phase=[r for r in resources if max(a,b-5)<=r['monotonic_s']<=b]
                    phases[begin_event]={'rss_bytes':stats([r['rss_bytes'] for r in phase]),'footprint_bytes':stats([r['physical_footprint_bytes'] for r in phase]),
                                        'note':'Last five seconds of phase; initial phase may overlap startup.'}
            sessions[name]['idle_phases']=phases
        for e in es:
            if e['event']=='request_end':
                row=dict(session=name,**e)
                prior=[s for s in starts if s['request']<e['request']]
                if prior:
                    previous=prior[-1]
                    previous_end=next(x['monotonic_s'] for x in ends if x['request']==previous['request'])
                    current_start=next(x['monotonic_s'] for x in starts if x['request']==e['request'])
                    queued=current_start-e['pacing_wait_s']
                    row['estimated_spacing_constraint_wait_s']=max(0,previous['monotonic_s']+2-max(previous_end,queued))
                recording=folder/'http'/(e['key']+'.json')
                if recording.exists():
                    value=json.loads(recording.read_text())
                    body=json.loads(base64.b64decode(value['body_base64']))
                    node=body.get('data',{}).get('node',{}) if isinstance(body,dict) and body.get('data') else {}
                    row['decoded_review_nodes']=len((node or {}).get('ratings',{}).get('edges',[]))
                requests.append(row)
            if e['event'] in ['window_appeared','terms_ready','course_results','ratings_ready','report_expanded','cached_search','local_filter_sort','cancel_completion','apple_complete','apple_failure','summary_view_state_observed']:
                timings.append(dict(session=name,**e))
    csvfile(BASE/'timings.csv',timings);csvfile(BASE/'requests.csv',requests)
    save(BASE/'performance.json',sessions)
    lines=['# BYE collection and performance audit — October 11, 2026','',
           'Instrumented optimized native build on the local Mac. This is a small screening pilot, not a production reliability study. All raw data and measurements remain local.','',
           '## Collection outcome','',
           f"Corrected pilot: {sessions.get('live-corrected',{}).get('requests',0)} requests, {corpus['new_cases']} new verified professor/course cases, {corpus['new_source_reviews']} source reviews, **{corpus['new_exact_course_reviews']} exact-course reviews**. Target was six verified professors; biology matches could not be confirmed. No automatic session extension or identity guessing was performed.",'',
           '| New case | Selected course | Cached source reviews | Exact-course reviews | Partition |',
           '|---|---|---:|---:|---|']
    for c in corpus['cases']:
        if c['newly_collected']:lines.append(f"| {c['profile_name']} | {c['course']} | {len(c['reviews'])} | {len(c['matching_reviews'])} | {c['partition']} |")
    lines+=['','PSYC/PSYCH and honors variants were not silently treated as equivalent. Missing exact evidence becomes an abstention/course-leakage test. Histories are bounded and some previews remain partial. Newly collected cases have not been passed to a summary model.','',
            '## Measured resources','',
            '| Session | Requests | Peak RSS, MB | Peak physical footprint, MB | Lifetime footprint peak, MB |',
            '|---|---:|---:|---:|---:|']
    for name,s in sessions.items():lines.append(f"| {name} | {s['requests']} | {s['sampled_peak_rss_bytes']/1e6:.1f} | {s['sampled_peak_footprint_bytes']/1e6:.1f} | {s['lifetime_peak_footprint_bytes']/1e6:.1f} |")
    lines+=['','RSS, footprint, and exit-time max RSS are separate accounting views. Do not add them together. CSV samples are 500 ms apart and can miss short spikes; kernel lifetime footprint and wait4 max RSS supplement sampled peaks. CPU percentage uses one core = 100%. Shared Apple inference services are not included in the app process and are not wholly attributable to BYE.','',
            '## Timing','', '| Workflow | Session | Runs | Median, s | Range, s |','|---|---|---:|---:|---|']
    for name in sessions:
        es=events(BASE/name)
        for event,field in [('cached_search','seconds'),('apple_complete','generation_s')]:
            data=stats([e[field] for e in es if e['event']==event])
            if data:lines.append(f"| {event} | {name} | {data['n']} | {data['median']:.3f} | {data['min']:.3f}–{data['max']:.3f} |")
    lines+=['','Live timings include intentional request pacing and single observations of network conditions. Request CSV separates combined queue/pacing wait from HTTP service time and derives decoded review-node counts from the saved response. Estimated spacing-constraint wait is derived from preceding request times; it is not an independently instrumented phase. Concurrent callers can have overlapping queue waits, so do not sum them as total elapsed time. Warm-cache timings use 50 ms observer polling and are approximate. Report-open times for previews that remain incomplete are not full review-loading times.','',
            '## Audit limitations and incidents','',
            '- The initial 9-request attempt sent empty POST bodies because the recording transport cleared httpBody after assignment. RMP returned GraphQL errors; no new review evidence came from that attempt. Body forwarding and canonical replay keys now have a passing regression test.',
            '- Delayed UI inspection relaunched the app without audit arguments after the first process exited. It was closed; its startup PCC traffic was not instrumented, so the overall traffic total is not fully known. The measurement build now refuses argument-free startup. The corrected pilot was separately authorized with a 28-request/180-second cap.',
            '- The first offline Apple display harness used empty section arrays, causing the UI to filter those injected reports out. Generated summaries were saved, but those runs do not prove display latency. The corrected harness uses matching real schedule sections; unavailable matches are logged explicitly.',
            '- A report-open observer could snapshot a second professor before the asynchronous detail task started. Original snapshots and final raw caches are both retained; corpus freezing prefers the final cache. Incomplete reports are labeled. The observer now waits for task startup before checking completion.',
            '- An existing WebKit test stalled in the host sandbox. Targeted gate/transport/app-model tests passed; inspect test logs for exact runs. This is not a claim that the entire original test suite passed.',
            '- Main-thread scheduling delay is a responsiveness proxy, not frame time or measured input-to-pixel latency. App-owned view PNGs are not compositor screenshots.',
            '- Legacy resource CSV cpu_ns columns actually contained Mach ticks. Original files are retained; resources-calibrated.csv and performance.json apply the measured 125/3 timebase. Sampler v2 converts at capture and passes a getrusage reference check. Legacy resource timestamps used a different clock origin; calibration aligns them approximately with app events.',
            '- Instrumentation records large schedule responses and view bitmaps, adding CPU, I/O and memory overhead. Results describe this build and its workflows, not an unrestricted release.',
            '- GPU energy and attributable whole-system Apple model memory are unavailable without additional instrumentation. CPU time is not energy per summary. No battery-efficiency conclusion is supported.',
            '', '## Preserved evidence and cleanup','']
    cleanup=json.loads((BASE/'cleanup.json').read_text())
    lines += [f"Removed only the nine rejected model/app/ZIP paths: {cleanup['logical_bytes_removed']:,} logical bytes and {cleanup['allocated_bytes_removed']:,} allocated bytes. Before/after retained-evidence hashes matched: {cleanup['retained_evidence_unchanged']}. See cleanup.json and retained-evidence inventories.",'',
              'Raw events, requests, resource samples, source recordings, snapshots, source hashes, app build identities, test/build logs and failures are preserved alongside this report. Production releases were not replaced.','',
              '## Next model screening','',
              'Unproven candidates: Qwen3.5-2B Q4_K_M, Qwen3-1.7B Q4_K_M, Qwen2.5-1.5B-Instruct Q5_K_M. Pin exact GGUF revisions, bytes, hashes, upstream identities, licenses, and templates before downloading. Verify Metal compatibility and staged installed app <1,500,000,000 bytes. No replacement weights were downloaded in this audit.',
              '', 'Compare direct summaries and evidence extraction followed by summarization using the frozen development/held-out split. Rank factual support first; no candidate is release-approved. The present held-out sample is small and concentrated, so recommendations remain provisional.']
    if (BASE/'FINDINGS.md').exists():lines+=['', (BASE/'FINDINGS.md').read_text()]
    (BASE/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({'dataset':{k:v for k,v in corpus.items() if k not in ['cases']},'sessions':sessions},indent=2))
if __name__=='__main__':report(freeze())
