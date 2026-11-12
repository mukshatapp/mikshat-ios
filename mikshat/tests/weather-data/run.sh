#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
weather_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mikshat-weather-tests.XXXXXX")"
trap 'rm -rf "$weather_tmp"' EXIT
swiftc -parse-as-library \
  "$repo_root/iphone/Maps/UI/Mikshat/Weather/MikshatWeatherData.swift" \
  "$repo_root/mikshat/tests/weather-data/WeatherDataTests.swift" \
  -o "$weather_tmp/weather-tests"
"$weather_tmp/weather-tests" "$repo_root/mikshat/tests/weather-data/fixtures/riyadh-synthetic.json"
