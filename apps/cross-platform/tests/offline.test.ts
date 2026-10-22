import { test } from 'node:test'
import assert from 'node:assert/strict'
import { PCC, RMP, Transport, offlineFetch } from '../src/main/network'
import { NETWORK_ENABLED, NETWORK_RETIRED_MESSAGE } from '../src/shared/features'

// 0.5.0 turns BYE back on; the retirement switch and its offline fetch stay for a future retired release.
test('0.5.0 policy turns network features back on', () => {
  assert.equal(NETWORK_ENABLED, true)
})
test('offline fetch refuses before any request leaves the app', async () => {
  await assert.rejects(offlineFetch('https://example.com'), { message: NETWORK_RETIRED_MESSAGE })
  await assert.rejects(new PCC(offlineFetch).terms(), { message: NETWORK_RETIRED_MESSAGE })
  const rmp = new RMP(new Transport(offlineFetch, 0, 0))
  await assert.rejects(rmp.search('John Harris', new AbortController().signal), { message: NETWORK_RETIRED_MESSAGE })
})
