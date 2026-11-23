#include "TrackStatistics.hpp"

#include "app/organicmaps/sdk/core/jni_helper.hpp"

jobject ToJavaTrackStatistics(JNIEnv * env, TrackStatistics const & stats, bool hasElevationInfo)
{
#if defined(MUKSHAT_LEGACY_SDK_ABI)
  static jmethodID const cId = jni::GetConstructorID(env, g_trackStatisticsClazz, "(DDDDII)V");
  return env->NewObject(g_trackStatisticsClazz, cId, stats.m_length, stats.m_duration, stats.m_ascent, stats.m_descent,
                        static_cast<jint>(stats.m_minElevation), static_cast<jint>(stats.m_maxElevation));
#else
  static jmethodID const cId = jni::GetConstructorID(env, g_trackStatisticsClazz, "(DDDDIIZ)V");
  return env->NewObject(g_trackStatisticsClazz, cId, stats.m_length, stats.m_duration, stats.m_ascent, stats.m_descent,
                        static_cast<jint>(stats.m_minElevation), static_cast<jint>(stats.m_maxElevation),
                        static_cast<jboolean>(hasElevationInfo));
#endif
}
