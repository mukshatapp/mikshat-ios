"""Compile the actual scoped scale-policy fragments for both build variants."""
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
header = (ROOT / 'libs/indexer/data_header.cpp').read_text()
start = header.index('std::pair<int, int> DataHeader::GetScaleRange() const')
body = header.index('{', start)
depth = 1
end = body + 1
while depth:
    depth += (header[end] == '{') - (header[end] == '}')
    end += 1
function = header[start:end]
source = (ROOT / 'libs/indexer/data_source.cpp').read_text()
start = source.index('#if defined(MUKSHAT_LEGACY_SDK_ABI)')
end = source.index('      // Use last coding scale for covering', start)
read_policy = source[start:end]
cmake = (ROOT / 'android/sdk/src/main/cpp/CMakeLists.txt').read_text()
assert 'target_compile_definitions(indexer PRIVATE MUKSHAT_LEGACY_SDK_ABI)' in cmake
program = '''
#include <array>
#include <cassert>
#include <type_traits>
#include <utility>
#define ASSERT_EQUAL(a,b,...) assert((a)==(b))
namespace scales { int GetUpperScale() { return 17; } int GetUpperWorldScale() { return 9; } }
namespace feature {
struct DataHeader {
 enum class MapType { World, WorldCoasts, Country };
 MapType type; int last;
 MapType GetType() const { return type; }
 int GetLastScale() const { return last; }
 std::pair<int,int> GetScaleRange() const;
};
''' + function + '''
}
namespace covering { struct CoveringGetter {}; struct Covering {}; }
template <class CoveringT> int ReadScale(int scale, int last) {
 feature::DataHeader header{feature::DataHeader::MapType::Country, last};
''' + read_policy + '''
 return scale;
}
int main() {
 using T=feature::DataHeader::MapType;
 assert((feature::DataHeader{T::World,17}.GetScaleRange()==std::pair<int,int>{0,9}));
 assert((feature::DataHeader{T::WorldCoasts,17}.GetScaleRange()==std::pair<int,int>{0,17}));
#if defined(MUKSHAT_LEGACY_SDK_ABI)
 assert((feature::DataHeader{T::Country,17}.GetScaleRange()==std::pair<int,int>{9,17}));
 const std::array<int,6> expected{4,12,13,17,17,17};
#else
 assert((feature::DataHeader{T::Country,17}.GetScaleRange()==std::pair<int,int>{10,17}));
 const std::array<int,6> expected{0,8,9,13,16,17};
#endif
 const std::array<int,6> scales{0,8,9,13,16,17};
 for (unsigned i=0;i<scales.size();++i) {
  assert(ReadScale<covering::CoveringGetter>(scales[i],17)==expected[i]);
  assert(ReadScale<covering::Covering>(scales[i],17)==scales[i]);
 }
 assert(ReadScale<covering::CoveringGetter>(20,9)==9);
 assert(ReadScale<covering::Covering>(20,9)==9);
}
'''
with tempfile.TemporaryDirectory(prefix='mukshat-detail-') as directory:
    path = Path(directory)
    cpp = path / 'policy.cpp'
    cpp.write_text(program)
    for enabled in (False, True):
        output = path / ('legacy' if enabled else 'upstream')
        command = ['g++', '-std=c++23', '-Wall', '-Wextra', '-Werror', str(cpp), '-o', str(output)]
        if enabled:
            command.append('-DMUKSHAT_LEGACY_SDK_ABI=1')
        subprocess.run(command, check=True)
        subprocess.run([str(output)], check=True)
print(json.dumps({'passed': True, 'variants': ['upstream', 'legacy'],
                  'checks_per_variant': 17, 'cmake_indexer_flag_present': True}))
