from pathlib import Path
import json,re,collections
import argparse
p=argparse.ArgumentParser(description="Check literal JNI callbacks against the preserved Mukshat Java API")
p.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[2])
p.add_argument('--contract',type=Path,default=Path(__file__).with_name('legacy-java-callback-api.json'))
p.add_argument('--snapshot',type=Path)
p.add_argument('--override-root',type=Path)
p.add_argument('--report',type=Path)
a=p.parse_args()
if a.snapshot:
 sources=json.loads(a.snapshot.read_text())
else:
 native=a.source_root/'android/sdk/src/main/cpp/app'
 sources={str(f.relative_to(native)):f.read_text() for f in native.rglob('*') if f.suffix in ('.cpp','.hpp')}
if not sources:raise SystemExit('No JNI source files found')
if a.override_root:
 native=a.override_root/'android/sdk/src/main/cpp/app'
 for f in native.rglob('*'):
  if f.suffix in ('.cpp','.hpp'):sources[str(f.relative_to(native))]=f.read_text()
models=json.loads(a.contract.read_text())['classes']
classes={name:(set(value['methods']),set(value['fields']),value['parents']) for name,value in models.items()}
methodclasses=collections.defaultdict(list);fieldclasses=collections.defaultdict(list)
for name,(ms,fs,parents) in classes.items():
 for sig in ms:methodclasses[sig].append(name)
 for sig in fs:fieldclasses[sig].append(name)

def has(cls,sig,field=False,seen=None):
 if cls not in classes:return False
 seen=set() if seen is None else seen
 if cls in seen:return False
 seen.add(cls);ms,fs,parents=classes[cls]
 return sig in (fs if field else ms) or any(has(p,sig,field,seen) for p in parents)

