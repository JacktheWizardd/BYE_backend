import {createRequire} from 'node:module'
import {fileURLToPath} from 'node:url'
import path from 'node:path'
import {readFile,writeFile,mkdir,cp,mkdtemp,stat,chmod} from 'node:fs/promises'
import {createHash} from 'node:crypto'
import {execFileSync} from 'node:child_process'
const root=path.dirname(fileURLToPath(import.meta.url)),repo=path.resolve(root,'../..')
const require=createRequire(path.join(root,'package.json'))
const {build,Platform,Arch}=require('electron-builder'),asar=require('@electron/asar')
const pkg=JSON.parse(await readFile(path.join(root,'package.json'),'utf8'))
const output=path.join(repo,'dist/retirement'),stage=await mkdtemp(path.join(await mkdir(output,{recursive:true}).then(()=>output),'.windows-'))
const artifact=path.join(output,`BYE-Retirement-${pkg.version}-windows-x64.zip`)
try {await stat(artifact);throw Error('Refusing to overwrite an existing retirement artifact')} catch(error) {if(error.code!=='ENOENT')throw error}
const electronDist=process.env.BYE_RETIREMENT_ELECTRON_DIST
if(!electronDist)throw Error('Set BYE_RETIREMENT_ELECTRON_DIST to a verified Electron 44.7.0 Windows x64 runtime')
await cp(path.join(repo,'Sources/Classwise/Resources/LibreBaskerville-Bold.ttf'),path.join(root,'LibreBaskerville-Bold.ttf'))
await build({projectDir:root,targets:Platform.WINDOWS.createTarget('dir',Arch.x64),config:{appId:'org.bye.crossplatform.beta',productName:'BYE',electronVersion:'44.7.0',electronDist,directories:{output:stage},npmRebuild:false,asar:true,files:['main.cjs','preload.cjs','policy.cjs','uninstall.cjs','renderer.js','index.html','retirement.css','LibreBaskerville-Bold.ttf','THIRD_PARTY_NOTICES.txt','package.json'],win:{executableName:'BYE',signAndEditExecutable:false}}})
const app=path.join(stage,'win-unpacked'),archive=path.join(app,'resources/app.asar')
const expected=['/main.cjs','/preload.cjs','/policy.cjs','/uninstall.cjs','/renderer.js','/index.html','/retirement.css','/LibreBaskerville-Bold.ttf','/THIRD_PARTY_NOTICES.txt','/package.json']
const packaged=asar.listPackage(archive)
if(packaged.some(file=>!expected.includes(file.replaceAll('\\','/'))))throw Error('Unexpected module in retirement ASAR')
if(JSON.parse(asar.extractFile(archive,'package.json')).dependencies)throw Error('Retirement package must have no runtime npm dependencies')
const hash=async file=>createHash('sha256').update(await readFile(file)).digest('hex')
// Portable delivery has no installer, cleanup helper or automatic file removal.
// Users quit BYE, move its old application folder to Recycle Bin, and extract this into a fresh folder.
const seven=require('7zip-bin').path7za
const localSeven=path.join(stage,path.basename(seven));await cp(seven,localSeven);await chmod(localSeven,0o755)
execFileSync(localSeven,['a','-tzip','-mx=5',artifact,'.'],{cwd:app,stdio:'inherit'})
execFileSync(localSeven,['t',artifact],{stdio:'inherit'})
await writeFile(artifact+'.sha256',(await hash(artifact))+'  '+path.basename(artifact)+'\n')
await writeFile(path.join(output,'windows-package.json'),JSON.stringify({version:pkg.version,delivery:'portable ZIP; manual removal of old application',stage:path.relative(repo,stage),asarFiles:packaged,nativeWindowsTested:false,releaseBlocked:true},null,2)+'\n')
console.log('Prepared unpublished Windows retirement ZIP. Native Windows acceptance is required before release.')
