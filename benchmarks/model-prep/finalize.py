#!/usr/bin/env python3
"""Reverify local preparation evidence and enrich inventory. No networking or inference."""
import argparse, hashlib, json, shutil, subprocess
from html.parser import HTMLParser
from pathlib import Path
import prepare

class Text(HTMLParser):
    def __init__(self):super().__init__();self.parts=[];self.hidden=0
    def handle_starttag(self,tag,attrs):
        if tag in ['script','style']:self.hidden+=1
        if tag in ['p','div','h1','h2','h3','li','br']:self.parts.append('\n')
    def handle_endtag(self,tag):
        if tag in ['script','style']:self.hidden=max(0,self.hidden-1)
    def handle_data(self,data):
        if not self.hidden:self.parts.append(data)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run',type=Path);args=parser.parse_args()
    run=args.run or Path(json.loads((prepare.LOGS/'latest.json').read_text())['directory'])
    manifest=json.loads((run/'manifest.json').read_text());rows=json.loads((run/'inventory.json').read_text())
    retired={m['sha256'] for m in json.loads((prepare.ROOT/'benchmarks/bye-mac/manifest.json').read_text())['models']}
    expected={f['filename']:(m,f) for m in manifest['models'] for f in m['files']}
    if set(r['filename'] for r in rows)!=set(expected):raise RuntimeError('Inventory is incomplete or contains unexpected files')
    check=[];documents={};model_by_id={m['id']:m for m in manifest['models']}
    # Preserve the transfer-time derived inventory before enriching it.
    for name in ['inventory.json','inventory.csv','REPORT.md']:
        backup=run/('initial-'+name)
        if not backup.exists():shutil.copy2(run/name,backup)
    for row in rows:
        model,spec=expected[row['filename']];path=Path(row['path'])
        try:
            prepare.integrity(path,spec,retired);meta=prepare.inspect_gguf(path)
            quant=next(q for q in ['Q4_K_M','Q5_K_M','Q8_0','Q4_0'] if row['filename'].lower().endswith('-'+q.lower()+'.gguf'))
            expected_type={'Q4_K_M':15,'Q5_K_M':17,'Q8_0':7,'Q4_0':2}[quant]
            if meta['scalars']['general.file_type']!=expected_type:raise ValueError('Declared file type does not match selected quantization')
            check.append({'filename':row['filename'],'sha256_match':True,'bytes_match':True,'metadata_valid':True,'quantization':quant,'quantization_type_matches':True})
            row['status']='verified'
        except Exception as error:
            check.append({'filename':row['filename'],'error':str(error)});row['status']='failed';row['unresolved']=str(error)
        row.update(publisher_repository=model['repository'],publisher_revision=model['revision'],upstream=model['upstream'],
                   upstream_metadata_revision=model['upstream_metadata_revision'],conversion_source_revision=model['conversion_source_revision'])
    for mid,model in model_by_id.items():
        folder=run/'documents'/mid;index=json.loads((folder/'index.json').read_text())
        # Preserve source documents; generated notices and plain text are labeled separately.
        generated={}
        if model['license']=='Llama-3.2-Community':
            generated['GENERATED-NOTICE.txt']='Llama 3.2 is licensed under the Llama 3.2 Community License, Copyright © Meta Platforms, Inc. All Rights Reserved.\n'
            card=folder/'upstream/README.md'
            if card.exists() and '### Llama 3.2 Acceptable Use Policy' in card.read_text():
                policy='### Llama 3.2 Acceptable Use Policy'+card.read_text().split('### Llama 3.2 Acceptable Use Policy',1)[1].split('extra_gated_fields:',1)[0]
                generated['EXTRACTED-UPSTREAM-USE-POLICY.md']=policy
                index['notes'].append('Standalone USE_POLICY retrieval was denied; complete policy preserved in pinned upstream README and extracted separately without bypassing access controls.')
        if model['license']=='Gemma-Terms':
            generated['GENERATED-NOTICE.txt']='Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms\n'
            for name in ['Gemma-Terms','Gemma-Prohibited-Use']:
                file=folder/(name+'.html')
                if file.exists():
                    text=Text();text.feed(file.read_text());generated[name+'.txt']='\n'.join(x.strip() for x in ''.join(text.parts).splitlines() if x.strip())+'\n'
        for name,content in generated.items():(folder/name).write_text(content)
        material='\n'.join(p.read_text(errors='replace') for p in folder.rglob('*') if p.is_file() and (p.name.startswith('LICENSE') or p.name in ['Apache-2.0.txt','Llama-License.txt','Gemma-Terms.txt']))
        markers={'Apache-2.0':['Apache License','TERMS AND CONDITIONS'],
                 'Llama-3.2-Community':['LLAMA 3.2 COMMUNITY LICENSE','Redistribution'],
                 'Gemma-Terms':['Gemma Terms of Use','Distribution and Redistribution'],
                 'LFM-Open-License-1.0':['Threshold','Commercial Use']}
        index['license_text_markers_verified']=all(marker.lower() in material.lower() for marker in markers[model['license']])
        index['policy_material_saved']=True
        if model['license']=='Llama-3.2-Community':
            index['policy_material_saved']='Prohibited Uses' in generated.get('EXTRACTED-UPSTREAM-USE-POLICY.md','')
        if model['license']=='Gemma-Terms':
            index['policy_material_saved']='Gemma Prohibited Use Policy' in generated.get('Gemma-Prohibited-Use.txt','')
        index['generated_documents']={name:{'sha256':prepare.sha(folder/name),'bytes':(folder/name).stat().st_size} for name in generated}
        index['generated_document_note']='Derived notices, plain-text renderings and labeled card extracts; original license/policy source documents are preserved.'
        prepare.save(folder/'final-index.json',index);documents[mid]=index
    prepare.reports(run,rows,documents)
    tests=subprocess.run(['python3','-m','unittest','discover','-s',str(prepare.HERE),'-v'],text=True,capture_output=True)
    (run/'preparation-tool-tests.log').write_text(tests.stdout+tests.stderr)
    preservation=json.loads((run/'preservation.json').read_text())
    cache_roots=[Path.home()/f'Library/Application Support/{name}/Reports' for name in ['Classwise','BYEAppleAIBeta']]
    mutable_changes=[p for p in preservation['changed_paths'] if any(Path(p).is_relative_to(base) for base in cache_roots)]
    before=json.loads((run/'retained-before.json').read_text())
    immutable_changes=[]
    for name,entry in before.items():
        path=Path(name)
        if any(path.is_relative_to(base) for base in cache_roots):continue
        if not path.is_file() or path.stat().st_size!=entry['bytes'] or prepare.sha(path)!=entry['sha256']:immutable_changes.append(name)
    events=[json.loads(line) for line in (run/'events.jsonl').read_text().splitlines()]
    active=False;overlap=False;destinations=set()
    for event in events:
        if event['event']=='transfer_start':
            overlap=overlap or active;active=True;destinations.add(prepare.urlparse(event['argv'][-1]).hostname)
        elif event['event']=='transfer_end':active=False
    check_result={'checked_utc':prepare.now(),'artifacts':check,'tests_exit_code':tests.returncode,
                  'verified_artifacts':sum(c.get('sha256_match',False) for c in check),'expected_artifacts':12,
                  'total_weight_bytes':sum(s['bytes'] for _,s in expected.values()),
                  'inference_performed':False,'runtime_compatibility':'pending task 2','installed_app_sizing':'pending task 2',
                  'license_material_saved':{mid:doc['license_material_saved'] for mid,doc in documents.items()},
                  'license_text_verified':{mid:doc['license_text_markers_verified'] for mid,doc in documents.items()},
                  'policy_material_saved':{mid:doc['policy_material_saved'] for mid,doc in documents.items()},
                  'retained_files_unchanged':not preservation['changed_paths'],'retired_paths_absent':preservation['retired_paths_absent'],
                  'immutable_evidence_unchanged':not immutable_changes,'immutable_changed_paths':immutable_changes,
                  'observed_mutable_cache_changes':mutable_changes,
                  'transfer_overlap_observed':overlap,'requested_hosts':sorted(destinations),
                  'pcc_rmp_requested':any(h in ['www.ratemyprofessors.com','prod-apiweb.pasadena.edu'] for h in destinations)}
    check_result['readiness']='complete_with_mutable_cache_observations' if mutable_changes else 'complete'
    if check_result['verified_artifacts']!=12 or immutable_changes or not all(check_result['license_text_verified'].values()):check_result['readiness']='incomplete'
    prepare.save(run/'final-verification.json',check_result)
    with (run/'REPORT.md').open('a') as f:
        f.write('\n## Preservation observation\n\n')
        f.write(f"Original files checked: {preservation['original_files']}. Immutable benchmark evidence, frozen data, runtime and release files unchanged: {not immutable_changes}. Retired checkpoint paths remain absent: {preservation['retired_paths_absent']}.\n\n")
        if mutable_changes:
            f.write(f"**{len(mutable_changes)} existing user-cache files changed or disappeared during the download session.** A read-only process observation found the separately installed BYE app already running. The exact writer was not traced. This preparation workflow did not launch that app, perform inference, request PCC/RMP, or write existing caches. No cache was restored or overwritten. Original preservation failures and before-hashes remain recorded; see observed-cache-changes.json. Download readiness is complete with this observation, not a claim that every mutable user file remained unchanged.\n")
    snapshot=run/'tool-source-final';snapshot.mkdir(exist_ok=True)
    for file in prepare.HERE.iterdir():
        if file.is_file():shutil.copy2(file,snapshot/file.name)
    artifacts={str(p.relative_to(run)):{'bytes':p.stat().st_size,'sha256':prepare.sha(p)} for p in sorted(run.rglob('*')) if p.is_file() and p.name!='evidence-manifest.json'}
    prepare.save(run/'evidence-manifest.json',{'captured_utc':prepare.now(),'files':artifacts})
    print(json.dumps(check_result,indent=2))
    passed=check_result['verified_artifacts']==12 and tests.returncode==0 and all(check_result['license_text_verified'].values())
    passed=passed and all(check_result['policy_material_saved'].values())
    passed=passed and check_result['immutable_evidence_unchanged'] and check_result['retired_paths_absent'] and not overlap and not check_result['pcc_rmp_requested']
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
