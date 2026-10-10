import { app, BrowserWindow, ipcMain, shell } from 'electron'
import path from 'node:path'
import os from 'node:os'
import { Engine } from './engine'
import { PCC, RMP } from './network'
import { Store } from './storage'
import { LocalSummaries } from './summary'
import type { Command, Snapshot, Term } from '../shared/types'
const storage = process.env.BYE_TEST_STORAGE && !app.isPackaged ? process.env.BYE_TEST_STORAGE : path.join(process.platform === 'win32' ? process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData', 'Local') : app.getPath('appData'), 'BYECrossPlatformBeta')
app.setPath('userData', storage)
let window: BrowserWindow | undefined
const ai = new LocalSummaries(app.isPackaged ? path.join(process.resourcesPath, 'models') : path.resolve(import.meta.dirname, '../../models'))
const engine = new Engine(new PCC(), new RMP(), new Store(path.join(storage, 'reports')), ai, (state: Snapshot) => window?.webContents.send('bye:state', state))
function validate(raw: unknown): Command {
  if (!raw || typeof raw !== 'object') throw new Error('Unsupported command.')
  const c = raw as Record<string, unknown>, kinds = ['terms', 'suggest', 'search', 'stop', 'retry', 'discover', 'dismiss', 'summary', 'select', 'details', 'source']
  if (typeof c.kind !== 'string' || !kinds.includes(c.kind)) throw new Error('Unsupported command.')
  const text = (key: string, max: number, optional = false) => { if (optional && c[key] === undefined) return; if (typeof c[key] !== 'string' || !c[key] || (c[key] as string).length > max) throw new Error('Invalid ' + key) }
  if (['retry', 'discover', 'dismiss', 'summary', 'select', 'details'].includes(c.kind)) text('professorId', 300)
  if (c.kind === 'select') { text('profileId', 30); if (!/^[1-9]\d*$/.test(c.profileId as string)) throw new Error('Invalid profile ID.') }
  if (c.kind === 'details') text('filter', 100, true)
  if (c.kind === 'suggest') { text('term', 6); if (!/^\d{6}$/.test(c.term as string)) throw new Error('Invalid semester.'); if (typeof c.query !== 'string' || c.query.length > 100) throw new Error('Invalid query.') }
  if (c.kind === 'search') {
    text('query', 100)
    const t = c.term as Term; if (!t || !/^\d{6}$/.test(t.termCode) || typeof t.termName !== 'string' || t.termName.length > 100 || (c.refresh !== undefined && typeof c.refresh !== 'boolean')) throw new Error('Invalid search.')
  }
  if (c.kind === 'source') { if (!['pcc', 'rmp'].includes(String(c.target))) throw new Error('Invalid source.'); text('professorId', 300, true); text('candidateId', 30, true) }
  return c as unknown as Command
}
function createWindow() {
  window = new BrowserWindow({ width: 1180, height: 800, minWidth: 1000, minHeight: 700, title: 'BYE — Before You Enroll', backgroundColor: '#f8f7f3', show: false,
    webPreferences: { preload: path.join(import.meta.dirname, '../preload/index.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false, spellcheck: false } })
  window.removeMenu()
  window.once('ready-to-show', () => window?.show())
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  window.webContents.on('will-navigate', event => event.preventDefault())
  window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
  window.webContents.on('did-finish-load', () => engine.emit())
  window.on('closed', () => { window = undefined; engine.stop() })
  if (!app.isPackaged && process.env.ELECTRON_RENDERER_URL) void window.loadURL(process.env.ELECTRON_RENDERER_URL)
  else void window.loadFile(path.join(import.meta.dirname, '../renderer/index.html'))
}
app.whenReady().then(() => {
  ipcMain.handle('bye:command', async (event, raw) => {
    if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame) throw new Error('Untrusted command sender.')
    const c = validate(raw)
    switch (c.kind) {
      case 'terms': return engine.pcc.terms()
      case 'suggest': return engine.pcc.suggest(c.term, c.query)
      case 'search': void engine.search(c.query, c.term, c.refresh); return undefined
      case 'stop': engine.stop(); return undefined
      case 'retry': void engine.retry(c.professorId); return undefined
      case 'discover': void engine.discover(c.professorId); return undefined
      case 'dismiss': engine.dismiss(c.professorId); return undefined
      case 'select': void engine.select(c.professorId, c.profileId); return undefined
      case 'details': void engine.expand(c.professorId, c.filter); return undefined
      case 'summary': void engine.summarize(c.professorId); return undefined
      case 'source': {
        const p = engine.state.professors.find(x => x.id === c.professorId)
        const candidate = c.candidateId ? p?.candidates.find(x => x.id === c.candidateId) : undefined
        if (c.candidateId && !candidate) throw new Error('This candidate is no longer in the current list.')
        const url = c.target === 'pcc' ? `https://findclasses.pasadena.edu/?term=${engine.state.term?.termCode ?? ''}&q=${encodeURIComponent(engine.state.course?.display ?? '')}` : candidate || p?.profile ? `https://www.ratemyprofessors.com/professor/${(candidate ?? p!.profile!).id}` : `https://www.ratemyprofessors.com/search/professors/2649?q=${encodeURIComponent(p?.name ?? '')}`
        await shell.openExternal(url); return undefined
      }
    }
  })
  createWindow()
})
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
app.on('activate', () => { if (!window) createWindow(); else { if (window.isMinimized()) window.restore(); window.show(); window.focus() } })
app.on('before-quit', () => { engine.stop(); void ai.dispose() })
