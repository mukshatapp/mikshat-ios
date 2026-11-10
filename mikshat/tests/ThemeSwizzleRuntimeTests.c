// Standalone Objective-C runtime regression: no UIKit or Objective-C compiler required.
// Run against libobjc (GNU on Linux or Apple on macOS), using the production helper.
#include "../../iphone/Maps/Core/Theme/Swizzle/SwizzleRuntime.h"

#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

typedef void (*VoidMethod)(id, SEL);

struct Counters
{
  unsigned parentOriginal;
  unsigned childOriginal;
  unsigned parentHook;
  unsigned childHook;
  unsigned depth;
  bool recursion;
};

static struct Counters counts;
static Class activeChild;

#ifndef __APPLE__
// GNU libobjc can retain stale inherited IMPs for synthesized classes after
// method_exchangeImplementations. This test-only cache refresh changes no
// methods or selectors; Apple's runtime branch requires no private API.
extern void __objc_update_dispatch_table_for_class(Class);
#endif

static void Check(bool condition, char const * message)
{
  if (!condition)
  {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(EXIT_FAILURE);
  }
}

static void Send(id receiver, char const * selectorName)
{
  SEL selector = sel_registerName(selectorName);
#ifdef __APPLE__
  ((VoidMethod)objc_msgSend)(receiver, selector);
#else
  ((VoidMethod)objc_msg_lookup(receiver, selector))(receiver, selector);
#endif
}

static void SendSuper(id receiver, char const * selectorName)
{
  SEL selector = sel_registerName(selectorName);
  struct objc_super superInfo = {receiver, class_getSuperclass(activeChild)};
#ifdef __APPLE__
  ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, selector);
#else
  ((VoidMethod)objc_msg_lookup_super(&superInfo, selector))(receiver, selector);
#endif
}

static void ParentOriginal(id self, SEL command)
{
  (void)self;
  (void)command;
  ++counts.parentOriginal;
}

static void Initialize(id self, SEL command)
{
  (void)self;
  (void)command;
}

static void ChildOriginal(id self, SEL command)
{
  (void)command;
  ++counts.childOriginal;
  SendSuper(self, "didMoveToWindow");
}

static bool EnterHook(void)
{
  // Stop safely instead of overflowing the stack in the legacy failure case.
  if (++counts.depth > 8)
  {
    counts.recursion = true;
    --counts.depth;
    return false;
  }
  return true;
}

static void LegacyParentHook(id self, SEL command)
{
  (void)command;
  ++counts.parentHook;
  if (!EnterHook())
    return;
  Send(self, "sw_didMoveToWindow");
  --counts.depth;
}

static void LegacyChildHook(id self, SEL command)
{
  (void)command;
  ++counts.childHook;
  if (!EnterHook())
    return;
  Send(self, "sw_didMoveToWindow");
  --counts.depth;
}

static void SafeParentHook(id self, SEL command)
{
  (void)command;
  ++counts.parentHook;
  if (!EnterHook())
    return;
  Send(self, "sw_viewDidMoveToWindow");
  --counts.depth;
}

static void SafeChildHook(id self, SEL command)
{
  (void)command;
  ++counts.childHook;
  if (!EnterHook())
    return;
  Send(self, "sw_textFieldDidMoveToWindow");
  --counts.depth;
}

static void AddMethod(Class cls, char const * selector, VoidMethod method)
{
  Check(class_addMethod(cls, sel_registerName(selector), (IMP)method, "v@:"), "Add runtime method");
}

