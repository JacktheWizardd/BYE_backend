import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { LocalSummaries } from '../src/main/summary'
import manifest from '../models/manifest.json'
test('missing and corrupt bundled models produce actionable failures without runtime download', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'bye-model-')); t.after(() => rm(directory, { recursive: true, force: true }))
  const model = new LocalSummaries(directory), signal = new AbortController().signal
  await assert.rejects(model.verify(signal), /model is missing/)
  await writeFile(path.join(directory, manifest.filename), 'GGUF-invalid')
  await assert.rejects(model.verify(signal), /model is incomplete/)
  await model.dispose()
})
