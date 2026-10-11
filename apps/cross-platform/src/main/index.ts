import { app } from 'electron'
import path from 'node:path'
import os from 'node:os'
import { startApplication } from './bootstrap'
import { PCC, RMP } from './network'
import { LocalSummaries } from './summary'
const storage = process.env.BYE_TEST_STORAGE && !app.isPackaged ? process.env.BYE_TEST_STORAGE : path.join(process.platform === 'win32' ? process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData', 'Local') : app.getPath('appData'), 'BYECrossPlatformBeta')
startApplication({
  storage, pcc: new PCC(), rmp: new RMP(),
  ai: new LocalSummaries(app.isPackaged ? path.join(process.resourcesPath, 'models') : path.resolve(import.meta.dirname, '../../models')),
  preload: path.join(import.meta.dirname, '../preload/index.cjs'), renderer: path.join(import.meta.dirname, '../renderer/index.html'),
  rendererURL: !app.isPackaged ? process.env.ELECTRON_RENDERER_URL : undefined
})
