#include "pythia_platform_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <softpub.h>
#include <wintrust.h>
#include <uiautomation.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <cctype>
#include <map>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "tray_action_map.h"
#include "screenshot_ocr.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;
using flutter::StandardMethodCodec;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kPythiaSettingsKey[] = L"Software\\Pythia";
constexpr wchar_t kPythiaValueName[] = L"Pythia";
constexpr wchar_t kWindowPlacementValueName[] = L"WindowPlacement";
constexpr UINT_PTR kTrayIconId = 1;
constexpr UINT kTrayCallbackMessage = WM_APP + 0x504;
constexpr int kHotKeyBaseId = 0x5040;

HWND g_window = nullptr;
WNDPROC g_original_wnd_proc = nullptr;
bool g_close_to_tray = false;
bool g_hide_on_blur = false;
bool g_tray_installed = false;
bool g_tray_menu_open = false;
int g_next_hotkey_id = kHotKeyBaseId;
std::map<int, std::string> g_hotkey_actions;
MethodChannel<EncodableValue>* g_platform_channel = nullptr;

void ShowPythiaWindow(HWND window) {
  if (window == nullptr) {
    return;
  }
  ::ShowWindow(window, SW_SHOWNORMAL);
  ::SetForegroundWindow(window);
}

void RemoveTrayIcon() {
  if (!g_tray_installed || g_window == nullptr) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = g_window;
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  g_tray_installed = false;
}

void ShowTrayMenu(HWND window) {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandShow,
                L"\u663e\u793a Pythia");
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandInputTranslate,
                L"\u5feb\u901f\u7ffb\u8bd1");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandHistory,
                L"\u5386\u53f2\u8bb0\u5f55");
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandSyncHistory,
                L"\u540c\u6b65\u5386\u53f2");
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandSettings,
                L"\u8bbe\u7f6e");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, pythia::kTrayCommandQuit,
                L"\u9000\u51fa Pythia");

  POINT cursor;
  ::GetCursorPos(&cursor);
  ::SetForegroundWindow(window);
  g_tray_menu_open = true;
  const UINT command = ::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x, cursor.y,
      0, window, nullptr);
  g_tray_menu_open = false;
  ::DestroyMenu(menu);

  if (command == pythia::kTrayCommandShow) {
    ShowPythiaWindow(window);
  } else if (const char* action = pythia::TrayActionForCommand(command);
             action != nullptr && g_platform_channel != nullptr) {
    if (command != pythia::kTrayCommandSyncHistory &&
        command != pythia::kTrayCommandQuit) {
      ShowPythiaWindow(window);
    }
    auto arguments = std::make_unique<EncodableValue>(std::string(action));
    g_platform_channel->InvokeMethod("tray.action", std::move(arguments));
  }
}

LRESULT CALLBACK PlatformWindowProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  if (message == WM_HOTKEY) {
    const int hotkey_id = static_cast<int>(wparam);
    const auto found = g_hotkey_actions.find(hotkey_id);
    if (found != g_hotkey_actions.end() && g_platform_channel != nullptr) {
      auto arguments = std::make_unique<EncodableValue>(found->second);
      g_platform_channel->InvokeMethod("hotkey.triggered", std::move(arguments));
    }
    return 0;
  }
  if (message == kTrayCallbackMessage) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowPythiaWindow(window);
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu(window);
    }
    return 0;
  }
  if (message == WM_CLOSE && g_close_to_tray) {
    ::ShowWindow(window, SW_HIDE);
    return 0;
  }
  if (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE &&
      g_hide_on_blur && !g_tray_menu_open) {
    ::ShowWindow(window, SW_HIDE);
  }
  if (message == WM_DESTROY) {
    RemoveTrayIcon();
  }
  if (g_original_wnd_proc != nullptr) {
    return ::CallWindowProcW(g_original_wnd_proc, window, message, wparam,
                             lparam);
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

void EnsureWindowSubclass(HWND window) {
  if (window == nullptr || g_original_wnd_proc != nullptr) {
    return;
  }
  g_window = window;
  g_original_wnd_proc = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtrW(window, GWLP_WNDPROC,
                          reinterpret_cast<LONG_PTR>(PlatformWindowProc)));
}

