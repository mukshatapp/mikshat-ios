#include "drape_frontend/render_state_extension.hpp"
#include "drape_frontend/gui/ruler_helper.hpp"

#include <array>
#include <tuple>

namespace
{
using namespace df;

std::array<RenderStateExtension, static_cast<size_t>(DepthLayer::LayersCount)> kStateExtensions = {
    RenderStateExtension(DepthLayer::GeometryLayer),    RenderStateExtension(DepthLayer::Geometry3dLayer),
    RenderStateExtension(DepthLayer::UserLineLayer),    RenderStateExtension(DepthLayer::MwmBorderLayer),
    RenderStateExtension(DepthLayer::OverlayLayer),     RenderStateExtension(DepthLayer::TransitSchemeLayer),
    RenderStateExtension(DepthLayer::UserMarkLayer),    RenderStateExtension(DepthLayer::RoutingBottomMarkLayer),
    RenderStateExtension(DepthLayer::RoutingMarkLayer), RenderStateExtension(DepthLayer::SearchMarkLayer),
    RenderStateExtension(DepthLayer::GuiLayer)};

RenderStateExtension kProtectedAreaFillExtension(DepthLayer::GeometryLayer, true);

struct RenderStateExtensionFactory
{
  static ref_ptr<RenderStateExtension> Get(DepthLayer depthLayer, bool isProtectedAreaFill)
  {
    if (isProtectedAreaFill)
    {
      ASSERT_EQUAL(depthLayer, DepthLayer::GeometryLayer, ());
      return make_ref(&kProtectedAreaFillExtension);
    }
    ASSERT_LESS(static_cast<size_t>(depthLayer), kStateExtensions.size(), ());
    return make_ref(&kStateExtensions[static_cast<size_t>(depthLayer)]);
  }
};
}  // namespace

namespace df
{
RenderStateExtension::RenderStateExtension(DepthLayer depthLayer, bool isProtectedAreaFill)
  : m_depthLayer(depthLayer)
  , m_isProtectedAreaFill(isProtectedAreaFill)
{}

bool RenderStateExtension::Less(ref_ptr<dp::BaseRenderStateExtension> other) const
{
  auto const extension = ref_ptr<RenderStateExtension>(other);
  return std::tie(m_depthLayer, m_isProtectedAreaFill) <
         std::tie(extension->m_depthLayer, extension->m_isProtectedAreaFill);
}

bool RenderStateExtension::Equal(ref_ptr<dp::BaseRenderStateExtension> other) const
{
  auto const extension = ref_ptr<RenderStateExtension>(other);
  return m_depthLayer == extension->m_depthLayer && m_isProtectedAreaFill == extension->m_isProtectedAreaFill;
}

DepthLayer GetDepthLayer(dp::RenderState const & state)
{
  return state.GetRenderStateExtension<RenderStateExtension>()->GetDepthLayer();
}

bool IsProtectedAreaFill(dp::RenderState const & state)
{
  return state.GetRenderStateExtension<RenderStateExtension>()->IsProtectedAreaFill();
}

bool IsProtectedAreaFillVisible(ScreenBase const & screen)
{
  return gui::RulerHelper::GetMetricRulerDistance(screen) > 2000.0;
}

dp::RenderState CreateRenderState(gpu::Program program, DepthLayer depthLayer, bool isProtectedAreaFill)
{
  return dp::RenderState(program, RenderStateExtensionFactory::Get(depthLayer, isProtectedAreaFill));
}
}  // namespace df
