#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace kml
{
using MarkId = int;
using TrackId = int;
constexpr int kInvalidMarkId = -1, kInvalidTrackId = -1, kTempRelationTrackId = -2;
}  // namespace kml
struct Point
{
  double x = 0, y = 0;
};
namespace df
{
struct SelectionShape
{
  enum class ESelectedObject
  {
    OBJECT_TRACK
  };
};
}  // namespace df
int FeatureID()
{
  return 0;
}
namespace routing
{
enum class RouterType
{
  Vehicle,
  Ruler
};
}  // namespace routing
namespace place_page
{
struct BuildInfo
{
  enum class Source
  {
    User,
    Search,
    Other
  };
  Source m_source = Source::Other;
  bool m_isLongTap = false;
  int m_userMarkId = kml::kInvalidMarkId;
  Point m_mercator{47.1, 23.9};
};
struct Info
{
  bool routePoint = false, bookmark = false;
  int track = kml::kInvalidTrackId;
  std::string title = "history location";
  struct Bookmark
  {
    Point m_point{48.0, 24.0};
  } data;
  bool IsRoutePoint() const { return routePoint; }
  bool IsBookmark() const { return bookmark; }
  Bookmark GetBookmarkData() const { return data; }
  std::string GetTitle() const { return title; }
  int GetTrackId() const { return track; }
  Point GetMercator() const { return data.m_point; }
  int GetID() const { return 0; }
};
}  // namespace place_page
struct UserMark
{
  enum class Type
  {
    ROUTE_ALT,
    API
  };
  static Type GetMarkType(int id) { return id == 99 ? Type::ROUTE_ALT : Type::API; }
};
struct RouteAltMark : UserMark
{
  int GetRouteIdx() const { return 2; }
};
enum class RouteMarkType
{
  Finish
};
struct RouteMarkData
{
  std::string m_title, m_subTitle;
  RouteMarkType m_pointType{};
  int m_intermediateIndex = 0;
  bool m_isMyPosition = false;
  Point m_position;
};
struct Route
{
  bool active = true;
  routing::RouterType type = routing::RouterType::Ruler;
  int removed = 0, built = 0, swapped = 0;
  std::vector<Point> points{{46.0, 23.0}, {47.0, 24.0}};
  bool IsRoutingActive() const { return active; }
  routing::RouterType GetRenderRouterType() const { return type; }
  bool TryTapOnAlternativeRoute(Point, double) const { return false; }
  void SwapActiveAlternative(int) { ++swapped; }
  int GetRoutePointsCount() const { return static_cast<int>(points.size()); }
  bool ContinueRouteToPoint(RouteMarkData data)
  {
    points.push_back(data.m_position);
    return true;
  }
  void RemoveRoute(bool) { ++removed; }
  void BuildRoute() { ++built; }
};
struct Bookmarks
{
  RouteAltMark alt;
  UserMark const * GetUserMark(int id) { return id == 99 ? &alt : nullptr; }
  void UpdateElevationMyPosition(int, bool) {}
};
struct ModelView
{
  double GetScale() const { return 1.0; }
};
struct Drape
{
  template <typename... Args>
  void SelectObject(Args...)
  {}
};
class Framework
{
public:
  Route m_routingManager;
  ModelView m_currentModelView;
  Bookmarks bookmarks;
  place_page::Info nextInfo;
  std::optional<place_page::Info> m_currentPlacePageInfo;
  Drape * m_drapeEngine = nullptr;
  int shown = 0, deactivated = 0, fullScreen = 0;
  void SwitchFullScreen() { ++fullScreen; }
  Bookmarks & GetBookmarkManager() { return bookmarks; }
  place_page::Info BuildPlacePageInfo(place_page::BuildInfo const &) { return nextInfo; }
  void DeactivateMapSelection() { ++deactivated; }
  void DeactivateHotelSearchMark() {}
  void ActivateMapSelection() { ++shown; }
  void OnTapEvent(place_page::BuildInfo const & buildInfo);
};

// The runner inserts the exact shipping function body here, without rewriting it.
// MUKSHAT_ACTUAL_ON_TAP_FUNCTION

int checks = 0;
void Check(bool value, char const * message)
{
  ++checks;
  if (!value)
  {
    std::cerr << message << '\n';
    std::exit(1);
  }
}
int main()
{
  using Source = place_page::BuildInfo::Source;
  for (auto source : {Source::User, Source::Search, Source::Other})
    for (bool active : {false, true})
      for (bool ruler : {false, true})
        for (bool routePoint : {false, true})
          for (bool bookmark : {false, true})
          {
            Framework fm;
            fm.m_routingManager.active = active;
            fm.m_routingManager.type = ruler ? routing::RouterType::Ruler : routing::RouterType::Vehicle;
            fm.nextInfo.routePoint = routePoint;
            fm.nextInfo.bookmark = bookmark;
            place_page::BuildInfo info;
            info.m_source = source;
            info.m_userMarkId = 7;  // An API point, as created by a saved-history map request.
            fm.OnTapEvent(info);
            bool extends = active && ruler && !routePoint;
#if defined(MUKSHAT_LEGACY_SDK_ABI)
            extends = extends && source == Source::User;
#endif
            Check(fm.m_routingManager.points.size() == (extends ? 3 : 2), "Unexpected route-point mutation");
            Check(fm.m_routingManager.points[1].x == 47.0 && fm.m_routingManager.points[1].y == 24.0,
                  "Existing destination changed");
            Check(fm.m_routingManager.built == (extends ? 1 : 0), "Unexpected route rebuild");
            Check(fm.m_routingManager.removed == (extends ? 1 : 0), "Unexpected route removal");
            Check(fm.shown == (extends ? 0 : 1), "Browse request did not activate its place card");
            Check(fm.m_currentPlacePageInfo.has_value() == !extends, "Selected place state missing");
            if (extends)
              Check(fm.m_routingManager.points.back().x == (bookmark ? 48.0 : 47.1),
                    "Explicit tap lost original bookmark/tap coordinates");
          }
  Framework alt;
  place_page::BuildInfo altTap;
  altTap.m_source = Source::User;
  altTap.m_userMarkId = 99;
  alt.OnTapEvent(altTap);
  Check(alt.m_routingManager.swapped == 1 && alt.m_routingManager.points.size() == 2,
        "Alternative-route selection changed");
  Framework longTap;
  place_page::BuildInfo longInfo;
  longInfo.m_isLongTap = true;
  longTap.OnTapEvent(longInfo);
  Check(longTap.fullScreen == 1 && longTap.m_routingManager.points.size() == 2, "Long tap behavior changed");
  std::cout << "PASS " << checks << " actual OnTapEvent browse/route preservation assertions\n";
}
