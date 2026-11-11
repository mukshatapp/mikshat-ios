#pragma once

#include <objc/runtime.h>
#include <stdbool.h>

// Kept independent of UIKit so inheritance dispatch can be regression-tested
// against an Objective-C runtime without a simulator.
static inline bool MWMSwizzleInstanceMethods(Class targetClass, SEL original, SEL replacement)
{
  if (!targetClass || !original || !replacement)
    return false;

  Method originalMethod = class_getInstanceMethod(targetClass, original);
  Method replacementMethod = class_getInstanceMethod(targetClass, replacement);
  if (!originalMethod || !replacementMethod)
    return false;

  if (class_addMethod(targetClass, original, method_getImplementation(replacementMethod),
                      method_getTypeEncoding(replacementMethod)))
  {
    class_replaceMethod(targetClass, replacement, method_getImplementation(originalMethod),
                        method_getTypeEncoding(originalMethod));
  }
  else
  {
    method_exchangeImplementations(originalMethod, replacementMethod);
  }
  return true;
}
