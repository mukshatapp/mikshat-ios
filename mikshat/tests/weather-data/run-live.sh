#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
weather_live_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mikshat-weather-live.XXXXXX")"
trap 'rm -rf "$weather_live_tmp"' EXIT
swiftc -parse-as-library \
  "$repo_root/iphone/Maps/UI/Mikshat/Weather/MikshatWeatherData.swift" \
  "$repo_root/mikshat/tests/weather-data/WeatherLiveProbe.swift" \
  -o "$weather_live_tmp/live-probe"
"$weather_live_tmp/live-probe"
