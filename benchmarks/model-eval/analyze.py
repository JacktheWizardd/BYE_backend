#!/usr/bin/env python3
"""Read-only offline analysis. Never loads a model or changes trial evidence."""
import argparse,collections,csv,datetime,json,re,statistics
from pathlib import Path
import run as r
import review

def write_csv(path,rows):
 if not rows:return
 fields=list(dict.fromkeys(k for row in rows for k in row))
 with path.open('w') as f:
  w=csv.DictWriter(f,fields);w.writeheader();w.writerows(rows)

def distribution(values):
 values=[v for v in values if v is not None]
 return {'n':len(values),'median':statistics.median(values) if values else None,'min':min(values) if values else None,'max':max(values) if values else None}

def jsonlines(path):
 return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []

def resource_rows(path):
 if not path.exists():return []
 with path.open() as f:rows=list(csv.DictReader(f))
 valid=[]
 for row in rows:
  try:
   for key in ('monotonic_s','rss_bytes','physical_footprint_bytes','lifetime_peak_footprint_bytes','cpu_ns'):float(row[key])
   valid.append(row)
  except (KeyError,ValueError,TypeError):pass
 return valid

def first_summary_text(stage):
 """Arrival of decoded JSON value text, not a UI/compositor timestamp."""
 text=''
 for item in stage.get('stream_events',[]):
  text+=item['event'].get('content','')
  if '<think>' in text:
   if '</think>' not in text:continue
   answer=text.split('</think>',1)[1]
  else:answer=text
  if re.search(r'"(?:overview|text)"\s*:\s*"[^"\s]',answer):return item['arrival_s']
 return None

