"""Check preserved Java native declarations against the selected C++ JNI build variant."""
from pathlib import Path
import re,json,sys
R=Path(__file__).resolve().parents[2];contract=json.loads((R/'tools/mukshat/legacy-jni-contract.json').read_text())
def legacy(text):
 output=[];active=True;stack=[]
 for line in text.splitlines():
  if line.startswith('#if'):
   known='MUKSHAT_LEGACY_SDK_ABI' in line;stack.append((active,known));active=active if not known else active and '!defined' not in line;continue
  if line.startswith('#else'):
   if stack and stack[-1][1]:active=stack[-1][0] and not active
   continue
  if line.startswith('#endif'):
   if stack:active=stack.pop()[0]
   continue
  if active:output.append(line)
 return '\n'.join(output)
s='\n'.join(legacy(p.read_text(errors='replace')) for p in (R/'android/sdk/src/main/cpp').rglob('*.cpp'))
functions={n:(t,a) for t,n,a in re.findall(r'JNIEXPORT\s+(\w+)\s+(?:JNICALL\s+)?(Java_\w+)\s*\((.*?)\)\s*\{',s,re.S)}
types={'void':'V','jboolean':'Z','jbyte':'B','jchar':'C','jshort':'S','jint':'I','int':'I','jlong':'J','jfloat':'F','jdouble':'D','double':'D','jstring':'L','jobject':'L','jclass':'L'}
for t in ['jobjectArray','jbyteArray','jintArray','jlongArray','jdoubleArray','jfloatArray','jbooleanArray']:types[t]='['
fail=[]
for key,desc in contract.items():
 cls,name=key.rsplit('.',1);symbol='Java_'+cls.replace('/','_').replace('$','_00024')+'_'+name
 if symbol not in functions:fail.append((key,'missing'));continue
 ret,args=functions[symbol];argtypes=[p.strip().split()[0].replace('*','') for p in args.split(',')[2:] if p.strip()];actual=''.join(types.get(t,'?') for t in argtypes)
 params,result=desc.split(')');expected=''.join('[' if t.startswith('[') else 'L' if t.startswith('L') else t for t in re.findall(r'\[*L[^;]+;|\[*[ZBCSIJFD]',params[1:]));expected_result='[' if result.startswith('[') else 'L' if result.startswith('L') else result
 if actual!=expected or types.get(ret,'?')!=expected_result:fail.append((key,desc,ret,argtypes))
if fail:
 print(json.dumps(fail,indent=2));raise SystemExit(1)
print('PASS',len(contract),'legacy JNI entrypoint argument/return contracts. Object model callbacks still require runtime tests.')
