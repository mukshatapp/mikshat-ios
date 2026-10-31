#!/usr/bin/env python3
"""Run the real Android integration check with a bounded wait and retained diagnostics."""
from pathlib import Path
import re, subprocess, time
root=Path('artifacts');root.mkdir(exist_ok=True)
def adb(*args,timeout=30):
    return subprocess.run(['adb',*args],capture_output=True,timeout=timeout)
adb('root')
adb('wait-for-device')
adb('logcat','-c')
with (root/'native-logcat.txt').open('wb') as log, (root/'native-result.txt').open('wb') as result:
    logger=subprocess.Popen(['adb','logcat','-v','time'],stdout=log,stderr=subprocess.STDOUT)
    timed_out=False
    try:
        subprocess.run(['adb','shell','am','instrument','-w','com.mikshat.prototype.test/androidx.test.runner.AndroidJUnitRunner'],
                       stdout=result,stderr=subprocess.STDOUT,timeout=180)
    except subprocess.TimeoutExpired:
        timed_out=True
        print('Native integration check exceeded 180 seconds.',flush=True)
        pids=adb('shell','pidof','com.mikshat.prototype').stdout.decode().split()
        for pid in pids:
            if pid.isdigit(): adb('shell','kill','-3',pid)
        time.sleep(3)
        for name in adb('shell','ls','-t','/data/anr').stdout.decode().split()[:2]:
            if re.fullmatch(r'[A-Za-z0-9_.-]+',name):
                trace=adb('shell','cat','/data/anr/'+name).stdout.decode(errors='replace')
                (root/('thread-'+name+'.txt')).write_text(trace)
                print('ANDROID_THREAD_DUMP',trace[:18000],flush=True)
    finally:
        screenshot=adb('exec-out','screencap','-p').stdout
        if screenshot.startswith(b'\x89PNG'): (root/'native-map.png').write_bytes(screenshot)
        logger.terminate()
        try: logger.wait(timeout=5)
        except subprocess.TimeoutExpired: logger.kill()
text=(root/'native-result.txt').read_text(errors='replace')
print(text,flush=True)
lines=(root/'native-logcat.txt').read_text(errors='replace').splitlines()
selected=[line for line in lines if any(word in line for word in
          ('MukshatEngine','MukshatSearch','MukshatCheck','AndroidRuntime','FATAL','onRoutingEvent','Maps initialized','Search API initialized'))]
print('\n'.join(selected[-120:]),flush=True)
if timed_out or 'OK (1 test)' not in text: raise SystemExit(1)
