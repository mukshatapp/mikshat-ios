"""Compile actual GUI policy fragments for both preserved and modern SDK builds."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


def body(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--reference-root', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()

    def read(relative):
        path = args.source_root / relative
        if not path.is_file() and args.reference_root is not None:
            path = args.reference_root / relative
        return path.read_text()

    gui = read('libs/drape_frontend/gui/drape_gui.hpp')
    layers = read('libs/drape_frontend/gui/layer_render.cpp')
    ruler = read('libs/drape_frontend/gui/ruler_helper.cpp')
    skin = read('libs/drape_frontend/gui/skin.hpp')
    enum = body(gui, 'enum class CopyrightState') + ';'
    defaults = re.search(r'#ifdef MUKSHAT_LEGACY_SDK_ABI\n  CopyrightState.*?\n#endif', gui, re.S).group()
    active = body(gui, 'bool IsCopyrightActive() const')
    visible = body(ruler, 'bool RulerHelper::IsVisible')
    widgets = body(skin, 'enum EWidget') + ';'
    condition = re.search(r'#ifdef MUKSHAT_LEGACY_SDK_ABI\n    if \(routingActive.*?\n      continue;', layers, re.S).group()
    program = r'''
#include <cassert>
struct ScreenBase { int scale; };
namespace df { int GetDrawTileScale(ScreenBase const & s) { return s.scale; } }
namespace gui {
WIDGETS
struct DrapeGui {
ENUM
DEFAULTS
ACTIVE
static DrapeGui & Instance() { static DrapeGui gui; return gui; }
};
int constexpr kVisibleRulerBottomScale = 5;
struct RulerHelper { static bool IsVisible(ScreenBase const & screen); };
VISIBLE
bool RenderWidget(int widget, bool routingActive) {
  for (int once = 0; once < 1; ++once) {
    struct { int first; } r{widget};
CONDITION
    return true;
  }
  return false;
}
}
int main() {
  using namespace gui;
  DrapeGui & gui = DrapeGui::Instance();
#ifdef MUKSHAT_LEGACY_SDK_ABI
  assert(gui.m_copyrightState == DrapeGui::CopyrightState::Hidden);
  for (int scale = 1; scale <= 20; ++scale)
    assert(RulerHelper::IsVisible(ScreenBase{scale}) == (scale >= 5));
#else
  assert(gui.m_copyrightState == DrapeGui::CopyrightState::Pending);
  for (int scale = 1; scale <= 20; ++scale)
    assert(!RulerHelper::IsVisible(ScreenBase{scale}));
  gui.m_copyrightState = DrapeGui::CopyrightState::Hidden;
  for (int scale = 1; scale <= 20; ++scale)
    assert(RulerHelper::IsVisible(ScreenBase{scale}) == (scale >= 5));
#endif
  for (bool routing : {false, true}) {
    assert(RenderWidget(WIDGET_COPYRIGHT, routing));
    assert(RenderWidget(WIDGET_SCALE_FPS_LABEL, routing));
    assert(RenderWidget(WIDGET_COMPASS, routing) == !routing);
#ifdef MUKSHAT_LEGACY_SDK_ABI
    assert(RenderWidget(WIDGET_RULER, routing));
#else
    assert(RenderWidget(WIDGET_RULER, routing) == !routing);
#endif
  }
  assert(WIDGET_RULER == 1 && WIDGET_COPYRIGHT == 4);
}
'''
    for marker, text in [('WIDGETS', widgets), ('ENUM', enum), ('DEFAULTS', defaults),
                         ('ACTIVE', active), ('VISIBLE', visible), ('CONDITION', condition)]:
        program = program.replace(marker, text)
    program = '#include <initializer_list>\n' + program
    with tempfile.TemporaryDirectory(prefix='mukshat-gui-policy-') as work:
        source = Path(work) / 'test.cpp'
        source.write_text(program)
        for legacy in (False, True):
            binary = Path(work) / ('legacy' if legacy else 'modern')
            command = ['c++', '-std=c++20', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)]
            if legacy:
                command.insert(1, '-DMUKSHAT_LEGACY_SDK_ABI')
            subprocess.run(command, check=True)
            subprocess.run([str(binary)], check=True)
    report = {'verified': True, 'actual_source_fragments_compiled': True,
              'legacy_checks': 30, 'modern_checks': 50,
              'copyright_widget_default_hidden_in_legacy': True,
              'ruler_visible_without_copyright_widget_from_drawscale5': True,
              'ruler_visible_during_legacy_routing': True,
              'compass_routing_policy_unchanged': True,
              'modern_sdk_behavior_unchanged': True,
              'android_gpu_render_tested': False}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
