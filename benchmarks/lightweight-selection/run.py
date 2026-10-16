"""Frozen 21-case baseline using the existing llama.cpp Metal runtime."""
import argparse
import os
import shutil
from common import *

def verify(spec):
    path = WORK / 'models' / spec['id'] / 'gguf' / spec['filename']
    if not path.is_file() or path.stat().st_size != spec['bytes'] or sha(path) != spec['sha256']:
        raise ValueError('GGUF integrity mismatch')
    return path

def prepare():
    if (BASE/'freeze.json').exists():raise FileExistsError('Frozen experiment exists')
    specs=[]
    for key in MODELS:
        a=load(BASE/'artifacts'/(key+'.json'));g=a['gguf'];f=g['artifacts'][0]
        specs.append(dict(id=key,repository=g['repository'],revision=g['revision'],filename=f['rfilename'],
            bytes=f['size'],sha256=f['lfs']['sha256'],native_repository=a['native']['repository'],native_revision=a['native']['revision']))
    save(HERE/'manifest.json',dict(models=specs,quantization='Q8_0',purpose='Untuned baseline; training uses native publisher weights'))
    p.prepare()
    save(BASE/'protocol.json',dict(cases=[c['name'] for c in cases()],prompt=p.PROMPTS[1],
        training_pairs_sha256=sha(ROOT/'.local-docs/evidence-summary-2026-10-15/training-pairs.json'),
        train_settings=dict(steps=10,batch=1,rank=8,scale=16,num_layers=4,learning_rate=0.0001,max_sequence=2048,seed=42),
        selection='Factual support, disagreements, training feasibility, startup timing, size. Qwen3-1.7B tie default.',
        note='Original held-out cases excluded from all inference. Native weights and Q8 baseline are distinct artifacts; conversion lineage recorded separately.'))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','screen','diagnostics']);parser.add_argument('--model',choices=MODELS)
    args=parser.parse_args();configure();p.verify=verify;deny_external()
    if args.action=='prepare':prepare();return
    frozen=load(BASE/'freeze.json')
    if sha(p.DATA/'corpus-full.json')!=frozen['corpus_sha256'] or p.PROMPTS!=frozen['prompts']:
        raise ValueError('Corpus or shared prompt changed after freeze')
    if args.action=='screen':p.screen(args.model,1)
    else:
        p.diagnostics(args.model,1)
        # Force actual overflow after deduplication, with unique complete fictional reviews.
        out=BASE/'overflow'/args.model
        reviews=[]
        body=('The explanations in my class were clear and the worked examples helped me understand the readings. '
              'I asked questions about those examples and received clear answers. '
              'My experience with the readings was positive because the examples connected the ideas together. ')
        for i in range(48):
            deadline='The deadlines stayed predictable.' if i%2==0 else 'Deadlines changed unexpectedly, which was confusing.'
            reviews.append(dict(id=f'overflow-{i}',course='ETH014',text=f'This is fictional student account {i}. '+body*3+deadline))
        case=dict(name='forced-overflow',course='ETH014',reviews=reviews)
        save(out/'source.json',case)
        with p.Server(p.model_spec(args.model),out/'session') as server:
            result=server.summarize(case,1)
            save(out/'result.json',result)
            if not result.get('chunked'):raise ValueError('Overflow diagnostic did not exercise chunking')
            supplied=[r for stage in result['stages'][:-1] for r in __import__('json').loads(stage['messages'][1]['content'].split('\n')[-1])]
            if supplied!=reviews:raise ValueError('Chunking lost or changed complete reviews')

if __name__=='__main__':main()
