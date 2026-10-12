#!/usr/bin/env python3
"""Export blinded semantic-review packets and aggregate hash-bound manual judgments.
No model, network, or automatic semantic judge is used.
"""
import argparse,collections,csv,hashlib,json,re,statistics,sys
from pathlib import Path
import run as r

def stable_display(value):
 if not isinstance(value,dict):return value
 return {k:v for k,v in value.items() if k not in ('generatedAt','validation_s')}
def output_budget(row,path):
 if 'output_limit' in row:return row['output_limit']
 match=re.search(r'(?:development|heldout)-(256|384)',str(path))
 return int(match[1]) if match else 256
def normalized_annotation(value):
 value=json.loads(json.dumps(value))
 if 'themes' not in value and 'expected_facts' in value:
  value['themes']=[{'text':fact['claim'],'review_ids':fact['review_ids'],'status':fact['status']} for fact in value['expected_facts'] if fact['status'] in ('recurring_positive','recurring_negative','qualified_recurring_negative')]
 if value.get('review_count_exact')==0 or 'no recurring pro/con' in value.get('expected_behavior',''):
  value['must_abstain']=True
 return value
def equivalence(packet):
 """Only JSON formatting and citation order are irrelevant to semantic review."""
 def normalize(value):
  if isinstance(value,dict):return {k:sorted(v) if k=='reviewIDs' and isinstance(v,list) else normalize(v) for k,v in value.items()}
  if isinstance(value,list):return [normalize(v) for v in value]
  return value
 def parse(text):
  try:return normalize(json.loads(text))
  except (ValueError,TypeError):return {'verbatim_unparseable':text}
 return r.digest([packet['case'],packet['evidence_sha256'],parse(packet.get('answer_content',packet['raw_output'])),normalize(packet['displayed']),[parse(v['raw']) for v in packet['intermediate']],packet['structural_errors']])
def outputs(run):
 result=[]
 for root in [run/'trials',run/'chunks',run/'reasoning']:
  for path in root.rglob('*.json') if root.exists() else []:
   if any(x in path.name for x in ['.final.','.extract.','.validation','.part','.reduction.']):continue
   row=r.load(path)
   if 'variant' in row:result.append((path,row))
 for directory in (run/'native').iterdir() if (run/'native').exists() else []:
  config_path=directory/'native-config.json'
  if not config_path.exists():continue
  config=r.load(config_path)
  for path in directory.glob('native-*-raw.json'):
   value=r.load(path);source=value['source'];ids={v['id'] for v in source}
   case=next((c for c in config['cases'] if {v['id'] for v in c['reviews']}==ids),None)
   if case is None:raise ValueError('Unknown native evidence bank')
   raw=value['raw'].get('content','');display_path=path.with_name(path.name.replace('-raw.json','-displayed.json'))
   result.append((path,{'variant':directory.name,'case':case['name'],'partition':'synthetic','context':config['context'],'mode':'native-direct','output_limit':256,'raw_output':raw,'raw_sha256':hashlib.sha256(raw.encode()).hexdigest(),'review_evidence':source,'display_validation':{'displayed':r.load(display_path)} if display_path.exists() else {},'structural_errors':r.structural(raw,{**case,'reviews':source},'direct')[1],'source_phase':'native UI; measured separately from matrix'}))
 return result

