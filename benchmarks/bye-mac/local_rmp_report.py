#!/usr/bin/env python3
"""Render private cached-data results and persist agent semantic observations."""
import csv
import hashlib
import json
import statistics as s
from pathlib import Path
import local_rmp as r
import benchmark as b

NOTES={
'lfm':{
'ethnic14':('Unfair/unclear grading appears under positives. Textbook-link point cites R4, which does not mention a textbook. Concern combines expectations/feedback from R1 with R3 without support for every clause.','Misses differing email responsiveness; overview reduces recurring grading complaints to one student.'),
'eth14':('No-penalty late work cites R1/R4, but R4 explicitly reports a three-point penalty. Easy/fun online experience is placed under concerns and cites R4 without that evidence.','Does not preserve the late-penalty conflict; adds a recurring concern where none is corroborated.'),
'cs2':('Lively/patient claim cites generic praise R4; support/barrier-removal claim cites workload-only R5. Unclear lectures cite R2, which instead discusses hostile behavior.','Does not provide a correctly cited recurring helpful/clear-teaching theme from R3/R6.'),
'math55':('Helpful-book point is sourced from R2 but cites R3/R5. Negative reviews from others is not a recurring first-hand concern supported by R1/R2.','Omits well-corroborated exam/practice alignment and fast grading; does not describe grading disagreement.'),
'english1b':('Thoughtful-feedback point cites R4, which describes help/extensions rather than feedback. Rushed/stressful concern cites R3 without either claim.','Fails to flag the American Literature 030B body versus ENGL001B source-label conflict and near-duplicate R1/R2.'),
'chem22':('Scary/hard-to-ask-for-help experience is a pro. Extra-credit/heavy-exam-weight claim cites R6 without those facts. Weekly-unfair-quiz concern cites R4/R5 without weekly-quiz support.','Does not preserve mixed difficulty reports or identify a correctly cited preparation/extra-credit theme.'),
'sparseenglish':('Empty theme lists are appropriate, but overview invents mixed experience and varied teaching style from a single review.','Does not give the required insufficient-evidence summary.'),
'cs2-long':('Negative unclear-lecture text appears under positives and cites R3, which praises clear explanation. Curriculum-adjustment claim originates in R9, not cited R13/R14. Recurring unclear-lecture concern cites favorable R15.','Overview drops the unfavorable side of the mixed teaching/interaction reports; useful support/extra-credit themes are not faithfully cited.'),
'chem22-long':('Extra-credit/heavy-exam-weight point cites R10 without extra credit. Preparation point cites R15, which instead criticizes lack of help. Negative-comments concern cites a favorable R13.','Does not preserve conflicting grading/late-penalty/approachability experiences; overview is not a representative synthesis.')},
'qwen':{
'ethnic14':('Invents structured discussion environment. Available-for-email pro cites R3, which explicitly says emails were not answered.','Correctly notices harsh grading in overview but fails to preserve email conflict; pros lack corroboration.'),
'eth14':('Safe-space point is only in R1, not R4. Slow-grading/significant-late-penalty concern combines disjoint evidence and contradicts no-penalty R1. Online-versus-in-person comparison is only R2, not R6.','Does not preserve late-work disagreement; elevates isolated experiences into recurring concerns.'),
'cs2':('Structure/support point cites workload-only R5. Frequent-hostility point extends isolated R2 using R1, which is about lecture quality. Unclear/boring-lecture point cites wholly favorable R4.','Overview recognizes mixed teaching experiences but supporting pros/cons lack accurate paired citations.'),
'math55':('Excellent-lectures-and-notes point adds notes to R1; lenient-grading point cites R6 without an explicit leniency report. Fast-pace concern cites R5 without pacing evidence. Lenient-or-unfair grading appears under concerns without cited unfairness.','Omits the strongest exam/practice alignment and fast-feedback themes; weakens actual grading disagreement.'),
'english1b':('Exceptional-feedback point cites R6 without feedback. Finance-course concern is isolated R3 but cites unrelated R4. R1/R2 rushed-course evidence describes American Literature 030B despite ENGL001B label.','Does not flag course-label/body mismatch or near-duplicate evidence; flexibility/help has some support but output is not fully reliable.'),
'chem22':('Clear explanation/extra-credit pro cites R6 without extra credit. Well-structured lectures cite R5, which reports unclear lectures. Extremely hard to pass overstates cited R4.','Approachability concern has support in R1/R4, but difficulty/clarity conflicts and paired support are mishandled elsewhere.'),
'sparseenglish':('Invents enthusiasm, lively discussions, unclear grading and academic-rigor claims; repeats R1 to manufacture two citations.','Violates both sparse-evidence and distinct-source rules; structurally rejected.'),
'cs2-long':('Project-guidance claim goes beyond R15/R16. Personal/career-help claim cites R14/R18, which do not mention career help. Unclear/repetitive lectures cite R2 without lecture evidence. Hostile/rude concern cites favorable R3.','Overview recognizes mixed experiences but citations do not support full claims; 256-token output truncates before closing JSON.'),
'chem22-long':('Basic-to-advanced progression is invented. Extra-credit/flexible-grading point cites R32 without extra credit. No-notes/study-guide concern cites R5 without that evidence; lack of all notes overstates the sources.','Fails to preserve opposed reports on flexibility/approachability and exam alignment; 256-token output truncates.')},
'smol':{
'ethnic14':('Tough/unfair/stressful experiences are placed under positives, while claiming insufficient evidence despite six reviews.','Fails to synthesize recurring grading/workload concerns and conflicting responsiveness.'),
'eth14':('No-penalty late-work statement is only R1 but cites R2; weekly discussions/quizzes are placed under concerns with unsupported R2 citation.','Incorrect insufficient-evidence overview; misses explicit late-penalty conflict and recurring support.'),
'cs2':('Informative lectures cite R1/R2 although R1 criticizes lectures. Extra-credit/support point cites R3/R4 without extra credit. Helpful high standards are a concern with workload-only R5 citation.','Incorrect insufficient-evidence overview; polarity and paired citations fail.'),
'math55':('Excellent lectures cite R2, which reports difficulty understanding them. Knowledgeable/sassy point cites R2/R3 rather than R1. Fair/easy tests and lenient grading are placed under concerns.','Incorrect insufficient-evidence overview; misses exam alignment and fast grading.'),
'english1b':('Writing-feedback point cites R3/R4 without writing-feedback evidence. Willingness to help is categorized as a concern and cites R6 without support.','Incorrect insufficient-evidence overview; does not flag course/body mismatch or near duplicates.'),
'chem22':('Invents electronics allowed, reversing multiple no-electronics reports. Easy-lab-grading point is from R6 but cites R1/R2. Difficult/scary claims cite R2/R3 despite favorable experiences there.','Incorrect insufficient-evidence overview; reverses policy evidence and mishandles difficulty conflicts.'),
'sparseenglish':('Overview correctly says insufficient evidence, but model still generates pro/con themes using R1 twice.','Sparse and distinct-source rules fail; structurally rejected.'),
'cs2-long':('Copies output instructions into overview. Negative lecture experience is a pro; mandatory extra credit is invented. All detailed points have mismatched or contradictory source pairs.','No usable summary; mixed teaching/support evidence is not synthesized.'),
'chem22-long':('Extra-credit/lab-partner claim cites R1/R2 without lab-partner evidence. Accommodating/helpful claim cites R2/R3 without those full claims. Caring/answering-questions experience is placed under concerns.','Incorrect insufficient-evidence overview with 34 reviews; conflict synthesis and citation support fail.')}
}


