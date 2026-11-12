# Production logging thread-safety regression

Run the actual production logging implementation under ThreadSanitizer:

```sh
CXX=g++ bash mikshat/tests/logging/run.sh
```

To prove the earlier race and compare it with the fixed source:

```sh
MIKSHAT_LOG_TEST_OUTPUT=/tmp/mikshat-log-comparison \
  CXX=g++ bash mikshat/tests/logging/run.sh \
    --baseline-ref eb1bf79b03d51bb70c3ed40ebf9f7bcf3c77ba1f
```

Use a locally available baseline commit; this script fetches nothing. A shallow
CI checkout must include the parent baseline. The local proof also used
`3e42f10`, whose source tree equals the published 4.6.11 commit above.
The comparison extracts the baseline's actual `libs/base` and `libs/std` sources
from Git. It does not mirror the thread-ID algorithm or edit either source.

The harness compiles production `logging.cpp` and `thread.cpp`; the timer uses its
production inline implementation. Unused sections are removed at link time so
no full application build is needed. A C++23 compiler with ThreadSanitizer,
Python 3, Git and tar are required. Linux GCC 14 and modern Apple Clang use the
appropriate platform link flags. Compiler or sanitizer-runtime errors fail the
script; they are not treated as a successful race verdict.
The runner disables the sanitizer's default abort on Apple platforms so the
expected race still must exit with the configured code 66; the race stack and
zero-report controls remain mandatory.

Thirty-two simultaneously live threads start at one barrier and each call the
production `WriteProlog` 1,000 times with its own output stream. The test checks
positive, stable and unique thread IDs, the ID embedded in every prolog, the
level/delimiters and a finite, nonnegative elapsed time.

The unsafe baseline must produce a ThreadSanitizer race in production
`GetThreadID`/`WriteProlog`. A serialized baseline control must pass. The current
source must then pass **without a caller lock**, matching the iOS logger's
calling pattern. Logs and a bounded summary are written to the reported output
directory, not to the app's logger.

The fix protects only the shared map and counter inside `GetThreadID`. It
preserves thread-ID and output-format behavior and releases the lock before
formatting, OS logging or file logging. This also covers direct assertion-path
callers that do not hold the default logger's output mutex. There is no call
from this critical section into the logger, so the default output mutex's
ordering does not acquire an inverse edge.

This regression establishes a logging data race and its synchronization fix. It
does **not** establish the cause of the reported iOS search hang or Jetsam event.
