#!/usr/bin/env bash
set -euo pipefail

python3 mikshat/tests/update-native/rotation_diagnostic.py "${1:-build/rotation-diagnostic}"