std::optional<bool> BoolArg(const EncodableValue* args, const char* name) {
  if (args == nullptr) {
    return std::nullopt;
  }
  const auto* map = std::get_if<EncodableMap>(args);
  if (map == nullptr) {
    return std::nullopt;
  }
  const auto found = map->find(EncodableValue(name));
  if (found == map->end()) {
    return std::nullopt;
  }
  return std::get<bool>(found->second);
}

std::optional<std::string> StringArg(const EncodableValue* args,
                                     const char* name) {
  if (args == nullptr) {
    return std::nullopt;
  }
  const auto* map = std::get_if<EncodableMap>(args);
  if (map == nullptr) {
    return std::nullopt;
  }
  const auto found = map->find(EncodableValue(name));
  if (found == map->end()) {
    return std::nullopt;
  }
  const auto* value = std::get_if<std::string>(&found->second);
  if (value == nullptr) {
    return std::nullopt;
  }
  return *value;
}

std::string Lower(std::string value) {
  for (char& c : value) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return value;
}

std::vector<std::string> SplitAccelerator(const std::string& accelerator) {
  std::vector<std::string> parts;
  std::stringstream stream(accelerator);
  std::string part;
  while (std::getline(stream, part, '+')) {
    const auto begin = part.find_first_not_of(" \t\r\n");
    const auto end = part.find_last_not_of(" \t\r\n");
    if (begin != std::string::npos && end != std::string::npos) {
      parts.push_back(Lower(part.substr(begin, end - begin + 1)));
    }
  }
  return parts;
}

std::optional<UINT> VirtualKeyForToken(const std::string& token) {
  if (token.size() == 1) {
    const char c = token[0];
    if (c >= 'a' && c <= 'z') {
      return static_cast<UINT>('A' + (c - 'a'));
    }
    if (c >= '0' && c <= '9') {
      return static_cast<UINT>(c);
    }
  }
  if (token.size() >= 2 && token[0] == 'f') {
    const int number = std::atoi(token.c_str() + 1);
    if (number >= 1 && number <= 24) {
      return static_cast<UINT>(VK_F1 + number - 1);
    }
  }
  if (token == "space") return VK_SPACE;
  if (token == "tab") return VK_TAB;
  if (token == "enter" || token == "return") return VK_RETURN;
  if (token == "esc" || token == "escape") return VK_ESCAPE;
  if (token == "left") return VK_LEFT;
  if (token == "right") return VK_RIGHT;
  if (token == "up") return VK_UP;
  if (token == "down") return VK_DOWN;
  return std::nullopt;
}

std::optional<std::pair<UINT, UINT>> ParseAccelerator(
    const std::string& accelerator) {
  UINT modifiers = MOD_NOREPEAT;
  std::optional<UINT> virtual_key;
  for (const auto& token : SplitAccelerator(accelerator)) {
    if (token == "ctrl" || token == "control") {
      modifiers |= MOD_CONTROL;
    } else if (token == "alt" || token == "option") {
      modifiers |= MOD_ALT;
    } else if (token == "shift") {
      modifiers |= MOD_SHIFT;
    } else if (token == "win" || token == "super" || token == "meta") {
      modifiers |= MOD_WIN;
    } else {
      virtual_key = VirtualKeyForToken(token);
    }
  }
  if (!virtual_key.has_value()) {
    return std::nullopt;
  }
  return std::make_pair(modifiers, *virtual_key);
}

std::wstring ExePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD size = ::GetModuleFileNameW(nullptr, buffer.data(),
                                    static_cast<DWORD>(buffer.size()));
  while (size == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    size = ::GetModuleFileNameW(nullptr, buffer.data(),
                                static_cast<DWORD>(buffer.size()));
  }
  buffer.resize(size);
  return buffer;
}

std::optional<std::wstring> ReadClipboardText() {
  if (!::OpenClipboard(nullptr)) {
    return std::nullopt;
  }
  std::optional<std::wstring> text;
  HANDLE handle = ::GetClipboardData(CF_UNICODETEXT);
  if (handle != nullptr) {
    const auto* data = static_cast<const wchar_t*>(::GlobalLock(handle));
    if (data != nullptr) {
      text = std::wstring(data);
      ::GlobalUnlock(handle);
    }
  }
  ::CloseClipboard();
  return text;
}

