#!/usr/bin/env python3
"""Launch the compiled native iOS host, retain crash reports, and capture the displayed map."""
import base64, json, os, pathlib, subprocess, sys, time
app=pathlib.Path(sys.argv[1]).resolve()
if not (app/'shaders_metal.metallib').is_file():
    raise SystemExit('The application bundle is missing shaders_metal.metallib')
proof=pathlib.Path('artifacts/ios-runtime');proof.mkdir(parents=True,exist_ok=True)
data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
candidates=[(r,d) for r,ds in data['devices'].items() if '.iOS-' in r for d in ds if 'iPhone' in d['name']]
if not candidates: raise SystemExit('No available iPhone simulator')
runtime,device=sorted(candidates,key=lambda pair:pair[0])[-1]
uid=device['udid'];print('Simulator:',device['name'],runtime,flush=True)
if device['state']!='Booted': subprocess.run(['xcrun','simctl','boot',uid],check=True,timeout=240)
subprocess.run(['xcrun','simctl','bootstatus',uid,'-b'],check=True,timeout=240)
developer=pathlib.Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
subprocess.run(['open','-a',str(developer/'Applications/Simulator.app'),'--args','-CurrentDeviceUDID',uid],check=True,timeout=30)
subprocess.run(['xcrun','simctl','install',uid,str(app)],check=True,timeout=90)
launch=subprocess.run(['xcrun','simctl','launch','--terminate-running-process',
                      '--stdout='+str((proof/'stdout.log').resolve()),
                      '--stderr='+str((proof/'stderr.log').resolve()),
                      uid,'com.mikshat.prototype'],capture_output=True,text=True,timeout=120)
print('Launch:',launch.returncode,launch.stdout,launch.stderr,flush=True)
launch.check_returncode()
pid=launch.stdout.strip().rsplit(':',1)[-1].strip()
if not pid.isdigit(): raise SystemExit('No application PID')
time.sleep(30)
status=subprocess.run(['ps','-p',pid,'-o','stat=','-o','comm='],capture_output=True,text=True)
alive=status.returncode==0 and not status.stdout.strip().startswith('Z')
print('Actual app process:',status.returncode,status.stdout,flush=True)
if alive:
    subprocess.run(['xcrun','simctl','launch',uid,'com.apple.Preferences'],check=True,capture_output=True,timeout=60)
    time.sleep(5)
    subprocess.run(['xcrun','simctl','launch',uid,'com.mikshat.prototype'],check=True,capture_output=True,timeout=60)
    time.sleep(10)
    status=subprocess.run(['ps','-p',pid,'-o','stat=','-o','comm='],capture_output=True,text=True)
    alive=status.returncode==0 and not status.stdout.strip().startswith('Z')
    print('Process after background/foreground:',status.returncode,status.stdout,flush=True)
screenshot=proof/'native-map.png'
subprocess.run(['xcrun','simctl','io',uid,'screenshot',str(screenshot)],check=True,timeout=30)
for source in [proof/'stdout.log',proof/'stderr.log']:
    if source.exists(): print(source.name,source.read_text(errors='replace')[-14000:],flush=True)
for report in list((pathlib.Path.home()/'Library/Logs/DiagnosticReports').glob('Runner*.ips'))[-2:]:
    raw=report.read_text(errors='replace');(proof/report.name).write_text(raw)
    try:
        crash=json.loads(raw.split('\n',1)[1])
        print('Crash:',crash.get('exception'),flush=True)
        thread=crash['threads'][crash['faultingThread']]
        for frame in thread.get('frames',[])[:20]: print('Crash frame:',json.dumps(frame),flush=True)
    except (ValueError,KeyError): pass
print('MUKSHAT_IOS_IMAGE_BEGIN')
encoded=base64.b64encode(screenshot.read_bytes()).decode()
for start in range(0,len(encoded),12000): print(encoded[start:start+12000])
print('MUKSHAT_IOS_IMAGE_END',flush=True)
(proof/'result.txt').write_text('Actual simulator process alive: '+str(alive)+'\n')
if not alive: raise SystemExit('The native iOS application exited during startup')