static Class MakeHierarchy(bool legacy, bool inheritsOriginal)
{
  char const * parentName = legacy ? "MikshatLegacyParent" :
                                    (inheritsOriginal ? "MikshatInheritedParent" : "MikshatSafeParent");
  char const * childName = legacy ? "MikshatLegacyChild" :
                                   (inheritsOriginal ? "MikshatInheritedChild" : "MikshatSafeChild");
  Class parent = objc_allocateClassPair(Nil, parentName, 0);
  Check(parent != Nil, "Allocate parent runtime class");
  AddMethod(parent, "didMoveToWindow", ParentOriginal);
  AddMethod(parent, legacy ? "sw_didMoveToWindow" : "sw_viewDidMoveToWindow",
            legacy ? LegacyParentHook : SafeParentHook);
  AddMethod(object_getClass((id)parent), "initialize", Initialize);
  objc_registerClassPair(parent);

  Class child = objc_allocateClassPair(parent, childName, 0);
  Check(child != Nil, "Allocate child runtime class");
  if (!inheritsOriginal)
    AddMethod(child, "didMoveToWindow", ChildOriginal);
  AddMethod(child, legacy ? "sw_didMoveToWindow" : "sw_textFieldDidMoveToWindow",
            legacy ? LegacyChildHook : SafeChildHook);
  objc_registerClassPair(child);

  // Realize and initialize the hierarchy before exchanging methods, as UIKit
  // classes are initialized before the app styles its search screen.
  activeChild = child;
  id warming = class_createInstance(child, 0);
  Check(warming != nil, "Allocate warm-up instance");
  Send(warming, "didMoveToWindow");
  object_dispose(warming);

  // Match production order: hook subclasses before UIView.
  SEL original = sel_registerName("didMoveToWindow");
  Check(MWMSwizzleInstanceMethods(child, original,
                                 sel_registerName(legacy ? "sw_didMoveToWindow" : "sw_textFieldDidMoveToWindow")),
        "Install child hook");
  Check(MWMSwizzleInstanceMethods(parent, original,
                                 sel_registerName(legacy ? "sw_didMoveToWindow" : "sw_viewDidMoveToWindow")),
        "Install parent hook");
#ifndef __APPLE__
  __objc_update_dispatch_table_for_class(parent);
  __objc_update_dispatch_table_for_class(child);
#endif
  return child;
}

static void Exercise(Class cls)
{
  counts = (struct Counters){0};
  activeChild = cls;
  id object = class_createInstance(cls, 0);
  Check(object != nil, "Allocate runtime instance");
  Send(object, "didMoveToWindow");
  object_dispose(object);
}

int main(void)
{
  Exercise(MakeHierarchy(true, false));
  Check(counts.recursion, "Legacy shared selector must reproduce recursive dispatch");
  Check(counts.parentOriginal == 0, "Legacy dispatch never reaches parent original");
  Check(counts.childOriginal > 1, "Legacy child original is called repeatedly");
  printf("PASS: reproduced legacy recursion safely (child original %u, parent hook %u, parent original %u)\n",
         counts.childOriginal, counts.parentHook, counts.parentOriginal);

  Class safe = MakeHierarchy(false, false);
  Exercise(safe);
  Check(!counts.recursion && counts.depth == 0, "Distinct aliases return normally");
  Check(counts.parentOriginal == 1 && counts.childOriginal == 1, "Both original methods execute exactly once");
  Check(counts.parentHook == 1 && counts.childHook == 1, "Both hooks execute exactly once");
  printf("PASS: distinct aliases preserve child/super calls exactly once\n");

  Class inherited = MakeHierarchy(false, true);
  Exercise(inherited);
  Check(!counts.recursion && counts.depth == 0, "Inherited-method installation returns normally");
  Check(counts.parentOriginal == 1 && counts.childOriginal == 0 && counts.childHook == 1,
        "Class-add/replace branch preserves the inherited original exactly once");
  printf("PASS: inherited original is installed on child without modifying parent dispatch\n");

  Exercise(class_getSuperclass(inherited));
  Check(counts.parentOriginal == 1 && counts.parentHook == 1 && counts.childHook == 0,
        "Installing inherited child hook leaves the parent's hook chain intact");

  SEL original = sel_registerName("didMoveToWindow");
  SEL missing = sel_registerName("missingMikshatSelector");
  Check(!MWMSwizzleInstanceMethods(Nil, original, missing), "Reject missing class");
  Check(!MWMSwizzleInstanceMethods(safe, original, missing), "Reject missing replacement");
  Check(!MWMSwizzleInstanceMethods(safe, missing, original), "Reject missing original");
  printf("PASS: invalid hook inputs are rejected\n");
  return EXIT_SUCCESS;
}
