import { randomBytes, randomUUID } from "node:crypto";
import { boundedJSON, database, type Database } from "./database.ts";
import { sha } from "./domain.ts";
import { AUTH_PUBLISHABLE_KEY } from "./config.ts";

export const adminStatuses: Record<string, number> = {UNAUTHORIZED:401, FORBIDDEN:403, NOT_FOUND:404, CONFLICT:409, IDEMPOTENCY_CONFLICT:409, REVOKED:409, REGISTRY_FULL:409, RATE_LIMITED:429, DATABASE_UNAVAILABLE:503};
export function management(url: string, publishableKey: string, request: typeof fetch=fetch,
  connect: (token:string)=>Database = token=>database(url,publishableKey,token)) {
  return async (req:Request):Promise<Response> => {
    const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(status===429?{'Retry-After':'60'}:{})}});
    const fail=(code:string)=>reply({error:{code,message:code.replaceAll('_',' ').toLowerCase(),retryable:['DATABASE_UNAVAILABLE','RATE_LIMITED'].includes(code)}},adminStatuses[code]??400);
    if(req.method!=='POST') return reply({error:{code:'METHOD_NOT_ALLOWED'}},405);
    const token=req.headers.get('Authorization')?.match(/^Bearer ([\w.-]{20,8192})$/)?.[1];
    if(!token) return fail('UNAUTHORIZED');
    try {
      // A network Auth check validates signature, expiry and the actual user.
      const user=await request(url+'/auth/v1/user',{headers:{apikey:publishableKey,Authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)});
      if(!user.ok) {await user.body?.cancel();return fail(user.status>=500?'DATABASE_UNAVAILABLE':'UNAUTHORIZED');}
      await user.body?.cancel();
      const db=connect(token);
      const owner=await db.rpc('bye_key_management',{action:'session',args:{}});
      if(owner.error) return fail(owner.error);
      if(Number(req.headers.get('content-length')??0)>8192) return fail('INVALID_QUERY');
      let input:any;
      try {input=(await boundedJSON(new Response(req.body),8192)).data;}catch{return fail('INVALID_QUERY');}
      if(!input || typeof input!=='object' || Array.isArray(input) || !['session','list','audit','create','rotate','extend','disable','enable','revoke'].includes(input.action)) return fail('INVALID_QUERY');
      const action=input.action, args={...(input.args??{})};
      // Never accept caller-supplied digest or generated key material.
      delete args.digest;delete args.newId;delete args.mask;
      let plaintext:string|undefined;
      if(['create','rotate'].includes(action)) {
        plaintext='bye_pk_'+randomBytes(32).toString('base64url');
        args.digest=await sha(plaintext);args.newId=randomUUID();args.mask='bye_pk_…'+plaintext.slice(-4);
      }
      const result=await db.rpc('bye_key_management',{action,args});
      if(result.error) return fail(result.error);
      if(plaintext && !result.replayed && result.key?.id===args.newId) result.plaintext=plaintext;
      return reply(result);
    }catch{return fail('DATABASE_UNAVAILABLE');}
  };
}
if(import.meta.main) Deno.serve(management(Deno.env.get('SUPABASE_URL')!,Deno.env.get('BYE_AUTH_PUBLISHABLE_KEY')??AUTH_PUBLISHABLE_KEY));