def native_analysis(run,sessions=()):
 rows=[];display=[]
 for directory in (run/'native').iterdir() if (run/'native').exists() else []:
  if not directory.is_dir():continue
  events=jsonlines(directory/'native-events.jsonl');samples=resource_rows(directory/'app-resources.csv')
  kinds=collections.defaultdict(list)
  for v in events:kinds[v['kind']].append(v)
  result=r.load(directory/'result.json') if (directory/'result.json').exists() else {}
  helper=r.load(directory/'helper-failure.json') if (directory/'helper-failure.json').exists() else {}
  rows.append({'variant':directory.name,'native_workflow_complete':result.get('native_complete',False),'error':result.get('error'),'bundled_stack_start_to_window_s':kinds['window_appeared'][0].get('bundled_stack_start_to_observed_window_s') if kinds['window_appeared'] else None,'ui_prelaunch_to_window_s':kinds['window_appeared'][0].get('controller_prelaunch_to_observed_window_s') if kinds['window_appeared'] else None,'launch_note':'UI startup and controller-orchestrated bundled stack startup reported separately; uncontrolled filesystem cache. Measurement driver supplies configuration; not an end-user first-launch readiness claim.','app_sampled_peak_rss_bytes':max((int(v['rss_bytes']) for v in samples),default=None),'app_sampled_peak_footprint_bytes':max((int(v['physical_footprint_bytes']) for v in samples),default=None),'app_lifetime_peak_footprint_bytes':max((int(v['lifetime_peak_footprint_bytes']) for v in samples),default=None),'app_final_footprint_bytes':int(samples[-1]['physical_footprint_bytes']) if samples else None,'main_thread_probe_samples':len(kinds['main_thread_probe']),'main_thread_delay_median_s':statistics.median(v['delay_s'] for v in kinds['main_thread_probe']) if kinds['main_thread_probe'] else None,'main_thread_delay_max_s':max((v['delay_s'] for v in kinds['main_thread_probe']),default=None),'text_editor_observed':any(v.get('field_editor_found') for v in kinds['text_edit_observed']),'text_actions_while_loading':sum(v.get('summary_loading',False) for v in kinds['text_edit_observed']),'sort_filter_actions_while_loading':sum(v.get('summary_loading',False) for v in kinds['programmatic_ui_actions']),'scroll_moved':any(v.get('document_height',0)>v.get('viewport_height',0) and v.get('before_y')!=v.get('after_y') for v in kinds['scroll_observed']),'fresh_cancel_was_loading':any(v.get('summary_was_loading') for v in kinds['fresh_request_cancel_state_completed']),'cached_view_reopened_same_summary':any(v.get('same_summary') for v in kinds['cached_view_reopened']),'helper_failure_propagated':helper.get('host_propagated_failure'),'helper_failure_ui_error_observed':helper.get('native_ui_observed_error'),'summary_present':any(v.get('present') for v in kinds['summary_state_observed'])})
  idle=[v for v in samples if kinds['native_ui_idle_begin'] and kinds['native_ui_idle_end'] and kinds['native_ui_idle_begin'][0]['uptime_s']<=float(v['monotonic_s'])<=kinds['native_ui_idle_end'][0]['uptime_s']]
  rows[-1]['app_idle_baseline_footprint_bytes']=statistics.median(int(v['physical_footprint_bytes']) for v in idle) if idle else None
  rows[-1]['app_idle_baseline_samples']=len(idle)
  helper_samples=next((s['samples'] for s in sessions if s['name'].startswith('native-'+directory.name+'-') and kinds['native_ui_idle_begin'] and s['start']<=kinds['native_ui_idle_begin'][0]['uptime_s']<=s['end']),[])
  loaded_idle=[v for v in helper_samples if kinds['native_ui_idle_begin'] and kinds['native_ui_idle_end'] and kinds['native_ui_idle_begin'][0]['uptime_s']<=float(v['monotonic_s'])<=kinds['native_ui_idle_end'][0]['uptime_s']]
  rows[-1]['helper_loaded_idle_footprint_bytes']=statistics.median(int(v['physical_footprint_bytes']) for v in loaded_idle) if loaded_idle else None
  unload=r.load(directory/'idle-unload.json') if (directory/'idle-unload.json').exists() else {}
  after_unload=[v for v in samples if unload.get('unload_start_s',float('inf'))<=float(v['monotonic_s'])]
  rows[-1]['app_after_helper_unload_footprint_bytes']=statistics.median(int(v['physical_footprint_bytes']) for v in after_unload) if after_unload else None
  for phase in ['prompt','generation']:
   file=directory/f'cancel-{phase}.json';cancel=r.load(file) if file.exists() else {}
   rows[-1][phase+'_cancel_proven_phase']=cancel.get('phase_proven')
   rows[-1][phase+'_cancel_stream_close_s']=cancel.get('cancel_s')
   rows[-1][phase+'_cancel_runtime_idle_wait_s']=cancel.get('runtime_idle',{}).get('seconds')
   for label,source in [('helper',helper_samples),('app',samples)]:
    recovered=[v for v in source if cancel.get('recovery_sample_window_start_s',float('inf'))<=float(v['monotonic_s'])<=cancel.get('recovery_sample_window_end_s',-1)]
    rows[-1][label+'_'+phase+'_cancel_recovered_footprint_bytes']=statistics.median(int(v['physical_footprint_bytes']) for v in recovered) if recovered else None
  rows[-1]['actual_text_edits_verified']=len(kinds['text_edit_observed'])==5 and all(v.get('field_editor_found') and v.get('bound_input')==v.get('expected_input') for v in kinds['text_edit_observed'])
  rows[-1]['text_edit_dispatch_median_s']=statistics.median(v['edit_dispatch_s'] for v in kinds['text_edit_observed']) if kinds['text_edit_observed'] else None
  rows[-1]['replacement_started_during_loading']=any(v.get('first_request_was_loading') for v in kinds['rapid_replacement_requested'])
  cache=kinds['disk_cache_reopened'];rows[-1]['disk_cache_reopen_trials']=len(cache)
  rows[-1]['disk_cache_reopen_median_s']=statistics.median(v['seconds'] for v in cache) if cache else None
  rows[-1]['disk_cache_reopen_min_s']=min((v['seconds'] for v in cache),default=None)
  rows[-1]['disk_cache_reopen_max_s']=max((v['seconds'] for v in cache),default=None)
  rows[-1]['disk_cache_all_summaries_match']=bool(cache) and all(v['summary_matches'] for v in cache)
  rows[-1]['wrong_identity_hides_summary']=any(v['wrong_identity_hides_summary'] for v in kinds['cache_identity_checked'])
  config=r.load(directory/'native-config.json') if (directory/'native-config.json').exists() else {}
  for rawfile in directory.glob('native-*-raw.json'):
   raw=r.load(rawfile);ids={v['id'] for v in raw['source']};index=next((i for i,c in enumerate(config.get('cases',[])) if {v['id'] for v in c['reviews']}==ids),None)
   displayed_file=rawfile.with_name(rawfile.name.replace('-raw.json','-displayed.json'))
   displayed_summary=r.load(displayed_file) if displayed_file.exists() else {}
   generated=displayed_summary.get('generatedAt')
   # A repeated UI row can use the same fictional source bank. The generated
   # summary timestamp identifies its exact state update across professor IDs.
   after=[v for v in kinds['summary_view_state_observed'] if v['uptime_s']>=raw['generation_finished_uptime'] and generated is not None and v.get('generated_at_reference_s')==generated and v.get('report_view_enabled')]
   display.append({'variant':directory.name,'raw_path':str(rawfile.relative_to(run)),'raw_file_sha256':r.sha(rawfile),'generation_and_transport_s':raw['generation_finished_uptime']-raw['started_uptime'],'completion_to_observed_view_state_s':after[0]['uptime_s']-raw['generation_finished_uptime'] if after else None,'display_observed':bool(after),'note':'Includes validation/persistence/state scheduling; not compositor timing.'})
 write_csv(run/'native-workflow-comparison.csv',rows);write_csv(run/'native-display-timings.csv',display)

