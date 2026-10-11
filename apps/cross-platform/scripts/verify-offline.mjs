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
  await page.getByRole('button', { name: 'Summary disabled', exact: true }).waitFor()
  // Include React presentation and two browser frames in report-loading latency.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
}
async function search(app, page) {
  const before = (await state(app)).operationId, start = performance.now()
  await page.getByRole('button', { name: 'Find classes' }).click()
  await readyReport(app, page, before)
  return performance.now() - start
}
async function launch(storage) {
  const start = performance.now()
  const app = await electron.launch({ executablePath: require('electron'), args: [entry], env: { ...env, BYE_OFFLINE_ROOT: root, BYE_OFFLINE_STORAGE: storage }, timeout: 30000 })
  try {
    const page = await app.firstWindow({ timeout: 30000 }); page.on('pageerror', error => errors.push(error.message))
    await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202650')
    await page.getByRole('combobox', { name: 'Course', exact: true }).fill('ETH14')
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
  await page.getByRole('combobox', { name: 'Sort', exact: true }).selectOption('highest')
  await page.getByRole('button', { name: /Alex Example.*sections?/ }).click()
  await page.getByRole('heading', { name: 'Alex Example', exact: true }).waitFor()
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
  await page.getByRole('combobox', { name: 'Sort', exact: true }).selectOption('highest')
  assert.match(await page.locator('.review').first().innerText(), /Rating 5\.0/)
  await page.getByRole('combobox', { name: 'Sort', exact: true }).selectOption('lowest')
  assert.match(await page.locator('.review').first().innerText(), /Rating 1\.0/)
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('HIST001')
  assert.equal(await page.locator('.review').count(), 3)
  for (const label of await page.locator('.review-heading strong').allTextContents()) assert.equal(label, 'HIST001')
  await page.getByRole('combobox', { name: 'Sort professors', exact: true }).selectOption('difficulty')
  checks.push('Search, professor switching, review loading, course filters, rating sorts and progressive reveal passed')
  await app.evaluate(() => { globalThis.__offline.controls.ambiguous = true })
  await page.getByRole('button', { name: 'Change profile', exact: true }).click()
  await page.getByRole('dialog').waitFor()
  assert.equal(await page.getByRole('button', { name: 'Use this profile', exact: true }).count(), 2)
  await page.getByRole('button', { name: 'Use this profile', exact: true }).last().click()
  await until(async () => { const p = (await state(app)).professors[0]; return p.profile?.coverage.all?.hasNextPage === false && !p.detailLoading }, 'chosen profile report')
  checks.push('Ambiguous profile chooser and persisted manual selection passed')
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('HIST001')
  await app.evaluate(() => { globalThis.__offline.controls.holdPages = true })
  await page.getByRole('button', { name: 'Find more for this class', exact: true }).click()
  await page.getByRole('button', { name: 'Stop', exact: true }).waitFor()
  await page.getByRole('button', { name: 'Stop', exact: true }).click()
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
  assert.equal(await page.getByRole('button', { name: 'Summary disabled', exact: true }).isDisabled(), true)
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
const perf = process.argv.includes('--perf')
for (let number = 1; number <= (perf ? 3 : 1); number++) {
  const storage = await mkdtemp(path.join(cache, 'offline-user-')), finishMonitor = perf ? await monitor(number) : undefined
  let app, record
  try {
    const launched = await launch(storage); app = launched.app; const page = launched.page
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
