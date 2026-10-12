#!/usr/bin/env python3
"""Export allowlisted experiment data for GitHub; no inference or network access.

Original evidence is read-only. Real cases receive opaque labels; no real review
text, source IDs, prompts, machine paths, or free-form errors are exported.
"""
import argparse
import collections
import csv
import hashlib
import json
import statistics
from pathlib import Path


def load(path):
    return json.loads(path.read_text())


def write_csv(path, rows):
    if not rows:
        return
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def export(run, out):
    out.mkdir(parents=True, exist_ok=False)
    sources = {}

    def evidence(path):
        sources[str(path.relative_to(run))] = hashlib.sha256(path.read_bytes()).hexdigest()
        return load(path)

    trials = []
    real_names = set()
    for path in sorted((run / 'trials').rglob('*.json')):
        if '.' in path.stem:
            continue
        row = evidence(path)
        if 'variant' not in row:
            continue
        if row.get('partition') != 'synthetic':
            real_names.add(row['case'])
        trials.append((path, row))
    aliases = {name: f'real-{i:02d}' for i, name in enumerate(sorted(real_names), 1)}
    public, stages = [], []
    for index, (path, row) in enumerate(trials, 1):
        relative = path.relative_to(run / 'trials')
        phase, round_name = relative.parts[:2]
        shared = dict(trial=index, phase=phase, round=round_name,
                      variant=row['variant'], context=row['context'], mode=row['mode'],
                      final_output_limit=row.get('output_limit', int(phase.rsplit('-', 1)[1])),
                      case=row['case'] if row.get('partition') == 'synthetic' else aliases[row['case']],
                      input_class='near_limit' if row['case'].startswith('near-') else 'ordinary',
                      partition=row.get('partition'))
        stage_values = []
        for stagepath in row.get('stages', []):
            stage = evidence(run / stagepath)
            stage_values.append(stage)
            timing = stage.get('timings') or {}
            stages.append({**shared, 'stage':stage.get('stage'),
                           'prompt_tokens':stage.get('prompt_tokens'),
                           'output_tokens':timing.get('predicted_n'),
                           'prompt_tokens_per_second':timing.get('prompt_per_second'),
                           'generation_tokens_per_second':timing.get('predicted_per_second'),
                           'template_s':stage.get('template_s'),
                           'tokenization_s':stage.get('tokenization_s'),
                           'first_decoded_content_s':stage.get('first_generated_content_s'),
                           'generation_request_s':stage.get('generation_request_s'),
                           'total_stage_s':stage.get('total_stage_s'),
                           'token_count_matches':stage.get('prompt_token_count_match'),
                           'stopped_at_limit':bool((stage.get('stop') or {}).get('stopped_limit')),
                           'execution_error':bool(stage.get('error'))})
        public.append({**shared, 'pipeline_s':row.get('total_pipeline_s'),
                       'first_inference':row.get('first_inference'),
                       'execution_error':bool(row.get('error')),
                       'structural_error_count':len(row.get('structural_errors') or []),
                       'stopped_at_limit':any((v.get('stop') or {}).get('stopped_limit') for v in stage_values),
                       'recovered_checkpoint':bool(row.get('recovered_from_stage_checkpoint')),
                       'completed_stages':len(stage_values)})
    write_csv(out / 'trials.csv', public)
    write_csv(out / 'stages.csv', stages)
    grouped = collections.defaultdict(list)
    for row in public:
        grouped[tuple(row[k] for k in ('phase','variant','context','mode','case','partition'))].append(row)
    repeats = []
    for key, rows in sorted(grouped.items()):
        durations = [r['pipeline_s'] for r in rows if r['pipeline_s'] is not None and not r['execution_error'] and not r['recovered_checkpoint']]
        repeats.append({**dict(zip(('phase','variant','context','mode','case','partition'),key)),
                        'recorded_trials':len(rows), 'timed_trials':len(durations),
                        'execution_errors':sum(r['execution_error'] for r in rows),
                        'structural_failures':sum(bool(r['structural_error_count']) for r in rows),
                        'limit_stops':sum(r['stopped_at_limit'] for r in rows),
                        'pipeline_median_s':statistics.median(durations) if durations else None,
                        'pipeline_min_s':min(durations) if durations else None,
                        'pipeline_max_s':max(durations) if durations else None})
    write_csv(out / 'matched-case-timings.csv', repeats)
    sessions = []
    for index, path in enumerate(sorted((run/'sessions').glob('*/startup.json')),1):
        startup=evidence(path)
        compat_path=path.parent/'compatibility.json'
        compat=evidence(compat_path) if compat_path.exists() else {}
        metrics={'session':index,'variant':compat.get('model'),'context':compat.get('context'),
                 'phase':'preflight' if path.parent.name.startswith('preflight') else path.parent.name.split('-r',1)[0],
                 'process_to_ready_s':startup.get('load_s'),'metal_observed':compat.get('metal_observed')}
        for prefix, name in [('helper','resources.csv'),('supervisor','host-resources.csv')]:
            samples=list(csv.DictReader((path.parent/name).open())) if (path.parent/name).exists() else []
            metrics[prefix+'_samples']=len(samples)
            for column in ['rss_bytes','physical_footprint_bytes','lifetime_peak_footprint_bytes']:
                metrics[prefix+'_peak_'+column]=max((int(v[column]) for v in samples),default=None)
            metrics[prefix+'_sampled_cpu_s']=(int(samples[-1]['cpu_ns'])-int(samples[0]['cpu_ns']))/1e9 if len(samples)>1 else None
        sessions.append(metrics)
    write_csv(out/'load-and-resources.csv',sessions)
    quality=evidence(run/'quality-summary.json')
    # Aggregate numeric/configuration fields only; do not copy per-case notes.
    (out/'quality-checkpoint.json').write_text(json.dumps(quality,indent=2)+'\n')
    sizes=evidence(run/'sizes.json')
    write_csv(out/'prototype-bundle-sizes.csv',[{k:v for k,v in r.items() if k!='app'} for r in sizes])
    manifest=evidence(run/'manifest.json')
    write_csv(out/'candidates.csv',[{'model':m['name'],'filename':f['filename'],'repository':m['repository'],
                                   'revision':m['revision'],'bytes':f['bytes'],'sha256':f['sha256'],
                                   'license':m['license'],'obligations':m['redistribution_obligations']}
                                  for m in manifest['models'] for f in m['files']])
    (out/'settings.json').write_text(json.dumps(evidence(run/'settings.json'),indent=2)+'\n')
    packets=evidence(run/'semantic-review-packets.json')
    keys=evidence(run/'semantic-review-key.json')
    judgments={v['blind_id']:v for v in map(json.loads,(run/'semantic-judgments.jsonl').read_text().splitlines())}
    examples=[]
    used_variants=set()
    for case in ['sparse_evidence','duplicate_distinct_ids','contradictory_reports','negation','injected_instructions','mixed_sentiment']:
        candidates=[p for p in packets if p['partition']=='synthetic' and p['case']==case and p['blind_id'] in judgments]
        packet=next((p for p in candidates if next(k for k in keys if k['blind_id']==p['blind_id'])['variant'] not in used_variants),candidates[0] if candidates else None)
        if not packet:continue
        key=next(k for k in keys if k['blind_id']==packet['blind_id'])
        used_variants.add(key['variant'])
        examples.append({k:packet[k] for k in ['case','reviews','expected','raw_output','raw_sha256','displayed','structural_errors']})
        examples[-1].update({k:key[k] for k in ['variant','context','mode','output_limit']})
        examples[-1]['review_notes']=judgments[packet['blind_id']]['notes']
    (out/'synthetic-examples.json').write_text(json.dumps(examples,indent=2)+'\n')
    summary={'run_id':run.name,'status':'stopped_by_user','completed_pipeline_counts':dict(collections.Counter(r['phase'] for r in public)),
             'quality_scope':'Saved semantic-review checkpoint, not complete review of every final trial.',
             'held_out_inference_started':False,'energy_joules':None,
             'raw_real_reviews_exported':False,'exporter_writes_original_evidence':False,'source_hashes':sources}
    (out/'provenance.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('Exported',len(public),'pipelines;',len(stages),'stages;',len(sessions),'load/resource sessions to',out)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    export(args.run,args.output)
