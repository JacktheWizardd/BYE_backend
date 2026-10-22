import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { ByeNumberClient, refreshedNumber, schoolEmail, sessionCookie, validCode } from '../src/main/bye-numbers'
import { SettingsStore, validateSettings } from '../src/main/settings'

// Fixture website only: no request leaves this test.
const SITE = 'https://fixture.test'
function fixture(routes: Record<string, (init: RequestInit) => Response>) {
  const calls: { url: string; init: RequestInit }[] = []
  const request = (async (url: string, init: RequestInit) => {
    calls.push({ url, init })
    const route = routes[url.replace(SITE + '/api/reviews/', '')]
    return route ? route(init) : new Response('{}', { status: 404 })
  }) as typeof fetch
  return { calls, client: new ByeNumberClient(SITE, request) }
}
const json = (body: unknown, init: ResponseInit = {}) => new Response(JSON.stringify(body), { status: 200, ...init, headers: { 'Content-Type': 'application/json', ...init.headers } })
const header = (init: RequestInit, name: string) => (init.headers as Record<string, string>)[name]

test('school email and code rules match the website and the Mac', () => {
  assert.equal(schoolEmail('  GTruong7@go.pasadena.edu '), 'gtruong7@go.pasadena.edu')
  for (const bad of ['a+b@go.pasadena.edu', '@go.pasadena.edu', 'a@gmail.com', 'a@pasadena.edu', 'a b@go.pasadena.edu', 42]) assert.equal(schoolEmail(bad), null)
  assert.equal(validCode(' 123456 '), '123456'); assert.equal(validCode('12345'), null); assert.equal(validCode('12a456'), null)
  assert.equal(sessionCookie('__Secure-bye-review=abc; Path=/; HttpOnly; Secure'), '__Secure-bye-review=abc')
  assert.equal(sessionCookie('other=abc; Path=/'), null); assert.equal(sessionCookie('__Secure-bye-review=; Path=/'), null); assert.equal(sessionCookie(null), null)
})

test('verify signs in, claims the number with the session, then forgets the session', async () => {
  const { calls, client } = fixture({
    'auth/send': () => json({ data: { sent: true, retryAfter: 45 } }),
    'auth/verify': () => json({ data: { signedIn: true } }, { headers: { 'Set-Cookie': '__Secure-bye-review=session1; Path=/; HttpOnly' } }),
    number: () => json({ data: { number: 1, total: 1 } })
  })
  assert.deepEqual(await client.sendCode('gtruong7@go.pasadena.edu'), { ok: true, retryAfter: 45 })
  assert.deepEqual(await client.verify('gtruong7@go.pasadena.edu', '123456'), { ok: true, number: { number: 1, total: 1 } })
  assert.deepEqual(calls.map(c => c.url.split('/').slice(-2).join('/')), ['auth/send', 'auth/verify', 'reviews/number'])
  for (const c of calls) { assert.equal(c.init.method, 'POST'); assert.equal(header(c.init, 'Origin'), SITE); assert.equal(c.init.redirect, 'error') }
  assert.equal(header(calls[1].init, 'Cookie'), undefined)
  assert.equal(header(calls[2].init, 'Cookie'), '__Secure-bye-review=session1')
  // The next request carries no session.
  const later = fixture({ numbers: () => json({ data: { total: 2 } }) })
  assert.equal(await later.client.total(), 2); assert.equal(header(later.calls[0].init, 'Cookie'), undefined); assert.equal(later.calls[0].init.method, 'GET')
})

test('website errors reach the student; bad input never leaves the app', async () => {
  const { calls, client } = fixture({
    'auth/verify': () => json({ error: { message: 'That code has expired. Request a new one.' } }, { status: 400 }),
    'auth/send': () => json({ error: { message: 'x'.repeat(400) } }, { status: 429 })
  })
  assert.deepEqual(await client.verify('a@go.pasadena.edu', '123456'), { ok: false, message: 'That code has expired. Request a new one.' })
  assert.deepEqual(await client.sendCode('a@go.pasadena.edu'), { ok: false, message: 'Please wait before trying again.' })
  const before = calls.length
  assert.equal((await client.sendCode('a@gmail.com')).ok, false)
  assert.deepEqual(await client.verify('a@go.pasadena.edu', '12'), { ok: false, message: 'Enter the complete numeric code from your email.' })
  assert.equal(calls.length, before)
})

test('a sign-in without a session cookie or with a bad number is refused', async () => {
  const noCookie = fixture({ 'auth/verify': () => json({ data: { signedIn: true } }) })
  assert.equal((await noCookie.client.verify('a@go.pasadena.edu', '123456')).ok, false)
  const badNumber = fixture({
    'auth/verify': () => json({ data: { signedIn: true } }, { headers: { 'Set-Cookie': 'bye-review-local=s; Path=/' } }),
    number: () => json({ data: { number: 0, total: 3 } })
  })
  assert.equal((await badNumber.client.verify('a@go.pasadena.edu', '123456')).ok, false)
  const offline = new ByeNumberClient(SITE, (async () => { throw new TypeError('offline') }) as typeof fetch)
  assert.deepEqual(await offline.sendCode('a@go.pasadena.edu'), { ok: false, message: 'BYE could not reach its website. Try again shortly.' })
  assert.equal(await offline.total(), null)
})

test('the total only grows past your own number', () => {
  assert.deepEqual(refreshedNumber({ number: 2, total: 2 }, 5), { number: 2, total: 5 })
  assert.equal(refreshedNumber({ number: 2, total: 2 }, 1), null)
  assert.equal(refreshedNumber({ number: 2, total: 5 }, 5), null)
  assert.equal(refreshedNumber({ number: 2, total: 5 }, null), null)
})

test('only main may save a BYE number, and no email is ever stored', async () => {
  assert.throws(() => validateSettings({ byeNumber: { number: 1, total: 1 } }), /Invalid settings/)
  assert.throws(() => validateSettings({ byeNumber: { number: 3, total: 2 } }, 'main'), /Invalid BYE number/)
  assert.throws(() => validateSettings({ byeNumber: { number: 1, total: 1, email: 'a@go.pasadena.edu' } }, 'main'), /Invalid BYE number/)
  assert.throws(() => validateSettings({ email: 'a@go.pasadena.edu' }, 'main'), /Invalid settings/)
  const file = path.join(await mkdtemp(path.join(os.tmpdir(), 'bye-number-')), 'settings.json'), store = new SettingsStore(file)
  await store.set({ name: 'Jack', onboarded: true })
  await assert.rejects(store.set({ byeNumber: { number: 1, total: 1 } }), /Invalid settings/)
  const saved = await store.set({ byeNumber: { number: 1, total: 1 }, byeNumberCheckedAt: '2026-10-22T17:00:00.000Z' }, 'main')
  assert.deepEqual(saved.byeNumber, { number: 1, total: 1 }); assert.equal((await store.get()).name, 'Jack')
  assert.doesNotMatch(await readFile(file, 'utf8'), /pasadena\.edu/)
})
