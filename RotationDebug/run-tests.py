#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Run command-driven rotations against the existing monitor topology, saving full traces."""
import argparse,json,subprocess,time,datetime
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--label',default='current-topology')
p.add_argument('--settle',type=float,default=12)
p.add_argument('--repair',choices=['on','off'],default='off')
p.add_argument('--baseline',choices=['current','hidpi','native'],default='current')
p.add_argument('--angles',default='90,0,270,0')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
angles=[int(x) for x in a.angles.split(',')]
assert all(x in (0,90,180,270) for x in angles)
assert 1 <= a.settle <= 60
exe='/Applications/RotationDebug.app/Contents/MacOS/RotationDebug'
timeline=Path.home()/'Library/Logs/RotationDebug/timeline.jsonl'
a.output.mkdir(parents=True,exist_ok=False)
offset=timeline.stat().st_size if timeline.exists() else 0
records=[]
def command(text):
 start=time.monotonic()
 result=subprocess.run([exe,'--command',text],capture_output=True,text=True,timeout=50)
 try:reply=json.loads(result.stdout)
 except json.JSONDecodeError:reply={'stdout':result.stdout,'stderr':result.stderr}
 reply['clientReturnCode']=result.returncode
 record={'time':datetime.datetime.now().astimezone().isoformat(),'command':text,'duration':time.monotonic()-start,'reply':reply}
 records.append(record);print(json.dumps(record),flush=True)
 if result.returncode:raise RuntimeError(text+': '+result.stdout+result.stderr)
 return reply
initial=command('status')
internal=next(x for x in initial['displays'] if x['builtin'])
original=int(internal['angle'])
try:
 command('repair '+a.repair)
 if a.baseline != 'current':command(a.baseline);time.sleep(2)
 command('modes')
 for angle in angles:
  command('rotate '+str(angle));time.sleep(a.settle);command('status')
finally:
 # Return to original orientation; do not change mirror topology beyond normal app behavior.
 try:command('rotate '+str(original))
 except Exception as exc:print('Restore orientation failed: '+str(exc),flush=True)
 time.sleep(1)
 (a.output/'commands.json').write_text(json.dumps({'label':a.label,'repair':a.repair,'baseline':a.baseline,'initial':initial,'commands':records},indent=2)+'\n')
 if timeline.exists():(a.output/'timeline.jsonl').write_bytes(timeline.read_bytes()[offset:])
print('Saved '+str(a.output),flush=True)