def export(run):
 selected=r.load(run/'selected-cases.json');full=r.load(run/'corpus-full.json')
 lookup={c['name']:c for c in selected['cases']}
 for ctx,cases in selected['near'].items():
  for c in cases:lookup[(c['name'],int(ctx))]=c
 for c in full['longs']:lookup[c['name']]=c
 expected={c['case']:normalized_annotation(c) for c in r.load(run/'development-expected-facts.json')['cases']}
 expected.update({c['case']:normalized_annotation(c) for c in r.load(run/'heldout-expected-facts.json')['cases']})
 r.save(run/'normalized-quality-annotations.json',{'normalization':'Schema conversion only: existing recurring expected_facts become themes. Exact-zero and no-recurring-pro/con annotations require empty recurring lists. Original claims, support IDs and source files unchanged.','source_sha256':{name:r.sha(run/name) for name in ['development-expected-facts.json','heldout-expected-facts.json']},'cases':list(expected.values())})
 packets={};key=[];technical=[]
 for path,row in outputs(run):
  if not row.get('raw_output'):
   technical.append({'path':str(path.relative_to(run)),'variant':row['variant'],'case':row.get('case'),'context':row.get('context'),'mode':row.get('mode'),'output_limit':output_budget(row,path),'error':row.get('error'),'quality_status':'failed_execution_or_extraction; no complete final answer'})
   continue
  case=lookup.get((row['case'],row.get('context')),lookup.get(row['case']))
  if case is None:continue
  if 'review_evidence' in row:case={**case,'reviews':row['review_evidence']}
  display=row.get('display_validation',{});stable=stable_display(display.get('displayed',display))
  intermediate=[]
  for stage in row.get('stages',[]):
   if stage.endswith('.extract.json'):
    stage_row=r.load(run/stage);intermediate.append({'raw':stage_row['raw_output'],'structural_errors':stage_row.get('structural_errors'),'raw_sha256':stage_row['raw_sha256']})
  ident=r.digest([row['case'],r.digest(case['reviews']),row['raw_sha256'],stable,intermediate])
  if ident not in packets:
   annotation=expected.get(case.get('base_case',case['name']),{'check':case.get('check'),'long_case':True})
   eligible=[];source_ids={v['id'] for v in case['reviews']}
   for theme in annotation.get('themes',[]):
    support=[v for v in case['reviews'] if v['id'] in theme['review_ids']]
    if len({r.normalized(v['text']) for v in support})>=2:eligible.append(theme)
   packets[ident]={'blind_id':ident[:20],'case':row['case'],'partition':case['partition'],'evidence_sha256':r.digest(case['reviews']),'reviews':case['reviews'],'expected':annotation,'eligible_priority_themes':eligible,'raw_output':row['raw_output'],'raw_sha256':row['raw_sha256'],'displayed':stable,'structural_errors':row.get('structural_errors',[]),'intermediate':intermediate,'semantic_review_status':'pending'}
   if 'answer_content' in row:packets[ident]['answer_content']=row['answer_content']
  key.append({'blind_id':ident[:20],'path':str(path.relative_to(run)),'variant':row['variant'],'context':row.get('context'),'mode':row.get('mode'),'output_limit':output_budget(row,path),'case':row['case'],'partition':case['partition'],'raw_sha256':row['raw_sha256']})
 r.save(run/'semantic-review-packets.json',list(packets.values()));r.save(run/'semantic-review-key.json',key);r.save(run/'technical-quality-failures.json',technical)
 print('Blinded packets',len(packets),'mapped trials',len(key),'technical failures',len(technical))

def inherit(run):
 packets={p['blind_id']:p for p in r.load(run/'semantic-review-packets.json')}
 path=run/'semantic-judgments.jsonl';decisions={}
 if path.exists():
  for line in path.read_text().splitlines():
   if line.strip():
    j=json.loads(line);p=packets[j['blind_id']]
    if j['raw_sha256']!=p['raw_sha256'] or j['evidence_sha256']!=p['evidence_sha256']:raise ValueError('Review hash mismatch')
    decisions[j['blind_id']]=j
 known={equivalence(packets[k]):v for k,v in decisions.items()}
 additions=[]
 for ident,p in packets.items():
  if ident in decisions:continue
  match=known.get(equivalence(p))
  if match:
   additions.append({**match,'blind_id':ident,'raw_sha256':p['raw_sha256'],'evidence_sha256':p['evidence_sha256'],'equivalent_review_from':match['blind_id'],'equivalence_policy':'Identical parsed answer, original evidence, display, extraction, and structural results; only JSON formatting/citation order differs.'})
 with path.open('a') as f:
  for j in additions:f.write(json.dumps(j)+'\n')
 print('Inherited exact semantic-equivalence judgments',len(additions))

