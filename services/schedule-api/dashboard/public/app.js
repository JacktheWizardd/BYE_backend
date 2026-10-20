const $=id=>document.getElementById(id);let csrf='',offset=0,auditOffset=0,pending=null,expiryTimer;
function notice(text=''){ $('notice').textContent=text; }
function clearSecret(){ $('plaintext').textContent='';$('secret').hidden=true; }
async function post(path,input){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-BYE-Local':'1',...(csrf?{'X-CSRF-Token':csrf}:{})},body:JSON.stringify(input)});let data;try{data=await r.json();}catch{throw Error('Response lost; retry the same request.');}if(!r.ok){if(r.status===401||r.status===403){csrf='';clearSecret();$('workspace').hidden=true;$('login').hidden=false;$('signout').hidden=true;}$('notice').textContent='';const code=data.error?.code??data.error??'REQUEST_FAILED';throw Error(code+(data.userId?' · Account UUID: '+data.userId:'')+(data.message?' · '+data.message:''));}return data;}
async function busy(fn){document.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn();}catch(e){notice(e.message);}finally{document.querySelectorAll('button').forEach(b=>b.disabled=false);}}
async function manage(action,args={}){return post('/api/manage',{action,args});}
async function mutate(action,args){
 const semantic=JSON.stringify({action,args});
 if(pending && pending.semantic!==semantic) throw Error('A previous result is uncertain. Retry its action with the same values before starting another mutation. Refresh lists and audit to inspect it. Reloading this page abandons recovery; any created plaintext is then unrecoverable.');
 pending??={semantic,requestId:crypto.randomUUID(),requestedAt:new Date().toISOString(),action,args};$('retry').hidden=true;
 try{const r=await manage(action,{...args,requestId:pending.requestId,requestedAt:pending.requestedAt});pending=null;clearSecret();if(r.plaintext){$('plaintext').textContent=r.plaintext;$('secret').hidden=false;notice('Key created. Copy it once before leaving this page.');}else if(r.replayed){notice('The earlier request completed. Its plaintext is not recoverable. Inspect the key and revoke it if you did not save it; create a new one only after resolving this result.');}else notice('Saved. Registry changes apply to the next schedule request.');await load();return r;}catch(e){if(!/REQUEST_FAILED|DATABASE_UNAVAILABLE|Response lost|fetch|network/i.test(e.message))pending=null;$('retry').hidden=!pending;throw e;}
}
function signedIn(s){csrf=s.csrf;$('login').hidden=true;$('workspace').hidden=false;$('signout').hidden=false;clearTimeout(expiryTimer);expiryTimer=setTimeout(()=>{csrf='';pending=null;clearSecret();$('workspace').hidden=true;$('login').hidden=false;$('signout').hidden=true;$('retry').hidden=true;notice('Session expired. Sign in again.');},Math.max(0,s.expires-Date.now()));}
$('retry').onclick=()=>void busy(async()=>{if(pending)await mutate(pending.action,pending.args);});
$('send').onsubmit=e=>{e.preventDefault();void busy(async()=>{await post('/api/auth/send',{email:$('email').value.trim()});notice('Check your BYE account email for the code.');});};
$('verify').onsubmit=e=>{e.preventDefault();void busy(async()=>{const s=await post('/api/auth/verify',{email:$('email').value.trim(),code:$('code').value.trim()});$('code').value='';signedIn(s);notice('Signed in as an approved owner.');await load();});};
$('create').onsubmit=e=>{e.preventDefault();void busy(()=>mutate('create',{label:$('label').value.trim(),clientType:$('client').value}));};
$('signout').onclick=()=>void busy(async()=>{await post('/api/signout',{});csrf='';pending=null;clearSecret();$('workspace').hidden=true;$('login').hidden=false;$('signout').hidden=true;$('retry').hidden=true;clearTimeout(expiryTimer);$('keys').replaceChildren();$('audit').replaceChildren();notice('Signed out.');});
$('dismiss').onclick=clearSecret;$('copy').onclick=()=>void busy(async()=>{await navigator.clipboard.writeText($('plaintext').textContent);notice('Copied. Store it in your application configuration.');});
const date=value=>value?new Date(value).toLocaleString()+' · '+value:'None';
function node(tag,text,cls){const n=document.createElement(tag);n.textContent=text;if(cls)n.className=cls;return n;}
function askAction(k,action){
 return new Promise(resolve=>{
  const dialog=$('action-dialog'),expired=!!k.retire_at&&new Date(k.retire_at)<=new Date();
  $('action-title').textContent=action==='rotate'?'Rotate this key':action==='extend'?'Extend retirement':'Permanently revoke this key';
  $('action-message').textContent=action==='rotate'?'This creates an active replacement and retires the selected key 30 days from now. Installed apps need the replacement separately.':action==='extend'?'Postpone the selected key’s retirement. A disabled key remains disabled.':'This permanently blocks the selected key. It cannot be undone.';
  $('action-key').textContent=k.label+' · '+k.mask+' · ID '+k.id;
  $('retirement-fields').hidden=action!=='extend';$('retirement-date').value='';
  $('restore-field').hidden=action!=='extend'||!expired;$('restore-confirm').checked=false;$('restore-confirm').required=action==='extend'&&expired;
  $('action-submit').textContent=action==='rotate'?'Create replacement':action==='extend'?'Extend retirement':'Revoke permanently';
  $('action-submit').className=action==='revoke'?'danger':'';
  dialog.querySelectorAll('button').forEach(b=>b.disabled=false);
  const finish=value=>{dialog.oncancel=null;$('action-form').onsubmit=null;$('action-cancel').onclick=null;dialog.close();resolve(value);};
  $('action-cancel').onclick=()=>finish(null);dialog.oncancel=e=>{e.preventDefault();finish(null);};
  $('action-form').onsubmit=e=>{e.preventDefault();if(action==='extend'&&expired&&!$('restore-confirm').checked)return;const value={confirm:true,confirmRestore:expired};if(action==='extend'&&$('retirement-date').value){const d=new Date($('retirement-date').value);if(!Number.isFinite(+d))return;value.retireAt=d.toISOString();}finish(value);};
  dialog.showModal();
 });
}
async function load(){const r=await manage('list',{offset});$('keys').replaceChildren();for(const k of r.items){const card=node('article','','card');card.append(node('h3',k.label+' · '+k.effective_status),node('p',k.client_type+' · '+k.mask),node('p','ID: '+k.id),node('p','Created: '+date(k.created_at)),node('p','Retires: '+date(k.retire_at)+(k.retire_at?' · '+Math.max(0,Math.ceil((new Date(k.retire_at)-Date.now())/86400000))+' days remaining':'')),node('p','Last sampled use: '+date(k.last_used_at)));if(k.rotated_from)card.append(node('p','Replaces: '+k.rotated_from));if(k.rotated_to)card.append(node('p','Replacement: '+k.rotated_to));const actions=node('div','','actions');if(k.status!=='revoked'){
 const button=(label,fn,danger=false)=>{const b=node('button',label,danger?'danger':'');b.onclick=()=>void busy(fn);actions.append(b);};
 if(!k.rotated_to)button('Rotate',async()=>{if(await askAction(k,'rotate'))await mutate('rotate',{id:k.id,revision:k.revision,label:k.label.slice(0,68)+' replacement',clientType:k.client_type});});
 if(k.retire_at)button('Extend retirement',async()=>{const choice=await askAction(k,'extend');if(choice)await mutate('extend',{id:k.id,revision:k.revision,confirmRestore:choice.confirmRestore,...(choice.retireAt?{retireAt:choice.retireAt}:{})});});
 button(k.status==='disabled'?'Enable':'Disable',()=>mutate(k.status==='disabled'?'enable':'disable',{id:k.id,revision:k.revision}));
 button('Revoke permanently',async()=>{if(await askAction(k,'revoke'))await mutate('revoke',{id:k.id,revision:k.revision,confirm:true});},true);
 }card.append(actions);$('keys').append(card);}if(!r.items.length)$('keys').append(node('p','No keys on this page.'));$('page').textContent=`${offset+1}–${Math.min(offset+25,r.total)} of ${r.total}`;}
async function audit(){const r=await manage('audit',{offset:auditOffset});$('audit').replaceChildren();for(const e of r.items)$('audit').append(node('p',date(e.at)+' · '+e.action+' · '+(e.key_id??'owner access')+' · '+e.actor));$('audit-page').textContent=`${auditOffset+1}–${Math.min(auditOffset+25,r.total)} of ${r.total}`;}
$('reload').onclick=()=>void busy(load);$('previous').onclick=()=>void busy(async()=>{offset=Math.max(0,offset-25);await load();});$('next').onclick=()=>void busy(async()=>{offset+=25;await load();});$('audit-load').onclick=()=>void busy(audit);$('audit-previous').onclick=()=>void busy(async()=>{auditOffset=Math.max(0,auditOffset-25);await audit();});$('audit-next').onclick=()=>void busy(async()=>{auditOffset+=25;await audit();});
window.addEventListener('pagehide',clearSecret);
void busy(async()=>{const r=await fetch('/api/session');const s=await r.json();if(s.csrf){signedIn(s);await load();}});
