import { createServer, type IncomingMessage } from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

type Session={token:string;expires:number;csrf:string;owner:string};
type Options={url:string;key:string;port?:number;request?:typeof fetch;clock?:()=>number;ownerEmail?:string};
const assets:Record<string,[string,string]>={'/':['index.html','text/html'],'/app.js':['app.js','text/javascript'],'/style.css':['style.css','text/css']};
export function dashboard(options:Options) {
  if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(options.url) && options.url!=='http://fixture.test') throw Error('Expected Supabase HTTPS project URL');
  if(!options.key || options.key.startsWith('sb_secret_')) throw Error('Use a genuine Supabase publishable key, never a server credential');
  // Legacy anon JWTs are allowed, but never legacy service_role JWTs.
  if(options.key.startsWith('eyJ')) {try {if(JSON.parse(Buffer.from(options.key.split('.')[1],'base64url').toString()).role!=='anon') throw Error();}catch{throw Error('Expected a public anon/publishable key');}}
  else if(!options.key.startsWith('sb_publishable_')) throw Error('Expected a Supabase publishable key (not a BYE client key)');
  const request=options.request??fetch, now=options.clock??Date.now, sessions=new Map<string,Session>();
  let emailWindow=0,emailCount=0,verifyCount=0,active=0;
  const purge=()=>{for(const [id,s] of sessions) if(s.expires<=now()) sessions.delete(id);};
  const timer=setInterval(purge,30000);timer.unref();
  const server=createServer(async(req,res)=>{
    const send=(status:number,body:unknown,cookie?:string)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(cookie?{'Set-Cookie':cookie}:{})});res.end(JSON.stringify(body));};
    const origin='http://127.0.0.1:'+((server.address() as any)?.port??4178);
    const cookie=(id:string,max=3600)=>`bye_admin=${id}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${max}`;
    if(req.headers.host!==new URL(origin).host) return send(403,{error:'HOST_DENIED'});
    if(active>=8) return send(429,{error:'BUSY'});
    active++;purge();
    try {
      const path=req.url??'';
      if(req.method==='GET' && assets[path]) {
        const [file,type]=assets[path];
        const content=await readFile(new URL('./public/'+file,import.meta.url));
        res.writeHead(200,{'Content-Type':type+'; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",'Referrer-Policy':'no-referrer'});res.end(content);return;
      }
      if(!path.startsWith('/api/')) return send(404,{error:'NOT_FOUND'});
      const id=req.headers.cookie?.match(/(?:^|; )bye_admin=([A-Za-z0-9_-]{43})(?:;|$)/)?.[1]??'';
      const session=sessions.get(id);
      if(req.method==='GET' && path==='/api/session') return send(200,session?{owner:session.owner,csrf:session.csrf,expires:session.expires}:{signedIn:false});
      if(req.method!=='POST') return send(405,{error:'METHOD_NOT_ALLOWED'});
      // Applies to pre-login requests too; JSON/custom header defeats form CSRF.
      if(req.headers.origin!==origin || !req.headers['content-type']?.startsWith('application/json') || req.headers['x-bye-local']!=='1') return send(403,{error:'ORIGIN_DENIED'});
      if(!['/api/auth/send','/api/auth/verify'].includes(path)) {
        if(!session) return send(401,{error:'SESSION_EXPIRED'},cookie('',0));
        const csrf=String(req.headers['x-csrf-token']??'');
        if(csrf.length!==session.csrf.length || !timingSafeEqual(Buffer.from(csrf),Buffer.from(session.csrf))) return send(403,{error:'CSRF_DENIED'});
      }
      const input=await body(req);
      if(path==='/api/auth/send' || path==='/api/auth/verify') {
        if(now()-emailWindow>=600000){emailWindow=now();emailCount=0;verifyCount=0;}
        if(typeof input.email!=='string' || input.email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email) || (options.ownerEmail && input.email.toLowerCase()!==options.ownerEmail.toLowerCase())) return send(400,{error:'INVALID_EMAIL'});
        if(path.endsWith('/send')) {
          if(now()-emailWindow>=600000){emailWindow=now();emailCount=0;}
          if(++emailCount>3) return send(429,{error:'WAIT_BEFORE_RETRY'});
          const r=await request(options.url+'/auth/v1/otp',{method:'POST',headers:{apikey:options.key,'Content-Type':'application/json'},body:JSON.stringify({email:input.email,create_user:false}),signal:AbortSignal.timeout(15000)});
          await r.body?.cancel();return send(r.ok?200:400,{sent:r.ok,...(!r.ok?{error:'EMAIL_REQUEST_FAILED'}:{})});
        }
        if(typeof input.code!=='string' || !/^\d{6,10}$/.test(input.code)) return send(400,{error:'INVALID_CODE'});
        if(++verifyCount>20) return send(429,{error:'WAIT_BEFORE_RETRY'});
        const r=await request(options.url+'/auth/v1/verify',{method:'POST',headers:{apikey:options.key,'Content-Type':'application/json'},body:JSON.stringify({email:input.email,token:input.code,type:'email'}),signal:AbortSignal.timeout(15000)});
        if(!r.ok){await r.body?.cancel();return send(401,{error:'INVALID_CODE'});}
        const data=await r.json() as any;
        const access=data.access_token;
        if(typeof access!=='string' || !data.user?.id || !Number.isFinite(data.expires_in) || data.expires_in<=0) return send(502,{error:'INVALID_AUTH_RESPONSE'});
        const owner=await manage(access,{action:'session',args:{}});
        if(owner.status!==200) return send(owner.status,{error:'OWNER_ACCESS_REQUIRED',userId:data.user.id});
        if(sessions.size>=8) return send(429,{error:'SESSION_LIMIT'});
        if(id) sessions.delete(id);
        const newId=randomBytes(32).toString('base64url'), csrf=randomBytes(32).toString('base64url');
        const expires=now()+Math.min(3600,data.expires_in)*1000;
        sessions.set(newId,{token:access,expires,csrf,owner:data.user.id});
        return send(200,{owner:data.user.id,csrf,expires},cookie(newId,Math.floor((expires-now())/1000)));
      }
      if(path==='/api/signout') {
        sessions.delete(id);
        // Revoke the Supabase session as well; local sign-out still succeeds offline.
        try {const r=await request(options.url+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:options.key,Authorization:'Bearer '+session!.token},signal:AbortSignal.timeout(5000)});await r.body?.cancel();}catch{}
        return send(200,{signedOut:true},cookie('',0));
      }
      if(path!=='/api/manage') return send(404,{error:'NOT_FOUND'});
      const result=await manage(session!.token,input);
      if(result.status===401 || result.status===403){sessions.delete(id);return send(result.status,result.data,cookie('',0));}
      return send(result.status,result.data);
    }catch {send(503,{error:'REQUEST_FAILED',message:'Result uncertain. Retry the same request ID; do not create another key blindly.'});}
    finally{active--;}
  });
  async function manage(token:string,input:unknown){
    const r=await request(options.url+'/functions/v1/bye-key-admin',{method:'POST',headers:{apikey:options.key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(input),signal:AbortSignal.timeout(20000)});
    return {status:r.status,data:await r.json()};
  }
  server.maxConnections=16;server.requestTimeout=10000;server.headersTimeout=10000;server.keepAliveTimeout=1000;
  server.on('close',()=>{clearInterval(timer);sessions.clear();});
  return {server,sessionCount:()=>{purge();return sessions.size;},async start(){await new Promise<void>((resolve,reject)=>{server.once('error',reject);server.listen(options.port??4178,'127.0.0.1',resolve);});return server.address();},async close(){sessions.clear();server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));clearInterval(timer);}};
}
async function body(req:IncomingMessage):Promise<any>{let length=0;const chunks:Buffer[]=[];for await(const chunk of req){length+=chunk.length;if(length>8192)throw Error('BODY_TOO_LARGE');chunks.push(chunk);}return JSON.parse(Buffer.concat(chunks).toString());}
if(process.argv[1] && fileURLToPath(import.meta.url)===process.argv[1]) {
 const app=dashboard({url:process.env.BYE_SUPABASE_URL??'https://nahvhampsxtasfwvvfei.supabase.co',key:process.env.BYE_PUBLISHABLE_KEY??'',ownerEmail:process.env.BYE_OWNER_EMAIL});
 await app.start();console.log('BYE key dashboard: http://127.0.0.1:4178 (local only)');
 for(const signal of ['SIGINT','SIGTERM'] as const) process.on(signal,()=>{void app.close().then(()=>process.exit(0));});
}
