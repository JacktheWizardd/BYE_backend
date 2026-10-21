import { app } from 'electron'
import path from 'node:path'
import os from 'node:os'
import { startApplication } from './bootstrap'
import { RMP } from './network'
import { SchedulePCC } from './schedule-pcc'
import { ScheduleCatalogStore } from './schedule-catalog-store'
import { ScheduleClient } from '../shared/schedule-api'
import { LocalSummaries } from './summary'
declare const __BYE_SCHEDULE_CONFIG__: {url:string;key:string}
const configuredSchedule=typeof __BYE_SCHEDULE_CONFIG__==='undefined'?{url:'',key:''}:__BYE_SCHEDULE_CONFIG__
const storage = process.env.BYE_TEST_STORAGE && !app.isPackaged ? process.env.BYE_TEST_STORAGE : path.join(process.platform === 'win32' ? process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData', 'Local') : app.getPath('appData'), 'BYECrossPlatformBeta')
startApplication({
  storage, pcc: new SchedulePCC(new ScheduleClient(process.env.BYE_SCHEDULE_API_URL ?? configuredSchedule.url,process.env.BYE_SCHEDULE_API_KEY ?? process.env.BYE_CLIENT_KEY ?? configuredSchedule.key),new ScheduleCatalogStore(path.join(storage,'schedule-catalogs'))), rmp: new RMP(),
  ai: new LocalSummaries(app.isPackaged ? path.join(process.resourcesPath, 'models') : path.resolve(import.meta.dirname, '../../models')),
  preload: path.join(import.meta.dirname, '../preload/index.cjs'), renderer: path.join(import.meta.dirname, '../renderer/index.html'),
  rendererURL: !app.isPackaged ? process.env.ELECTRON_RENDERER_URL : undefined
})
