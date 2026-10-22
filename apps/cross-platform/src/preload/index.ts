import { contextBridge, ipcRenderer } from 'electron'
import type { Bridge, Snapshot } from '../shared/types'
import type { AppBridge } from '../shared/app'
const api: Bridge = {
  command: command => ipcRenderer.invoke('bye:command', command),
  subscribe: listener => {
    const handler = (_event: Electron.IpcRendererEvent, state: Snapshot) => listener(state)
    ipcRenderer.on('bye:state', handler)
    return () => ipcRenderer.removeListener('bye:state', handler)
  }
}
contextBridge.exposeInMainWorld('bye', api)
// App preferences and the update check, separate from the data bridge above. Main validates every call.
const app: AppBridge = {
  info: () => ipcRenderer.invoke('bye:app:info'),
  getSettings: () => ipcRenderer.invoke('bye:settings:get'),
  setSettings: update => ipcRenderer.invoke('bye:settings:set', update),
  checkForUpdate: () => ipcRenderer.invoke('bye:update:check'),
  openDownload: url => ipcRenderer.invoke('bye:update:open', url),
  sendNumberCode: email => ipcRenderer.invoke('bye:number:send', email),
  verifyNumberCode: (email, code) => ipcRenderer.invoke('bye:number:verify', email, code),
  refreshNumberTotal: () => ipcRenderer.invoke('bye:number:refresh')
}
contextBridge.exposeInMainWorld('byeApp', app)
