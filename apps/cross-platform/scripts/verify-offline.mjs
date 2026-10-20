import { _electron as electron } from 'playwright'
import { build } from 'esbuild'
import { spawn, execFileSync } from 'node:child_process'
import { readFile, writeFile, mkdir, mkdtemp, access, readdir } from 'node:fs/promises'
import { createRequire } from 'node:module'
import path from 'node:path'
import assert from 'node:assert/strict'
import { setTimeout as delay } from 'node:timers/promises'
import { buildInfo, assertPolicy, digest } from './package-policy.mjs'
import policy from '../src/shared/features.json' with { type: 'json' }
const UNAVAILABLE_NOTE = 'AI summaries are temporarily unavailable. Read the original student reviews below.'
const require = createRequire(import.meta.url), root = path.resolve(import.meta.dirname, '..')
if (process.platform !== 'win32') throw new Error('This baseline measures Windows process memory.')
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8')), info = buildInfo(pkg.version, policy)
assert.equal(info.aiSummariesEnabled, false, 'This verification requires the paused-summary policy.')
assertPolicy(JSON.parse(await readFile(path.join(root, 'out/main/build-info.json'), 'utf8')), info)
const cache = path.join(root, '.cache'), results = path.join(root, 'test-results')
await mkdir(cache, { recursive: true }); await mkdir(results, { recursive: true })
const output = await mkdtemp(path.join(results, process.argv.includes('--perf') ? 'offline-perf-' : 'offline-ui-'))
const entry = path.join(cache, 'offline-entry.mjs')
await build({ entryPoints: [path.join(root, 'scripts/offline-entry.mjs')], outfile: entry, bundle: true, platform: 'node', format: 'esm', packages: 'external', external: ['../out/main/bootstrap.js'], logLevel: 'warning' })
const env = { ...process.env }; delete env.ELECTRON_RUN_AS_NODE; delete env.ELECTRON_RENDERER_URL
const errors = [], checks = [], launches = []
const state = app => app.evaluate(() => structuredClone(globalThis.__offline.engine.state))
async function until(work, label, timeout = 15000) {
  const start = performance.now()
  while (performance.now() - start < timeout) { if (await work()) return; await delay(25) }
  throw new Error('Timed out: ' + label)
}
async function readyReport(app, page, previous) {
  await until(async () => {
    const s = await state(app), p = s.professors.find(p => p.name === 'Alex Example')
    return s.operationId !== previous && !s.loading && !s.previewPending && p?.state === 'ready' && p.profile?.coverage.all?.hasNextPage === false && !p.detailLoading
  }, 'complete original-review report')
  await page.getByRole('heading', { name: 'Alex Example', exact: true }).waitFor()
  await page.getByText(UNAVAILABLE_NOTE, { exact: true }).waitFor()
  // Include React presentation and two browser frames in report-loading latency.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
}
async function search(app, page) {
  const before = (await state(app)).operationId, start = performance.now()
  // Results open on the course overview; repeat searches go back through Change search, as on the Mac.
  if (await page.getByRole('button', { name: 'Change search', exact: true }).count()) await page.getByRole('button', { name: 'Change search', exact: true }).click()
  await page.getByRole('button', { name: 'Find professors' }).click()
  await page.getByRole('button', { name: /Alex Example.*sections?/ }).click()
  await readyReport(app, page, before)
  return performance.now() - start
}
async function launch(storage, { firstRun = false } = {}) {
  // Ordinary runs start past first-run setup; appFlowChecks covers welcome and naming on its own fresh storage.
  if (!firstRun) await writeFile(path.join(storage, 'settings.json'), JSON.stringify({ name: '', onboarded: true, recent: [] }), { flag: 'wx' }).catch(error => { if (error.code !== 'EEXIST') throw error })
  const start = performance.now()
  const app = await electron.launch({ executablePath: require('electron'), args: [entry], env: { ...env, BYE_OFFLINE_ROOT: root, BYE_OFFLINE_STORAGE: storage }, timeout: 30000 })
  try {
    const page = await app.firstWindow({ timeout: 30000 }); page.on('pageerror', error => errors.push(error.message))
    if (firstRun) return { app, page, startupMs: performance.now() - start }
    await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202650')
    await page.getByRole('combobox', { name: 'Class', exact: true }).fill('ETH14')
    return { app, page, startupMs: performance.now() - start }
  } catch (error) {
    await app.close().catch(() => {})
    throw error
  }
}
async function inactive(app) {
  const counters = await app.evaluate(() => ({ ai: globalThis.__offline.aiCalls, network: globalThis.__offline.networkAttempts, services: globalThis.__offline.calls }))
  assert.deepEqual(counters.ai, { summarize: 0, verify: 0 }); assert.deepEqual(counters.network, [])
  return counters
}
async function interactions(app, page) {
  await page.getByRole('button', { name: /Blair Sample.*sections?/ }).click()
  await page.getByRole('heading', { name: 'Blair Sample', exact: true }).waitFor()
  await until(async () => { const p = (await state(app)).professors.find(p => p.name === 'Blair Sample'); return !p.detailLoading && p.profile.coverage.all?.hasNextPage === false }, 'second professor reviews')
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('all')
  await page.getByRole('combobox', { name: 'Sort reviews', exact: true }).selectOption('highest')
  await page.getByRole('button', { name: /Alex Example.*sections?/ }).click()
  await page.getByRole('heading', { name: 'Alex Example', exact: true }).waitFor()
}
async function searchRegressionChecks(app, page) {
  const input = page.getByRole('combobox', { name: 'Class', exact: true })
  const list = page.getByRole('listbox', { name: 'Matching PCC courses' })
  const closed = async () => assert.equal(await input.getAttribute('aria-expanded'), 'false')
  for (const query of ['MATH 005A', 'math 005a', 'math 5a', 'MATH5A']) {
    await input.fill(query)
    await list.getByRole('option').first().waitFor()
    assert.match(await list.getByRole('option').first().innerText(), /MATH 005A/)
  }
  await input.fill('MATH 005')
  await until(async () => await list.getByRole('option').count() === 2, 'partial suffix suggestions')
  await input.press('ArrowDown'); await input.press('Enter')
  assert.equal(await input.inputValue(), 'MATH 005A'); await closed()
  await input.fill('MATH 005B'); await list.waitFor()
  await list.getByRole('option').first().click()
  assert.equal(await input.inputValue(), 'MATH 005B'); await closed()
  await input.fill('MATH 005A'); await list.waitFor()
  await page.screenshot({ path: path.join(output, 'math-exact-suggestions.png') })
  await input.press('Escape'); await closed()
  await input.fill('MATH 005'); await list.waitFor()
  await page.getByRole('combobox', { name: 'Semester', exact: true }).focus(); await closed()

  // Start a delayed request, dismiss it, then allow its result to arrive.
  await app.evaluate(() => { globalThis.__offline.controls.suggestDelay = 650 })
  let before = await app.evaluate(() => globalThis.__offline.calls.suggestions)
  await input.fill('MATH 005A')
  await until(async () => await app.evaluate(() => globalThis.__offline.calls.suggestions) > before, 'delayed suggestions started')
  await input.press('Escape'); await delay(750); await closed()

  before = await app.evaluate(() => globalThis.__offline.calls.suggestions)
  await input.fill('MATH 005A ')
  await until(async () => await app.evaluate(() => globalThis.__offline.calls.suggestions) > before, 'old query started')
  await app.evaluate(() => { globalThis.__offline.controls.suggestDelay = 0 })
  await input.fill('MATH 005B'); await list.waitFor()
  await delay(750)
  assert.match(await list.getByRole('option').first().innerText(), /MATH 005B/)
  assert.equal(await list.getByRole('option').count(), 1)
  // A previous semester's response cannot replace suggestions for the new term.
  await app.evaluate(() => { globalThis.__offline.controls.suggestDelay = 650 })
  before = await app.evaluate(() => globalThis.__offline.calls.suggestions)
  await input.fill('MATH 005')
  await until(async () => await app.evaluate(() => globalThis.__offline.calls.suggestions) > before, 'old semester started')
  await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202670')
  await app.evaluate(() => { globalThis.__offline.controls.suggestDelay = 0 })
  await input.focus(); await list.waitFor(); await delay(750)
  assert.equal(await list.getByRole('option').count(), 1)
  assert.match(await list.getByRole('option').first().innerText(), /MATH 005B/)
  await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202650')
  await input.focus()
  await input.fill('MATH 005A'); await list.waitFor()
  await app.evaluate(() => { globalThis.__offline.controls.ambiguous = true })
  await input.press('Enter') // No highlighted option: submit the typed course.
  await page.getByRole('button', { name: 'Change search', exact: true }).waitFor()
  await until(async () => !(await state(app)).loading, 'mixed MATH professor search')
  assert.equal((await state(app)).course.key, 'MATH005A')
  assert.equal((await state(app)).professors.length, 4)
  assert.equal(await page.getByRole('dialog').count(), 0)
  await page.screenshot({ path: path.join(output, 'math-results-without-popups.png') })
  const card = name => page.locator('.professor-card').filter({ hasText: name })
  await card('Alex Example').getByRole('button', { name: 'Choose profile', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.waitFor()
  await until(async () => await dialog.getByRole('button', { name: 'Use this profile', exact: true }).count() === 2, 'explicit candidates')
  await page.screenshot({ path: path.join(output, 'explicit-profile-dialog.png') })
  await dialog.getByRole('button', { name: 'Close', exact: true }).click()
  await dialog.waitFor({ state: 'hidden' })
  assert.equal(await page.getByRole('dialog').count(), 0)
  await app.evaluate(() => { globalThis.__offline.controls.candidateDelay = 650 })
  await card('Blair Sample').getByRole('button', { name: 'Choose profile', exact: true }).click()
  await dialog.getByText('Finding matching profiles…', { exact: true }).waitFor()
  await dialog.getByRole('button', { name: 'Close', exact: true }).click()
  await delay(750)
  assert.equal(await page.getByRole('dialog').count(), 0)
  await app.evaluate(() => { globalThis.__offline.controls.candidateDelay = 0 })
  await app.evaluate(() => { globalThis.__offline.controls.candidateEmpty = true })
  await card('Alex Example').getByRole('button', { name: 'Choose profile', exact: true }).click()
  await dialog.getByText('No eligible profile is available. Retry this professor or check the source.', { exact: true }).waitFor()
  await app.evaluate(() => { globalThis.__offline.controls.candidateEmpty = false; globalThis.__offline.controls.candidateFailure = true })
  await dialog.getByRole('button', { name: 'Try again', exact: true }).click()
  await dialog.getByText('Fixture profile discovery unavailable.', { exact: true }).waitFor()
  await app.evaluate(() => { globalThis.__offline.controls.candidateFailure = false })
  await dialog.getByRole('button', { name: 'Try again', exact: true }).click()
  await until(async () => await dialog.getByRole('button', { name: 'Use this profile', exact: true }).count() === 2, 'discovery recovery')
  await dialog.getByRole('button', { name: 'Close', exact: true }).click()
  await dialog.waitFor({ state: 'hidden' })
  await card('Dana Identity').getByRole('button', { name: 'Choose profile', exact: true }).click()
  await until(async () => await dialog.getByRole('button', { name: 'Use this profile', exact: true }).count() === 1, 'identity candidate')
  await dialog.getByRole('button', { name: 'Use this profile', exact: true }).click()
  await app.evaluate(() => globalThis.__offline.engine.idle())
  await dialog.waitFor({ state: 'hidden' })
  assert.equal(await page.getByRole('dialog').count(), 0)
  await card('Dana Identity').getByText('Profile needs confirmation · Choose profile', { exact: true }).waitFor()
  await page.getByRole('button', { name: 'Refresh', exact: true }).click()
  await until(async () => !(await state(app)).loading, 'refresh without dialogs')
  assert.equal(await page.getByRole('dialog').count(), 0)
  await page.getByRole('button', { name: 'Change search', exact: true }).click()
  await app.evaluate(() => { globalThis.__offline.controls.suggestFailure = true })
  before = await app.evaluate(() => globalThis.__offline.calls.suggestions)
  await input.fill('MATH 005B')
  await until(async () => await app.evaluate(() => globalThis.__offline.calls.suggestions) > before, 'suggestion failure')
  await closed()
  await input.press('Enter')
  await page.getByRole('button', { name: 'Change search', exact: true }).waitFor()
  await until(async () => !(await state(app)).loading, 'search independent of suggestions')
  assert.equal((await state(app)).course.key, 'MATH005B')
  assert.equal((await state(app)).professors.length, 1)
  await page.getByRole('button', { name: 'Change search', exact: true }).click()
  await input.fill('ETH14')
  await app.evaluate(() => { globalThis.__offline.controls.ambiguous = false; globalThis.__offline.controls.suggestFailure = false })
  checks.push('Exact MATH suffix suggestions, mouse/keyboard selection, dismissal, delayed response isolation, mixed professor states and explicit-only dialogs passed')
}
async function uiChecks(app, page, storage) {
  assert.equal(await page.evaluate(() => typeof window.require), 'undefined')
  const prefs = await app.evaluate(() => globalThis.__offline.getWindow().webContents.getLastWebPreferences())
  assert.equal(prefs.sandbox, true); assert.equal(prefs.contextIsolation, true); assert.equal(prefs.nodeIntegration, false)
  checks.push('Production bootstrap, real Engine, built renderer/preload and sandbox/context isolation verified')
  await interactions(app, page)
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('all')
  await page.getByRole('button', { name: 'View more reviews', exact: true }).click()
  assert.equal(await page.locator('.review').count(), 8)
  await page.getByRole('combobox', { name: 'Sort reviews', exact: true }).selectOption('highest')
  assert.match(await page.locator('.review').first().innerText(), /Rating 5\.0/)
  await page.getByRole('combobox', { name: 'Sort reviews', exact: true }).selectOption('lowest')
  assert.match(await page.locator('.review').first().innerText(), /Rating 1\.0/)
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('HIST001')
  assert.equal(await page.locator('.review').count(), 3)
  for (const label of await page.locator('.review-heading strong').allTextContents()) assert.equal(label, 'HIST001')
  await page.getByRole('group', { name: 'Sort professors', exact: true }).getByRole('button', { name: 'Difficulty', exact: true }).click()
  assert.equal(await page.getByRole('group', { name: 'Sort professors', exact: true }).getByRole('button', { name: 'Difficulty', exact: true }).getAttribute('aria-pressed'), 'true')
  checks.push('Search, professor switching, review loading, course filters, rating sorts and progressive reveal passed')
  await app.evaluate(() => { globalThis.__offline.controls.ambiguous = true })
  await page.getByRole('button', { name: 'Change profile', exact: true }).click()
  await page.getByRole('dialog').waitFor()
  // The dialog opens before discovery returns, as in the other chooser checks.
  await until(async () => await page.getByRole('button', { name: 'Use this profile', exact: true }).count() === 2, 'changed-profile candidates')
  await page.getByRole('button', { name: 'Use this profile', exact: true }).last().click()
  await until(async () => { const p = (await state(app)).professors[0]; return p.profile?.coverage.all?.hasNextPage === false && !p.detailLoading }, 'chosen profile report')
  checks.push('Ambiguous profile chooser and persisted manual selection passed')
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('HIST001')
  await app.evaluate(() => { globalThis.__offline.controls.holdPages = true })
  await page.getByRole('button', { name: 'Find more for this class', exact: true }).click()
  await page.getByRole('button', { name: 'Stop loading', exact: true }).waitFor()
  await page.getByRole('button', { name: 'Stop loading', exact: true }).click()
  await app.evaluate(() => globalThis.__offline.engine.idle())
  await page.getByText('Stopped. Retrieved reviews are still available.', { exact: true }).waitFor()
  assert.ok((await app.evaluate(() => globalThis.__offline.calls.aborted)) > 0)
  await app.evaluate(() => { globalThis.__offline.controls.holdPages = false })
  checks.push('Cancellation aborts the fixture page and preserves downloaded reviews')
  await app.evaluate(async () => {
    const { engine, ai } = globalThis.__offline, p = engine.state.professors[0]
    const summary = { overview: 'HIDDEN_CACHED_SUMMARY_SENTINEL', positives: [], concerns: [], analyzedCount: p.profile.reviews.length, exactCourseCount: 20, generatedAt: Date.now(), providerIdentity: ai.cacheIdentity, evidence: p.profile.reviews }
    await engine.store.setSummary(p.profile.id, engine.state.course, summary, p.profile.reviews)
    p.summary = summary; engine.emit()
  })
  const reports = path.join(storage, 'reports'), summaryFile = (await readdir(reports)).find(n => n.startsWith('summary-'))
  assert.ok(summaryFile); const summaryPath = path.join(reports, summaryFile), original = await readFile(summaryPath, 'utf8')
  assert.equal(await page.getByText('HIDDEN_CACHED_SUMMARY_SENTINEL', { exact: true }).count(), 0)
  await page.getByText(UNAVAILABLE_NOTE, { exact: true }).waitFor()
  await page.evaluate(async () => {
    // The unmodified production bridge still accepts the existing command type.
    await window.bye.command({ kind: 'summary', professorId: 'alex example' })
  })
  assert.equal((await state(app)).professors[0].summary, undefined)
  assert.equal(await readFile(summaryPath, 'utf8'), original)
  await inactive(app)
  const providerMessage = await app.evaluate(async () => {
    const { ai, engine } = globalThis.__offline
    try { await ai.summarize(engine.state.professors[0].profile.reviews, engine.state.course, new AbortController().signal) } catch (error) { return error.message }
  })
  assert.match(providerMessage, /temporarily disabled/)
  assert.equal(await app.evaluate(() => globalThis.__offline.aiCalls.verify), 0)
  assert.equal(await app.evaluate(() => globalThis.__offline.aiCalls.summarize), 1)
  // One deliberate provider guard call above; all UI/backend commands made zero calls.
  await app.evaluate(() => { globalThis.__offline.aiCalls.summarize = 0 })
  checks.push('Summary UI, direct bridge command and provider guard stay inactive; existing summary cache is byte-for-byte retained and hidden')
  return { summaryPath, original }
}
async function monitor(number) {
  const base = path.join(output, `launch-${number}`), ready = base + '.ready', stop = base + '.stop', file = base + '-memory.json'
  const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, 'scripts/monitor-process-tree.ps1'), '-ControllerId', String(process.pid), '-OutputFile', file, '-ReadyFile', ready, '-StopFile', stop], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] })
  let diagnostics = ''; child.stdout.on('data', data => { diagnostics += data }); child.stderr.on('data', data => { diagnostics += data })
  const completed = new Promise((resolve, reject) => { child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error('Memory monitor failed: ' + diagnostics))) })
  // Attach rejection handling while waiting for ready; fail immediately on monitor errors.
  await Promise.race([until(async () => { try { await access(ready); return true } catch { return false } }, 'memory monitor readiness', 30000), completed.then(() => { throw new Error('Memory monitor exited before ready') })])
  return async () => { await writeFile(stop, 'stop'); await completed; return JSON.parse((await readFile(file, 'utf8')).replace(/^\uFEFF/, '')) }
}
// First run (welcome, name, ID card), the app bridge, Ctrl K command menu, settings sheet and remembered classes.
async function appFlowChecks() {
  const storage = await mkdtemp(path.join(cache, 'offline-first-run-'))
  const { app, page } = await launch(storage, { firstRun: true })
  try {
    await page.getByRole('button', { name: 'Let’s go →', exact: true }).click()
    await page.getByRole('button', { name: 'That’s me →', exact: true }).click()
    await page.getByText('Type a name, or skip for now.', { exact: true }).waitFor()
    await page.getByLabel('Your name', { exact: true }).fill('Sam')
    await page.getByRole('button', { name: 'That’s me →', exact: true }).click()
    await page.getByRole('heading', { level: 1 }).filter({ hasText: 'Sam' }).waitFor()
    assert.deepEqual(JSON.parse(await readFile(path.join(storage, 'settings.json'), 'utf8')), { name: 'Sam', onboarded: true, recent: [] })
    assert.equal(await page.evaluate(() => Object.keys(window.byeApp).sort().join(',')), 'checkForUpdate,getSettings,info,openDownload,setSettings')
    assert.equal(await page.evaluate(() => Object.keys(window.bye).sort().join(',')), 'command,subscribe')
    await page.keyboard.press('Control+k')
    await page.getByRole('dialog', { name: 'Command menu' }).waitFor()
    await page.keyboard.press('Escape')
    await page.getByRole('dialog', { name: 'Command menu' }).waitFor({ state: 'hidden' })
    await page.getByRole('button', { name: 'Your name and settings', exact: true }).click()
    await page.getByRole('dialog', { name: 'Settings' }).waitFor()
    await page.getByRole('group', { name: 'Settings sections' }).getByRole('button', { name: 'Updates', exact: true }).click()
    await page.getByRole('button', { name: 'Check for updates', exact: true }).waitFor()
    await page.getByRole('button', { name: 'Close settings', exact: true }).click()
    await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202650')
    await page.getByRole('combobox', { name: 'Class', exact: true }).fill('ETH14')
    await page.getByRole('button', { name: 'Find professors' }).click()
    await page.getByRole('button', { name: 'Change search', exact: true }).waitFor()
    await until(async () => JSON.parse(await readFile(path.join(storage, 'settings.json'), 'utf8')).recent.length === 1, 'remembered class')
    await page.getByRole('navigation', { name: 'Places' }).getByRole('button', { name: /ETH/ }).first().waitFor()
    // Classes behave like tabs: stable order, and each one comes back exactly as it was left.
    const places = page.getByRole('navigation', { name: 'Places' })
    const idle = async label => until(async () => { const st = await state(app); return !st.loading && !st.previewPending }, label)
    await idle('ETH results')
    await page.getByRole('group', { name: 'Sort professors', exact: true }).getByRole('button', { name: 'Difficulty', exact: true }).click()
    await page.getByRole('button', { name: /Blair Sample.*sections?/ }).click()
    await page.getByRole('heading', { name: 'Blair Sample', exact: true }).waitFor()
    // Switching professors updates the page in place (no remount, no flash).
    await page.evaluate(() => { document.querySelector('.report').dataset.kept = 'yes' })
    await page.getByRole('button', { name: /Alex Example.*sections?/ }).click()
    await page.getByRole('heading', { name: 'Alex Example', exact: true }).waitFor()
    assert.equal(await page.evaluate(() => document.querySelector('.report')?.dataset.kept), 'yes', 'Report remounted when switching professors')
    await page.getByRole('button', { name: /Blair Sample.*sections?/ }).click()
    await page.getByRole('heading', { name: 'Blair Sample', exact: true }).waitFor()
    await page.getByRole('button', { name: 'Change search', exact: true }).click()
    await page.getByRole('combobox', { name: 'Class', exact: true }).fill('MATH 005A')
    await page.getByRole('button', { name: 'Find professors' }).click()
    await page.getByRole('button', { name: 'Change search', exact: true }).waitFor(); await idle('MATH results')
    assert.deepEqual(JSON.parse(await readFile(path.join(storage, 'settings.json'), 'utf8')).recent, ['ETH 014', 'MATH 005A'])
    assert.equal(await page.getByRole('heading', { name: 'Blair Sample', exact: true }).count(), 0, 'A new class opens on the overview')
    await places.getByRole('button', { name: 'ETH 014', exact: true }).click()
    await page.getByRole('heading', { name: 'Blair Sample', exact: true }).waitFor({ timeout: 2000 })
    assert.equal(await page.getByRole('group', { name: 'Sort professors', exact: true }).getByRole('button', { name: 'Difficulty', exact: true }).getAttribute('aria-pressed'), 'true')
    await idle('ETH reload'); await page.getByRole('heading', { name: 'Blair Sample', exact: true }).waitFor()
    await places.getByRole('button', { name: 'MATH 005A', exact: true }).click(); await idle('MATH reload')
    assert.deepEqual(await places.getByRole('button', { name: /^(ETH|MATH)/ }).allTextContents(), ['ETH 014', 'MATH 005A'], 'Sidebar order stays put')
    checks.push('Your classes keep their order; each class keeps its professor, sort and page; switching professors updates in place')
    await page.screenshot({ path: path.join(output, 'first-run-results.png') })
    // Source freshness applies to the overview too, including co-instructor deduplication.
    await app.evaluate(() => { const e=globalThis.__offline.engine; for(const p of e.state.professors) for(const s of p.sections) { s.source={source:'pcc',retrievedAt:Date.now()-3600000,expiresAt:Date.now()-2700000,stale:true};s.details={...s.details,seatsOpen:7,capacity:30} }; e.emit() })
    assert.equal(await page.getByRole('region',{name:'Course overview'}).getByText('open seats',{exact:true}).count(),0,'Stale overview must not show seat totals')
    await page.getByRole('button',{name:/Alex Example.*sections?/}).click()
    await page.getByRole('heading',{name:'Alex Example',exact:true}).waitFor()
    const bye=page.getByRole('region',{name:'BYE student reviews'})
    await bye.getByText('25 BYE reviews across all courses',{exact:false}).waitFor()
    assert.equal(await bye.locator('[data-bye-unsafe]').count(),0,'BYE review text must not become HTML')
    assert.match(await bye.innerText(),/<img data-bye-unsafe/)
    assert.equal(await bye.locator('.review-card').count(),20)
    await bye.getByRole('button',{name:'Show more BYE reviews',exact:true}).click()
    await until(async()=>await bye.locator('.review-card').count()===25,'second BYE page')
    await bye.getByLabel('Sort BYE reviews',{exact:true}).selectOption('highest')
    await until(async()=>await bye.locator('.review-card').count()===20,'BYE sort replaces previous page')
    assert.equal(await page.evaluate(()=>!!(document.querySelector('.bye-reviews').compareDocumentPosition(document.querySelector('[aria-label="Rate My Professors scores"]')) & Node.DOCUMENT_POSITION_FOLLOWING)),true,'BYE reviews must precede RMP scores')
    await page.evaluate(()=>{document.querySelector('.report').dataset.refreshKept='yes'})
    await app.evaluate(()=>{globalThis.__offline.controls.scheduleFailure=true})
    await page.getByRole('button',{name:'Refresh',exact:true}).click()
    await page.getByText('Fixture schedule refresh failed.',{exact:false}).first().waitFor()
    assert.equal(await page.evaluate(()=>document.querySelector('.report')?.dataset.refreshKept),'yes','Refresh failure must retain the open report')
    assert.equal(await page.locator('.seats').count(),0)
    await app.evaluate(()=>{globalThis.__offline.controls.scheduleFailure=false})
    await page.getByRole('button',{name:'Refresh',exact:true}).click()
    await until(async()=>!(await state(app)).refreshing,'retry schedule refresh')
    assert.equal(await page.getByText('Fixture schedule refresh failed.',{exact:false}).count(),0,'Successful retry clears refresh error')
    await page.locator('.detail').evaluate(el=>el.scrollTo(0,0)); await delay(1000)
    await page.screenshot({path:path.join(output,'bye-first-report.png'),fullPage:true})
    checks.push('BYE-first source separation, safe review text, 20-row pagination, stale overview suppression and visible refresh failure/retry passed')
    // The same course in a different semester must not restore that semester's professor selection or filters.
    await page.getByRole('button',{name:'Change search',exact:true}).click()
    await page.getByRole('combobox',{name:'Class',exact:true}).fill('MATH 005B')
    await page.getByRole('button',{name:'Find professors'}).click();await idle('Summer MATH 005B')
    await page.getByRole('button',{name:/Alex Example.*sections?/}).click()
    await page.getByRole('heading',{name:'Alex Example',exact:true}).waitFor()
    await page.getByRole('button',{name:'Friday',exact:true}).click()
    await page.getByRole('button',{name:'Change search',exact:true}).click()
    await page.getByRole('combobox',{name:'Semester',exact:true}).selectOption('202670')
    await page.getByRole('button',{name:'Find professors'}).click();await idle('Fall MATH 005B')
    await page.getByRole('region',{name:'Course overview'}).waitFor()
    assert.equal(await page.getByRole('button',{name:'Friday',exact:true}).getAttribute('aria-pressed'),'false','Filters must be scoped to semester and course')
    assert.equal(await page.locator('.report-name').count(),0,'A different semester cannot restore the other semester’s selected professor')
    checks.push('Semester-scoped class tabs keep professor selection and filters isolated')

    await inactive(app)
    checks.push('First run, name saved on this PC, app bridge, command menu, settings sheet and remembered classes passed; no network')
  } finally { await app.close().catch(() => {}) }
}
const perf = process.argv.includes('--perf')
if (!perf) await appFlowChecks()
for (let number = 1; number <= (perf ? 3 : 1); number++) {
  const storage = await mkdtemp(path.join(cache, 'offline-user-')), finishMonitor = perf ? await monitor(number) : undefined
  let app, record
  try {
    const launched = await launch(storage); app = launched.app; const page = launched.page
    if (!perf) await searchRegressionChecks(app, page)
    const coldSearchMs = await search(app, page), warmReportMs = []
    if (perf) {
      for (let i = 0; i < 20; i++) { warmReportMs.push(await search(app, page)); await interactions(app, page) }
      record = { launch: number, startupMs: launched.startupMs, coldSearchMs, coldLaunchToReportMs: launched.startupMs + coldSearchMs, warmReportMs, counters: await inactive(app), processes: await app.evaluate(() => globalThis.__offline.metrics().map(p => ({ pid: p.pid, type: p.type, serviceName: p.serviceName }))) }
      assert.ok(record.processes.some(p => p.type === 'GPU')); assert.ok(record.processes.some(p => p.type === 'Tab')); assert.ok(record.processes.some(p => p.type === 'Utility'))
    } else {
      const saved = await uiChecks(app, page, storage)
      await app.close(); app = undefined
      const restored = await launch(storage); app = restored.app
      await search(app, restored.page)
      const calls = await inactive(app)
      assert.equal(calls.services.candidates, 0); assert.equal(calls.services.pages, 0)
      assert.equal(await readFile(saved.summaryPath, 'utf8'), saved.original)
      assert.equal(await restored.page.getByText('HIDDEN_CACHED_SUMMARY_SENTINEL', { exact: true }).count(), 0)
      checks.push('Fresh process restores profiles, complete review coverage and manual choices; summary cache remains stored and hidden')
    }
  } catch (error) {
    await writeFile(path.join(output, `launch-${number}-failure.json`), JSON.stringify({ error: String(error), state: app ? await state(app).catch(() => undefined) : undefined, body: app ? await (await app.firstWindow()).locator('body').innerText().catch(() => undefined) : undefined }, null, 2))
    throw error
  } finally {
    if (app) await app.close().catch(() => {})
    if (finishMonitor) { const memory = await finishMonitor(); if (record) { record.memory = memory; launches.push(record) } }
  }
  console.log(perf ? `Offline measured launch ${number}/3: 1 cold + 20 warm searches completed` : 'Offline UI and cache restoration passed')
}
assert.deepEqual(errors, [])
const report = { date: new Date().toISOString(), buildInfo: info, verification: perf ? 'whole-app offline performance' : 'offline UI', checks, network: 'blocked; no unexpected requests', launches, errors }
if (perf) {
  const hardware = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command', '$c = Get-CimInstance Win32_Processor; $s = Get-CimInstance Win32_ComputerSystem; $o = Get-CimInstance Win32_OperatingSystem; @{ cpu = @($c.Name); logicalProcessors = $s.NumberOfLogicalProcessors; installedRamBytes = $s.TotalPhysicalMemory; operatingSystem = $o.Caption; osVersion = $o.Version } | ConvertTo-Json -Compress'], { windowsHide: true }).toString())
  const warm = launches.flatMap(l => l.warmReportMs).sort((a, b) => a - b), peakRssBytes = Math.max(...launches.map(l => l.memory.peakRssBytes)), peakPrivateBytes = Math.max(...launches.map(l => l.memory.peakPrivateBytes))
  assert.equal(warm.length, 60); assert.ok(launches.every(l => l.memory.samples.length > 0 && l.processes.every(p => l.memory.processes[String(p.pid)])), 'Monitor must observe main, renderer, GPU and utility PIDs')
  Object.assign(report, { hardware, runtime: { node: process.versions.node, electron: pkg.devDependencies.electron }, peakRssBytes, peakPrivateBytes, thresholdBytes: 1500000000, ramPassed: peakRssBytes < 1500000000 && peakPrivateBytes < 1500000000, warmReportP95Ms: warm[Math.ceil(warm.length * .95) - 1], aiWarmP95: 'UNVERIFIED: summaries disabled', limitations: ['Three fresh processes with isolated storage; Windows filesystem/OS caches were not flushed.', 'Saved schedule with fictional profiles/reviews; fixture delays are not live API latency.', 'RSS sums process working sets and can double-count shared pages; private bytes reported separately.', '100 ms target interval plus enumeration overhead; brief spikes or processes between samples may be missed.', 'Playwright controller and PowerShell monitor are excluded; instrumentation still affects scheduling.', 'Warm report-loading latency includes IPC, Engine/cache work, React presentation and two browser frames; it does not measure AI.'] })
  await writeFile(path.join(output, 'REPORT.md'), `# Windows offline baseline ${info.version}\n\nAI disabled; weights omitted. Electron ${pkg.devDependencies.electron}.\n\nThree fresh launches, one initial search and twenty warm searches each (60 warm).\n\n| Metric | Result |\n|---|---:|\n| Sampled whole-app peak RSS | ${peakRssBytes} bytes |\n| Sampled whole-app peak private memory | ${peakPrivateBytes} bytes |\n| Strict RAM threshold | < 1,500,000,000 bytes: ${report.ramPassed ? 'PASS' : 'FAIL'} |\n| Warm report-loading P95 (nearest rank) | ${report.warmReportP95Ms.toFixed(2)} ms |\n| AI P95 < 3 seconds | UNVERIFIED (disabled) |\n\nCold launch-to-report timings: ${launches.map(l => l.coldLaunchToReportMs.toFixed(2) + ' ms').join(', ')}. Startup and initial search are recorded separately in report.json.\n\nHardware: ${hardware.cpu.join(', ')}; ${hardware.logicalProcessors} logical CPUs; ${hardware.installedRamBytes} bytes installed RAM; ${hardware.operatingSystem} ${hardware.osVersion}.\n\n${report.limitations.map(s => '- ' + s).join('\n')}\n\nNo PCC/RMP requests. Raw per-process samples, all timings and process types are retained beside this report.\n`)
}
report.builtMainSha256 = await digest(path.join(root, 'out/main/bootstrap.js'))
report.builtFilesSha256 = {}
async function fingerprint(folder) {
  for (const item of await readdir(folder, { withFileTypes: true })) {
    const file = path.join(folder, item.name)
    if (item.isDirectory()) await fingerprint(file)
    else if (item.isFile()) report.builtFilesSha256[path.relative(path.join(root, 'out'), file)] = await digest(file)
  }
}
await fingerprint(path.join(root, 'out'))
await writeFile(path.join(output, 'report.json'), JSON.stringify(report, null, 2))
await writeFile(path.join(results, perf ? 'offline-perf-latest.json' : 'offline-ui-latest.json'), JSON.stringify({ directory: path.relative(root, output), report: path.relative(root, path.join(output, 'report.json')) }, null, 2))
console.log(`Report: ${path.relative(root, output)}`)
if (perf && !report.ramPassed) throw new Error('Whole-app sampled RAM exceeds the strict threshold; see measurement report.')
