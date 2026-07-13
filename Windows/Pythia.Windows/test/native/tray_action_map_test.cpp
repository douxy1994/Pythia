#include <cassert>
#include <cstring>

#include "../../windows/runner/tray_action_map.h"

int main() {
  assert(std::strcmp(
             pythia::TrayActionForCommand(pythia::kTrayCommandInputTranslate),
             "translate.input") == 0);
  assert(std::strcmp(
             pythia::TrayActionForCommand(pythia::kTrayCommandSettings),
             "settings.open") == 0);
  assert(std::strcmp(
             pythia::TrayActionForCommand(pythia::kTrayCommandHistory),
             "history.open") == 0);
  assert(std::strcmp(
             pythia::TrayActionForCommand(pythia::kTrayCommandSyncHistory),
             "history.sync") == 0);
  assert(pythia::TrayActionForCommand(pythia::kTrayCommandShow) == nullptr);
  assert(std::strcmp(
             pythia::TrayActionForCommand(pythia::kTrayCommandQuit),
             "app.quitRequested") == 0);
  assert(pythia::TrayActionForCommand(9999) == nullptr);
  return 0;
}
