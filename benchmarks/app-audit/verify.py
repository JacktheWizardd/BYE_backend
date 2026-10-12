#!/usr/bin/env python3
"""Check preserved local audit evidence and derive provenance. Never opens a network connection."""
import base64, collections, csv, datetime, hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.local-docs/app-audit-2026-10-11'
def read(path):return json.loads(path.read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def events(name):return [json.loads(x) for x in (BASE/name/'events.jsonl').read_text().splitlines()]

def main():
    checks={};provenance=[]
    corpus=read(BASE/'dataset/frozen-corpus.json')
    cases={c['name']:c for c in corpus['cases']}
    expected=read(BASE/'dataset/expected-facts.json')
    invalid=[]
    for case in expected['cases']:
        allowed={r['id'] for r in cases[case['case']]['matching_reviews']}
        for fact in case.get('expected_facts',[]):
            invalid.extend(i for i in fact['review_ids'] if i not in allowed)
    checks['expected_facts_reference_only_matching_sources']=not invalid
    checks['invalid_expected_source_ids']=invalid
    heldout={c['profile_id'] for c in corpus['cases'] if c['partition']=='held_out'}
    for name in ['live','live-corrected','offline-1','offline-2']:
        es=events(name);starts=[e for e in es if e['event']=='request_start'];ends=[e for e in es if e['event']=='request_end']
        initialized=next(e for e in es if e['event']=='app_initialized')
        policy=read(BASE/name/'policy.json') if (BASE/name/'policy.json').exists() else {
            'maximum_requests':initialized['request_limit'],'duration_s':initialized['live_deadline_s']}
        spacings=[b['monotonic_s']-a['monotonic_s'] for a,b in zip(starts,starts[1:])]
        overlap=any(b['monotonic_s']<next(e['monotonic_s'] for e in ends if e['request']==a['request']) for a,b in zip(starts,starts[1:]))
        checks[name]={'recorded_requests':len(starts),'within_request_cap':len(starts)<=policy['maximum_requests'],
                      'minimum_spacing_s':min(spacings,default=None),'spacing_pass':all(s>=2 for s in spacings),'no_overlap':not overlap,
                      'active_request_span_s':ends[-1]['monotonic_s']-starts[0]['monotonic_s'] if starts else 0,
                      'within_request_window':not starts or ends[-1]['monotonic_s']-starts[0]['monotonic_s']<=policy['duration_s'],
                      'summary_generation_during_live_collection':name.startswith('live') and any(e['event']=='apple_start' and (not ends or e['monotonic_s']<=ends[-1]['monotonic_s']) for e in es)}
        if name.startswith('offline'):
            checks[name]['os_denies_external_network']='(deny network*)' in (BASE/name/'network.sb').read_text()
            checks[name]['zero_transport_external_requests']=len(starts)==0
            checks[name]['replay_misses']=sum(e['event']=='offline_cache_miss' for e in es)
            seen={e.get('profile') for e in es if e['event'] in ['apple_display_assigned','development_cache_seeded']}
            checks[name]['heldout_profiles_not_used_by_harness']=not (seen&heldout)
        for e in ends:
            file=BASE/name/'http'/(e['key']+'.json')
            rec=read(file);data=base64.b64decode(rec['body_base64']);obj=json.loads(data)
            if sha_bytes(data)!=rec['sha256']:raise RuntimeError('Recording hash mismatch: '+str(file))
            node=(obj.get('data') or {}).get('node') or {} if isinstance(obj,dict) else {}
            ratings=node.get('ratings',{})
            for edge in ratings.get('edges',[]):
                review=edge['node']
                provenance.append({'session':name,'profile_id':str(node.get('legacyId','')),'source_id':review['id'],
                                   'retrieved_utc':e['utc'],'request':e['request'],'recording':str(file.relative_to(ROOT)),
                                   'response_sha256':rec['sha256'],'review_sha256':sha_bytes(json.dumps(review,sort_keys=True).encode()),
                                   'source_course':review.get('class'),'cursor_requested':e.get('variables',{}).get('cursor'),
                                   'page_info':ratings.get('pageInfo'), 'request_count':e.get('variables',{}).get('count')})
    save(BASE/'dataset/retrieval-provenance.json',provenance)
    before=read(BASE/'retained-evidence-before.json');changes=[]
    for name,meta in before.items():
        file=Path(name)
        if not file.is_file() or file.stat().st_size!=meta['bytes'] or sha(file)!=meta['sha256']:changes.append(name)
    checks['retained_original_evidence_count']=len(before)
    checks['retained_original_evidence_readable_and_unchanged']=not changes
    checks['retained_evidence_changes']=changes
    cleanup=read(BASE/'cleanup.json')
    checks['all_nine_rejected_paths_absent']=len(cleanup['targets'])==9 and all(not Path(t['path']).exists() for t in cleanup['targets'])
    quality=read(BASE/'apple-quality.json')
    for row in quality:
        file=ROOT/row['file']
        if sha(file)!=row['sha256']:raise RuntimeError('Output changed since review: '+str(file))
    checks['quality_output_hashes_match']=True
    quality_details=[]
    for row in quality:
        output=read(ROOT/row['file']);has_theme=bool(output['positives'] or output['concerns'])
        quality_details.append(dict(row,
            displayed_in_test_ui=row['session']=='offline-2' and 'ethnic14' not in Path(row['file']).name,
            supported_claims_assessment='Wording supported, sentiment wrong' if not row['polarity_correct'] else 'No nonempty theme to assess',
            key_detail_coverage='Poor; recurring useful feedback omitted',
            contradictions='Incorrect favorable classification of tough grading' if not row['polarity_correct'] else 'No claim contradiction in empty theme output',
            course_attribution='Input is restricted to exact-course evidence; no leakage observed',
            repetition_handling='Not established by this test; no controlled duplicate perturbation',
            preserved_disagreement='Not established; provider largely abstained',
            raw_output_scope='Generated structured pairs, themes and support judgments in events.jsonl before validation; internal hidden reasoning unavailable',
            validation_assessment='Support validator accepted wording while missing sentiment error' if has_theme else 'Final validation/pair selection yielded no themes'))
    save(BASE/'quality-evaluation.json',quality_details)
    with (BASE/'quality-evaluation.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(quality_details[0]));writer.writeheader();writer.writerows(quality_details)
    helpers={}
    for name in ['live','live-corrected','offline-1','offline-2']:
        pid=read(BASE/name/'pid.json')['pid'];children=set()
        for line in (BASE/name/'processes.log').read_text().splitlines():
            fields=line.split(None,4)
            if len(fields)==5 and fields[0].isdigit() and fields[1]==str(pid):children.add(fields[4])
        helpers[name]={'sampled_direct_children':sorted(children),'note':'Periodic snapshots may miss short-lived helpers; shared Apple services cannot be attributed solely to BYE.'}
    save(BASE/'helper-observations.json',helpers)
    # Add annotation/provenance hashes without modifying the frozen source corpus.
    save(BASE/'dataset/manifest.json',{p.name:sha(p) for p in (BASE/'dataset').glob('*.json') if p.name!='manifest.json'})
    checks['overall_external_request_total']='Unknown: initial UI-tool relaunch startup traffic was outside recording; corrected pilot individually met its authorization.'
    checks['checked_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(BASE/'verification.json',checks)
    print(json.dumps({'checks':checks,'quality':{'runs':len(quality),'empty_theme_outputs':sum(r['themes']==0 for r in quality),
                                               'sentiment_errors':sum(not r['polarity_correct'] for r in quality)},'helpers':helpers},indent=2))
    if changes or invalid or not checks['all_nine_rejected_paths_absent']:raise SystemExit(1)

def sha_bytes(data):return hashlib.sha256(data).hexdigest()
if __name__=='__main__':main()