def preprocess(s):
 out=[];active=True;stack=[]
 for line in s.splitlines():
  st=line.lstrip()
  if st.startswith(('#if ','#ifdef ','#ifndef ')):
   known='MUKSHAT_LEGACY_SDK_ABI' in st
   value=not ('!defined' in st or st.startswith('#ifndef'))
   stack.append((active,known,value));active=active and(value if known else True);continue
  if st.startswith('#else'):
   if stack:
    parent,known,value=stack[-1];active=parent and(not value if known else True)
   continue
  if st.startswith('#endif'):
   if stack:active=stack.pop()[0]
   continue
  if active:out.append(line)
 s='\n'.join(out)
 s=re.sub(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|//[^\n]*|/\*.*?\*/',lambda m:m[1] or '',s,flags=re.S)
 while re.search(r'("(?:\\.|[^"\\])*")\s*("(?:\\.|[^"\\])*")',s):
  s=re.sub(r'("(?:\\.|[^"\\])*")\s*("(?:\\.|[^"\\])*")',lambda m:m[1][:-1]+m[2][1:],s)
 return s
sources={k:preprocess(v) for k,v in sources.items()}
assign=collections.defaultdict(set)
for s in sources.values():
 for v,c in re.findall(r'(\w+)\s*=\s*(?:jni::|env->)?(?:GetGlobalClassRef|FindClass)\([^;\n]*?"([^"\n]+)"\)',s):assign[v].add(c)

def args_at(s,pos):
 begin=s.index('(',pos);depth=1;i=begin+1;start=i;args=[];quote=None
 while i<len(s) and depth:
  ch=s[i]
  if quote:
   if ch=='\\':i+=2;continue
   if ch==quote:quote=None
  elif ch in '\"\'':quote=ch
  elif ch=='(':depth+=1
  elif ch==')':
   depth-=1
   if not depth:args.append(s[start:i].strip());return args,i
  elif ch==',' and depth==1:args.append(s[start:i].strip());start=i+1
  i+=1
 return [],i

def literal(x):
 if re.fullmatch(r'"(?:\\.|[^"\\])*"',x.strip()):
  try:return json.loads(x.strip())
  except:return None
 return None

def manual_receiver(file, receiver, name):
 key=file.removeprefix('organicmaps/sdk/')
 direct={
  'DownloadResourcesLegacyActivity.cpp':'DownloadResourcesLegacyActivity$Listener',
  'LocationState.cpp':'location/LocationState$ModeChangeListener',
  'Map.cpp':'MapRenderingListener',
  'MukshatLegacySdk.cpp':'routing/RoutingLoadPointsListener',
  'OrganicMaps.cpp':'java/lang/Runnable',
  'TrackRecorder.cpp':'location/TrackRecorder$TrackRecordingUpdateHandler',
  'TrafficState.cpp':'maplayer/traffic/TrafficState$StateChangeListener',
  'editor/Editor.cpp':'editor/Editor$UploadListener',
  'isolines/IsolinesManager.cpp':'maplayer/isolines/OnIsolinesChangedListener',
  'platform/AndroidPlatform.cpp':'util/ConnectionState',
  'platform/Localization.cpp':'java/text/Collator',
  'platform/SocketImpl.cpp':'location/PlatformSocket',
  'search/SearchEngine.cpp':'search/SearchEngine',
  'subway/SubwayManager.cpp':'maplayer/subway/OnTransitSchemeChangedListener',
  'util/NetworkPolicy.cpp':'util/NetworkPolicy',
  'core/jni_java_methods.cpp':'java/util/List',
 }
 value=direct.get(key)
 if key=='Framework.cpp':
  value={'onRoutingEvent':'routing/RoutingListener','onRouteBuildingProgress':'routing/RoutingProgressListener',
   'onRecommend':'routing/RoutingRecommendationListener','onPlacePageActivated':'PlacePageActivationListener',
   'onPlacePageDeactivated':'PlacePageActivationListener','onSwitchFullScreenMode':'PlacePageActivationListener',
   'enabled':'Framework$Params3dMode','buildings':'Framework$Params3dMode'}.get(name)
 elif key=='MapManager.cpp':
  value='downloader/MapManager$CurrentCountryChangedListener' if name=='onCurrentCountryChanged' else 'downloader/MapManager$StorageCallback'
 elif key=='bookmarks/data/BookmarkManager.cpp':
  value='bookmarks/data/Track' if receiver=='trackClazz' else 'bookmarks/data/BookmarkManager'
 elif key=='bookmarks/data/ElevationInfo.cpp':value='bookmarks/data/ElevationInfo$Point'
 elif key=='bookmarks/data/Metadata.cpp':value='bookmarks/data/MapObject'
 elif key=='bookmarks/data/Track.cpp':value='bookmarks/data/TrackSelectionCandidate'
 elif key=='core/jni_helper.cpp':
  value={'getStackTraceString':'android/util/Log','dumpReferenceTables':'dalvik/system/VMDebug'}.get(name)
 elif key=='routing/RoutingJni.cpp' and name=='ordinal':value='java/lang/Enum'
 elif key=='util/HttpClient.cpp' and receiver=='callClass':value='okhttp3/internal/connection/RealCall'
 if value and not value.startswith(('java/','android/','dalvik/','okhttp3/')):value='app/organicmaps/sdk/'+value
 return value

checks=[]
for file,s in sources.items():
 for m in re.finditer(r'\b(GetConstructorID|GetMethodID|GetStaticMethodID|GetFieldID|GetStaticFieldID)\s*\(',s):
  kind=m[1];args,end=args_at(s,m.start());cppenv='->' in s[max(0,m.start()-4):m.start()]
  offset=0 if cppenv else 1
  if len(args)<offset+2:continue
  receiver=args[offset];isctor=kind=='GetConstructorID';isfield='Field' in kind
  name='<init>' if isctor else literal(args[-2]);desc=literal(args[-1])
  if name is None or desc is None:continue
  cls=None;var=receiver.strip('*& ')
  # Last local class assignment wins over global aliases.
  patterns=list(re.finditer(r'\b'+re.escape(var)+r'\s*=\s*(?:jni::|env->)?(?:GetGlobalClassRef|FindClass)\([^;\n]*?"([^"\n]+)"\)',s[:m.start()])) if re.fullmatch(r'\w+',var) else []
  if patterns:cls=patterns[-1][1]
  elif len(assign.get(var,set()))==1:cls=next(iter(assign[var]))
  elif 'getBookmarkCategoryClass' in receiver:cls='app/organicmaps/sdk/bookmarks/data/BookmarkCategory'
  sig=name+(':'+desc if isfield else desc)
  if cls is None:cls=manual_receiver(file,receiver,name)
  if cls:
   if cls in classes:status='resolved_match' if has(cls,sig,isfield) else 'RESOLVED_MISSING'
   elif cls.startswith(('java/','android/','javax/','dalvik/')):status='platform_class'
   else:status='RESOLVED_CLASS_MISSING'
   candidates=[]
  else:
   candidates=(fieldclasses if isfield else methodclasses).get(sig,[])
   status='unresolved_receiver_signature_present' if candidates else 'UNRESOLVED_SIGNATURE_MISSING'
  checks.append({'file':file,'line':s[:m.start()].count('\n')+1,'lookup':kind,'receiver':receiver,'class':cls,'name':name,'descriptor':desc,'status':status,'candidate_count':len(candidates),'candidate_examples':candidates[:3]})
summary=dict(collections.Counter(x['status'] for x in checks));bad=[x for x in checks if 'MISSING' in x['status'] or x['status'].startswith('unresolved_')]
report={'contract_consumer':'Mukshat 26112503 preserved Java API','source_cpp_and_hpp_files':len(sources),'literal_callback_lookups':len(checks),'summary':summary,'missing_checks':bad,'checks':checks,'limitations':['Static source audit; no Android VM/native execution.','MUKSHAT_LEGACY_SDK_ABI selected; unrelated preprocessor alternatives conservatively included.','Receiver-unresolved signature matches establish descriptor availability only, not the actual receiver type.','Dynamic/constructed method names or descriptors are not fully resolved by this scanner.']}
if a.report:
 a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'source_files':len(sources),'lookups':len(checks),'summary':summary,'missing':bad},indent=2))
if bad:raise SystemExit(1)
