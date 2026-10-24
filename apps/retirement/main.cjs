const {app,BrowserWindow,ipcMain,session,shell}=require('electron')
const path=require('node:path')
const {pathToFileURL}=require('node:url')
const {readLatest,newer,DOWNLOAD_URL}=require('./policy.cjs')
const {openRegisteredUninstaller}=require('./uninstall.cjs')
let window, offered=false, checking=false
app.setAppUserModelId('org.bye.crossplatform.beta')
// Never open or migrate the previous BYE preferences/cache directory.
app.whenReady().then(() => {
  session.defaultSession.webRequest.onBeforeRequest({urls:['http://*/*','https://*/*','ws://*/*','wss://*/*']},(_details,callback)=>callback({cancel:true}))
  session.defaultSession.setPermissionRequestHandler((_webContents,_permission,callback)=>callback(false))
  const page=pathToFileURL(path.join(__dirname,'index.html')).href
  window=new BrowserWindow({width:680,height:520,minWidth:360,minHeight:420,backgroundColor:'#faf8f3',autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,devTools:false}})
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}))
  window.webContents.on('will-navigate',event=>event.preventDefault())
  const trusted=event=>{if(event.sender!==window.webContents || event.senderFrame!==window.webContents.mainFrame || event.senderFrame.url!==page) throw Error('Untrusted sender')}
  ipcMain.handle('retirement:info',event=>{trusted(event);return {version:app.getVersion()}})
  ipcMain.handle('retirement:check',async event=>{
    trusted(event);if(checking) throw Error('An update check is already running')
    checking=true;offered=false
    try {const latest=await readLatest();offered=newer(latest.version,app.getVersion());return {available:offered,version:latest.version}} finally {checking=false}
  })
  ipcMain.handle('retirement:open-update',async event=>{trusted(event);if(!offered) throw Error('Check for updates first');await shell.openExternal(DOWNLOAD_URL)})
  ipcMain.handle('retirement:show-folder',event=>{trusted(event);shell.showItemInFolder(process.execPath)})
  ipcMain.handle('retirement:uninstall',async event=>{
    trusted(event)
    if(process.platform!=='win32')throw Error('Windows only')
    const result=await openRegisteredUninstaller()
    if(result.opened){setImmediate(()=>app.quit());return {mode:'uninstaller'}}
    await shell.openExternal('ms-settings:appsfeatures')
    return {mode:'settings'}
  })
  ipcMain.handle('retirement:quit',event=>{trusted(event);app.quit()})
  window.loadFile(path.join(__dirname,'index.html'))
})
app.on('window-all-closed',()=>app.quit())
