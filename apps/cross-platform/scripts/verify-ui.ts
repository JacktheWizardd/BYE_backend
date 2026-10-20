import { _electron as electron } from 'playwright'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import assert from 'node:assert/strict'
const root = path.resolve(import.meta.dirname, '..'), output = path.join(root, 'test-results')
await mkdir(output, { recursive: true })
const data = await mkdtemp(path.join(os.tmpdir(), 'BYE UI 测试 '))
const env: Record<string, string> = Object.fromEntries(Object.entries(process.env).filter((entry): entry is [string, string] => entry[1] !== undefined))
env.BYE_TEST_STORAGE = data
delete env.ELECTRON_RUN_AS_NODE
// Start past first-run setup (scripts/verify-offline.mjs covers welcome and naming).
await writeFile(path.join(data, 'settings.json'), JSON.stringify({ name: '', onboarded: true, recent: [] }))
const app = await electron.launch({ executablePath: path.join(root, 'node_modules/electron/dist/electron.exe'), args: [root], env, timeout: 30000 })
const errors: string[] = [], results: string[] = []
app.process().stderr?.on('data', chunk => { const text = String(chunk); if (/Error|failed to load/i.test(text)) errors.push(text) })
try {
  const page = await app.firstWindow(); page.on('pageerror', e => errors.push(e.message))
  await page.getByText('What are you taking next term?', { exact: true }).waitFor()
  await page.getByLabel('Semester', { exact: true }).selectOption('202710', { timeout: 45000 })
  await page.getByRole('combobox', { name: 'Class', exact: true }).fill('math 5a')
  await page.getByRole('button', { name: 'Find professors' }).click()
  await page.getByRole('heading', { name: 'Professors', exact: true }).waitFor({ timeout: 45000 })
  await page.getByText('MATH 005A', { exact: true }).first().waitFor()
  await page.getByText('8 sections · 7 professors', { exact: false }).waitFor()
  await page.getByText('Choose a professor on the left to see their sections, ratings and student reviews.').waitFor()
  await page.getByRole('button', { name: /Anahit Asadyan/ }).click()
  await page.getByRole('heading', { name: 'Anahit Asadyan', exact: true }).waitFor()
  await page.getByRole('button', { name: 'Change profile', exact: true }).waitFor({ timeout: 45000 })
  results.push('Live shorthand search: Winter 2027 MATH 005A, 8 sections, 7 professors; course overview opens first; verified ratings rendered')
  await page.screenshot({ path: path.join(output, 'windows-report.png'), fullPage: true })
  await page.getByRole('button', { name: 'Cancel', exact: true }).click().catch(() => {})
  // Renderer isolation and typed-only bridge are checked in the actual Electron window.
  assert.equal(await page.evaluate(() => typeof (window as any).require), 'undefined')
  assert.equal(await page.evaluate(() => Object.keys(window.bye).sort().join(',')), 'command,subscribe')
  assert.equal(await page.evaluate(() => Object.keys((window as any).byeApp).sort().join(',')), 'checkForUpdate,getSettings,info,openDownload,setSettings')
  results.push('Renderer has no require; data bridge exposes only command and subscribe; app bridge only settings, info and the update check')
  const reportName = await page.getByRole('heading', { name: 'Anahit Asadyan', exact: true }).textContent()
  await page.getByRole('combobox', { name: 'Review course', exact: true }).selectOption('all')
  await page.getByRole('combobox', { name: 'Sort reviews', exact: true }).selectOption('lowest')
  assert.equal(await page.getByRole('heading', { name: 'Anahit Asadyan', exact: true }).textContent(), reportName)
  results.push('Review course/sort controls retain selected report')
  await page.getByRole('button', { name: 'Change profile', exact: true }).click()
  await page.getByRole('dialog').waitFor()
  await page.keyboard.press('Escape')
  await page.getByRole('dialog').waitFor({ state: 'hidden' })
  results.push('Profile chooser opens, Escape dismisses, report remains')
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.setZoomFactor(1.25))
  await page.screenshot({ path: path.join(output, 'windows-report-125-percent.png'), fullPage: true })
  results.push('125% zoom and reduced motion rendered; screenshots saved')
  await page.keyboard.press('Tab')
  assert.notEqual(await page.evaluate(() => document.activeElement?.tagName), 'BODY')
  results.push('Keyboard focus reaches controls')
  await app.evaluate(({ BrowserWindow }) => { const window = BrowserWindow.getAllWindows()[0]; window.minimize(); window.restore() })
  results.push('Window minimize/restore succeeds')
  await page.getByRole('button', { name: 'Cancel', exact: true }).click().catch(() => {})
  assert.deepEqual(errors.filter(x => !/GPU|cache|disk_cache|Passthrough/i.test(x)), [])
} finally {
  await app.close()
  await writeFile(path.join(output, 'ui-verification.json'), JSON.stringify({ date: new Date().toISOString(), results, errors, isolatedStorage: true, limitations: ['Development Electron app on the current Windows host; not a clean-machine test.', 'Full Narrator and physical interaction checks remain pending.'] }, null, 2))
}
console.log(results.join('\n'))
