"""Add an opt-in ABI adapter for the preserved Mukshat 26112301 Java SDK."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[2];base=R/'android/sdk/src/main/cpp/app/organicmaps/sdk'
def function(path,name,legacy):
 s=path.read_text();m=re.search(r'JNIEXPORT\s+\w+\s+'+re.escape(name)+r'\s*\([^)]*\)\s*\{',s,re.S)
 if not m:raise ValueError(name)
 start=m.start();i=m.end();depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 original=s[start:i];replacement='#if defined(MUKSHAT_LEGACY_SDK_ABI)\n'+legacy+'\n#else\n'+original+'\n#endif'
 path.write_text(s[:start]+replacement+s[i:])
for method in ['Download','Cancel']:
 p=base/'MapManager.cpp';name='Java_app_organicmaps_sdk_downloader_MapManager_native'+method
 operation='GetStorage().DownloadNode(jni::ToNativeString(env, root), false /* isUpdate */, false /* withTerrain */);' if method=='Download' else 'GetStorage().CancelDownloadNode(GetRootId(env, root), false /* withTerrain */);'
 function(p,name,f'JNIEXPORT void {name}(JNIEnv * env, jclass, jstring root)\n{{\n  StartBatchingCallbacks();\n  {operation}\n  EndBatchingCallbacks(env);\n}}')
for method in ['Add','Remove']:
 name='Java_app_organicmaps_sdk_routing_RoutingOptions_native'+method+'Option'
 body=f'''JNIEXPORT void {name}(JNIEnv *, jclass, jint option)
{{
  using routing::RoutingOptions;
  auto const vehicle = RoutingOptions::GetVehicleType(frm()->GetRoutingManager().GetRouter());
  if (!vehicle)
    return;
  auto value = RoutingOptions::LoadFromSettings(*vehicle);
  value.{method}(routing_jni::ToRoutingOptionsRoad(option));
  RoutingOptions::SaveToSettings(*vehicle, value);
}}'''
 function(base/'routing/RoutingJni.cpp',name,body)
name='Java_app_organicmaps_sdk_util_Config_nativeDeleteConfigValue'
function(base/'util/Config.cpp',name,f'''JNIEXPORT jboolean {name}(JNIEnv * env, jclass, jstring name)
{{
  auto const key = jni::ToNativeString(env, name);
  std::string old;
  bool const existed = settings::Get(key, old);
  settings::Delete(key);
  return existed;
}}''')
for name,path,call in [('Java_app_organicmaps_sdk_Framework_nativeSaveRoute',base/'Framework.cpp','frm()->SaveRoute()'),('Java_app_organicmaps_sdk_location_TrackRecorder_nativeSaveTrackRecordingWithName',base/'TrackRecorder.cpp','frm()->SaveTrackRecordingWithName(jni::ToNativeString(env, name))')]:
 args='JNIEnv * env, jclass, jstring name' if 'TrackRecorder' in name else 'JNIEnv *, jclass'
 function(path,name,f'JNIEXPORT void {name}({args})\n{{\n  (void){call};\n}}')
name='Java_app_organicmaps_sdk_Framework_nativeLoadRoutePoints'
p=base/'Framework.cpp';s=p.read_text();s=s.replace('#include "app/organicmaps/sdk/Framework.hpp"','#include "app/organicmaps/sdk/Framework.hpp"\n#if defined(MUKSHAT_LEGACY_SDK_ABI)\n#include "app/organicmaps/sdk/MukshatLegacySdk.hpp"\n#endif',1);p.write_text(s)
function(p,name,f'''JNIEXPORT void {name}(JNIEnv * env, jclass)
{{
  MukshatOnRoutePointsLoaded(env, frm()->GetRoutingManager().LoadRoutePoints());
}}''')
p=R/'android/sdk/src/main/cpp/CMakeLists.txt';s=p.read_text();needle='omim_add_library(${PROJECT_NAME} SHARED ${SRC})';s=s.replace(needle,needle+'''\n\noption(MUKSHAT_LEGACY_SDK_ABI "Build against the preserved Mukshat 26112301 JNI contract" OFF)
if (MUKSHAT_LEGACY_SDK_ABI)
  target_sources(${PROJECT_NAME} PRIVATE app/organicmaps/sdk/MukshatLegacySdk.cpp)
  target_compile_definitions(${PROJECT_NAME} PRIVATE MUKSHAT_LEGACY_SDK_ABI)
endif()
''');p.write_text(s)
print('Prepared opt-in legacy adapter. Default upstream SDK ABI is unchanged.')
