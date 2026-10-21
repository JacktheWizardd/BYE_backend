import {mkdir,readFile,writeFile,rename,readdir,unlink} from 'node:fs/promises'
import path from 'node:path'
import type {ScheduleCourse} from '../shared/schedule-api'
export class ScheduleCatalogStore {
  constructor(private directory:string){}
  private file(term:string){if(!/^\d{6}$/.test(term))throw new Error('Invalid semester');return path.join(this.directory,term+'.json')}
  async get(term:string):Promise<ScheduleCourse[]|undefined>{
    try {const text=await readFile(this.file(term),'utf8');if(text.length>2*1024*1024)return;const value=JSON.parse(text);if(!Array.isArray(value.courses)||value.courses.length>25000||value.courses.some((c:ScheduleCourse)=>!c||typeof c.key!=='string'||typeof c.title!=='string'||typeof c.subject!=='string'||typeof c.number!=='string'))return;return value.courses}catch{return}
  }
  async set(term:string,courses:ScheduleCourse[]){
    await mkdir(this.directory,{recursive:true});const file=this.file(term),temporary=file+'.tmp';await writeFile(temporary,JSON.stringify({courses,storedAt:Date.now()}));await rename(temporary,file);
    const entries=await readdir(this.directory);const others=entries.filter(x=>/^\d{6}\.json$/.test(x)&&x!==term+'.json').sort().reverse();for(const old of others.slice(2))await unlink(path.join(this.directory,old));
  }
}
