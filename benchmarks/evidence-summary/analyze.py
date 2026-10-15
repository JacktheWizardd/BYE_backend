#!/usr/bin/env python3
"""Summarize hash-bound exploratory reviews; never contacts a data provider."""
import statistics
import run


def main():
    decisions=run.load(run.BASE/'reviews.json')
    methods=['A-extractive','B-classifier','C-hybrid','D-finetuned','E-untuned-control']
    summary=[];samples=['# Saved-data evidence-first summary samples','','Private: real-review text remains local. Training cases are fit diagnostics, not independent evaluation.']
    for method in methods:
        rows=[run.load(p) for p in (run.BASE/method).glob('*.json')]
        evaluated=[r for r in rows if r.get('split')=='evaluation']
        for row in evaluated:
            decision=decisions[method][row['case']]
            assert decision['output_hash']==row['output_hash']==run.digest(row['text'])
            assert decision['evidence_hash']==row['evidence_hash']==run.digest(row['evidence'])
        judged=[decisions[method][r['case']] for r in evaluated]
        summary.append(dict(method=method,evaluation_cases=len(evaluated),fit_diagnostic_cases=len(rows)-len(evaluated),
            unsupported_cases=sum(not j['faithful'] for j in judged),unusable_cases=sum(not j['usable'] for j in judged),
            missed_conflict_cases=sum(not j['conflicts_preserved'] for j in judged),
            priority_covered=sum(j['covered'] for j in judged),priority_eligible=sum(j['eligible'] for j in judged),
            loaded_diagnostic_median_s=statistics.median(r['seconds'] for r in evaluated if r['case']!='sparseenglish'),
            fallback_cases=sum(r.get('fallback',False) for r in evaluated),
            raw_unsupported_cases=sum(j.get('raw_faithful') is False for j in judged)))
        for row in rows:
            samples+=['',f'## {method} / {row["case"]} / {row["split"]}', '',row.get('text',row.get('error','')), '',
                'Raw generation before fallback: '+row['raw_text'] if 'raw_text' in row else '',
                '', 'Source evidence:', '```json',__import__('json').dumps(row.get('evidence'),indent=2,ensure_ascii=False),'```']
    run.save(run.BASE/'SUMMARY.json',dict(methods=summary,source_corpus_sha256=run.sha(run.DATA/'corpus-full.json'),
        evaluation_cases=11,fit_diagnostics_per_method=10,output_files=105,training_steps=120,training_pairs=39,
        pcc_rmp_requests=0,pi_hardware_tested=False,original_heldout_inference_cases=0,
        reviewer='Codex exploratory source review; teacher-derived training targets, not independent human gold'))
    (run.BASE/'SAMPLES.md').write_text('\n'.join(samples)+'\n')
    print(__import__('json').dumps(summary,indent=2))


if __name__=='__main__':main()
