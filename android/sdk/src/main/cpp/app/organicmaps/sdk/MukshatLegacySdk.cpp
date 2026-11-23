#include "app/organicmaps/sdk/MukshatLegacySdk.hpp"
#include "app/organicmaps/sdk/Framework.hpp"
#include "app/organicmaps/sdk/core/jni_helper.hpp"
#include "map/gps_tracker.hpp"
#include "routing/routing_options.hpp"

namespace
{
std::shared_ptr<jobject> g_loadListener;
}

void MukshatOnRoutePointsLoaded(JNIEnv * env, bool loaded)
{
  // Keep a local owner in case the callback removes its subscription synchronously.
  auto const listener = g_loadListener;
  if (!listener)
    return;
  auto const method = jni::GetMethodID(env, *listener, "onRoutePointsLoaded", "(Z)V");
  env->CallVoidMethod(*listener, method, static_cast<jboolean>(loaded));
  jni::HandleJavaException(env);
}

extern "C"
{
JNIEXPORT void Java_app_organicmaps_sdk_Framework_nativeSetRoutingLoadPointsListener(JNIEnv *, jclass, jobject listener)
{
  g_loadListener = listener ? jni::make_global_ref(listener) : nullptr;
}

JNIEXPORT void Java_app_organicmaps_sdk_Framework_nativeApplyRoutePointsTransaction(JNIEnv *, jclass, jint id)
{
  frm()->GetRoutingManager().ApplyRoutePointsTransaction(static_cast<uint32_t>(id));
}

JNIEXPORT void Java_app_organicmaps_sdk_Framework_nativeCancelRoutePointsTransaction(JNIEnv *, jclass, jint id)
{
  frm()->GetRoutingManager().CancelRoutePointsTransaction(static_cast<uint32_t>(id));
}

JNIEXPORT jint Java_app_organicmaps_sdk_Framework_nativeInvalidRoutePointsTransactionId(JNIEnv *, jclass)
{
  return RoutingManager::InvalidRoutePointsTransactionId();
}

JNIEXPORT jboolean Java_app_organicmaps_sdk_location_TrackRecorder_nativeIsTrackRecordingEmpty(JNIEnv *, jclass)
{
  return GpsTracker::Instance().GetTrackStatistics().m_length == 0.0;
}

JNIEXPORT jboolean Java_app_organicmaps_sdk_routing_RoutingOptions_nativeHasOption(JNIEnv *, jclass, jint id)
{
  using routing::RoutingOptions;
  auto const vehicle = RoutingOptions::GetVehicleType(frm()->GetRoutingManager().GetRouter());
  auto const road = RoutingOptions::RoadFromId(static_cast<uint32_t>(id));
  return vehicle && road && RoutingOptions::LoadFromSettings(*vehicle).Has(*road);
}
JNIEXPORT void Java_app_organicmaps_sdk_Framework_nativeRemoveRoute(JNIEnv *, jclass)
{
  frm()->GetRoutingManager().RemoveRoute(false /* deactivateFollowing */);
}

JNIEXPORT jint Java_app_organicmaps_sdk_downloader_MapManager_nativeGetOverallProgress(JNIEnv * env, jclass,
                                                                                     jobjectArray values)
{
  storage::CountriesVec countries;
  auto const count = env->GetArrayLength(values);
  countries.reserve(count);
  for (jsize i = 0; i < count; ++i)
  {
    jni::TScopedLocalRef const item(env, env->GetObjectArrayElement(values, i));
    countries.push_back(jni::ToNativeString(env, static_cast<jstring>(item.get())));
  }
  auto const progress = frm()->GetStorage().GetOverallProgress(countries);
  return progress.m_bytesTotal ? static_cast<jint>(progress.m_bytesDownloaded * 100.0 / progress.m_bytesTotal) : 0;
}

}
