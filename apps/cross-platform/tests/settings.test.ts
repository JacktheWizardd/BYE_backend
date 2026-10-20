import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile, writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { SettingsStore, UPDATE_URL, checkForUpdate, compareVersions, isUpdateLink, validateSettings } from '../src/main/settings'

test('settings validation accepts names and course codes, rejects anything else', () => {
  assert.deepEqual(validateSettings({ name: '  Jack  ' }), { name: 'Jack' })
  assert.deepEqual(validateSettings({ name: 'María-José O’Neil' }), { name: 'María-José O’Neil' })
  assert.deepEqual(validateSettings({ onboarded: true, recent: ['MATH 5A', 'ETH 014', 'MATH 5A'] }), { onboarded: true, recent: ['MATH 5A', 'ETH 014'] })
  assert.deepEqual(validateSettings({ name: '' }), { name: '' })
  for (const bad of [null, [], 'x', { name: 'x'.repeat(21) }, { name: '<script>' }, { name: 'a\nb' }, { name: 3 }, { onboarded: 'yes' },
    { recent: ['math 5a'] }, { recent: ['A B C D E F'.split(' ')] }, { recent: Array(6).fill('MATH 5A') }, { theme: 'dark' }])
    assert.throws(() => validateSettings(bad), JSON.stringify(bad))
})

test('settings store merges updates, survives a corrupt file and writes JSON', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'bye-settings-')), file = path.join(dir, 'settings.json')
  const store = new SettingsStore(file)
  assert.deepEqual(await store.get(), { name: '', onboarded: false, recent: [] })
  await store.set({ name: 'Jack' })
  await store.set({ onboarded: true })
  assert.deepEqual(await store.get(), { name: 'Jack', onboarded: true, recent: [] })
  assert.deepEqual(JSON.parse(await readFile(file, 'utf8')), { name: 'Jack', onboarded: true, recent: [] })
  await assert.rejects(() => store.set({ name: '<b>' }))
  await writeFile(file, '{not json')
  assert.deepEqual(await store.get(), { name: '', onboarded: false, recent: [] })
})

test('versions compare with prereleases before releases', () => {
  assert.ok(compareVersions('0.5.0', '0.4.0-beta.1') > 0)
  assert.ok(compareVersions('0.4.0', '0.4.0-beta.1') > 0)
  assert.ok(compareVersions('0.4.0-beta.2', '0.4.0-beta.1') > 0)
  assert.ok(compareVersions('0.4.0-beta.10', '0.4.0-beta.9') > 0)
  assert.equal(compareVersions('0.4.0-beta.1', '0.4.0-beta.1'), 0)
  assert.ok(compareVersions('0.3.9', '0.4.0-beta.1') < 0)
  assert.throws(() => compareVersions('latest', '0.4.0'))
})

const reply = (body: string, ok = true) => (async () => new Response(body, { status: ok ? 200 : 500 })) as unknown as typeof fetch

test('update check asks only the fixed website address and only links to the website', async () => {
  let asked = ''
  const spy = (async (url: string) => { asked = url; return new Response('{"version":"0.5.0-beta.1"}') }) as unknown as typeof fetch
  assert.deepEqual(await checkForUpdate('0.4.0-beta.1', spy), { status: 'available', version: '0.4.0-beta.1', latest: '0.5.0-beta.1', downloadUrl: 'https://bye-before-you-enroll.pages.dev/#download' })
  assert.equal(asked, UPDATE_URL)
  assert.equal((await checkForUpdate('0.4.0-beta.1', reply('{"version":"0.5.0","downloadUrl":"https://evil.example/bye.zip"}')) as { downloadUrl: string }).downloadUrl, 'https://bye-before-you-enroll.pages.dev/#download')
  assert.equal((await checkForUpdate('0.4.0-beta.1', reply('{"version":"0.5.0","downloadUrl":"https://bye-before-you-enroll.pages.dev/downloads/BYE-win.zip"}')) as { downloadUrl: string }).downloadUrl, 'https://bye-before-you-enroll.pages.dev/downloads/BYE-win.zip')
  assert.equal((await checkForUpdate('0.4.0-beta.1', reply('{"version":"0.4.0-beta.1"}'))).status, 'current')
  for (const bad of [reply('nope'), reply('{}'), reply('{"version":"0.5.0"}', false), reply('{"version":"0.5.0","x":"' + 'a'.repeat(5000) + '"}'), (async () => { throw new Error('offline') }) as unknown as typeof fetch])
    assert.equal((await checkForUpdate('0.4.0-beta.1', bad)).status, 'error')
  assert.equal(isUpdateLink('https://bye-before-you-enroll.pages.dev/#download'), true)
  assert.equal(isUpdateLink('https://bye-before-you-enroll.pages.dev.evil.example/'), false)
  assert.equal(isUpdateLink('file:///C:/Windows'), false)
})
