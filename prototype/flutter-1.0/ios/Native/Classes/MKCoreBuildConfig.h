#pragma once
// The embedded C++ archive is built as Release in every Flutter configuration.
#ifdef DEBUG
#undef DEBUG
#endif
#ifndef RELEASE
#define RELEASE 1
#endif
#ifndef NDEBUG
#define NDEBUG 1
#endif

#if defined(__OBJC__) && !__has_feature(objc_arc)
#error Mukshat Objective-C++ bridges require ARC
#endif