def main():
    root=r.OUT
    rows=json.loads((root/'results.json').read_text())
    extra=json.loads((root/'long384/results.json').read_text())
    cases={c['name']:c for c in json.loads((root/'cases.json').read_text())}
    peaks=json.loads((root/'memory-peaks.json').read_text())
    judgments=[];outputs=['# Cached RMP — exact model outputs','',
        'Private local results. Source labels and citations map to `cases.json`; no RMP or PCC request was sent. Grammar controls JSON shape, not factual correctness. These are experimental outputs, not verified instructor descriptions.','']
    for name,case in cases.items():
        outputs += ['## '+case['profile_name']+' — '+case['course']+' ('+name+')','',
                    f"{len(case['reviews'])} reviews analyzed; {case['matching_course_reviews']} matching reviews in chosen cache snapshot. Cached at {case['cached_at']}.",'']
        for key in ['lfm','qwen','smol']:
            matching=[x for x in rows if x['model']==key and x['case']==name]
            assert len(matching)==3
            assert len({x['raw_output'] for x in matching})==1
            row=matching[0];findings,missing=NOTES[key][name]
            judgments.append(dict(model=key,case=name,output_limit=256,repetitions=3,
                                  output_sha256=hashlib.sha256(row['raw_output'].encode()).hexdigest(),
                                  syntax_and_distinct_ids_valid=not row['validation_errors'],
                                  factual_and_citation_quality='poor',fully_acceptable=False,
                                  concrete_errors=findings,missing_details_or_conflicts=missing,
                                  readability='incomplete JSON' if row['stop_type']=='limit' else 'readable JSON; several points exceed requested brevity',
                                  method='Agent semantic review against supplied local evidence; not independent human review'))
            outputs += ['### '+key,'']
            if row['parsed_output']:
                value=row['parsed_output'];outputs += ['**Summary:** '+value['overview'],'','**Pros:**','']
                outputs += ['- '+p['text']+' ['+', '.join(p['reviewIDs'])+']' for p in value['positives']] or ['- None']
                outputs += ['','**Cons:**','']
                outputs += ['- '+p['text']+' ['+', '.join(p['reviewIDs'])+']' for p in value['concerns']] or ['- None']
            else:outputs += ['Incomplete JSON; raw output preserved in the run file.']
            outputs += ['','**Quality:** '+findings+' '+missing,'']
            if name.endswith('-long'):
                follow=[x for x in extra if x['model']==key and x['case']==name]
                assert len(follow)==3 and len({x['raw_output'] for x in follow})==1
                newer=follow[0]
                judgments.append(dict(model=key,case=name,output_limit=384,repetitions=3,
                                      output_sha256=hashlib.sha256(newer['raw_output'].encode()).hexdigest(),
                                      syntax_and_distinct_ids_valid=not newer['validation_errors'],
                                      factual_and_citation_quality='poor',fully_acceptable=False,
                                      concrete_errors=findings.replace('; 256-token output truncates before closing JSON.','.').replace('; 256-token output truncates.','.'),
                                      missing_details_or_conflicts=missing.replace('; 256-token output truncates before closing JSON.','.').replace('; 256-token output truncates.','.'),
                                      note='384-token follow-up removes Qwen truncation but does not repair source support or polarity'))
                outputs += ['**384-token follow-up (exact JSON):**','','```json',newer['raw_output'],'```','']
    (root/'OUTPUTS.md').write_text('\n'.join(outputs)+'\n')
    b.save(root/'quality-judgments.json',judgments)
    fields=['model','case','output_limit','syntax_and_distinct_ids_valid','fully_acceptable','concrete_errors','missing_details_or_conflicts']
    with (root/'quality.csv').open('w') as file:
        writer=csv.DictWriter(file,fields,extrasaction='ignore');writer.writeheader();writer.writerows(judgments)
    report=['# Cached RMP benchmark — October 11, 2026','',
        '**All three models still need quality work before release.** This test used real RMP text already cached on this Mac to generate summaries, pros and cons. Every unique case has at least one material source-support, polarity, sparse-evidence, or course-attribution defect. Valid JSON and valid-looking citation IDs do not establish factual reliability.','',
        '## Local-only execution','',
        '- No PCC schedule or RMP request was sent. No model or runtime was downloaded. The Python controller permits only 127.0.0.1 socket connections and bypasses proxies. Every native inference host/helper runs under an OS sandbox denying network access except localhost, with llama.cpp `--offline` and local GGUF paths. Both network audit files record zero external connections.',
        '- Read fixed snapshots from existing Classwise/BYEAppleAIBeta report caches. Original selected cache-file SHA-256 hashes remained unchanged through the primary run. No source cache was refreshed or edited.',
        '- Seven profiles; 37 selected reviews across seven short cases, plus 23-review CS and 34-review chemistry long cases. Snapshot contains 114 matching-course cached reviews overall. Sources were cached October 9–10; they are historical local snapshots, not complete/current RMP coverage. Completeness flags and pagination metadata are preserved without reinterpreting a 50-review cap as all reviews.',
        '- 81 primary requests: three models × nine cases × three rotated sequential rounds. Eighteen additional long-input requests use a 384-token ceiling to diagnose truncation. All repeated outputs are byte-identical within a case/model/budget.',
        '- Raw real-review snapshots, outputs, profiler logs and this report stay in ignored `.local-docs`, separate from repository-tracked synthetic benchmark artifacts.','',
        '## Time and resources','',
        'Apple M5 / 16 GB / macOS 26.6.2; same pinned llama.cpp b11559 and verified GGUFs as the earlier benchmark. Four inference threads, full Metal offload, greedy decoding, one request at a time, prompt caching disabled. Short context 2,048; long context 4,096. Native JSON-schema constraints limit shape/ID vocabulary. Main ceiling 256 output tokens. Latency includes chat-template rendering, token-count preflight and inference; source-snapshot preparation is excluded.','',
        '| Model | Short total median (range), s | Long total median, s | First content median, s | Prompt tok/s | Output tok/s | Peak runtime RSS MB | Runtime peak footprint MB | Host/helper footprint proxy MB |',
        '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for key in ['lfm','qwen','smol']:
        a=[x for x in rows if x['model']==key and x['context']==2048];long=[x for x in rows if x['model']==key and x['context']==4096];m=[x for x in peaks if '-'+key+'-' in x['run']]
        t=[x['total_summary_seconds'] for x in a]
        report.append(f"| {key} | {s.median(t):.3f} ({min(t):.3f}–{max(t):.3f}) | {s.median(x['total_summary_seconds'] for x in long):.3f} | {s.median(x['first_token_seconds'] for x in a):.3f} | {s.median(x['timings']['prompt_per_second'] for x in a):.0f} | {s.median(x['timings']['predicted_per_second'] for x in a):.0f} | {max(x['runtime_lifetime_peak_rss'] for x in m)/1e6:.1f} | {max(x['runtime_peak_footprint'] for x in m)/1e6:.1f} | {max(x['host_helper_sampled_peak_footprint'] for x in m)/1e6:.1f} |")
    report+=['', 'RSS includes memory-mapped weights; physical footprint has different macOS accounting. Summed host/helper footprint is a sampled process-accounting proxy with possible shared-page overlap, not unique system unified-memory use. This runs the native measurement host, not the production browser/UI workflow. Full BYE app memory and battery energy remain unmeasured. Metal buffer logs are not added to RSS/footprint. Power and system snapshots are saved locally.','',
        '| Model | Fresh-process readiness median, s | Syntax + distinct citations valid at 256 tokens | Fully acceptable unique cases by agent review | Long total median at 384 tokens, s |',
        '|---|---:|---:|---:|---:|']
    for key in ['lfm','qwen','smol']:
        a=[x for x in rows if x['model']==key];e=[x for x in extra if x['model']==key]
        report.append(f"| {key} | {s.median(x['load_seconds'] for x in a):.3f} | {sum(not x['validation_errors'] for x in a)}/27 | 0/9 | {s.median(x['total_summary_seconds'] for x in e):.3f} |")
    report+=['', 'Readiness is process/model/context startup with uncontrolled OS caches, not disk-cold loading. Qwen hit the 256-token cap on both long cases in every round. At 384 tokens all six follow-up outputs per model complete valid JSON, but citation and factual defects remain. Citation validation checks only known distinct IDs, not semantic entailment; LFM’s invented single-review overview can pass that structural validator.','',
        '## Output quality','',
        '- **LFM:** often readable and fast, but puts unfair grading or intimidating interactions under pros; treats no-penalty late work as corroborated despite a cited three-point penalty; invents paired support by citing unrelated reviews. On the single-review case it leaves theme lists empty but invents a mixed-experience overview.',
        '- **Qwen:** the most fluent overview prose, but detailed points combine facts from different reviews or use citations that contradict the claim. It invents paired support for safe-space claims and finance-course concerns, overstates penalties, and fabricates multiple themes from the single review using R1 twice. Additional output tokens fix truncation, not truth.',
        '- **SmolLM2:** fastest but frequently says insufficient evidence while generating themes from six or 34 reviews; places positive experiences under concerns and negative ones under pros. It reverses no-electronics evidence into electronics allowed and copies instructions into a long-input overview.',
        '- The ENGL001B cache includes near-duplicate review text referring to American Literature 030B. Distinct review IDs do not prove independent authors; none of the models flags the source-label/body conflict. These are evidence-quality limitations, not verified facts about an instructor.',
        '- Agent review examined each unique output against its selected source text and cited source pairs. It is an exploratory semantic assessment, not an independent blinded human study. Findings and omissions are in `quality.csv` and `quality-judgments.json`; exact rendered summaries/pros/cons are in [OUTPUTS.md](OUTPUTS.md). No generative output was silently rewritten into a better summary. Invalid outputs remain raw evidence and are withheld by the structural display check.',
        '', '## Practical next step','',
        'Keep the production provider unchanged. Before spending more benchmark time, add deterministic sparse-evidence handling and duplicate/source-label diagnostics to the experimental path, then test a smaller extraction-first task: select genuinely supported source pairs before paraphrasing one pro or con. Validate polarity and every cited pair against the original review text. A JSON grammar alone is insufficient. Current evidence does not justify choosing any of these three for release.','',
        'Reproduce locally with `python3 benchmarks/bye-mac/local_rmp.py snapshot`, then `run`, then `long384`. Existing evidence directories are refused. No command in this runner fetches RMP, PCC, runtime files or models. `local_rmp_report.py` regenerates this report from saved outputs and persisted semantic notes; changed outputs require fresh review.']
    (root/'REPORT.md').write_text('\n'.join(report)+'\n')
    checks=dict(primary_requests=len(rows),followup_requests=len(extra),external_connections=0,
                source_files_unchanged=all(b.sha(Path(c['source_file']))==c['source_sha256'] for c in cases.values()),
                no_prompt_cache=all(x['timings']['cache_n']==0 for x in rows+extra),
                token_counts_match=all(x['timings']['prompt_n']==x['prompt_tokens_preflight'] for x in rows+extra),
                contexts_fit=all(x['prompt_tokens_preflight']+x['output_limit']<=x['context'] for x in rows+extra))
    assert checks['source_files_unchanged'] and checks['no_prompt_cache'] and checks['token_counts_match'] and checks['contexts_fit']
    assert len(rows)==81 and len(extra)==18
    b.save(root/'evidence-checks.json',checks)


if __name__=='__main__':main()
