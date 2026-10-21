import { test } from 'node:test'
import assert from 'node:assert/strict'
import { PCC, RMP, Transport, offlineFetch } from '../src/main/network'
import { NETWORK_ENABLED, NETWORK_RETIRED_MESSAGE } from '../src/shared/features'

// The final release must never contact PCC, RMP or the BYE website.
test('final release policy turns every network feature off', () => {
  assert.equal(NETWORK_ENABLED, false)
})
test('offline fetch refuses before any request leaves the app', async () => {
  await assert.rejects(offlineFetch('https://example.com'), { message: NETWORK_RETIRED_MESSAGE })
  await assert.rejects(new PCC(offlineFetch).terms(), { message: NETWORK_RETIRED_MESSAGE })
  const rmp = new RMP(new Transport(offlineFetch, 0, 0))
  await assert.rejects(rmp.search('John Harris', new AbortController().signal), { message: NETWORK_RETIRED_MESSAGE })
})