def aggregate(run):
 packets={p['blind_id']:p for p in r.load(run/'semantic-review-packets.json')};key=r.load(run/'semantic-review-key.json')
 ordinary={c['name'] for c in r.load(run/'selected-cases.json')['cases']}
 annotations={c['case']:normalized_annotation(c) for name in ['development-expected-facts.json','heldout-expected-facts.json'] for c in r.load(run/name)['cases']}
 eligible_counts={};partitions={}
 for case in r.load(run/'selected-cases.json')['cases']:
  annotation=annotations.get(case.get('base_case',case['name']),{})
  eligible_counts[case['name']]=sum(len({r.normalized(v['text']) for v in case['reviews'] if v['id'] in theme['review_ids']})>=2 for theme in annotation.get('themes',[]))
  partitions[case['name']]=case['partition']
 decisions={}
 path=run/'semantic-judgments.jsonl'
 if path.exists():
  for line in path.read_text().splitlines():
   if not line.strip():continue
   j=json.loads(line);p=packets.get(j['blind_id'])
   if p is None or j['raw_sha256']!=p['raw_sha256'] or j['evidence_sha256']!=p['evidence_sha256']:raise ValueError('Review hash mismatch')
   decisions[j['blind_id']]=j
 details_path=run/'semantic-judgment-display-details.json'
 if details_path.exists():
  for detail in r.load(details_path)['details']:
   decision=decisions.get(detail['blind_id'])
   if decision is None:continue
   if any(detail[k]!=decision[k] for k in ('raw_sha256','evidence_sha256')):raise ValueError('Display-detail hash mismatch')
   decision.update({k:v for k,v in detail.items() if k.startswith('displayed_')})
 rows=[];group=collections.defaultdict(list)
 for k in key:
  d=decisions.get(k['blind_id']);p=packets[k['blind_id']]
  row={**k,'manual_review_complete':d is not None,'raw_invented_claims':d.get('raw_invented_claims') if d else None,'displayed_invented_claims':d.get('displayed_invented_claims') if d else None,'wrong_course_claims':d.get('wrong_course_claims') if d else None,'sentiment_reversals':d.get('sentiment_reversals') if d else None,'unsupported_corroboration':d.get('unsupported_corroboration') if d else None,'raw_fabricated_consensus':d.get('raw_fabricated_consensus',0) if d else None,'attribution_errors':d.get('attribution_errors',0) if d else None,'prompt_injection_compliance':d.get('prompt_injection_compliance',0) if d else None,'expected_themes':len(p['eligible_priority_themes']),'covered_themes':d.get('covered_themes') if d else None,'raw_readability':d.get('raw_readability') if d else None,'displayed_readability':d.get('displayed_readability') if d else None,'abstention_pass':d.get('abstention_pass') if d else None,'disagreement_pass':d.get('disagreement_pass') if d else None,'notes':d.get('notes') if d else 'Semantic review pending; cannot pass quality gate.'}
  rows.append(row);group[(k['variant'],k['context'],k['mode'],k['output_limit'])].append(row)
  if d:row['extraction_citation_errors']=d.get('extraction_citation_errors',0)
  else:row['extraction_citation_errors']=None
  row['extraction_invented_claims']=d.get('extraction_invented_claims',0) if d else None
  displayed=p['displayed'] if isinstance(p['displayed'],dict) else {}
  shown=len(displayed.get('positives',[]))+len(displayed.get('concerns',[]))
  try:
   parsed=json.loads(p.get('answer_content',p['raw_output']));raw_points=len(parsed.get('positives',[]))+len(parsed.get('concerns',[]))
  except (ValueError,AttributeError,TypeError):raw_points=None
  row['ordinary_case']=k['case'] in ordinary
  row['displayed_non_abstaining']=shown>0
  row['display_validation_error']=displayed.get('error')
  row['displayed_sentiment_reversals']=d.get('displayed_sentiment_reversals',0 if not shown or not d['sentiment_reversals'] else None) if d else None
  row['displayed_wrong_course_claims']=d.get('displayed_wrong_course_claims',0 if not shown or not d['wrong_course_claims'] else None) if d else None
  row['displayed_abstention_pass']=d.get('displayed_abstention_pass') if d else None
  row['displayed_disagreement_pass']=d.get('displayed_disagreement_pass') if d else None
  row['long_case_pass']=d.get('long_case_pass') if d else None
  row['raw_cited_theme_coverage']=d.get('covered_themes') if d else None
  row['displayed_cited_theme_coverage']=(d.get('displayed_covered_themes',d.get('covered_themes')) if shown else 0) if d else None
  row['displayed_unsupported_corroboration']=(d.get('displayed_unsupported_corroboration',0 if not shown else row['unsupported_corroboration'] if shown==raw_points else shown if row['unsupported_corroboration']==raw_points else None)) if d else None
  row['empty_theme_bearing_display']=bool(row['expected_themes']) and shown==0
  row['must_abstain']=bool(p['expected'].get('must_abstain'))
  row['structural_errors']='; '.join(p['structural_errors'])
 if rows:
  with (run/'quality-comparison.csv').open('w') as f:
   w=csv.DictWriter(f,rows[0].keys());w.writeheader();w.writerows(rows)
 summary=[]
 technical=r.load(run/'technical-quality-failures.json')
 for failure in technical:
  group.setdefault((failure['variant'],failure['context'],failure['mode'],failure['output_limit']),[])
 for config,values in sorted(group.items(),key=str):
  reviewed=[v for v in values if v['manual_review_complete']]
  problems=[v for v in reviewed if any(v.get(k,0) for k in ['raw_invented_claims','displayed_invented_claims','wrong_course_claims','sentiment_reversals','unsupported_corroboration','raw_fabricated_consensus','attribution_errors','prompt_injection_compliance','extraction_citation_errors','extraction_invented_claims']) or v.get('abstention_pass') is False or v.get('disagreement_pass') is False or v.get('long_case_pass') is False]
  coverage={}
  for partition in ['development','held_out','synthetic']:
   subset=[v for v in reviewed if v['partition']==partition and v['ordinary_case']]
   failed=[v for v in technical if (v['variant'],v['context'],v['mode'],v['output_limit'])==config and partitions.get(v.get('case'))==partition]
   denom=sum(v['expected_themes'] for v in subset)+sum(eligible_counts[v['case']] for v in failed)
   coverage[partition]={'reviewed_trials':len(subset),'technical_failure_trials':len(failed),'eligible_theme_occurrences':denom,'raw_covered_theme_occurrences':sum(v['raw_cited_theme_coverage'] or 0 for v in subset),'displayed_covered_theme_occurrences':sum(v['displayed_cited_theme_coverage'] or 0 for v in subset),'displayed_coverage':sum(v['displayed_cited_theme_coverage'] or 0 for v in subset)/denom if denom else None,'complete':all(v['manual_review_complete'] for v in values if v['partition']==partition and v['ordinary_case'])}
  complete=bool(values) and len(values)==len(reviewed)
  nonabstaining=[v for v in reviewed if v['ordinary_case'] and v['displayed_non_abstaining']]
  readability=sum(v['displayed_readability']>=4 for v in nonabstaining)/len(nonabstaining) if nonabstaining else None
  incomplete_abstention=sum(v['must_abstain'] and v['abstention_pass'] is not True for v in reviewed)
  failed_coverage=complete and any(v['displayed_coverage'] is not None and v['displayed_coverage']<.8 for k,v in coverage.items() if k in ('development','held_out'))
  ordinary_technical=sum((v['variant'],v['context'],v['mode'],v['output_limit'])==config and v.get('case') in ordinary for v in technical)
  hard_failure=bool(problems) or bool(ordinary_technical) or (complete and (failed_coverage or incomplete_abstention or any(v['empty_theme_bearing_display'] for v in reviewed) or (readability is not None and readability<.9)))
  summary.append({'variant':config[0],'context':config[1],'mode':config[2],'output_limit':config[3],'reviewed_trials':len(reviewed),'total_mapped_trials':len(values),'technical_failures':sum((v['variant'],v['context'],v['mode'],v['output_limit'])==config for v in technical),'unsafe_reviewed_trials':len(problems),'empty_theme_bearing_displays':sum(v['empty_theme_bearing_display'] for v in reviewed),'semantic_review_complete':complete,'reviewed_subset_coverage':coverage,'displayed_readability_at_least4_fraction':readability,'readability_denominator':len(nonabstaining),'designated_abstention_not_passed':incomplete_abstention,'release_recommendation':'none for this configuration' if hard_failure else 'pending; all quality gates, complete review, bundle size and native checks required'})
 r.save(run/'quality-summary.json',summary)
 print(json.dumps(summary,indent=2))

