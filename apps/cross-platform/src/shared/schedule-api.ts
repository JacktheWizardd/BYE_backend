// Portable v1 schedule consumer. Source facts are never inferred from counts.
export interface ScheduleCourse { key: string; subject: string; number: string; title: string }
export interface ScheduleTerm { termCode: string; name: string; published?: boolean }
export interface ScheduleAvailability { statusCode: string | null; enrolled: number | null; capacity: number | null; seatsAvailable: number | null; waitlistCount: number | null; waitlistCapacity: number | null; waitlistAvailable: number | null }
export interface ScheduleSection {
  crn: string; courseKey: string; units: string | null; information: Record<string, unknown>;
  meetings: { startDate: string | null; endDate: string | null; days: string[]; beginTime: string | null; endTime: string | null; formatCode: string | null; formatDescription: string | null; campus: string | null; building: string | null; room: string | null; sourceFields: Record<string, unknown> }[];
  instructors: { assignmentId: string; role: 'primary' | 'secondary'; name: string | null }[];
  availability: ScheduleAvailability | null;
}
export interface ScheduleMeta { term: string; catalogVersion: string; availabilityVersion: string; sourceCheckedAt: string | null; stale: boolean; refreshPolicy?: { targetSeconds: number; aggregateMinimumSeconds: number; nextEligibleAt: string; published: boolean } }
export interface ScheduleEnvelope<T> { data: T; meta: ScheduleMeta }
export class ScheduleError extends Error {
  constructor(readonly code: string, readonly retryAfter = 0) { super(code === 'UNCONFIGURED' ? 'The BYE schedule service is not configured.' : 'The BYE schedule service is unavailable. Try again shortly.') }
}
export const expired = (meta: Pick<ScheduleMeta,'sourceCheckedAt'|'stale'>, now = Date.now()) => meta.stale || !meta.sourceCheckedAt || !Number.isFinite(Date.parse(meta.sourceCheckedAt)) || now - Date.parse(meta.sourceCheckedAt) >= 900_000 || Date.parse(meta.sourceCheckedAt) > now + 60_000;

