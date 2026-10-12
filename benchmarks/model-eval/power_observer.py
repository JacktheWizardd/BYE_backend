#!/usr/bin/env python3
"""Read-only power/thermal observations; never changes system settings."""
import ctypes,json,os,subprocess,time
from pathlib import Path
import run as r
run=Path(r.load(r.BASE/'latest.json')['run']);controller=r.load(run/'observer-identity.json')['controller_pid']
ctypes.CDLL('/System/Library/Frameworks/Foundation.framework/Foundation')
objc=ctypes.CDLL('/usr/lib/libobjc.A.dylib');objc.objc_getClass.argtypes=[ctypes.c_char_p];objc.objc_getClass.restype=ctypes.c_void_p
objc.sel_registerName.argtypes=[ctypes.c_char_p];objc.sel_registerName.restype=ctypes.c_void_p
send=ctypes.CFUNCTYPE(ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p)(('objc_msgSend',objc))
scalar=ctypes.CFUNCTYPE(ctypes.c_long,ctypes.c_void_p,ctypes.c_void_p)(('objc_msgSend',objc))
info=send(objc.objc_getClass(b'NSProcessInfo'),objc.sel_registerName(b'processInfo'))
with (run/'power-thermal.jsonl').open('a') as f:
 while True:
  try:os.kill(controller,0)
  except ProcessLookupError:break
  power=r.command(['pmset','-g','batt'])
  state=scalar(info,objc.sel_registerName(b'thermalState'));low=scalar(info,objc.sel_registerName(b'isLowPowerModeEnabled'))
  f.write(json.dumps({'utc':r.stamp(),'monotonic_s':time.monotonic(),'power':power,'thermal_state':state,'thermal_name':['nominal','fair','serious','critical'][state] if 0<=state<4 else 'unknown','low_power_mode':bool(low)})+'\n');f.flush()
  time.sleep(15)