bool SetClipboardText(const std::wstring& text) {
  if (!::OpenClipboard(nullptr)) {
    return false;
  }
  ::EmptyClipboard();
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (handle == nullptr) {
    ::CloseClipboard();
    return false;
  }
  void* data = ::GlobalLock(handle);
  if (data == nullptr) {
    ::GlobalFree(handle);
    ::CloseClipboard();
    return false;
  }
  memcpy(data, text.c_str(), bytes);
  ::GlobalUnlock(handle);
  ::SetClipboardData(CF_UNICODETEXT, handle);
  ::CloseClipboard();
  return true;
}

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

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}

void LaunchUpdateInstaller(
    HWND window, const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto path_argument = StringArg(call.arguments(), "path");
  if (!path_argument.has_value()) {
    result->Error("invalid_args", "Missing update installer path.");
    return;
  }
  const std::wstring path = Utf8ToWide(*path_argument);
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (path.empty() || attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    result->Error("installer_missing", "Update installer file is missing.");
    return;
  }
  std::wstring lower_path = path;
  std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(),
                 [](wchar_t character) { return std::towlower(character); });
  const auto has_suffix = [&lower_path](const wchar_t* suffix) {
    const std::wstring value(suffix);
    return lower_path.size() >= value.size() &&
           lower_path.compare(lower_path.size() - value.size(), value.size(),
                              value) == 0;
  };
  const bool supported_extension = has_suffix(L".exe") || has_suffix(L".msix");
  const bool expected_name = lower_path.find(L"pythia") != std::wstring::npos &&
                             lower_path.find(L"windows") != std::wstring::npos &&
                             lower_path.find(L"x64") != std::wstring::npos;
  if (!supported_extension || !expected_name) {
    result->Error("installer_invalid",
                  "Only Pythia Windows x64 EXE/MSIX installers are allowed.");
    return;
  }
  WINTRUST_FILE_INFO file_info = {};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = path.c_str();
  GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  WINTRUST_DATA trust_data = {};
  trust_data.cbStruct = sizeof(trust_data);
  trust_data.dwUIChoice = WTD_UI_NONE;
  trust_data.fdwRevocationChecks = WTD_REVOKE_NONE;
  trust_data.dwUnionChoice = WTD_CHOICE_FILE;
  trust_data.pFile = &file_info;
  trust_data.dwStateAction = WTD_STATEACTION_VERIFY;
  trust_data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
  const LONG trust_status = ::WinVerifyTrust(nullptr, &policy, &trust_data);
  trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
  ::WinVerifyTrust(nullptr, &policy, &trust_data);
  if (trust_status != ERROR_SUCCESS) {
    result->Error("installer_signature_invalid",
                  "The update installer does not have a valid Authenticode signature.");
    return;
  }
  const auto launched = reinterpret_cast<INT_PTR>(::ShellExecuteW(
      window, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  if (launched <= 32) {
    result->Error("installer_launch_failed",
                  "Windows could not launch the update installer.");
    return;
  }
  result->Success();
  g_close_to_tray = false;
  RemoveTrayIcon();
  ::PostMessageW(window, WM_CLOSE, 0, 0);
}

void SendCopyShortcut() {
  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'C';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'C';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  ::SendInput(4, inputs, sizeof(INPUT));
}

std::optional<std::wstring> ReadSelectedTextWithUiAutomation() {
  IUIAutomation* automation = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_CUIAutomation, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&automation)))) {
    return std::nullopt;
  }

  IUIAutomationElement* focused = nullptr;
  HRESULT status = automation->GetFocusedElement(&focused);
  automation->Release();
  if (FAILED(status) || focused == nullptr) {
    return std::nullopt;
  }

  IUIAutomationTextPattern* pattern = nullptr;
  status = focused->GetCurrentPatternAs(UIA_TextPatternId,
                                        IID_PPV_ARGS(&pattern));
  focused->Release();
  if (FAILED(status) || pattern == nullptr) {
    return std::nullopt;
  }

  IUIAutomationTextRangeArray* ranges = nullptr;
  status = pattern->GetSelection(&ranges);
  pattern->Release();
  if (FAILED(status) || ranges == nullptr) {
    return std::nullopt;
  }

  int length = 0;
  ranges->get_Length(&length);
  std::wstring selected;
  for (int index = 0; index < length; ++index) {
    IUIAutomationTextRange* range = nullptr;
    if (FAILED(ranges->GetElement(index, &range)) || range == nullptr) {
      continue;
    }
    BSTR text = nullptr;
    if (SUCCEEDED(range->GetText(-1, &text)) && text != nullptr) {
      if (!selected.empty() && ::SysStringLen(text) > 0) {
        selected.push_back(L'\n');
      }
      selected.append(text, ::SysStringLen(text));
      ::SysFreeString(text);
    }
    range->Release();
  }
  ranges->Release();

  const auto first = std::find_if_not(selected.begin(), selected.end(),
                                      [](wchar_t value) {
                                        return std::iswspace(value) != 0;
                                      });
  const auto last = std::find_if_not(selected.rbegin(), selected.rend(),
                                     [](wchar_t value) {
                                       return std::iswspace(value) != 0;
                                     })
                        .base();
  if (first >= last) return std::nullopt;
  return std::wstring(first, last);
}

