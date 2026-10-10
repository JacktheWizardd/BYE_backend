import { _electron as electron } from 'playwright'
import { readFile, mkdtemp, writeFile, readdir, rename, unlink } from 'node:fs/promises'
import path from 'node:path'
import assert from 'node:assert/strict'
const root = path.resolve(import.meta.dirname, '..'), repo = path.resolve(root, '../..'), output = path.join(root, 'test-results')
const directory = process.argv[2] ? path.resolve(process.argv[2]) : path.join(repo, JSON.parse(await readFile(path.join(output, 'extracted.json'), 'utf8')).appDirectory)
if (!directory.startsWith(path.join(repo, 'dist') + path.sep)) throw new Error('Packaged test must run inside dist.')
const data = await mkdtemp(path.join(repo, 'dist', 'Packaged User 测试 ')), env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => entry[1] !== undefined))
env.LOCALAPPDATA = data; delete env.ELECTRON_RUN_AS_NODE
const results: string[] = [], errors: string[] = []
async function launch() { return electron.launch({ executablePath: path.join(directory, 'BYE.exe'), args: [], env, timeout: 30000 }) }
let app = await launch()
try {
  const page = await app.firstWindow({ timeout: 30000 }); page.on('pageerror', e => errors.push(e.message))
  await page.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202710', { timeout: 45000 })
  await page.getByRole('combobox', { name: 'Course', exact: true }).fill('math5a')
  await page.getByRole('button', { name: 'Find classes' }).click()
  await page.getByRole('heading', { name: 'MATH 005A', exact: true }).waitFor({ timeout: 45000 })
  await page.getByRole('heading', { name: 'Anahit Asadyan', exact: true }).waitFor()
  await page.getByText(/Analyzed \d+ complete reviews of/).waitFor({ timeout: 220000 })
  const analyzed = await page.getByText(/Analyzed \d+ complete reviews of/).textContent()
  assert.match(analyzed!, /downloaded/); results.push('Packaged BYE.exe launched and generated an embedded CPU summary: ' + analyzed)
  await page.screenshot({ path: path.join(output, 'packaged-windows-report.png'), fullPage: true })
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('all')
  await page.getByRole('button', { name: 'View more reviews', exact: true }).click()
  assert.ok(await page.locator('.review').count() > 3); results.push('Packaged review filters and progressive reveal work')
  const memory = await app.evaluate(() => process.getProcessMemoryInfo())
  await app.close()
  const reports = path.join(data, 'BYECrossPlatformBeta/reports'), files = await readdir(reports)
  assert.ok(files.some(name => name.startsWith('summary-'))); assert.ok(files.some(name => name.startsWith('profile-')))
  results.push('Profile and summary caches written outside the application folder')
  app = await launch()
  const again = await app.firstWindow(); await again.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202710', { timeout: 45000 })
  await again.getByRole('combobox', { name: 'Course', exact: true }).fill('MATH005A')
  await again.getByRole('button', { name: 'Find classes' }).click()
  await again.getByText(/Analyzed \d+ complete reviews of/).waitFor({ timeout: 60000 })
  results.push('Quit/relaunch restores cached profile evidence and summary after repeating search')
  await app.close()
  for (const name of await readdir(reports)) if (name.startsWith('summary-')) await unlink(path.join(reports, name))
  const manifest = JSON.parse(await readFile(path.join(directory, 'resources/models/manifest.json'), 'utf8'))
  const model = path.join(directory, 'resources/models', manifest.filename), backup = model + '.verification-backup'
  await rename(model, backup)
  try {
    for (const corrupt of [false, true]) {
      if (corrupt) await writeFile(model, 'incomplete model fixture')
      app = await launch()
      const recovery = await app.firstWindow({ timeout: 30000 })
      await recovery.getByRole('combobox', { name: 'Semester', exact: true }).selectOption('202710', { timeout: 45000 })
      await recovery.getByRole('combobox', { name: 'Course', exact: true }).fill('math5a')
      await recovery.getByRole('button', { name: 'Find classes' }).click()
      await recovery.getByText(corrupt ? /bundled AI model is incomplete/ : /bundled AI model is missing/).waitFor({ timeout: 60000 })
      await recovery.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('all')
      assert.ok(await recovery.locator('.review').count() > 0)
      results.push(`${corrupt ? 'Corrupt' : 'Missing'} model produces a recoverable summary error while original reviews remain usable`)
      await app.close()
      if (corrupt) await unlink(model)
    }
  } finally { await app.close().catch(() => {}); await unlink(model).catch(() => {}); await rename(backup, model) }
  assert.deepEqual(errors, [])
  await writeFile(path.join(output, 'packaged-verification.json'), JSON.stringify({ date: new Date().toISOString(), results, errors, isolatedStorage: true, mainProcessMemoryKB: memory, executableFrom: path.relative(repo, directory), limitations: ['Current development Windows host, not a clean VM.', 'No claim of complete Narrator coverage or downloaded-file SmartScreen behavior.'] }, null, 2))
} finally { await app.close().catch(() => {}) }
console.log(results.join('\n'))
