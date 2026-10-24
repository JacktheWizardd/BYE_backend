const path=require('node:path')
const fs=require('node:fs/promises')
const {execFile,spawn}=require('node:child_process')
const {promisify}=require('node:util')
const execute=promisify(execFile)
const GUID='bb2f0c74-b3a2-57e7-805f-e174cc40929e'
const INSTALL='HKCU\\Software\\'+GUID
const UNINSTALL='HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\'+GUID
function registration(location,command,displayName) {
  if(typeof location!=='string'||typeof command!=='string'||typeof displayName!=='string'||!/^BYE(?: \d+\.\d+\.\d+(?:-[\w.]+)?)?$/.test(displayName))return null
  if(!/^[A-Za-z]:\\/.test(location)||/[\x00-\x1f]/.test(location)||location.includes('..'))return null
  const root=path.win32.normalize(location).replace(/\\$/,'')
  if(root.length<6)return null
  // Preserve the original per-user, interactive uninstall; never request silent removal or data deletion.
  const match=/^"([^"\r\n]+)"(?:\s+(\/currentuser))?$/i.exec(command.trim())
  if(!match)return null
  const file=path.win32.join(root,'Uninstall BYE.exe')
  if(path.win32.normalize(match[1]).toLowerCase()!==file.toLowerCase())return null
  return {root,file,args:match[2]?['/currentuser']:[]}
}
async function openRegisteredUninstaller({readValue,checkPath,start}={}) {
  if(process.platform!=='win32'&&!readValue)return {opened:false}
  const reg=path.join(process.env.SystemRoot||'C:\\Windows','System32','reg.exe')
  readValue??=async(key,name)=>{const {stdout}=await execute(reg,['query',key,'/v',name,'/reg:64'],{timeout:5000,maxBuffer:16384,windowsHide:true});const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');return new RegExp('^\\s*'+escaped+'\\s+REG_SZ\\s+(.+)$','mi').exec(stdout)?.[1]?.trim()??''}
  checkPath??=async target=>{
    let current=target
    while(current){const item=await fs.lstat(current);if(item.isSymbolicLink())throw Error('Linked uninstaller paths are not allowed');const parent=path.dirname(current);if(parent===current)break;current=parent}
    const actual=await fs.realpath(target);if(actual.toLowerCase()!==path.resolve(target).toLowerCase())throw Error('Uninstaller path changed')
    if(!(await fs.stat(target)).isFile())throw Error('Uninstaller is not a file')
  }
  start??=async(file,args)=>new Promise((resolve,reject)=>{const child=spawn(file,args,{detached:true,stdio:'ignore',windowsHide:false,shell:false});child.once('error',reject);child.once('spawn',()=>{child.unref();resolve()})})
  try {
    const location=await readValue(INSTALL,'InstallLocation'),command=await readValue(UNINSTALL,'UninstallString'),name=await readValue(UNINSTALL,'DisplayName')
    const entry=registration(location,command,name);if(!entry)return {opened:false}
    await checkPath(path.win32.join(entry.root,'BYE.exe'));await checkPath(entry.file)
    await start(entry.file,entry.args)
    return {opened:true,root:entry.root}
  } catch {return {opened:false}}
}
module.exports={registration,openRegisteredUninstaller}