void ReadSelectedText(std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto automation_text = ReadSelectedTextWithUiAutomation();
  if (automation_text.has_value()) {
    result->Success(EncodableValue(WideToUtf8(*automation_text)));
    return;
  }

  const auto before = ReadClipboardText();
  const DWORD sequence_before = ::GetClipboardSequenceNumber();
  SendCopyShortcut();
  bool clipboard_changed = false;
  for (int attempt = 0; attempt < 10; ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(40));
    if (::GetClipboardSequenceNumber() != sequence_before) {
      clipboard_changed = true;
      break;
    }
  }
  const auto selected = ReadClipboardText();
  if (before.has_value()) {
    SetClipboardText(*before);
  }
  if (!clipboard_changed || !selected.has_value() || selected->empty()) {
    result->Error(
        "selection_unavailable",
        "The focused app exposed no UI Automation selection and did not copy selected text.");
    return;
  }
  result->Success(EncodableValue(WideToUtf8(*selected)));
}

void SetLaunchAtStartup(bool enabled,
                        std::unique_ptr<MethodResult<EncodableValue>> result) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    result->Error("startup_key", "Unable to open Windows Run registry key.");
    return;
  }
  LONG status = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring command = L"\"" + ExePath() + L"\"";
    status = ::RegSetValueExW(
        key, kPythiaValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = ::RegDeleteValueW(key, kPythiaValueName);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  ::RegCloseKey(key);
  if (status != ERROR_SUCCESS) {
    result->Error("startup_write", "Unable to update startup registration.");
    return;
  }
  result->Success();
}

void SetAlwaysOnTop(HWND window, bool enabled,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  const HWND insert_after = enabled ? HWND_TOPMOST : HWND_NOTOPMOST;
  if (!::SetWindowPos(window, insert_after, 0, 0, 0, 0,
                      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)) {
    result->Error("topmost_failed", "Unable to update always-on-top state.");
    return;
  }
  result->Success();
}

bool EnsurePlacementVisible(WINDOWPLACEMENT* placement) {
  if (placement == nullptr) {
    return false;
  }
  RECT rect = placement->rcNormalPosition;
  if (::MonitorFromRect(&rect, MONITOR_DEFAULTTONULL) != nullptr) {
    return true;
  }

  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!::GetMonitorInfoW(::MonitorFromWindow(nullptr, MONITOR_DEFAULTTOPRIMARY),
                         &monitor_info)) {
    return false;
  }

  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  const RECT work = monitor_info.rcWork;
  placement->rcNormalPosition.left = work.left + 80;
  placement->rcNormalPosition.top = work.top + 80;
  placement->rcNormalPosition.right =
      placement->rcNormalPosition.left + std::max<LONG>(width, 800);
  placement->rcNormalPosition.bottom =
      placement->rcNormalPosition.top + std::max<LONG>(height, 520);
  placement->showCmd = SW_SHOWNORMAL;
  return true;
}

