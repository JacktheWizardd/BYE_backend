import { app } from 'electron'
import path from 'node:path'
import os from 'node:os'
import { startApplication } from './bootstrap'
import { PCC, RMP, Transport, offlineFetch } from './network'
import { LocalSummaries } from './summary'
import { NETWORK_ENABLED } from '../shared/features'
const storage = process.env.BYE_TEST_STORAGE && !app.isPackaged ? process.env.BYE_TEST_STORAGE : path.join(process.platform === 'win32' ? process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData', 'Local') : app.getPath('appData'), 'BYECrossPlatformBeta')
startApplication({
  // The final release hands every client a fetch that refuses, so PCC and RMP can never be contacted.
  storage, pcc: NETWORK_ENABLED ? new PCC() : new PCC(offlineFetch), rmp: NETWORK_ENABLED ? new RMP() : new RMP(new Transport(offlineFetch)),
  ai: new LocalSummaries(app.isPackaged ? path.join(process.resourcesPath, 'models') : path.resolve(import.meta.dirname, '../../models')),
  preload: path.join(import.meta.dirname, '../preload/index.cjs'), renderer: path.join(import.meta.dirname, '../renderer/index.html'),
  rendererURL: !app.isPackaged ? process.env.ELECTRON_RENDERER_URL : undefined
})
