"""Isolated October 15 selection experiment; no review collection capability."""
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.build/bye-lightweight-selection-2026-10-15'
BASE = ROOT / '.local-docs/lightweight-selection-2026-10-15'
spec = importlib.util.spec_from_file_location('paragraph', ROOT / 'benchmarks/paragraph-summary/run.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
save, load, sha, digest = p.save, p.load, p.sha, p.digest
MODELS = {
 'qwen3-1.7b': ('Qwen/Qwen3-1.7B', 'Qwen/Qwen3-1.7B-GGUF'),
 'lfm2.5-1.2b': ('LiquidAI/LFM2.5-1.2B-Instruct', 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF'),
 'qwen3.5-0.8b': ('Qwen/Qwen3.5-0.8B', 'unsloth/Qwen3.5-0.8B-GGUF'),
}

def deny_external():
    def audit(event, args):
        if event == 'socket.connect':
            address = args[1]
            if not isinstance(address, tuple) or address[0] != '127.0.0.1':
                raise PermissionError('Experiment permits loopback only')
    sys.addaudithook(audit)

def cases():
    return [c for c in load(p.DATA / 'corpus-full.json')['cases'] if c['partition'] != 'held_out']

def configure():
    p.WORK, p.BASE, p.HERE = WORK, BASE, HERE
    return p
