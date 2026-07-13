#ifndef RUNNER_TRAY_ACTION_MAP_H_
#define RUNNER_TRAY_ACTION_MAP_H_

namespace pythia {

constexpr unsigned int kTrayCommandShow = 1001;
constexpr unsigned int kTrayCommandInputTranslate = 1002;
constexpr unsigned int kTrayCommandHistory = 1003;
constexpr unsigned int kTrayCommandSyncHistory = 1004;
constexpr unsigned int kTrayCommandSettings = 1005;
constexpr unsigned int kTrayCommandQuit = 1006;

inline const char* TrayActionForCommand(unsigned int command) {
  switch (command) {
    case kTrayCommandInputTranslate:
      return "translate.input";
    case kTrayCommandHistory:
      return "history.open";
    case kTrayCommandSyncHistory:
      return "history.sync";
    case kTrayCommandSettings:
      return "settings.open";
    case kTrayCommandQuit:
      return "app.quitRequested";
    default:
      return nullptr;
  }
}

}  // namespace pythia

#endif  // RUNNER_TRAY_ACTION_MAP_H_
