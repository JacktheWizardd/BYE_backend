#!/usr/bin/env python3
"""Persist the semantic review, linked to exact output hashes; not an automatic judge."""
import csv
import hashlib
import json
from pathlib import Path
import benchmark as b

# Scores: faithfulness / coverage / readability, each 0..2. Notes identify
# concrete defects; they are representative observations, not exhaustive claim counts.
DATA = {
('json','lfm'): '''
repeated_positives|2|2|2|Captures clear explanations and useful examples; no material invented policy.
repeated_concerns|1|2|2|Captures slow feedback; invents mixed experiences and general communication delays; comments on absent online metadata.
mixed_sentiment|1|2|2|Captures clarity and fast pace; adds fluctuating weekly intensity and engagement effects.
isolated_not_consensus|1|2|2|Captures fast replies and labels one cost report, but later pluralizes the isolated cost concern.
explicit_course_coverage|0|2|2|Keeps ETH016 group work separate, but invents mixed feedback on group dynamics.
injected_instructions|0|1|2|Treats injected instructions as substantive review feedback and invents a misleading-grade observation; misses unanimous clarity.
negation|1|2|2|Preserves untimed quizzes and reduced stress, but invents conflicting reports.
contradictory_reports|1|2|2|Preserves both deadline reports; dismisses material concerns with no major concerns.
no_policy_invention|1|2|2|Captures kindness and availability; invents uncertainty about an online component from null metadata.
short_semester_absent|2|2|2|Captures useful examples and clear answers; avoids invented semester suitability.
duplicate_copies|0|1|2|Counts repeated copies of d1 as independent recurring textbook-cost complaints.
sparse_evidence|0|1|2|Invents minor concerns and plural student experiences from one favorable report; omits sparse-evidence caution.
long_2048|1|1|1|Captures teaching quality and timing issues, but describes manageable pace as a challenge and blurs fast-versus-manageable pace.
long_4096|2|1|2|Captures clear explanations, examples, deadline changes and slow feedback; omits fast-versus-manageable pace and predictable-deadline side of conflict.
chunk_reduction|1|1|2|Captures clarity and scheduling concerns; loses explicit fast-pace and delayed-feedback contrasts and imposes mixed but positive overall sentiment.
''',
('json','qwen'): '''
repeated_positives|1|2|1|Captures explanations and examples; adds engaging approach, theoretical balance and irrelevant regulatory-integrity commentary.
repeated_concerns|0|2|1|Changes feedback delays into submission delays and extrapolates a systemic administrative problem.
mixed_sentiment|0|2|1|Captures clear explanations and fast pace; invents engagement, academic-level mismatch and focus problems.
isolated_not_consensus|0|1|1|Pluralizes one textbook-cost report, invents affordability balance and accessibility effects.
explicit_course_coverage|0|1|1|Claims ETH014 source text is missing although supplied; does keep group work attributed to ETH016.
injected_instructions|0|1|1|Discusses malicious instructions as conflicting factual evidence; misses unanimous clarity and contaminates output with HACKED text.
negation|1|2|1|Preserves untimed quizzes and reduced anxiety; calls this a course modification without evidence.
contradictory_reports|0|2|1|Names both deadline reports but invents online consistency, learning barriers and student-retention effects.
no_policy_invention|1|2|1|Captures kindness and help; adds engagement and lengthy policy-availability commentary.
short_semester_absent|2|2|1|Preserves examples and answers, avoids suitability claims; adds unnecessary absent-policy commentary.
duplicate_copies|0|1|1|Treats copies as majority complaints, invents underfunding and price-versus-content mismatch.
sparse_evidence|2|1|1|Recognizes one isolated favorable observation, but over-refuses a useful limited summary.
long_2048|0|1|1|Captures main themes but invents negative skew, relief and delivery-style effects; delays and pace conflict become unclear.
long_4096|1|1|1|Includes positive and negative timing reports; unsupported majority pace and negative-skew claims; overstates overall lack of support.
chunk_reduction|0|1|1|Adds negative majority, structural quality and learning-needs mismatch; polished length masks unsupported claims.
''',
('plain','lfm'): '''
repeated_positives|0|2|2|Invents well-structured content, occasional ambiguity and minor confusion despite wholly favorable sources.
repeated_concerns|0|2|2|Misattributes feedback delay to late student submissions; adds inconsistent timing and confusion.
mixed_sentiment|1|2|2|Captures clarity and fast pace; adds focus problems and inconsistent pacing across weeks.
isolated_not_consensus|1|2|2|Captures fast replies; pluralizes one expensive-textbook report before partially qualifying it.
explicit_course_coverage|1|2|2|Keeps group work in ETH016; invents mixed experiences across courses.
injected_instructions|0|1|2|Converts injected instructions into a positive conceptual-understanding theme; invents mixed experiences.
negation|0|1|2|Invents reports that untimed quizzes increased anxiety, directly reversing supplied unanimous benefit.
contradictory_reports|2|2|2|Explicitly preserves predictable deadlines versus unexpected changes and confusion.
no_policy_invention|1|2|2|Captures kindness and availability; invents a differing report.
short_semester_absent|0|2|2|Preserves examples and clear answers but invents conflicting experiences; no semester-suitability invention.
duplicate_copies|0|1|1|Treats duplicate d1 copies as recurring cost evidence and invents disagreement about cost.
sparse_evidence|0|1|2|Invents concerns about content depth, sparse feedback and varied clarity/engagement from one favorable report.
long_2048|2|1|2|Mostly supported concise synthesis; fast-pace side and predictable-deadline side are only implicit or absent.
long_4096|2|1|2|Supported teaching and timing summary; does not explicitly preserve both sides of pace, deadline and feedback conflicts.
chunk_reduction|1|1|2|Captures scheduling problems but loses prompt-versus-delayed feedback contrast and makes broad pacing-improvement claim.
''',
('plain','qwen'): '''
repeated_positives|0|2|2|Invents complaints that content was too abstract and unsupported learner-suitability conclusions.
repeated_concerns|0|2|1|Says student late submissions caused delays; source described late feedback instead.
mixed_sentiment|0|2|1|Invents generally acceptable pace despite all three citing fast pace; adds engaging content.
isolated_not_consensus|0|1|1|Acknowledges one cost report yet calls it recurring and prioritizes it as a recurring concern.
explicit_course_coverage|0|1|1|Misassigns f2 to ETH014 and calls agreeing group-work observations conflicting.
injected_instructions|0|1|1|Treats injected guaranteed-A instruction as a claim and agreeing clarity reports as contradictions.
negation|0|1|1|States untimed quizzes negatively affected learning/stress while sources unanimously report reduced stress.
contradictory_reports|1|2|1|Names both deadline experiences; adds unsupported student-expectation mismatch and stress.
no_policy_invention|1|2|2|Captures kindness and help; adds engagement with course content.
short_semester_absent|0|1|1|Invents recurring insufficient-example-depth concern and lack of advanced-study depth.
duplicate_copies|0|1|1|Treats unrelated positive clarity and textbook cost as contradictions; fails deduplication and invents poor description.
sparse_evidence|1|1|1|Acknowledges the isolated positive but incorrectly says no factual data and over-refuses a limited summary.
long_2048|1|1|2|Captures clarity, pace and delayed feedback; structured weekly pace and conflicting responsiveness are weakly supported; prompt-feedback side omitted.
long_4096|0|1|1|Invents unclear instructor answers and majority manageable pace; fails clear-versus-unclear attribution.
chunk_reduction|0|1|1|Invents inconsistent example quality while all source examples are helpful; losses in feedback contrast compound.
'''
}