void SaveWindowPlacement(HWND window,
                         std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!::GetWindowPlacement(window, &placement)) {
    result->Error("placement_read_failed", "Unable to read window placement.");
    return;
  }

  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kPythiaSettingsKey, 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    result->Error("placement_key_failed",
                  "Unable to open Pythia window placement registry key.");
    return;
  }
  const LONG status = ::RegSetValueExW(
      key, kWindowPlacementValueName, 0, REG_BINARY,
      reinterpret_cast<const BYTE*>(&placement), sizeof(WINDOWPLACEMENT));
  ::RegCloseKey(key);
  if (status != ERROR_SUCCESS) {
    result->Error("placement_write_failed",
                  "Unable to save Pythia window placement.");
    return;
  }
  result->Success();
}

void RestoreWindowPlacement(
    HWND window,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }

  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kPythiaSettingsKey, 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    result->Success();
    return;
  }

  WINDOWPLACEMENT placement = {};
  DWORD type = REG_BINARY;
  DWORD size = sizeof(WINDOWPLACEMENT);
  const LONG status = ::RegQueryValueExW(
      key, kWindowPlacementValueName, nullptr, &type,
      reinterpret_cast<BYTE*>(&placement), &size);
  ::RegCloseKey(key);

  if (status == ERROR_FILE_NOT_FOUND) {
    result->Success();
    return;
  }
  if (status != ERROR_SUCCESS || type != REG_BINARY ||
      size != sizeof(WINDOWPLACEMENT)) {
    result->Error("placement_invalid",
                  "Saved Pythia window placement is invalid.");
    return;
  }

  placement.length = sizeof(WINDOWPLACEMENT);
  if (!EnsurePlacementVisible(&placement) ||
      !::SetWindowPlacement(window, &placement)) {
    result->Error("placement_restore_failed",
                  "Unable to restore Pythia window placement.");
    return;
  }
  ShowPythiaWindow(window);
  result->Success();
}

void SetCloseToTray(HWND window, bool enabled,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  EnsureWindowSubclass(window);
  g_close_to_tray = enabled;
  result->Success();
}

void SetHideOnBlur(HWND window, bool enabled,
                   std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  EnsureWindowSubclass(window);
  g_hide_on_blur = enabled;
  result->Success();
}

void InstallTray(HWND window,
                 std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  EnsureWindowSubclass(window);

  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = window;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
  if (data.hIcon == nullptr) {
    data.hIcon = ::LoadIconW(nullptr, IDI_APPLICATION);
  }
  wcscpy_s(data.szTip, L"Pythia");

  const DWORD action = g_tray_installed ? NIM_MODIFY : NIM_ADD;
  if (!::Shell_NotifyIconW(action, &data)) {
    result->Error("tray_install_failed", "Unable to install Pythia tray icon.");
    return;
  }
  g_tray_installed = true;

  data.uVersion = NOTIFYICON_VERSION_4;
  ::Shell_NotifyIconW(NIM_SETVERSION, &data);
  result->Success();
}

void ShowSystemNotification(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (!g_tray_installed || g_window == nullptr) {
    result->Error("tray_missing",
                  "Pythia tray icon must be installed before notifications.");
    return;
  }
  const auto title = StringArg(call.arguments(), "title");
  const auto body = StringArg(call.arguments(), "body");
  const auto level = StringArg(call.arguments(), "level");
  if (!title.has_value() || title->empty() || !body.has_value() ||
      body->empty()) {
    result->Error("invalid_args", "Notification title and body are required.");
    return;
  }

  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = g_window;
  data.uID = kTrayIconId;
  data.uFlags = NIF_INFO;
  const std::wstring wide_title = Utf8ToWide(*title);
  const std::wstring wide_body = Utf8ToWide(*body);
  wcsncpy_s(data.szInfoTitle, _countof(data.szInfoTitle), wide_title.c_str(),
            _TRUNCATE);
  wcsncpy_s(data.szInfo, _countof(data.szInfo), wide_body.c_str(), _TRUNCATE);
  data.dwInfoFlags = level.has_value() && *level == "error" ? NIIF_ERROR
                                                              : NIIF_INFO;

  if (!::Shell_NotifyIconW(NIM_MODIFY, &data)) {
    result->Error("notification_failed",
                  "Windows could not display the Pythia notification.");
    return;
  }
  result->Success();
}

