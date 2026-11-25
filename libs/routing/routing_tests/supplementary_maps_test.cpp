#include "testing/testing.hpp"

#include "generator/generator_tests_support/test_feature.hpp"
#include "generator/generator_tests_support/test_with_custom_mwms.hpp"

#include "routing/data_source.hpp"
#include "routing/features_road_graph.hpp"

#include "routing_common/car_model.hpp"

#include "storage/storage.hpp"

#include <memory>
#include <string>
#include <vector>

namespace supplementary_maps_test
{
using namespace generator::tests_support;
using namespace routing;

class SupplementaryRoutingTest : public TestWithCustomMwms
{
public:
  std::shared_ptr<NumMwmIds> m_ids = std::make_shared<NumMwmIds>();
  MwmSet::MwmId m_official;
  MwmSet::MwmId m_supplementary;
  storage::Storage m_storage;
  std::vector<std::string> m_countryLookups;
  m2::RectD const m_rect{-0.002, -0.002, 0.002, 0.002};

  SupplementaryRoutingTest()
  {
    m_official = BuildCountry("Saudi Arabia_North", [](TestMwmBuilder & builder)
    { builder.Add(TestStreet({{-0.001, 0.001}, {0.001, 0.001}}, "Official road", "en")); });
    m_supplementary = BuildCountry("desert-ksa-north", [](TestMwmBuilder & builder)
    {
      // The display-only road is closer to the query than the routable road.
      builder.Add(TestStreet({{-0.001, 0}, {0.001, 0}}, "Supplementary road", "en"));
    });
    m_ids->RegisterFile(m_official.GetInfo()->GetLocalFile().GetCountryFile());
    CHECK(m_storage.IsNode("Saudi Arabia_North"), ());
    CHECK(!m_storage.IsNode("desert-ksa-north"), ());
  }

  std::shared_ptr<CarModelFactory> MakeFactory()
  {
    return std::make_shared<CarModelFactory>([this](std::string const & country)
    {
      m_countryLookups.push_back(country);
      // Use the production country callback: a supplementary name reaching
      // this call would hit Storage's always-on unknown-country CHECK.
      return m_storage.GetParentIdFor(country);
    });
  }
};

UNIT_CLASS_TEST(SupplementaryRoutingTest, RoadCandidatesExcludeDisplayMapsBeforeCountryLookup)
{
  MwmDataSource source(m_dataSource, m_ids);
  FeaturesRoadGraphBase graph(source, IRoadGraph::Mode::ObeyOnewayTag, MakeFactory());
  auto const roads = graph.FindRoads(m_rect, [&](FeatureID const & feature)
  { return m_ids->ContainsFile(feature.m_mwmId.GetInfo()->GetLocalFile().GetCountryFile()); });
  TEST_EQUAL(roads.size(), 1, ());
  TEST_EQUAL(roads.front().m_featureId.m_mwmId, m_official, ());
  TEST(!m_countryLookups.empty(), ());

  size_t visibleFeatures = 0;
  m_dataSource.ForEachInRect([&](FeatureType &) { ++visibleFeatures; }, m_rect, scales::GetUpperScale());
  TEST_EQUAL(visibleFeatures, 2, ("Display and search retain the supplementary features"));
}

UNIT_CLASS_TEST(SupplementaryRoutingTest, ProjectionExcludesCloserDisplayRoadBeforeCountryLookup)
{
  MwmDataSource source(m_dataSource, m_ids);
  FeaturesRoadGraphBase graph(source, IRoadGraph::Mode::ObeyOnewayTag, MakeFactory());
  std::vector<std::pair<Edge, geometry::PointWithAltitude>> edges;
  graph.FindClosestEdges(m_rect, 4, edges);
  TEST(!edges.empty(), ());
  for (auto const & [edge, projection] : edges)
    TEST_EQUAL(edge.GetFeatureId().m_mwmId, m_official, (projection));
  TEST(!m_countryLookups.empty(), ());
}

UNIT_CLASS_TEST(SupplementaryRoutingTest, MissingRoutingMapReturnsNoRoadsWithoutCountryLookup)
{
  MwmDataSource source(m_dataSource, std::make_shared<NumMwmIds>());
  FeaturesRoadGraphBase graph(source, IRoadGraph::Mode::ObeyOnewayTag, MakeFactory());
  TEST(graph.FindRoads(m_rect, {}).empty(), ());
  std::vector<std::pair<Edge, geometry::PointWithAltitude>> edges;
  graph.FindClosestEdges(m_rect, 4, edges);
  TEST(edges.empty(), ());
  TEST(m_countryLookups.empty(), ());
}

UNIT_CLASS_TEST(SupplementaryRoutingTest, UnrestrictedReaderKeepsCustomMaps)
{
  // OpenLR readers intentionally have no routing catalog.
  MwmDataSource source(m_dataSource, nullptr);
  size_t features = 0;
  bool hasSupplementary = false;
  source.ForEachStreet([&](FeatureType & feature)
  {
    ++features;
    hasSupplementary |= feature.GetID().m_mwmId == m_supplementary;
  }, m_rect);
  TEST_EQUAL(features, 2, ());
  TEST(hasSupplementary, ());
}
}  // namespace supplementary_maps_test
