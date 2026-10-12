#!/usr/bin/env python3
"""Create an offline synthesis from preserved measurements and semantic judgments.
No inference, downloads, live evidence access, or semantic auto-scoring.
"""
import argparse,collections,csv,json,statistics
from pathlib import Path
import run as r
import review
import analyze

def optional(path,default=None):return r.load(path) if path.exists() else default

def table(lines,headers,rows):
 lines.extend(['','| '+' | '.join(headers)+' |','|'+'|'.join('---' for _ in headers)+'|'])
 for row in rows:lines.append('| '+' | '.join(str(v).replace('|','/').replace('\n',' ') if v is not None else 'unavailable' for v in row)+' |')

def number(value,digits=3):return round(value,digits) if value is not None else None

def read_csv(path):
 if not path.exists():return []
 with path.open() as f:return list(csv.DictReader(f))

def make_report(run):
 quality=optional(run/'quality-summary.json',[]);sizes=optional(run/'native-ui-sizes.json',[])
 sizes={x['variant']:x for x in sizes};stages=read_csv(run/'stage-metrics.csv');trials=read_csv(run/'trial-metrics.csv');loads=read_csv(run/'load-metrics.csv')
 memory=optional(run/'memory-and-cpu.json',[]);session_variants={x['session']:x['variant'] for x in loads}
 packets={p['blind_id']:p for p in optional(run/'semantic-review-packets.json',[])}
 judgments={json.loads(line)['blind_id']:json.loads(line) for line in (run/'semantic-judgments.jsonl').read_text().splitlines() if line.strip()} if (run/'semantic-judgments.jsonl').exists() else {}
 keys=optional(run/'semantic-review-key.json',[]);models={m['id']:m for m in r.load(r.ROOT/'benchmarks/model-prep/manifest.json')['models']}
 ordinary={c['name'] for c in r.load(run/'selected-cases.json')['cases']}
 completed=any(v.get('kind')=='matrix_complete' for v in analyze.jsonlines(run/'events.jsonl'))
 complete_review=bool(keys) and all(k['blind_id'] in judgments for k in keys)
 preservation=optional(run/'preservation-check.json',{});integrity=optional(run/'final-weight-integrity.json',[])
 inventory=[];examples=[]
 for a in r.artifacts():
  variant=a['variant'];q=[x for x in quality if x['variant']==variant];t=[x for x in trials if x['variant']==variant];s=[x for x in stages if x['variant']==variant]
  timing=[float(x['pipeline_s']) for x in t if x['case'] in ordinary and x['context']=='2048' and x['mode']=='direct' and x['limit']=='256' and x['timing_eligible']=='True' and x['pipeline_s']]
  warmed=[float(x['pipeline_s']) for x in t if x['case'] in ordinary and x['context']=='2048' and x['mode']=='direct' and x['limit']=='256' and x['first_inference_pipeline']=='False' and x['timing_eligible']=='True' and x['pipeline_s']]
  peak=lambda field:max((int(x[field]) for x in s if x.get(field)),default=None)
  bound=sizes.get(variant,{})
  variant_memory=[v for v in memory if session_variants.get(v['session'])==variant]
  memory_peak=lambda field:max((v[field] for v in variant_memory if v.get(field) is not None),default=None)
  bad=sum(x['unsafe_reviewed_trials'] for x in q)
  failure=any(x['release_recommendation'].startswith('none') for x in q)
  # A positive selection requires every applicable configuration's full review and
  # the native scenario, never an automatically derived fluent-output score.
  status='observed quality failures; no passing configuration established' if failure else 'pending full quality/native review'
  examples_for=[]
  for k in keys:
   if k['variant']!=variant:continue
   d=judgments.get(k['blind_id']);p=packets[k['blind_id']]
   if d and p['partition']=='synthetic' and any(d.get(f,0) for f in ('raw_invented_claims','wrong_course_claims','sentiment_reversals','unsupported_corroboration','raw_fabricated_consensus')):
    if k['blind_id'] not in {x['blind_id'] for x in examples_for}:examples_for.append({**k,'raw_output':p['raw_output'],'displayed':p['displayed'],'notes':d['notes']})
   if len(examples_for)==2:break
  examples.extend(examples_for)
  inventory.append({'variant':variant,'model':models[a['id']]['name'],'license':models[a['id']]['license'],'weight_bytes':a['bytes'],'installed_logical_bytes':bound.get('installed_logical_bytes'),'allocated_disk_bytes':bound.get('allocated_bytes'),'zip_bytes':bound.get('archive_bytes'),'installed_below_1500000000':bound.get('below_mandatory_limit'),'recorded_pipeline_trials':len(t),'reviewed_final_answer_trials':sum(x['reviewed_trials'] for x in q),'unsafe_reviewed_trials':bad,'quality_configuration_count':len(q),'configurations_with_observed_failure':sum(x['release_recommendation'].startswith('none') for x in q),'helper_sampled_peak_rss_bytes':memory_peak('sampled_rss_peak_bytes'),'helper_exit_peak_rss_bytes':memory_peak('runtime_peak_rss_bytes'),'helper_sampled_peak_footprint_bytes':memory_peak('sampled_footprint_peak_bytes'),'helper_lifetime_peak_footprint_bytes':memory_peak('lifetime_footprint_peak_bytes'),'matrix_stage_peak_rss_bytes':peak('helper_sampled_peak_rss_bytes'),'matrix_stage_peak_footprint_bytes':peak('helper_sampled_peak_footprint_bytes'),'peak_scope':'All observed process phases/contexts, including loading, long/reasoning supplements and native scenarios; matched per-case matrix samples are separate.','reference_2048_direct_256_s_median':number(statistics.median(timing)) if timing else None,'reference_2048_direct_256_s_min':number(min(timing)) if timing else None,'reference_2048_direct_256_s_max':number(max(timing)) if timing else None,'reference_trials':len(timing),'warm_reference_s_median':number(statistics.median(warmed)) if warmed else None,'warm_reference_trials':len(warmed),'status':status})
 analyze.write_csv(run/'variant-comparison.csv',inventory);r.save(run/'representative-synthetic-failures.json',examples)
 lines=['# BYE local model comparison','',f'Run: `{run.name}`. Updated {r.stamp()} (UTC log timestamp).',f'Execution complete: **{completed}**. All mapped final answers semantically reviewed: **{complete_review}**.','',
 'No release model is selected by this automatic report. Selection requires a demonstrated passing configuration, completed native checks and the installed-app size gate. Observed failures are not erased by fluent text or display filtering.',
 '',f'{len(trials)} pipeline trials are recorded. Raw outputs, errors, extraction intermediates, source IDs and exact hashes remain in this ignored local directory. No PCC/RMP refresh or external judge request is part of this experiment.',
 '', 'The comparison uses llama.cpp b11559, embedded templates, greedy decoding, four CPU threads, one Metal model and one inference request at a time. The 384-token and natural-reasoning trials are supplements, not replacements for the 256-token baseline. Filesystem cache state is uncontrolled.',
 '', 'The mandatory limit is installed `.app` logical bytes strictly below 1,500,000,000. Weight, allocated blocks, ZIP and runtime memory are separate. APFS extents may be shared; RSS and Metal allocations must not be added.']
 table(lines,['Variant','Weight bytes','Installed app bytes','ZIP bytes','Size gate','Helper sampled peak RSS bytes','Helper sampled peak footprint bytes'],[(x['variant'],x['weight_bytes'],x['installed_logical_bytes'],x['zip_bytes'],x['installed_below_1500000000'],x['helper_sampled_peak_rss_bytes'],x['helper_sampled_peak_footprint_bytes']) for x in inventory])
 lines.extend(['','## Quality','', 'Semantic review is exploratory agent review against frozen facts, with model names hidden in review packets; it is not independent human certification. Exact duplicate output/evidence/display/intermediate combinations share a judgment while every repeat remains in the denominator. Diagnostic counts are error groups, not exhaustive atomic claim-level accuracy rates.', '', 'Raw and displayed judgments are separate. A rejected or filtered unsafe answer remains a model failure. Citation membership alone cannot establish complete-claim support, course attribution, independence or sentiment. Coverage uses supported cited priority themes from the actual supplied subset; development and held-out denominators are separate. Long synthetic cases have qualitative checks rather than post-hoc numeric theme gold.'])
 table(lines,['Variant','Reviewed final trials','Unsafe reviewed trials','Configurations with observed failure / evaluated','Status'],[(x['variant'],x['reviewed_final_answer_trials'],x['unsafe_reviewed_trials'],str(x['configurations_with_observed_failure'])+'/'+str(x['quality_configuration_count']),x['status']) for x in inventory])
 lines.extend(['','See `quality-comparison.csv` for per-case raw/display judgments and `quality-summary.json` for context/pipeline/budget-specific coverage, readability and denominators. `technical-quality-failures.json` retains extraction/execution failures without a complete final answer; these are not silently excluded as successful summaries.','', '## Timing and resources','', 'The following is a reference workload distribution for ordinary cases at 2048 context, direct pipeline and 256 output tokens. Cases differ in length; use the per-case three-repeat median/range for matched comparisons. “Structurally valid” does not mean factually correct. Pipeline time includes template/tokenization, inference and the separate validator process; native view-state timings are reported separately.'])
 table(lines,['Variant','Reference trials','Pipeline median s','Range s','Warm-only median s','Warm trials'],[(x['variant'],x['reference_trials'],x['reference_2048_direct_256_s_median'],str(x['reference_2048_direct_256_s_min'])+'–'+str(x['reference_2048_direct_256_s_max']),x['warm_reference_s_median'],x['warm_reference_trials']) for x in inventory])
 lines.extend(['','`stage-metrics.csv`: tokenizer counts/utilization, processing and generation rates, first decoded content/first summary-value text, complete stages, sampled resources and power/thermal cohort. `per-case-comparison.csv`: matched repeat statistics. `load-metrics.csv`: fresh-process readiness, internal load where logged, actual offload/flash lines. `host-metrics.csv`: supervisor accounting. `memory-and-cpu.json`: lifetime peaks and allocation logs.', '', 'First decoded content may be JSON syntax; first_summary_text_arrival_s measures decoded value text, and neither is a compositor-visible token. Native view-state delivery is reported separately. Only the first inference in a process has an observed startup-inclusive latency. Adding load to a warm request is a labeled hypothetical sum. Three repeats do not establish tail latency. Sampled 100 ms peaks may miss transients. Whole-app scenarios report native app, supervisor and runtime separately, without claiming their sum is unique physical memory.', '', 'Power telemetry began partway through round one. A charging transition occurred; unobserved and discharging intervals remain labeled. Charging and thermal state can affect results. Idle Ollama processes are recorded separately from observed competing inference activity; unrelated apps were not terminated.', '', '## Energy and native checks','', 'The fixed five-attempt workload repeats three rounds per variant. CPU time is an activity proxy, not battery energy. Inspect `energy-instrumentation.json` and individual workload logs; no joules per summary are claimed without measured counters and successful-summary denominators.', '', '`native-workflow-comparison.csv` and `native-display-timings.csv` report the optimized actual SwiftUI workflows, cache identity checks, errors, cancellation and scheduling probes. Programmatic editing/scrolling and view-state observation are proxies, not hardware-input-to-pixel timing. Missing observations are shortfalls. The controller demonstrates 30-second idle unloading; a production provider lifecycle is not implemented here.', '', '## Per-variant tradeoffs'])
 for x in inventory:
  example=next((v for v in examples if v['variant']==x['variant']),None)
  lines.extend(['',f"### {x['variant']}", '',f"Measured advantages: {x['weight_bytes']:,} weight bytes; installed-size gate {x['installed_below_1500000000']}; reference latency median {x['reference_2048_direct_256_s_median']} s. These resource advantages do not establish factual reliability.", '', 'Observed limitation: '+(example['notes'] if example else 'No completed reviewed representative synthetic failure is available yet; see per-case judgments and pending status.'), '',f"Redistribution: {x['license']}. Preserve the pinned task-1 license documents and notices; source conversion revision remains unknown where the publisher did not disclose it."])
 lines.extend(['','## Preservation and next step','',f"Preservation verified: {preservation.get('unchanged')}; protected files checked: {preservation.get('files')}; final original-weight verification entries: {len(integrity)}.",'', 'Existing releases and prior experiment evidence are retained. These twelve candidates remain available; no candidate deletion or production integration occurs in task 2. See `benchmarks/model-eval/production-integration-proposal.md` for the conditional native integration proposal. A pilot with four held-out professor cases cannot establish production reliability.'])
 (run/'COMPARISON.md').write_text('\n'.join(lines)+'\n')
 print('Report:',run/'COMPARISON.md')

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--run',type=Path);args=parser.parse_args();make_report(args.run or Path(r.load(r.BASE/'latest.json')['run']))
