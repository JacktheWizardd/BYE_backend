import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import vm from 'node:vm';
const html=await readFile(new URL('../dashboard/public/index.html',import.meta.url),'utf8');
const script=await readFile(new URL('../dashboard/public/app.js',import.meta.url),'utf8');
function fixture(){
 const nodes=new Map<string,any>();for(const [,id]of html.matchAll(/id="([^"]+)"/g))nodes.set(id,{value:'',checked:false,hidden:false,required:false,disabled:false,textContent:'',querySelectorAll:()=>[],showModal(){this.open=true;},close(){this.open=false;}});
 const context=vm.createContext({document:{getElementById:(id:string)=>{assert(nodes.has(id),'Missing HTML control: '+id);return nodes.get(id);},querySelectorAll:()=>[]},window:{addEventListener(){}},fetch:async()=>({json:async()=>({signedIn:false})}),Date,console,setTimeout,clearTimeout,prompt:()=>{throw Error('prompt unsupported');},confirm:()=>{throw Error('confirm unsupported');}});
 vm.runInContext(script+'\nglobalThis.ui={askAction};',context);return {nodes,ask:context.ui.askAction};
}
const key={id:'key-fixture',label:'Dashboard test',mask:'bye_pk_…test',retire_at:'2099-01-01T00:00:00Z'};
test('extend opens an in-page form and supports default or custom UTC retirement without prompt()',async()=>{
 const {nodes,ask}=fixture();const first=ask(key,'extend');assert.equal(nodes.get('action-dialog').open,true);assert.equal(nodes.get('retirement-fields').hidden,false);assert.match(nodes.get('action-key').textContent,/Dashboard test/);
 nodes.get('action-form').onsubmit({preventDefault(){}});const defaultChoice=await first;assert.equal(defaultChoice.retireAt,undefined);assert.equal(defaultChoice.confirmRestore,false);
 const second=ask(key,'extend');nodes.get('retirement-date').value='2099-02-01T10:00';nodes.get('action-form').onsubmit({preventDefault(){}});assert.equal((await second).retireAt,new Date('2099-02-01T10:00').toISOString());assert.equal(nodes.get('action-dialog').open,false);
});
test('expired retirement needs explicit restore confirmation and cancel never mutates',async()=>{
 const {nodes,ask}=fixture();const choice=ask({...key,retire_at:'2000-01-01T00:00:00Z'},'extend');assert.equal(nodes.get('restore-confirm').required,true);nodes.get('action-form').onsubmit({preventDefault(){}});assert.equal(nodes.get('action-dialog').open,true);nodes.get('restore-confirm').checked=true;nodes.get('action-form').onsubmit({preventDefault(){}});assert.equal((await choice).confirmRestore,true);
 const cancel=ask(key,'rotate');nodes.get('action-dialog').oncancel({preventDefault(){}});assert.equal(await cancel,null);
});
test('rotation and revocation show the selected key and use no native browser dialogs',async()=>{
 const {nodes,ask}=fixture();for(const action of ['rotate','revoke']){const result=ask(key,action);assert.match(nodes.get('action-key').textContent,/key-fixture/);assert.equal(nodes.get('retirement-fields').hidden,true);nodes.get('action-form').onsubmit({preventDefault(){}});assert.equal((await result).confirm,true);}
});
