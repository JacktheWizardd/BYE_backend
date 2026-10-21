import {ScheduleClient, expired, sectionRows, type ScheduleMeta, type ScheduleSection, type ScheduleCourse} from '../shared/schedule-api'
import {course, resolve, suggestions} from '../shared/domain'
import type {Row,Term} from '../shared/types'
export interface CourseSchedule {rows:Row[];meta:ScheduleMeta}
export class SchedulePCC {
  private catalogs=new Map<string,{data:ScheduleCourse[];version:string}>()
  private entries=new Map<string,{term:string;key:string;course:ScheduleCourse;sections:ScheduleSection[];meta:ScheduleMeta}>()
  constructor(readonly client:ScheduleClient,private catalogStore?:{get(term:string):Promise<ScheduleCourse[]|undefined>;set(term:string,courses:ScheduleCourse[]):Promise<void>}) {}
  async terms():Promise<Term[]> {return (await this.client.terms(AbortSignal.timeout(20_000))).data.map(t=>({termCode:t.termCode,termName:t.name,termDisplayControl:'Y'}))}
  async schedule(term:string):Promise<Row[]> {
    const cached=await this.catalogStore?.get(term);
    if(cached) {
      void this.client.catalog(term,AbortSignal.timeout(20_000)).then(response=>this.catalogStore?.set(term,response.data)).catch(()=>{});
      return cached.map(c=>({termCode:term,subjCode:c.subject,courseNumbDisplay:c.number,courseTitle:c.title,crn:'00000'}));
    }
    const catalog=await this.client.catalog(term,AbortSignal.timeout(20_000));
    await this.catalogStore?.set(term,catalog.data).catch(()=>{});
    return catalog.data.map(c=>({termCode:term,subjCode:c.subject,courseNumbDisplay:c.number,courseTitle:c.title,crn:'00000'}));
  }
  async suggest(term:string,query:string) {return suggestions(query,await this.schedule(term))}
  async courseSections(term:string,query:string,signal:AbortSignal):Promise<CourseSchedule> {
    const manifest=await this.client.manifest(term,signal);
    let catalog=this.catalogs.get(term);
    if(!catalog || catalog.version!==manifest.meta.catalogVersion) {
      const response=await this.client.catalog(term,signal);catalog={data:response.data,version:manifest.meta.catalogVersion};this.catalogs.set(term,catalog);
      while(this.catalogs.size>3)this.catalogs.delete(this.catalogs.keys().next().value!);
    }
    const selected=resolve(query,catalog.data.map(c=>({subjCode:c.subject,courseNumbDisplay:c.number,courseTitle:c.title,crn:'00000'})));
    const c=catalog.data.find(c=>course(c.key).key===selected.key);if(!c) throw new Error('Choose a published course.');
    const cacheKey=term+"|"+c.key;
    const previous=this.entries.get(cacheKey);
    let current=previous;
    if(!previous || previous.term!==term || previous.key!==c.key || previous.meta.catalogVersion!==manifest.meta.catalogVersion) {
      const sections=await this.client.sections(term,c.key,signal);
      current={term,key:c.key,course:c,sections:sections.data,meta:sections.meta};
    } else {
      const mustRefresh=previous.meta.availabilityVersion!==manifest.meta.availabilityVersion || expired(previous.meta)!==expired(manifest.meta);
      if(mustRefresh && previous.sections.length) {
        const crns=[...new Set(previous.sections.map(s=>s.crn))];
        const values=new Map<string,ScheduleSection['availability']>();
        for(let i=0;i<crns.length;i+=100) for(const item of (await this.client.availability(term,crns.slice(i,i+100),signal)).data) values.set(item.crn,item.availability);
        previous.sections=previous.sections.map(s=>({...s,availability:values.get(s.crn)??null}));
      }
      previous.meta=manifest.meta;
    }
    signal.throwIfAborted();
    this.entries.delete(cacheKey);this.entries.set(cacheKey,current!);while(this.entries.size>12)this.entries.delete(this.entries.keys().next().value!);
    return {rows:sectionRows(term,c,current!.sections,current!.meta),meta:current!.meta};
  }
}
