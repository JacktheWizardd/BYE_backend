#!/usr/bin/env python3
"""Measure rendering/tokenization overhead as well as inference request latency."""
import json
import benchmark as b

out=b.ROOT/'docs/verification/bye-local-total-time-2026-10-11'
if out.exists(): raise ValueError('Refusing to overwrite calibration')
out.mkdir(parents=True)
b.PROMPT_FORMAT='plain'
corpus=json.loads((b.HERE/'corpus.json').read_text())
long=json.loads((b.ROOT/'docs/verification/bye-local-2026-10-11/long-source-2048.json').read_text())
rows=[]
for round_index in range(3):
    keys=['lfm','qwen','smol']
    for key in keys[round_index:]+keys[:round_index]:
        server=b.Server(key,2048,out/f'round{round_index+1}-{key}-2048')
        try:
            for case in [corpus['cases'][0],long]: rows.append(server.summary(case,case['name']))
        finally: server.close()
b.save(out/'results.json',rows)
