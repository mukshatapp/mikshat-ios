#!/usr/bin/env python3
"""Exercise actual storage status/action methods with map/terrain test doubles.

The full storage tests also cover sizes and progress. This small host test is
usable in the Android-native workflow without building the host test runner.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def function(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    paths = ['libs/storage/storage.cpp', 'libs/storage/storage.hpp',
             'android/sdk/src/main/cpp/app/organicmaps/sdk/MapManager.cpp']
    source, header, jni = [(args.source_root / name).read_text() for name in paths]
    for name in ('GetNodeAttrs', 'GetNodeStatuses', 'GetUpdateInfo', 'UpdateNode', 'RetryDownloadNode'):
        if not re.search(r'\b' + name + r'\([^;]+bool withTerrain = true\)', header):
            raise ValueError('Modern terrain default was not preserved for ' + name)
    policy = re.search(r'#if defined\(MUKSHAT_LEGACY_SDK_ABI\)\s+constexpr bool kWithTerrain = false;'
                       r'\s+#else\s+constexpr bool kWithTerrain = true;\s+#endif', jni)
    if policy is None:
        raise ValueError('JNI consumer policy is missing')
    for name in ('GetNodeAttrs', 'GetNodeStatuses', 'GetUpdateInfo', 'UpdateNode', 'RetryDownloadNode'):
        calls = []
        for match in re.finditer(r'GetStorage\(\)\.' + name + r'\(', jni):
            start = match.end()
            depth, end = 1, start
            while depth:
                depth += (jni[end] == '(') - (jni[end] == ')')
                end += 1
            calls.append(jni[start:end - 1])
        if not calls or any('kWithTerrain' not in call for call in calls):
            raise ValueError('JNI reporting/action mismatch for ' + name)
    attrs = function(source, 'void Storage::GetNodeAttrs(')
    if 'auto const terrain = withTerrain ? GetTerrainAttrs(countryId) : TerrainAttrs{};' not in attrs:
        raise ValueError('Map-only attributes still inspect terrain')
    if 'GetDownloadSize({countryId}, withTerrain)' not in attrs:
        raise ValueError('Attribute download bytes ignore requested file types')
    if 'GetUpdateInfo(countryId, info, withTerrain)' not in attrs:
        raise ValueError('Attribute update bytes ignore requested file types')
    methods = '\n'.join(function(source, signature) for signature in (
        'StatusAndError Storage::GetEffectiveStatus(', 'void Storage::GetNodeStatuses(',
        'void Storage::UpdateNode(', 'void Storage::RetryDownloadNode('))
    harness = r'''
#include <algorithm>
#include <cstdint>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>
#define CHECK_THREAD_CHECKER(...) ((void)0)
#define CHECK(...) ((void)0)
using CountryId = std::string;
using CountriesSet = std::set<CountryId>;
enum class NodeStatus { Undefined, Downloading, Applying, InQueue, Error, OnDiskOutOfDate, OnDisk, NotDownloaded, Partly };
enum class NodeErrorCode { NoError, UnknownError, OutOfMemFailed, NoInetConnection };
enum class MapFileType { Map };
struct StatusAndError { NodeStatus status; NodeErrorCode error; };
struct NodeStatuses { NodeStatus m_status; NodeErrorCode m_error; bool m_groupNode; };
struct CountryTree {
  struct Node { int ChildrenCount() const { return 0; } } node;
  Node const * FindFirst(CountryId const &) const { return &node; }
};
struct LocalFile { bool OnDisk(MapFileType) const { return true; } };
struct DiffSource { bool HasDiffFor(CountryId const &) const { return false; } };
struct Storage {
  enum class TerrainStatus { NotAvailable, NotDownloaded, Downloading, Partly, OnDisk, Failed, OnDiskOutOfDate };
  struct TerrainAttrs { TerrainStatus m_status = TerrainStatus::NotAvailable; uint64_t m_remainingSize = 0; };
  CountryTree m_countries;
  StatusAndError mapState{NodeStatus::OnDisk, NodeErrorCode::NoError};
  TerrainAttrs terrain;
  std::map<CountryId, int> m_localFiles;
  struct { std::map<CountryId, CountryId> m_mwmToOld; } m_countriesInfo;
  CountriesSet m_failedCountries, failedTerrain;
  std::unique_ptr<DiffSource> m_diffsDataSource = std::make_unique<DiffSource>();
  std::vector<std::tuple<CountryId, bool, bool>> mapRequests;
  int terrainRequests = 0;
  StatusAndError GetNodeStatus(CountryTree::Node const &) const { return mapState; }
  TerrainAttrs GetTerrainAttrs(CountryId const &) const { return terrain; }
  template <class F> void ForEachInSubtree(CountryId const & id, F f) const { f(id, false); }
  template <class F> void ForEachTerrainBlockToUpdate(CountryId const & id, F f) const { f(id, uint32_t{0}); }
  std::shared_ptr<LocalFile> GetLatestLocalFile(CountryId const &) const { return {}; }
  bool IsRealObsolete(std::shared_ptr<LocalFile> const &) const { return false; }
  CountriesSet GetFailedTerrainRegions() const { return failedTerrain; }
  void DownloadNode(CountryId const & id, bool update, bool withTerrain = true) {
    mapRequests.emplace_back(id, update, withTerrain);
    if (withTerrain) ++terrainRequests;
  }
  void DownloadTerrain(CountriesSet const & ids) { if (!ids.empty()) ++terrainRequests; }
  StatusAndError GetEffectiveStatus(StatusAndError, TerrainAttrs const &) const;
  void GetNodeStatuses(CountryId const &, NodeStatuses &, bool withTerrain = true) const;
  void UpdateNode(CountryId const &, bool withTerrain = true);
  void RetryDownloadNode(CountryId const &, bool withTerrain = true);
};
int checks = 0;
void test(bool passed) { if (!passed) throw std::runtime_error("Storage policy regression"); ++checks; }
'''
    harness += policy[0] + '\n' + methods
    harness += r'''
int main() {
  for (int state = 0; state != 9; ++state) {
    for (auto terrain : {Storage::TerrainStatus::NotAvailable, Storage::TerrainStatus::Downloading,
                         Storage::TerrainStatus::Failed}) {
      Storage s;
      s.mapState = {static_cast<NodeStatus>(state), NodeErrorCode::NoError};
      s.terrain = {terrain, 100};
      NodeStatuses maps, combined;
      s.GetNodeStatuses("West", maps, false);
      test(maps.m_status == s.mapState.status && maps.m_error == s.mapState.error);
      s.GetNodeStatuses("West", combined);
      auto expected = s.GetEffectiveStatus(s.mapState, s.terrain);
      test(combined.m_status == expected.status && combined.m_error == expected.error);
    }
  }
  for (bool withTerrain : {false, true}) {
    Storage s;
    s.m_localFiles["West"] = 1;
    s.UpdateNode("West", withTerrain);
    test(s.mapRequests.size() == 1);
    test(std::get<1>(s.mapRequests[0]) && std::get<2>(s.mapRequests[0]) == withTerrain);
    test((s.terrainRequests > 0) == withTerrain);
    Storage missing;
    missing.UpdateNode("West", withTerrain);
    test(missing.mapRequests.empty());
    test((missing.terrainRequests > 0) == withTerrain);
    Storage retry;
    retry.m_failedCountries.insert("West");
    retry.failedTerrain.insert("West");
    retry.RetryDownloadNode("West", withTerrain);
    test(retry.mapRequests.size() == 1 && !std::get<2>(retry.mapRequests[0]));
    test((retry.terrainRequests > 0) == withTerrain);
    Storage terrainOnly;
    terrainOnly.failedTerrain.insert("West");
    terrainOnly.RetryDownloadNode("West", withTerrain);
    test(terrainOnly.mapRequests.empty());
    test((terrainOnly.terrainRequests > 0) == withTerrain);
  }
  Storage policy;
  policy.m_localFiles["West"] = 1;
  policy.UpdateNode("West", kWithTerrain);
#if defined(MUKSHAT_LEGACY_SDK_ABI)
  test(policy.terrainRequests == 0);
#else
  test(policy.terrainRequests > 0);
#endif
  std::cout << checks << " actual-method policy assertions passed\n";
}
'''
    compiler = shutil.which('g++') or shutil.which('clang++')
    if compiler is None:
        raise ValueError('A host C++ compiler is required')
    outputs = {}
    with tempfile.TemporaryDirectory(prefix='mukshat-maponly-storage-') as tmp:
        work = Path(tmp)
        (work / 'test.cpp').write_text(harness)
        for mode in ('legacy', 'modern'):
            command = [compiler, '-std=c++23', '-Wall', '-Wextra', '-Werror', str(work / 'test.cpp'),
                       '-o', str(work / mode)]
            if mode == 'legacy':
                command.insert(1, '-DMUKSHAT_LEGACY_SDK_ABI=1')
            subprocess.run(command, check=True)
            outputs[mode] = subprocess.check_output([str(work / mode)], text=True).strip()
    report = {'passed': True, 'host_method_results': outputs,
              'jni_policy': {'legacy_with_terrain': False, 'modern_with_terrain': True},
              'source_hashes': {name: hashlib.sha256((args.source_root / name).read_bytes()).hexdigest()
                                for name in paths},
              'full_storage_tests_extended': ['Storage_TerrainUpdatesUseCombinedStatusAndActions',
                  'Storage_TerrainLeafAndFolderSizes', 'Storage_TerrainRetry',
                  'Storage_MapAndTerrainDownloadingProgressAreIndependent'],
              'full_storage_test_runner_executed_by_this_tool': False,
              'android_download_runtime_tested_by_this_tool': False}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
