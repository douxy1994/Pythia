#include "utils.h"

#include <windows.h>
#include <shellapi.h>

#include <io.h>
#include <fcntl.h>

#include <cstdio>
#include <iostream>
#include <string>
#include <vector>

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                        static_cast<int>(value.size()),
                                        nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  return result;
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE* unused;
    freopen_s(&unused, "CONOUT$", "w", stdout);
    freopen_s(&unused, "CONOUT$", "w", stderr);
    freopen_s(&unused, "CONIN$", "r", stdin);
    std::ios::sync_with_stdio();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  int argc = 0;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  std::vector<std::string> arguments;
  if (argv != nullptr) {
    for (int i = 1; i < argc; ++i) {
      arguments.push_back(WideToUtf8(argv[i]));
    }
    ::LocalFree(argv);
  }
  return arguments;
}