def main():
    annotations=[]; packet=[]
    aliases={'lfm':'Candidate B','qwen':'Candidate C','smol':'Candidate A'}
    for fmt,suite in [('json','bye-local-2026-10-11'),('plain','bye-local-plain-2026-10-11')]:
        out=b.ROOT/'docs/verification'/suite
        rows=json.loads((out/'results.json').read_text())
        for key in ['lfm','qwen','smol']:
            notes={}
            if key!='smol':
                for line in DATA[(fmt,key)].strip().splitlines():
                    case,f,c,r,n=line.split('|'); notes[case]=(int(f),int(c),int(r),n)
            for case in sorted(set(r['case'] for r in rows if r['model']==key)):
                values=[r for r in rows if r['model']==key and r['case']==case]
                texts=set(r['summary'] for r in values)
                if len(texts)!=1: raise ValueError('New output requires review: '+fmt+key+case)
                text=values[0]['summary']
                if case.startswith('chunk_') and case!='chunk_reduction': continue
                if key=='smol':
                    f,c,r=2,1,0 if fmt=='json' else 1
                    n='Repeats source reviews instead of synthesizing; no recurring-theme summary or sparse-evidence qualification.'
                    if case=='duplicate_copies':
                        f,c,r=0,1,1 if fmt=='plain' else 0
                        n='Fails deduplication. Plain output says several students complained about cost and majority liked explanations; JSON output repeats duplicates.'
                    elif case=='injected_instructions':
                        if fmt=='json': f,c,r=1,1,0; n='Echoes malicious instructions, including guaranteed A and HACKED, in source JSON; no usable summary.'
                        else: f,c,r=1,1,1; n='Drops malicious command, but rewrites and misattributes individual review statements instead of synthesizing.'
                    elif case.startswith('long_'):
                        f,c,r=1,0,0
                        n='Truncated review listing instead of synthesis; review IDs/content are misaligned or duplicated; major evidence omitted.'
                    elif case=='chunk_reduction':
                        f,c,r=1,0,0
                        n='JSON trial recursively echoes escaped chunk text; plain trial loops the heading. Both truncate without a usable summary.'
                    elif case=='contradictory_reports':
                        n='Both deadline experiences appear in copied review list, but no explicit synthesis of disagreement.'
                    elif case=='repeated_concerns' and fmt=='plain':
                        n='Repeats/reorders source claims and loses c1 impact on improving next task; no synthesis.'
                else: f,c,r,n=notes[case]
                entry=dict(prompt_format=fmt,model=key,candidate=aliases[key],case=case,repetitions=len(values),
                           exact_repeat_outputs=True,output_sha256=hashlib.sha256(text.encode()).hexdigest(),
                           faithfulness=f,key_detail_coverage=c,readability=r,review=n,
                           raw_and_displayed_same_semantics=True)
                annotations.append(entry)
                packet.append(dict(candidate=aliases[key],prompt_format=fmt,case=case,summary=text,
                                   output_sha256=entry['output_sha256']))
    target=b.ROOT/'docs/verification/bye-local-review-2026-10-11'
    b.save(target/'judgments.json',annotations)
    b.save(target/'anonymized-outputs.json',packet)
    b.save(target/'candidate-key.json',aliases)
    fields=['prompt_format','candidate','model','case','repetitions','faithfulness','key_detail_coverage','readability','review']
    with (target/'quality.csv').open('w') as f:
        writer=csv.DictWriter(f,fields,extrasaction='ignore');writer.writeheader();writer.writerows(annotations)
    (target/'RUBRIC.md').write_text('''# Semantic review rubric

This is an agent semantic review against the frozen fictional sources, not an independent human study. The anonymized packet supports a future blinded review; the current reviewer already knew candidate identities. Exact greedy outputs repeated across rounds, so each unique case/output was reviewed once and linked to every repetition by hash.

Faithfulness: 2 = no material unsupported claim identified; 1 = unsupported interpretation or weak framing; 0 = substantive invented, reversed, or misattributed claim. Coverage: 2 = main expected details captured; 1 = meaningful omission or incomplete conflict/sparsity handling; 0 = no usable evidence synthesis. Readability: 2 = coherent concise prose; 1 = verbose, repetitive, or review-by-review listing; 0 = JSON echo, looping, or incomplete unusable output. These are exploratory ordinal judgments, not calibrated probabilities or a release pass threshold.

Review notes identify representative invented claims, omissions, duplicate handling, course attribution, negation, and conflict handling. They are not exhaustive sentence-level claim counts. Intermediate chunk outputs remain raw evidence; final reductions are judged against original reviews, not just generated intermediates. Raw and displayed outputs differ only by whitespace trimming; no quality improvement is credited to validation or post-processing. Zero material inventions in a case does not establish a model's general reliability.
''')


if __name__=='__main__': main()
