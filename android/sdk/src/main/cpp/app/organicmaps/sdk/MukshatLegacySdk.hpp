#pragma once
#include <jni.h>
// Called on the GUI thread after the current synchronous route-loading operation.
void MukshatOnRoutePointsLoaded(JNIEnv * env, bool loaded);