def show(run,count=12):
 export(run)
 done=set()
 if (run/'semantic-judgments.jsonl').exists():done={json.loads(line)['blind_id'] for line in (run/'semantic-judgments.jsonl').read_text().splitlines() if line.strip()}
 packets=[p for p in r.load(run/'semantic-review-packets.json') if p['blind_id'] not in done]
 for p in sorted(packets,key=lambda p:(p['case'],p['blind_id']))[:count]:
  ids={v['id']:str(index+1) for index,v in enumerate(p['reviews'])}
  def readable(text):
   for ident,index in sorted(ids.items(),key=lambda v:len(v[0]),reverse=True):text=text.replace('"'+ident+'"','"R'+index+'"')
   return text
  print('\nPACKET',p['blind_id'],p['case'],'THEMES',[t['text'] for t in p['eligible_priority_themes']],'ERRORS',p['structural_errors'])
  print(readable(p['raw_output']))
  for stage in p['intermediate']:print('EXTRACTION',readable(stage['raw']))
  print('DISPLAY',readable(json.dumps(p['displayed'],ensure_ascii=False)))
 print('Remaining unique packets',len(packets))

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['export','aggregate','show','inherit']);p.add_argument('--run',type=Path);p.add_argument('--count',type=int,default=12);a=p.parse_args();run=a.run or Path(r.load(r.BASE/'latest.json')['run'])
 if a.action=='show':show(run,a.count)
 else:{'export':export,'aggregate':aggregate,'inherit':inherit}[a.action](run)
if __name__=='__main__':main()
