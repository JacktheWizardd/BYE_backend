#!/usr/bin/env python3
"""Network-only preparation. No inference and no review-site access."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import quote
import run


def transfer(url, path, resume=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    argv = ['/usr/bin/curl', '-q', '--fail', '--location', '--silent', '--show-error',
            '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '20',
            '--max-time', '2400' if resume else '90', '--speed-limit', '1024', '--speed-time', '90']
    if resume:
        argv += ['--continue-at', '-']
    argv += [url, '--output', str(path)]
    start = time.monotonic()
    result = subprocess.run(argv, capture_output=True, text=True)
    run.save(path.with_suffix(path.suffix + '.transfer.json'), dict(url=url, code=result.returncode,
             seconds=time.monotonic() - start, stderr=result.stderr, bytes=path.stat().st_size if path.exists() else 0))
    if result.returncode:
        raise RuntimeError(result.stderr)


def documents(spec):
    folder = run.BASE / 'documents' / spec['id']
    for role, repo, revision in [('publisher', spec['repository'], spec['revision']),
                                  ('upstream', spec['upstream'], spec.get('upstream_metadata_revision'))]:
        metadata = folder / role / 'metadata.json'
        # Resolve upstream once, then preserve the pinned metadata across reruns.
        if not metadata.exists():
            url = 'https://huggingface.co/api/models/' + repo
            if revision:
                url += '/revision/' + revision
            transfer(url + '?blobs=true', metadata)
        data = run.load(metadata)
        if revision and data['sha'] != revision:
            raise ValueError('Publisher revision differs from manifest')
        revision = data['sha']
        names = {f['rfilename'] for f in data['siblings']}
        for name in ['README.md', 'LICENSE', 'LICENSE.txt', 'NOTICE', 'NOTICE.txt', 'config.json', 'tokenizer_config.json', 'generation_config.json']:
            dest = folder / role / name
            if name in names and not dest.exists():
                transfer('https://huggingface.co/' + repo + '/resolve/' + revision + '/' + quote(name), dest)
    apache = folder / 'Apache-2.0.txt'
    if not apache.exists():
        transfer('https://www.apache.org/licenses/LICENSE-2.0.txt', apache)
    run.save(folder / 'inventory.json', dict(files={str(p.relative_to(folder)): dict(bytes=p.stat().st_size, sha256=run.sha(p))
             for p in folder.rglob('*') if p.is_file() and p.name != 'inventory.json'},
             obligations='Include Apache-2.0, preserve attribution and applicable NOTICE, mark modifications. Conversion source revision remains unverified; release eligibility is not certified.'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--documents-only', action='store_true')
    parser.add_argument('--model', choices=[m['id'] for m in run.load(run.HERE / 'manifest.json')['models']])
    args = parser.parse_args()
    for spec in run.load(run.HERE / 'manifest.json')['models']:
        if args.model and args.model != spec['id']:
            continue
        documents(spec)
        if args.documents_only:
            continue
        path = run.WORK / 'models' / spec['filename']
        partial = path.with_suffix(path.suffix + '.part')
        if not path.exists() and (not partial.exists() or partial.stat().st_size != spec['bytes']):
            transfer('https://huggingface.co/' + spec['repository'] + '/resolve/' + spec['revision'] + '/' + spec['filename'], partial, resume=True)
        run.verify(spec)
        print(spec['id'], 'verified', flush=True)


if __name__ == '__main__':
    main()
