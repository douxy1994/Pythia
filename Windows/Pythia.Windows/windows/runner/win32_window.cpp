#include "win32_window.h"

#include <windowsx.h>

namespace {

constexpr wchar_t kWindowClassName[] = L"PYTHIA_WINDOW";

WNDCLASS RegisterWindowClass() {
  WNDCLASS window_class{};
  window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClassName;
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.cbClsExtra = 0;
  window_class.cbWndExtra = 0;
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.hIcon = nullptr;
  window_class.hbrBackground = nullptr;
  window_class.lpszMenuName = nullptr;
  window_class.lpfnWndProc = Win32Window::WndProc;
  ::RegisterClass(&window_class);
  return window_class;
}

}  // namespace

Win32Window::Win32Window() = default;

Win32Window::~Win32Window() {
  if (window_handle_) {
    ::DestroyWindow(window_handle_);
  }
}

bool Win32Window::Create(const std::wstring& title, const Point& origin,
                         const Size& size) {
  static WNDCLASS window_class = RegisterWindowClass();
  RECT frame = {static_cast<LONG>(origin.x), static_cast<LONG>(origin.y),
                static_cast<LONG>(origin.x + size.width),
                static_cast<LONG>(origin.y + size.height)};
  ::AdjustWindowRect(&frame, WS_OVERLAPPEDWINDOW, FALSE);
  window_handle_ = ::CreateWindow(
      window_class.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW,
      frame.left, frame.top, frame.right - frame.left, frame.bottom - frame.top,
      nullptr, nullptr, window_class.hInstance, this);
  return window_handle_ != nullptr;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  ::SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  ::SetWindowPos(content, nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  ::GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::Show() {
  ::ShowWindow(window_handle_, SW_SHOWNORMAL);
  ::UpdateWindow(window_handle_);
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {}

LRESULT Win32Window::MessageHandler(HWND window, UINT const message,
                                    WPARAM const wparam, LPARAM const lparam) {
  switch (message) {
    case WM_CREATE:
      window_handle_ = window;
      return OnCreate() ? 0 : -1;
    case WM_DESTROY:
      OnDestroy();
      if (quit_on_close_) {
        ::PostQuitMessage(0);
      }
      return 0;
    case WM_SIZE:
      if (child_content_) {
        RECT frame = GetClientArea();
        ::SetWindowPos(child_content_, nullptr, frame.left, frame.top,
                       frame.right - frame.left, frame.bottom - frame.top,
                       SWP_NOZORDER | SWP_NOACTIVATE);
      }
      return 0;
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));
  }
  if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      ::GetWindowLongPtr(window, GWLP_USERDATA));
}
