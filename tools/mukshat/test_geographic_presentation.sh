#!/usr/bin/env bash
set -euo pipefail
GEOGRAPHY_TEST_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEOGRAPHY_TEST_WORK="$(mktemp -d)"
trap 'rm -rf "$GEOGRAPHY_TEST_WORK"' EXIT
GEOGRAPHY_TEST_FLAGS=(-std=c++23 -Wall -Wextra -Werror -DMUKSHAT_GEOGRAPHY_STANDALONE)
if [[ "${MUKSHAT_TEST_SANITIZERS:-0}" == 1 ]]; then
  GEOGRAPHY_TEST_FLAGS+=(-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer)
else
  GEOGRAPHY_TEST_FLAGS+=(-O2)
fi
"${CXX:-c++}" "${GEOGRAPHY_TEST_FLAGS[@]}" -I"$GEOGRAPHY_TEST_ROOT/libs" \
  "$GEOGRAPHY_TEST_ROOT/libs/drape_frontend/drape_frontend_tests/mukshat_geographic_presentation_tests.cpp" \
  -o "$GEOGRAPHY_TEST_WORK/geographic_presentation_tests"
"$GEOGRAPHY_TEST_WORK/geographic_presentation_tests"