def analyze(run):
 events=jsonlines(run/'events.jsonl');power=jsonlines(run/'power-thermal.jsonl');background=jsonlines(run/'background-processes.jsonl')
 sessions=[]
 for path in (run/'sessions').glob('*/startup.json'):
  startup=r.load(path);resource=path.parent/'resources.csv'
  samples=resource_rows(resource)
  sessions.append({'name':path.parent.name,'start':float(samples[0]['monotonic_s']) if samples else 0,'end':float(samples[-1]['monotonic_s']) if samples else 0,'startup':startup,'samples':samples})
 trialrows=[];stage_rows=[]
 for path,row in review.outputs(run):
  if row.get('mode')=='native-direct':continue # Native workflow clocks and resources have their own tables.
  stages=[]
  for stagepath in row.get('stages',[]):
   file=run/stagepath
   if not file.exists():continue
   stage=r.load(file);stages.append(stage)
   timing=stage.get('timings') or {};start=stage.get('started_monotonic_s');end=stage.get('ended_monotonic_s')
   session=next((s for s in sessions if start is not None and s['start']-.2<=start<=s['end']+.2),None)
   samples=[v for v in session['samples'] if start<=float(v['monotonic_s'])<=end] if session and end else []
   observed=[v for v in power if start is not None and end is not None and start<=v['monotonic_s']<=end]
   prior=[v for v in power if start is not None and v['monotonic_s']<=start]
   if prior and start-prior[-1]['monotonic_s']<=30:observed.insert(0,prior[-1])
   def power_state(value):
    raw=value['power'].get('stdout','')
    return next((label for label in ['discharging','charging','finishing charge','charged'] if '; '+label+';' in raw),'other recorded state')
   power_states=sorted({power_state(v) for v in observed})
   competing=[v for v in background if start is not None and end is not None and start<=v['monotonic_s']<=end]
   preceding=[v for v in background if start is not None and v['monotonic_s']<=start]
   if preceding and start-preceding[-1]['monotonic_s']<=10:competing.insert(0,preceding[-1])
   active=[p for v in competing for p in v['external_inference_candidates'] if p['cpu_percent']>=5]
   busy={p['command'] for v in competing for p in v['other_cpu_busy']}
   stage_rows.append({'path':stagepath,'trial':str(path.relative_to(run)),'variant':row['variant'],'case':row['case'],'context':row.get('context'),'mode':row.get('mode'),'limit':review.output_budget(row,path),'stage':stage.get('stage'),'first_inference':stage.get('first_inference'),'prompt_tokens':stage.get('prompt_tokens'),'reserved_output_tokens':stage.get('output_limit'),'prompt_context_utilization':stage['prompt_tokens']/row['context'] if stage.get('prompt_tokens') is not None and row.get('context') else None,'prompt_plus_reservation_utilization':(stage['prompt_tokens']+stage.get('output_limit',0))/row['context'] if stage.get('prompt_tokens') is not None and row.get('context') else None,'prompt_token_count_match':stage.get('prompt_token_count_match'),'runtime_prompt_tokens':stage.get('runtime_prompt_tokens'),'prompt_tokens_per_second':timing.get('prompt_per_second'),'output_tokens':timing.get('predicted_n'),'generation_tokens_per_second':timing.get('predicted_per_second'),'template_s':stage.get('template_s'),'tokenization_s':stage.get('tokenization_s'),'first_generated_content_s':stage.get('first_generated_content_s'),'reported_first_visible_answer_s':stage.get('first_visible_answer_s'),'first_summary_text_arrival_s':first_summary_text(stage),'generation_request_s':stage.get('generation_request_s'),'complete_stage_s':stage.get('total_stage_s'),'helper_sampled_peak_rss_bytes':max((int(v['rss_bytes']) for v in samples),default=None),'helper_sampled_peak_footprint_bytes':max((int(v['physical_footprint_bytes']) for v in samples),default=None),'helper_cpu_s':(int(samples[-1]['cpu_ns'])-int(samples[0]['cpu_ns']))/1e9 if len(samples)>1 else None,'resource_samples':len(samples),'power_cohort':','.join(power_states) or 'unobserved','thermal_states':','.join(sorted({v['thermal_name'] for v in observed})),'error':stage.get('error'),'stopped_at_limit':bool((stage.get('stop') or {}).get('stopped_limit')),'session':session['name'] if session else None})
   stage_rows[-1].update(background_samples=len(competing),potential_competing_inference=bool(active) if competing else None,competing_inference_processes=' | '.join(sorted({p['command'] for p in active})),other_cpu_busy_processes=' | '.join(sorted(busy)),background_note='5-second OS recent CPU activity estimates; >=5% candidate CPU is possible activity, not proof. Other >=25% processes are recorded without attributing their resources to BYE.')
  usable=not row.get('error') and not row.get('structural_errors')
  first=stages[0].get('first_inference') if stages else None
  trialrows.append({'path':str(path.relative_to(run)),'variant':row['variant'],'case':row['case'],'partition':row.get('partition'),'context':row.get('context'),'mode':row.get('mode'),'limit':review.output_budget(row,path),'execution_failed':bool(row.get('error')),'structurally_valid':usable,'stopped_at_limit':any((v.get('stop') or {}).get('stopped_limit') for v in stages),'first_inference_pipeline':first,'pipeline_s':row.get('total_pipeline_s'),'observed_startup_inclusive_s':row.get('startup_inclusive_s') if first else None,'load_plus_warm_pipeline_s':row.get('startup_inclusive_s') if first is False else None,'timing_eligible':not row.get('recovered_from_stage_checkpoint') and not row.get('error'),'stages':len(stages),'error':row.get('error')})
 write_csv(run/'stage-metrics.csv',stage_rows);write_csv(run/'trial-metrics.csv',trialrows)
 grouped=collections.defaultdict(list)
 for row in trialrows:grouped[tuple(row[k] for k in ('variant','case','partition','context','mode','limit'))].append(row)
 aggregates=[]
 for key,values in sorted(grouped.items(),key=str):
  good=[v['pipeline_s'] for v in values if v['timing_eligible']]
  aggregates.append({**dict(zip(('variant','case','partition','context','mode','limit'),key)),'trials':len(values),'execution_failures':sum(v['execution_failed'] for v in values),'structural_failures':sum(not v['structurally_valid'] for v in values),'limit_stops':sum(v['stopped_at_limit'] for v in values),**{'pipeline_s_'+k:v for k,v in distribution(good).items()}})
 write_csv(run/'per-case-comparison.csv',aggregates)
 loads=[];hosts=[]
 for s in sessions:
  compat=s['startup'];path=run/'sessions'/s['name'];metal=r.load(path/'compatibility.json') if (path/'compatibility.json').exists() else {}
  log=(path/'server.log').read_text(errors='replace');internal=re.findall(r'load time\s*=\s*([0-9.]+) ms',log)
  loads.append({'session':s['name'],'variant':metal.get('model'),'context':metal.get('context'),'process_to_ready_s':compat['load_s'],'internal_load_s':float(internal[0])/1000 if internal else None,'filesystem_cache_state':'uncontrolled; no disk-cold claim','metal_observed':metal.get('metal_observed')})
  loads[-1]['flash_attention_lines']=' | '.join(line for line in log.splitlines() if 'flash_attn' in line or 'flash attention' in line.lower())
  loads[-1]['offload_lines']=' | '.join(line for line in log.splitlines() if 'offloaded' in line)
  host=resource_rows(path/'host-resources.csv')
  hosts.append({'session':s['name'],'variant':metal.get('model'),'context':metal.get('context'),'host_sampled_peak_rss_bytes':max((int(v['rss_bytes']) for v in host),default=None),'host_sampled_peak_footprint_bytes':max((int(v['physical_footprint_bytes']) for v in host),default=None),'host_lifetime_peak_footprint_bytes':max((int(v['lifetime_peak_footprint_bytes']) for v in host),default=None),'host_cpu_s':(int(host[-1]['cpu_ns'])-int(host[0]['cpu_ns']))/1e9 if len(host)>1 else None,'samples':len(host),'note':'BYEEvalHost supervisor; separate from llama-server and SwiftUI application. Shared mappings may overlap.'})
 write_csv(run/'load-metrics.csv',loads)
 write_csv(run/'host-metrics.csv',hosts)
 native_analysis(run,sessions)
 gaps=[]
 for before,after in zip(power,power[1:]):
  mono=after['monotonic_s']-before['monotonic_s']
  wall=(datetime.datetime.fromisoformat(after['utc'])-datetime.datetime.fromisoformat(before['utc'])).total_seconds()
  if mono>30 or abs(wall-mono)>2:gaps.append({'start_utc':before['utc'],'end_utc':after['utc'],'monotonic_gap_s':mono,'wall_gap_s':wall,'note':'Observation gap or clock divergence; possible sleep/scheduling/clock adjustment, not proof of cause.'})
 r.save(run/'observation-gaps.json',gaps)
 r.save(run/'analysis-limitations.json',{'utc':r.stamp(),'start_inclusive':'Observed only for first inference in each process. load_plus_warm_pipeline_s is a hypothetical sum, not an observed fresh-process request.','sampling':'100 ms sampled peaks can miss transients; lifetime footprint and exit RSS reported separately. CPU sample differences omit fractions at interval boundaries.','energy':'CPU seconds are activity, not energy. No joules claimed without available integrated counters.','power':'Power observer began partway through first development round; unobserved intervals remain labeled.','memory':'Helper, native app, and host accounting overlap potentially. Do not sum as unique physical memory or add Metal allocations to RSS.','statistics':'Three repeats support median/range, not reliable tail percentiles.','first_content':'First decoded SSE content can be JSON syntax, not an internal token timestamp or user-visible answer. Derived first_summary_text_arrival_s begins a JSON overview/text value after any exposed think block; native view-state delivery is separate.','quality':'Structural validity is not factual support. Semantic judgments remain a separate hash-bound artifact.','background_observation_rows':len(background),'power_observation_rows':len(power)})
 print('Analyzed',len(trialrows),'pipelines,',len(stage_rows),'stages,',len(loads),'loads')

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--run',type=Path);args=p.parse_args();analyze(args.run or Path(r.load(r.BASE/'latest.json')['run']))
