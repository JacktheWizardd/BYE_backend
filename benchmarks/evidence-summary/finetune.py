#!/usr/bin/env python3
"""Bounded offline fine-tuning pilot; training cases never score as evaluation."""
import argparse
import gc
import json
import os
import random
import time
import run

os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',WANDB_DISABLED='true',TOKENIZERS_PARALLELISM='false')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['control','train','evaluate']);args=parser.parse_args()
    run.deny_external()
    import torch
    import transformers
    from transformers import AutoTokenizer,AutoModelForSeq2SeqLM
    torch.manual_seed(42);random.seed(42);torch.set_num_threads(4)
    model_dir=run.WORK/'flan-t5-small'
    tokenizer=AutoTokenizer.from_pretrained(model_dir,local_files_only=True)
    checkpoint=run.WORK/'finetuned' if args.action=='evaluate' else model_dir
    model=AutoModelForSeq2SeqLM.from_pretrained(checkpoint,local_files_only=True)
    device='mps' if torch.backends.mps.is_available() else 'cpu'
    model.to(device)
    run.save(run.BASE/('environment-'+args.action+'.json'),dict(torch=torch.__version__,transformers=transformers.__version__,device=device,model=str(checkpoint),model_files={p.name:run.sha(p) for p in checkpoint.iterdir() if p.is_file()}))
    if args.action=='train':
        if (run.WORK/'finetuned').exists():raise FileExistsError('Refusing to overwrite fine-tuned checkpoint')
        rows=run.load(run.BASE/'training-pairs.json');encoded=[]
        for row in rows:
            inp=tokenizer(row['input'],return_tensors='pt');target=tokenizer(text_target=row['target'],return_tensors='pt')
            if inp.input_ids.shape[1]>512 or target.input_ids.shape[1]>192:continue
            encoded.append(row)
        model.train();optimizer=torch.optim.AdamW(model.parameters(),lr=.0001);logs=[];start=time.monotonic()
        for step in range(120):
            batch=random.choices(encoded,k=4)
            inputs=tokenizer([r['input'] for r in batch],padding=True,return_tensors='pt').to(device)
            targets=tokenizer(text_target=[r['target'] for r in batch],padding=True,return_tensors='pt').input_ids.to(device)
            targets[targets==tokenizer.pad_token_id]=-100
            optimizer.zero_grad(set_to_none=True);loss=model(**inputs,labels=targets).loss
            if not torch.isfinite(loss):raise RuntimeError('Nonfinite training loss')
            loss.backward();torch.nn.utils.clip_grad_norm_(model.parameters(),1.0);optimizer.step()
            logs.append(dict(step=step+1,loss=float(loss.detach().cpu()),seconds=time.monotonic()-start))
            if (step+1)%10==0:
                run.save(run.BASE/'training-progress.json',logs);print('step',step+1,'loss',logs[-1]['loss'],'seconds',round(logs[-1]['seconds'],1),flush=True)
        model.save_pretrained(run.WORK/'finetuned');tokenizer.save_pretrained(run.WORK/'finetuned')
        run.save(run.BASE/'training-complete.json',dict(training_pairs=len(encoded),skipped_overflow=len(rows)-len(encoded),steps=120,device=device,seconds=time.monotonic()-start,losses=logs,
            note='Tiny source-reviewed/teacher-derived pilot; training loss is not faithfulness or generalization.'))
    else:
        method='D-finetuned' if args.action=='evaluate' else 'E-untuned-control';folder=run.BASE/method;folder.mkdir(exist_ok=False)
        model.eval()
        for case in run.cases():
            row=run.load(run.BASE/'A-extractive'/(case['name']+'.json'));chosen=row['evidence'];start=time.monotonic()
            if not chosen:text=row['text'];tokens=0
            else:
                inputs=tokenizer(run.source_input(chosen),return_tensors='pt');tokens=inputs.input_ids.shape[1]
                if tokens>512:
                    run.save(folder/(case['name']+'.json'),dict(case=case['name'],split=run.split_name(case),error='complete evidence ledger exceeds 512-token pilot budget; no truncation'));continue
                with torch.inference_mode():
                    output=model.generate(**inputs.to(device),max_new_tokens=192,do_sample=False,num_beams=1)
                text=tokenizer.decode(output[0],skip_special_tokens=True)
            run.save(folder/(case['name']+'.json'),dict(case=case['name'],split=run.split_name(case),text=text,output_hash=run.digest(text),
                evidence=chosen,evidence_hash=run.digest(chosen),seconds=time.monotonic()-start,input_tokens=tokens,words=len(text.split()),device=device,
                note='Raw decoder output; no automatic semantic certification or fallback.'))
            print(method,case['name'],round(time.monotonic()-start,2),flush=True)


if __name__=='__main__':main()
