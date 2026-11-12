# Search investigation: verified logging race in 4.6.12

The user reports a search hang or process exit in 4.6.11, both on the first press
before typing and when reopening search. No fresh matching crash report has
arrived yet. This change fixes a separately reproduced defect; it does not
establish that the physical-device search termination has the same cause.

## Verified defect and change

The iOS logger installs a custom global logging callback and calls
`LogHelper::WriteProlog` concurrently from UI and native worker threads without
the default logger's output mutex. `LogHelper::GetThreadID` modified a shared
`std::map` and counter without its own synchronization. Direct assertion logging
also calls this method without the default output lock.

A private mutex now protects the thread-ID map and counter inside `GetThreadID`.
Its critical section returns the copied integer and ends before formatting,
OS logging or file-queue operations. It neither changes the ID/output format nor
adds a call back into the logger. The default output-lock-to-ID-lock order has
no observed reverse edge. All existing production consumers use references to
the helper; no copy call sites were found.

## Actual production-source comparison

The regression compiles the real `logging.cpp` and `thread.cpp`, using the real
inline timer, with GCC 14 and ThreadSanitizer. Thirty-two live threads start at
one barrier and make 1,000 calls each with their own streams. Assertions check
positive, stable, unique IDs and valid prologs. No copy of the ID algorithm is
used in the test.

- Published 4.6.11 source: ThreadSanitizer reports a data race in
  `GetThreadID`/`WriteProlog`, exit 66.
- The same baseline with an external caller lock: 32,000 calls pass.
- Fixed production source without a caller lock: 32,000 calls pass, no
  ThreadSanitizer reports.

The local comparison used commit `3e42f10`, whose tree is identical to published
`eb1bf79b03d51bb70c3ed40ebf9f7bcf3c77ba1f`. The repeatable CI comparison uses that
published baseline. See `mikshat/tests/logging/README.md` and workflow
`mikshat-logging-race.yml`. Native build results must also be checked before
promoting this source. Version fields are set to 4.6.12; identifiers, signing
configuration, activation and saved user data are unchanged.

## What this does not establish

The older supplied Jetsam record shows two Organic Maps processes terminated
at about 2,098 MiB, without an application version, stack or allocation-category
breakdown. It is not a matching 4.6.11 trace. ThreadSanitizer proves a data race;
it does not prove that this race caused heap corruption or the reported Jetsam.

The earlier 34 native UIKit tests passed with `-IsTests`, which disables active
map rendering. A separate diagnostic branch launches the normal Debug simulator
app with real Saudi map files, Metal and strict foreground/keyboard checks. That
probe has its own result and must not be described as executed search coverage
if its setup fails. Its logging/probe overhead and simulator memory limits also
differ from the physical devices. Neither the probe nor this regression alone
proves the user's issue resolved.

No signed IPA or TestFlight/App Store publication is performed by this change.
