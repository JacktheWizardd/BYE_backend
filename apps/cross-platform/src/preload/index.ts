import { contextBridge, ipcRenderer } from 'electron'
import type { Bridge, Snapshot } from '../shared/types'
const api: Bridge = {
  command: command => ipcRenderer.invoke('bye:command', command),
  subscribe: listener => {
    const handler = (_event: Electron.IpcRendererEvent, state: Snapshot) => listener(state)
    ipcRenderer.on('bye:state', handler)
    return () => ipcRenderer.removeListener('bye:state', handler)
  }
}
contextBridge.exposeInMainWorld('bye', api)
