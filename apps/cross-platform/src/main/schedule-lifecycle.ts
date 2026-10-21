import {net,type BrowserWindow} from 'electron'
import type {Engine} from './engine'
export function scheduleLifecycle(engine:Engine,window:BrowserWindow) {
  let timer:ReturnType<typeof setTimeout>|undefined, stopped=false, inFlight=false, failures=0;let controller:AbortController|undefined;
  const active=()=>!stopped && !window.isDestroyed() && window.isVisible() && !window.isMinimized() && net.isOnline();
  const schedule=()=>{if(timer) clearTimeout(timer);timer=undefined; if(active()) timer=setTimeout(()=>{void tick()},Math.min(900_000,60_000*2**failures)*(0.9+Math.random()*0.2));};
  const tick=async()=>{if(!active() || inFlight) return;inFlight=true;controller=new AbortController();try{await engine.refreshSchedule(controller.signal);failures=0}catch{failures=Math.min(failures+1,4)}finally{inFlight=false;schedule()}};
  const resume=()=>{if(timer)clearTimeout(timer);void tick()};
  const pause=()=>{controller?.abort();if(timer)clearTimeout(timer);timer=undefined};
  window.on('show',resume);window.on('restore',resume);window.on('focus',resume);window.on('hide',pause);window.on('minimize',pause);
  const expiry=setInterval(()=>{engine.expireAvailability();if(active()&&!timer&&!inFlight)void tick();if(!net.isOnline())pause()},10_000);
  window.once('closed',()=>{stopped=true;pause();clearInterval(expiry)});schedule();
}
