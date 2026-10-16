"""Ten-step offline MLX adapter feasibility check. No quality claim or held-out use."""
import argparse
import gc
import os
import random
import time
import traceback
from common import *

os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',TOKENIZERS_PARALLELISM='false')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--model',required=True,choices=MODELS);args=parser.parse_args()
    deny_external()
    folder=BASE/'training'/args.model;folder.mkdir(parents=True,exist_ok=False)
    save(folder/'environment-before.json',p.environment())
    sampler_output=(folder/'resources.csv').open('w')
    import subprocess
    sampler=subprocess.Popen([str(WORK/'sampler'),str(os.getpid())],stdout=sampler_output)
    started=time.monotonic()
    try:
        import mlx.core as mx
        import mlx.nn as nn
        import mlx.optimizers as opt
        from mlx.utils import tree_flatten
        from mlx_lm import load as mlx_load
        from mlx_lm.tuner.utils import linear_to_lora_layers
        if not mx.metal.is_available():raise RuntimeError('Metal unavailable; no CPU fallback')
        mx.random.seed(42);mx.set_memory_limit(12_000_000_000)
        model_dir=WORK/'models'/args.model/'native'
        native=load(BASE/'artifacts'/(args.model+'.json'))['native']
        verified=[]
        for item in native['artifacts']:
            file=model_dir/item['rfilename'];actual=sha(file)
            if file.stat().st_size!=item['size'] or (item.get('lfs') and actual!=item['lfs']['sha256']):
                raise ValueError('Native model integrity mismatch')
            verified.append(dict(filename=item['rfilename'],sha256=actual,bytes=file.stat().st_size))
        save(folder/'native-verification.json',verified)
        if sha(ROOT/'.local-docs/evidence-summary-2026-10-15/training-pairs.json')!=load(BASE/'protocol.json')['training_pairs_sha256']:
            raise ValueError('Training examples changed after freeze')
        model,tokenizer=mlx_load(str(model_dir),tokenizer_config={'trust_remote_code':False})
        load_seconds=time.monotonic()-started
        rows=load(ROOT/'.local-docs/evidence-summary-2026-10-15/training-pairs.json')
        encoded=[]
        for row in rows:
            msgs=[dict(role='user',content=row['input'])]
            prefix=tokenizer.apply_chat_template(msgs,tokenize=True,return_dict=False,add_generation_prompt=True,enable_thinking=False)
            full=tokenizer.apply_chat_template(msgs+[dict(role='assistant',content=row['target'])],tokenize=True,return_dict=False,add_generation_prompt=False,enable_thinking=False)
            if full[:len(prefix)]!=prefix:raise ValueError('Training template prefix mismatch; refusing incorrect masking')
            if len(full)>2048:raise ValueError('Training example exceeds frozen token budget; no truncation')
            encoded.append((full,len(prefix)))
        model.freeze()
        config=dict(rank=8,scale=16,dropout=0.0)
        linear_to_lora_layers(model,4,config)
        mx.eval(model.parameters())
        params=dict(tree_flatten(model.trainable_parameters()))
        if not params:raise RuntimeError('No trainable adapter weights')
        before={k:v+mx.zeros_like(v) for k,v in params.items()};mx.eval(before)
        save(folder/'setup.json',dict(native=str(model_dir),load_seconds=load_seconds,pairs=len(encoded),
             token_lengths=[len(x[0]) for x in encoded],trainable_parameters=sum(v.size for v in params.values()),
             adapter_tensor_names=list(params),training_pairs_sha256=sha(ROOT/'.local-docs/evidence-summary-2026-10-15/training-pairs.json')))
        def loss_fn(m,tokens,offset):
            logits=m(tokens[:,:-1]).astype(mx.float32)
            ce=nn.losses.cross_entropy(logits,tokens[:,1:])
            mask=mx.arange(1,tokens.shape[1])>=offset
            return (ce*mask).sum()/mask.sum()
        value_grad=nn.value_and_grad(model,loss_fn)
        optimizer=opt.Adam(learning_rate=0.0001)
        order=list(range(len(encoded)));random.Random(42).shuffle(order)
        logs=[];model.train();train_start=time.monotonic()
        for step,index in enumerate(order[:10]):
            sequence,offset=encoded[index]
            loss,grads=value_grad(model,mx.array([sequence]),offset)
            optimizer.update(model,grads);mx.eval(model.parameters(),optimizer.state,loss)
            scalar=float(loss.item())
            if not (0<=scalar<100):raise ValueError('Nonfinite or invalid training loss')
            logs.append(dict(step=step+1,pair_index=index,loss=scalar,seconds=time.monotonic()-train_start,
                mlx_peak_bytes=mx.get_peak_memory()))
            save(folder/'progress.json',logs)
            print(args.model,'step',step+1,'loss',round(scalar,4),'peak',mx.get_peak_memory(),flush=True)
        train_seconds=time.monotonic()-train_start
        adapter=WORK/'adapters'/args.model;adapter.mkdir(parents=True,exist_ok=False)
        trained=dict(tree_flatten(model.trainable_parameters()))
        changed=any(bool(mx.any(v!=before[k]).item()) for k,v in trained.items())
        if not changed:raise RuntimeError('Adapters did not update')
        mx.save_safetensors(str(adapter/'adapters.safetensors'),trained)
        save(adapter/'adapter_config.json',dict(fine_tune_type='lora',num_layers=4,lora_parameters=config))
        probe=mx.array([encoded[0][0][:encoded[0][1]]]);model.eval()
        expected=model(probe)[:,-1,:].astype(mx.float32);mx.eval(expected)
        mx.save_safetensors(str(folder/'pre-reload-logits.safetensors'),{'logits':expected})
        del model,params,trained,before,optimizer,grads,value_grad,loss
        gc.collect();mx.clear_cache()
        reloaded,_=mlx_load(str(model_dir),adapter_path=str(adapter),tokenizer_config={'trust_remote_code':False})
        actual=reloaded(probe)[:,-1,:].astype(mx.float32);mx.eval(actual)
        max_diff=float(mx.max(mx.abs(expected-actual)).item())
        same=bool(mx.allclose(expected,actual,rtol=1e-4,atol=1e-4).item())
        if not same:raise RuntimeError('Reloaded adapter logits differ: '+str(max_diff))
        save(folder/'result.json',dict(status='passed',steps=10,training_seconds=train_seconds,
            total_seconds=time.monotonic()-started,load_seconds=load_seconds,mlx_peak_bytes=mx.get_peak_memory(),
            adapter_bytes=(adapter/'adapters.safetensors').stat().st_size,adapter_sha256=sha(adapter/'adapters.safetensors'),
            weights_changed=changed,reload_logits_match=same,reload_max_abs_diff=max_diff,
            note='Feasibility only. Ten examples from prior training pool; not a quality or convergence experiment. Background artifact downloads may be active; training timing is diagnostic.'))
    except Exception as e:
        save(folder/'result.json',dict(status='blocked',error=repr(e),traceback=traceback.format_exc(),seconds=time.monotonic()-started))
        print(traceback.format_exc(),flush=True)
    finally:
        sampler.terminate();sampler.wait();sampler_output.close()
        save(folder/'environment-after.json',p.environment())

if __name__=='__main__':main()
