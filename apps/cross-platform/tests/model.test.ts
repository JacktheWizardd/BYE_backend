import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { LocalSummaries } from '../src/main/summary'
import manifest from '../models/manifest.json'
import { course } from '../src/shared/domain'
import { AI_SUMMARIES_DISABLED_MESSAGE } from '../src/shared/features'

test('disabled provider rejects direct calls before model verification or runtime loading', async () => {
  const model = new LocalSummaries('unused-model-directory')
  model.verify = async () => { assert.fail('Disabled summaries must not access model files') }
  await assert.rejects(model.summarize([
    { id: '1', course: 'ETH14', text: 'Clear explanations', date: '' },
    { id: '2', course: 'ETH14', text: 'Clear explanations', date: '' }
  ], course('ETH14'), new AbortController().signal), { message: AI_SUMMARIES_DISABLED_MESSAGE })
  assert.equal(model.lastOutput, undefined)
  await model.dispose()
})
test('missing and corrupt bundled models produce actionable failures without runtime download', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'bye-model-')); t.after(() => rm(directory, { recursive: true, force: true }))
  const model = new LocalSummaries(directory), signal = new AbortController().signal
  await assert.rejects(model.verify(signal), /model is missing/)
  await writeFile(path.join(directory, manifest.filename), 'GGUF-invalid')
  await assert.rejects(model.verify(signal), /model is incomplete/)
  await model.dispose()
})
