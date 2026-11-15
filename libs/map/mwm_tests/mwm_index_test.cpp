#include "testing/testing.hpp"

#include "map/features_fetcher.hpp"

#include "indexer/classificator_loader.hpp"
#include "indexer/scales.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <string>
#include <vector>

namespace mwm_index_test
{
using namespace std;

namespace
{
class CheckNonEmptyGeometry
{
public:
  vector<FeatureID> m_ids;

  void operator()(FeatureID const & id) { m_ids.push_back(id); }

  void operator()(FeatureType & ft)
  {
    bool res = false;
    ft.ForEachPoint([&res](m2::PointD const &) { res = true; }, m_scale);
    ft.ForEachTriangle([&res](m2::PointD const &, m2::PointD const &, m2::PointD const &) { res = true; }, m_scale);

    TEST(res, (ft.DebugString(), "Scale =", m_scale));
  }

  void SetScale(int scale)
  {
    m_ids.clear();
    m_scale = scale;
  }

private:
  int m_scale;
};

bool RunTest(string const & countryFileName, int lowS, int highS)
{
  FeaturesFetcher src;
  auto p = src.RegisterMap(platform::LocalCountryFile::MakeForTesting(countryFileName));
  if (p.second != MwmSet::RegResult::Success)
    return false;

  MwmSet::MwmId const & id = p.first;
  ASSERT(id.IsAlive(), ());

  version::Format const version = id.GetInfo()->m_version.GetFormat();
  if (version == version::Format::unknownFormat)
    return false;

  CheckNonEmptyGeometry doCheck;
  for (int scale = lowS; scale <= highS; ++scale)
  {
    doCheck.SetScale(scale);
    src.ForEachFeatureID(mercator::Bounds::FullRect(), doCheck, scale);
    src.ReadFeatures(doCheck, doCheck.m_ids);
  }

  return true;
}
}  // namespace

UNIT_TEST(ForEachFeatureID_Test)
{
  classificator::Load();

  TEST(RunTest("World", 0, scales::GetUpperWorldScale()), ());
  TEST(RunTest("WorldCoasts", 0, scales::GetUpperWorldScale()), ());
  // TEST(RunTest("Belarus", scales::GetUpperWorldScale() + 1, scales::GetUpperStyleScale()), ());
  TEST(RunTest("minsk-pass", scales::GetUpperWorldScale() + 1, scales::GetUpperStyleScale()), ());
}

UNIT_TEST(ForEachFeatureID_WorldGeometryScaleContract)
{
  classificator::Load();
  FeaturesFetcher src;
  auto const registered = src.RegisterMap(platform::LocalCountryFile::MakeForTesting("World"));
  TEST_EQUAL(registered.second, MwmSet::RegResult::Success, ("The bundled World fixture must register"));
  FeaturesLoaderGuard loader(src.GetDataSource(), registered.first);
  std::array<uint32_t, 2> constexpr reportedIds = {14409, 14858};
  TEST_GREATER(loader.GetNumFeatures(), reportedIds.back(), ("The World fixture must contain the reported features"));

  size_t totalReturned = 0;
  size_t totalEmpty = 0;
  for (int scale = 0; scale <= scales::GetUpperWorldScale(); ++scale)
  {
    std::vector<FeatureID> ids;
    src.ForEachFeatureID(mercator::Bounds::FullRect(), [&](FeatureID const & id) { ids.push_back(id); }, scale);
    std::sort(ids.begin(), ids.end());
    ids.erase(std::unique(ids.begin(), ids.end()), ids.end());
    size_t emptyAtScale = 0;
    src.GetDataSource().ReadFeatures([&](FeatureType & ft)
    {
      // Validate availability without calling GetLimitRect, whose assertion
      // is precisely what a wrongly inflated query can reach in the renderer.
      if (ft.IsEmptyGeometry(scale))
        ++emptyAtScale;
    }, ids);
    totalReturned += ids.size();
    totalEmpty += emptyAtScale;
    std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"scale\",\"scale\":" << scale
              << ",\"returned\":" << ids.size() << ",\"emptyGeometry\":" << emptyAtScale << "}\n";

    for (uint32_t const featureIndex : reportedIds)
    {
      // A new FeatureType per zoom avoids retaining another zoom's parsed
      // geometry. Report both query membership and the original data contract.
      auto ft = loader.GetFeatureByIndex(featureIndex);
      TEST(ft, (featureIndex));
      bool const returned = std::binary_search(ids.begin(), ids.end(), FeatureID(registered.first, featureIndex));
      bool const empty = ft->IsEmptyGeometry(scale);
      std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"reported-feature\",\"scale\":" << scale
                << ",\"id\":" << featureIndex << ",\"returned\":" << (returned ? "true" : "false")
                << ",\"emptyGeometry\":" << (empty ? "true" : "false") << "}\n";
    }
  }
  std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"summary\",\"scales\":"
            << scales::GetUpperWorldScale() + 1 << ",\"returned\":" << totalReturned
            << ",\"emptyGeometry\":" << totalEmpty << "}" << std::endl;
  TEST_GREATER(totalReturned, 0, ("The World fixture must exercise real indexed features"));
  TEST_EQUAL(totalEmpty, 0, ("Every returned World feature must have geometry at the requested zoom"));
}
}  // namespace mwm_index_test
