#!/usr/bin/env bash
set -euo pipefail
RESERVE_TEST_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RESERVE_TEST_WORK="$(mktemp -d)"
trap 'rm -rf "$RESERVE_TEST_WORK"' EXIT
RESERVE_TEST_FLAGS=(-std=c++23 -Wall -Wextra -Werror -DMUKSHAT_BOUNDARY_STANDALONE)
if [[ "${MUKSHAT_TEST_SANITIZERS:-0}" == 1 ]]; then
  RESERVE_TEST_FLAGS+=(-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer)
else
  RESERVE_TEST_FLAGS+=(-O2)
fi
"${CXX:-c++}" "${RESERVE_TEST_FLAGS[@]}" -I"$RESERVE_TEST_ROOT/libs" \
  "$RESERVE_TEST_ROOT/libs/drape_frontend/drape_frontend_tests/protected_area_boundary_tests.cpp" \
  -o "$RESERVE_TEST_WORK/protected_area_boundary_tests"
"$RESERVE_TEST_WORK/protected_area_boundary_tests"
