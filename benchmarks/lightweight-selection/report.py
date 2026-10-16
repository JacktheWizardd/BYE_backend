"""Aggregate completed, hash-bound source reviews without inventing judgments."""
import csv
import statistics
from common import *

def resources(path):
    if not path.exists():return {}
    rows=list(csv.DictReader(path.open()))
    return {key:max((int(r[key]) for r in rows),default=0) for key in ['rss_bytes','physical_footprint_bytes','lifetime_peak_footprint_bytes']}

def main():
    summaries=[];samples=['# Local summaries beside complete source reviews','','Exploratory Codex judgments; not independent human certification.']
    for model in MODELS:
        folder=BASE/'screen-v1'/model
        judgments=load(folder/'review/decisions.json')
        rows=[load(folder/(c['name']+'.json')) for c in cases()]
        if len(judgments)!=21:raise ValueError('Incomplete review')
        for r in rows:
            j=judgments[r['case']]
            for key,value in [('output_hash',digest(r['text'])),('evidence_hash',digest(r['evidence']))]:
                if r[key]!=value or j[key]!=value:raise ValueError('Stale evidence judgment')
            if r['prompt_hash']!=digest(p.PROMPTS[1]):raise ValueError('Prompt mismatch')
            samples+=['',f'## {model} / {r["case"]}','',r['text'],'',
                'Review: '+j['notes'],'',f'Words: {r["words"]}; completion: {r["seconds"]:.3f} s','',
                '```json',__import__('json').dumps(r['evidence'],indent=2,ensure_ascii=False),'```']
        real={c['name'] for c in cases() if c['partition']=='development'}
        times=[r['seconds'] for r in rows if r['case'] in real and not r.get('abstained')]
        pilots=[r['startup_inclusive_seconds'] for r in rows if 'startup_inclusive_seconds' in r]
        diagnostic=BASE/'diagnostics-v1'/model/'startup-pilot.json'
        if diagnostic.exists():pilots.append(load(diagnostic)['startup_inclusive_seconds'])
        artifact=load(BASE/'artifacts'/(model+'.json'))
        training=load(BASE/'training'/model/'result.json')
        overflow=BASE/'overflow'/model/'result.json'
        over=load(overflow) if overflow.exists() else {}
        summaries.append(dict(model=model,screen_cases=len(rows),generated_cases=sum(not r.get('abstained') for r in rows),
            unsupported_cases=sum(not j['safe'] for j in judgments.values()),
            missed_disagreement_cases=sum(not j['disagreements_preserved'] for j in judgments.values()),
            covered_priority_facts=sum(j['covered_priority_facts'] for j in judgments.values()),
            eligible_priority_facts=sum(j['eligible_priority_facts'] for j in judgments.values()),
            structural_failures=sum(bool(r['structural_errors']) for r in rows),
            overlength_cases=sum(r['words']>120 for r in rows),
            loaded_real_median_seconds=statistics.median(times),loaded_real_range_seconds=[min(times),max(times)],
            startup_pilots_seconds=pilots,startup_pilots_under_ten=sum(x<=10 for x in pilots),
            screen_resources=resources(folder/'session/resources.csv'),training=training,
            training_resources=resources(BASE/'training'/model/'resources.csv'),
            gguf_bytes=artifact['gguf']['artifact_bytes'],native_bytes=artifact['native']['artifact_bytes'],
            overflow_seconds=over.get('seconds'),overflow_stages=len(over.get('stages',[])),
            overflow_generation_stage_seconds=[s['generation_seconds'] for s in over.get('stages',[])],
            cancellation=load(BASE/'diagnostics-v1'/model/'cancellation.json') if (BASE/'diagnostics-v1'/model/'cancellation.json').exists() else None))
    save(BASE/'SUMMARY.json',dict(models=summaries,corpus_sha256=sha(p.DATA/'corpus-full.json'),
        held_out_inference=False,pcc_rmp_requests=0,reviewer='Codex exploratory source review; not independent human validation',
        timing_note='Fresh processes; uncontrolled filesystem cache/background workload; no UI overhead. Training and download activity excluded from model timing sessions.'))
    (BASE/'SAMPLES.md').write_text('\n'.join(samples)+'\n')
    print(__import__('json').dumps(summaries,indent=2))

if __name__=='__main__':main()