void RegisterHotKeyAction(
    HWND window,
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (window == nullptr) {
    result->Error("window_missing", "Pythia window handle is not available.");
    return;
  }
  const auto action = StringArg(call.arguments(), "action");
  const auto accelerator = StringArg(call.arguments(), "accelerator");
  if (!action.has_value() || action->empty() ||
      !accelerator.has_value() || accelerator->empty()) {
    result->Error("invalid_args", "Missing hotkey action or accelerator.");
    return;
  }
  const auto parsed = ParseAccelerator(*accelerator);
  if (!parsed.has_value()) {
    result->Error("invalid_hotkey", "Unsupported hotkey accelerator.");
    return;
  }

  EnsureWindowSubclass(window);
  const int id = g_next_hotkey_id++;
  if (!::RegisterHotKey(window, id, parsed->first, parsed->second)) {
    result->Error("hotkey_register_failed",
                  "Unable to register Windows global hotkey.");
    return;
  }
  g_hotkey_actions[id] = *action;
  result->Success();
}

void UnregisterAllHotKeys(HWND window,
                          std::unique_ptr<MethodResult<EncodableValue>> result) {
  for (const auto& entry : g_hotkey_actions) {
    ::UnregisterHotKey(window, entry.first);
  }
  g_hotkey_actions.clear();
  result->Success();
}

}  // namespace

void RegisterPythiaPlatformChannel(flutter::BinaryMessenger* messenger,
                                   HWND window) {
  EnsureWindowSubclass(window);

  auto channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, "pythia/windows_platform",
      &StandardMethodCodec::GetInstance());
  g_platform_channel = channel.get();

  channel->SetMethodCallHandler(
      [window](const MethodCall<EncodableValue>& call,
               std::unique_ptr<MethodResult<EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "selection.readText") {
          ReadSelectedText(std::move(result));
        } else if (method == "window.show") {
          ShowPythiaWindow(window);
          result->Success();
        } else if (method == "window.setAlwaysOnTop") {
          const auto enabled = BoolArg(call.arguments(), "enabled");
          if (!enabled.has_value()) {
            result->Error("invalid_args", "Missing enabled flag.");
            return;
          }
          SetAlwaysOnTop(window, *enabled, std::move(result));
        } else if (method == "startup.setLaunchAtStartup") {
          const auto enabled = BoolArg(call.arguments(), "enabled");
          if (!enabled.has_value()) {
            result->Error("invalid_args", "Missing enabled flag.");
            return;
          }
          SetLaunchAtStartup(*enabled, std::move(result));
        } else if (method == "window.setCloseToTray") {
          const auto enabled = BoolArg(call.arguments(), "enabled");
          if (!enabled.has_value()) {
            result->Error("invalid_args", "Missing enabled flag.");
            return;
          }
          SetCloseToTray(window, *enabled, std::move(result));
        } else if (method == "window.setHideOnBlur") {
          const auto enabled = BoolArg(call.arguments(), "enabled");
          if (!enabled.has_value()) {
            result->Error("invalid_args", "Missing enabled flag.");
            return;
          }
          SetHideOnBlur(window, *enabled, std::move(result));
        } else if (method == "tray.install" ||
                   method == "tray.updateMenu") {
          InstallTray(window, std::move(result));
        } else if (method == "notification.show") {
          ShowSystemNotification(call, std::move(result));
        } else if (method == "app.quit") {
          g_close_to_tray = false;
          RemoveTrayIcon();
          result->Success();
          ::PostMessageW(window, WM_CLOSE, 0, 0);
        } else if (method == "hotkey.register") {
          RegisterHotKeyAction(window, call, std::move(result));
        } else if (method == "hotkey.unregisterAll") {
          UnregisterAllHotKeys(window, std::move(result));
        } else if (method == "window.restorePlacement") {
          RestoreWindowPlacement(window, std::move(result));
        } else if (method == "window.savePlacement") {
          SaveWindowPlacement(window, std::move(result));
        } else if (method == "screenshot.captureAndRecognize") {
          const auto ocr = CaptureSelectionAndRecognize(window);
          if (ocr.succeeded()) {
            result->Success(EncodableValue(ocr.text));
          } else {
            result->Error(ocr.error_code, ocr.error_message);
          }
        } else if (method == "update.launchInstaller") {
          LaunchUpdateInstaller(window, call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });

  static std::unique_ptr<MethodChannel<EncodableValue>> retained_channel;
  retained_channel = std::move(channel);
}
