#ifndef RUNNER_SCREENSHOT_GEOMETRY_H_
#define RUNNER_SCREENSHOT_GEOMETRY_H_

#include <algorithm>

namespace pythia {

struct ScreenPoint {
  int x;
  int y;
};

struct ScreenRect {
  int left;
  int top;
  int right;
  int bottom;

  int width() const { return right - left; }
  int height() const { return bottom - top; }
  bool is_usable() const { return width() >= 4 && height() >= 4; }
};

inline ScreenRect NormalizeSelection(ScreenPoint first, ScreenPoint second) {
  return {
      std::min(first.x, second.x),
      std::min(first.y, second.y),
      std::max(first.x, second.x),
      std::max(first.y, second.y),
  };
}

}  // namespace pythia

#endif  // RUNNER_SCREENSHOT_GEOMETRY_H_
