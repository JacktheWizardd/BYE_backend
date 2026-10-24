const api=window.retirement
const status=document.querySelector('#status'),check=document.querySelector('#check'),download=document.querySelector('#download')
api.info().then(info=>{document.querySelector('#version').textContent='Version '+info.version}).catch(()=>{status.textContent='Could not read application version.'})
check.addEventListener('click',async()=>{check.disabled=true;download.hidden=true;status.textContent='Checking for updates…';try{const result=await api.check();status.textContent=result.available?'Version '+result.version+' is available.':'You have the latest version.';download.hidden=!result.available}catch{status.textContent='Could not check for updates. Try again later.'}finally{check.disabled=false}})
download.addEventListener('click',()=>api.openUpdate().catch(()=>{status.textContent='Could not open the update download.'}))
document.querySelector('#folder').addEventListener('click',()=>api.showFolder().catch(()=>{status.textContent='Could not show the application folder.'}))
document.querySelector('#quit').addEventListener('click',()=>api.quit())

document.querySelector('#uninstall').addEventListener('click',async()=>{const button=document.querySelector('#uninstall');button.disabled=true;try{const result=await api.uninstall();status.textContent=result.mode==='uninstaller'?'Follow the Windows uninstaller to remove BYE.':'Installed apps is open. If BYE is listed, choose Uninstall. For a portable copy, quit and move its application folder to the Recycle Bin.'}catch{status.textContent='Could not open Windows uninstall. You can remove a portable copy by quitting and moving its folder to the Recycle Bin.'}finally{button.disabled=false}})
