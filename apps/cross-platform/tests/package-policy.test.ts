import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
// Packaging runs directly in Node, independently of TypeScript.
// @ts-expect-error JavaScript packaging helper has no declaration file.
import { buildInfo, assertPolicy, verifyWeights, verifyPackage, digest, refuseOverwrite } from '../scripts/package-policy.mjs'
import { createPackage } from '@electron/asar'
test('disabled packages need no local model; stray weights are rejected', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bye-policy-'))
  const info = buildInfo('0.1.0-beta.2', { aiSummariesEnabled: false })
  await verifyWeights(dir, { filename: 'missing.gguf' }, info)
  await writeFile(path.join(dir, 'stray.GGUF'), 'weights')
  await assert.rejects(verifyWeights(dir, {}, info), /contains GGUF/)
})
test('enabled packaging still requires complete, correct model weights', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bye-policy-'))
  const folder = path.join(dir, 'resources/models'); await mkdir(folder, { recursive: true })
  const info = buildInfo('test', { aiSummariesEnabled: true })
  const model = path.join(folder, 'model.gguf'), manifest = { filename: 'model.gguf', bytes: 7, sha256: '' }
  await assert.rejects(verifyWeights(dir, manifest, info), /missing or corrupt/)
  await writeFile(model, 'weights'); manifest.sha256 = await digest(model)
  await verifyWeights(dir, manifest, info)
  await writeFile(model, 'changed')
  await assert.rejects(verifyWeights(dir, manifest, info), /missing or corrupt/)
})
test('staging version/policy drift and artifact overwrites are refused', async () => {
  const off = buildInfo('beta.2', { aiSummariesEnabled: false })
  assertPolicy({ ...off }, off)
  assert.throws(() => assertPolicy(buildInfo('beta.2', { aiSummariesEnabled: true }), off), /mismatch/)
  assert.throws(() => assertPolicy(buildInfo('beta.1', { aiSummariesEnabled: false }), off), /mismatch/)
  assert.throws(() => assertPolicy({ ...off, weightsBundled: true }, off), /Invalid/)
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bye-policy-')), zip = path.join(dir, 'existing.zip')
  await refuseOverwrite(zip); await writeFile(zip, 'preserve')
  await assert.rejects(refuseOverwrite(zip), /Refusing to overwrite/)
})
test('package verification uses embedded policy and rejects ASAR/resource disagreement', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bye-archive-')), source = path.join(dir, 'source'), app = path.join(dir, 'BYE')
  const info = buildInfo('independent-package-version', { aiSummariesEnabled: false })
  async function put(file: string, data: string) { await mkdir(path.dirname(file), { recursive: true }); await writeFile(file, data) }
  await put(path.join(source, 'package.json'), JSON.stringify({ version: info.version }))
  await put(path.join(source, 'out/main/build-info.json'), JSON.stringify(info))
  for (const name of ['out/main/index.js', 'out/main/bootstrap.js', 'out/preload/index.cjs', 'out/renderer/index.html']) await put(path.join(source, name), 'fixture application file')
  for (const name of ['binariesGithubRelease.json', 'llama.cpp.info.json']) await put(path.join(source, 'node_modules/node-llama-cpp/llama', name), '{}')
  await put(path.join(app, 'resources/build-info.json'), JSON.stringify(info))
  await put(path.join(app, 'resources/models/manifest.json'), JSON.stringify({ filename: 'absent.gguf' }))
  for (const name of ['BYE.exe', 'resources/models/LICENSE-QWEN.txt', 'START_HERE.txt', 'THIRD_PARTY_NOTICES.txt', 'VERIFICATION.md']) await put(path.join(app, name), 'fixture content')
  await createPackage(source, path.join(app, 'resources/app.asar'))
  assert.deepEqual(await verifyPackage(app), info, 'Verification does not depend on checkout version or feature flag')
  await put(path.join(app, 'resources/build-info.json'), JSON.stringify(buildInfo(info.version, { aiSummariesEnabled: true })))
  await assert.rejects(verifyPackage(app), /mismatch/)
})
