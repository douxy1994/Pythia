#include <cassert>

#include "../../windows/runner/screenshot_geometry.h"

int main() {
  const auto forward =
      pythia::NormalizeSelection({10, 20}, {210, 120});
  assert(forward.left == 10);
  assert(forward.top == 20);
  assert(forward.width() == 200);
  assert(forward.height() == 100);
  assert(forward.is_usable());

  const auto reverse =
      pythia::NormalizeSelection({210, 120}, {10, 20});
  assert(reverse.left == forward.left);
  assert(reverse.top == forward.top);
  assert(reverse.right == forward.right);
  assert(reverse.bottom == forward.bottom);

  const auto tiny = pythia::NormalizeSelection({1, 1}, {3, 3});
  assert(!tiny.is_usable());
  return 0;
}