export class ScheduleClient {
  private cache = new Map<string,{etag:string; body:ScheduleEnvelope<unknown>}>();
  private blockedUntil = 0;
  private flights=new Map<string,Promise<ScheduleEnvelope<unknown>>>();
  constructor(private base: string, private key: string, private request: typeof fetch = (...args) => fetch(...args), private now = Date.now) {
    if (base) { const url = new URL(base); if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1','localhost','[::1]'].includes(url.hostname))) throw new Error('Schedule API requires HTTPS'); }
  }
  async get<T>(path: string, signal: AbortSignal): Promise<ScheduleEnvelope<T>> {
    signal.throwIfAborted();
    let task=this.flights.get(path);
    if(!task) {
      if(this.flights.size>=32) throw new ScheduleError('BUSY',5);
      task=this.read<unknown>(path,AbortSignal.timeout(20_000));this.flights.set(path,task);
      const clear=()=>{if(this.flights.get(path)===task)this.flights.delete(path)};void task.then(clear,clear);
    }
    const result=await new Promise<ScheduleEnvelope<unknown>>((resolve,reject)=>{
      const abort=()=>{signal.removeEventListener('abort',abort);reject(signal.reason)};signal.addEventListener('abort',abort,{once:true});
      void task!.then(value=>{signal.removeEventListener('abort',abort);resolve(value)},error=>{signal.removeEventListener('abort',abort);reject(error)});
    });
    signal.throwIfAborted();return structuredClone(result) as ScheduleEnvelope<T>;
  }
  private async read<T>(path: string, signal: AbortSignal): Promise<ScheduleEnvelope<T>> {
    if (!this.base || !this.key) throw new ScheduleError('UNCONFIGURED');
    signal.throwIfAborted();
    if (this.now() < this.blockedUntil) throw new ScheduleError('RATE_LIMITED',Math.ceil((this.blockedUntil-this.now())/1000));
    const cached = this.cache.get(path);
    const response = await this.request(this.base.replace(/\/$/,'') + path, {signal:AbortSignal.any([signal,AbortSignal.timeout(20_000)]),redirect:'manual',headers:{Accept:'application/json',apikey:this.key,...(cached ? {'If-None-Match':cached.etag} : {})}});
    signal.throwIfAborted();
    if (response.status === 304 && cached) return structuredClone(cached.body) as ScheduleEnvelope<T>;
    if (!response.ok) {
      const value=response.headers.get('Retry-After');
      const seconds=value ? (/^\d+$/.test(value) ? Number(value) : Math.ceil((Date.parse(value)-this.now())/1000)) : 0;
      if (seconds>0) this.blockedUntil=this.now()+Math.min(seconds,86400)*1000;
      await response.body?.cancel();
      // Cached schedules cannot bypass revoked keys or conceal source failures.
      throw new ScheduleError(response.status===401 ? 'UNAUTHORIZED' : response.status===429 ? 'RATE_LIMITED' : 'SOURCE_UNAVAILABLE',Math.max(0,seconds||0));
    }
    if (!response.body) throw new ScheduleError('MALFORMED');
    const reader=response.body.getReader(), decoder=new TextDecoder('utf-8',{fatal:true}); let size=0,text='';
    try { for (;;) { const next=await reader.read(); if(next.done) break; size+=next.value.length; if(size>8*1024*1024) throw new ScheduleError('TOO_LARGE'); text+=decoder.decode(next.value,{stream:true}); } text+=decoder.decode(); }
    finally { await reader.cancel().catch(()=>{}); }
    const body=JSON.parse(text) as ScheduleEnvelope<T>;
    if (!body || !body.meta || !('data' in body)) throw new ScheduleError('MALFORMED');
    const tag=response.headers.get('ETag');
    if(tag) { this.cache.delete(path); this.cache.set(path,{etag:tag,body:structuredClone(body)}); while(this.cache.size>24) this.cache.delete(this.cache.keys().next().value!); }
    return body;
  }
  terms(signal:AbortSignal) { return this.get<ScheduleTerm[]>('/v1/terms',signal); }
  manifest(term:string,signal:AbortSignal) { return this.get<ScheduleMeta>(this.path(term)+'/manifest',signal); }
  catalog(term:string,signal:AbortSignal) { return this.get<ScheduleCourse[]>(this.path(term)+'/catalog',signal); }
  sections(term:string,key:string,signal:AbortSignal) { return this.get<ScheduleSection[]>(this.path(term)+'/courses/'+encodeURIComponent(key)+'/sections',signal); }
  availability(term:string,crns:string[],signal:AbortSignal) {
    if(!crns.length || crns.length>100 || crns.some(c=>!/^\d{5}$/.test(c))) throw new ScheduleError('INVALID_CRNS');
    return this.get<{crn:string;availability:ScheduleAvailability|null}[]>(this.path(term)+'/availability?crns='+encodeURIComponent([...new Set(crns)].sort().join(',')),signal);
  }
  private path(term:string) { if(!/^\d{6}$/.test(term)) throw new ScheduleError('INVALID_TERM'); return '/v1/terms/'+term; }
}

// Adapter into the existing parsers. Only allowlisted public schedule fields are
// projected; source HTML is carried as inert text and no private source rows exist here.
export function sectionRows(term:string, course:ScheduleCourse, sections:ScheduleSection[], meta:ScheduleMeta): Record<string,string|number|null>[] {
  const rows:Record<string,string|number|null>[]=[];
  for(const section of sections) {
    if(section.courseKey!==course.key || !/^\d{5}$/.test(section.crn)) throw new ScheduleError('MALFORMED');
    const value=expired(meta) ? null : section.availability;
    const instructors=section.instructors.length ? section.instructors : [{name:null}];
    for(const meeting of section.meetings) for(const instructor of instructors) {
      const row:Record<string,string|number|null>={termCode:term,subjCode:course.subject,courseNumbDisplay:course.number,courseTitle:course.title,crn:section.crn,pfaName:instructor.name,creditHrLow:section.units,ptrmStartDate:meeting.startDate,ptrmEndDate:meeting.endDate,beginTime:meeting.beginTime,endTime:meeting.endTime,schdCode:meeting.formatCode,schdDesc:meeting.formatDescription,campDesc:meeting.campus,stvbldgDesc:meeting.building,bldgDesc:meeting.building,roomCode:meeting.room,
        fwSectOpenInd:value?.statusCode??null,seatsAvail:value?.seatsAvailable??null,maxEnrl:value?.capacity??null,enrl:value?.enrolled??null,waitCount:value?.waitlistCount??null,waitCapacity:value?.waitlistCapacity??null,waitAvail:value?.waitlistAvailable??null};
      for(const day of ['mon','tue','wed','thu','fri','sat','sun']) row[day+'Day']=meeting.days.includes(day) ? day : '';
      for(const [key,source] of Object.entries(meeting.sourceFields)) if(['ptrmDesc','ptrmCode','ptrmCatagory','ssrmeetSchdCode','ssrmeetMtypCode','weeklyHrs'].includes(key) && (typeof source==='string'||typeof source==='number')) row[key]=source;
      for(const [key,source] of Object.entries(section.information)) if(Array.isArray(source)) row[key]=source.filter(x=>typeof x==='string').join('\n');
      rows.push(row);
    }
  }
  return rows;
}
