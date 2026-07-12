#include "screenshot_ocr.h"

#include <windows.h>
#include <windowsx.h>
#include <windows.graphics.imaging.h>
#include <windows.media.ocr.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <future>
#include <string>
#include <utility>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/base.h>

#include "screenshot_geometry.h"

namespace {

struct __declspec(uuid("5B0D3235-4DBA-4D44-865F-BC92D3E5BF87"))
    IMemoryBufferByteAccess : IUnknown {
  virtual HRESULT __stdcall GetBuffer(uint8_t** value,
                                      uint32_t* capacity) = 0;
};

struct PixelBuffer {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> bgra;
};

struct SelectionState {
  int virtual_left = 0;
  int virtual_top = 0;
  bool dragging = false;
  bool done = false;
  bool cancelled = false;
  pythia::ScreenPoint anchor = {};
  pythia::ScreenPoint cursor = {};
  HBITMAP desktop_bitmap = nullptr;
  int desktop_width = 0;
  int desktop_height = 0;
};

constexpr wchar_t kSelectionWindowClass[] = L"PythiaScreenshotSelection";

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = ::WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  std::string utf8(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), utf8.data(), size,
                        nullptr, nullptr);
  return utf8;
}

bool CapturePixels(const pythia::ScreenRect& rect, PixelBuffer* output) {
  if (output == nullptr || !rect.is_usable()) return false;
  HDC screen_dc = ::GetDC(nullptr);
  HDC memory_dc = ::CreateCompatibleDC(screen_dc);
  if (screen_dc == nullptr || memory_dc == nullptr) {
    if (memory_dc != nullptr) ::DeleteDC(memory_dc);
    if (screen_dc != nullptr) ::ReleaseDC(nullptr, screen_dc);
    return false;
  }

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = rect.width();
  info.bmiHeader.biHeight = -rect.height();
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap =
      ::CreateDIBSection(screen_dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (bitmap == nullptr || pixels == nullptr) {
    if (bitmap != nullptr) ::DeleteObject(bitmap);
    ::DeleteDC(memory_dc);
    ::ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ previous = ::SelectObject(memory_dc, bitmap);
  const BOOL copied = ::BitBlt(memory_dc, 0, 0, rect.width(), rect.height(),
                               screen_dc, rect.left, rect.top,
                               SRCCOPY | CAPTUREBLT);
  if (copied) {
    const size_t byte_count =
        static_cast<size_t>(rect.width()) * rect.height() * 4;
    output->width = rect.width();
    output->height = rect.height();
    output->bgra.assign(static_cast<uint8_t*>(pixels),
                        static_cast<uint8_t*>(pixels) + byte_count);
  }
  ::SelectObject(memory_dc, previous);
  ::DeleteObject(bitmap);
  ::DeleteDC(memory_dc);
  ::ReleaseDC(nullptr, screen_dc);
  return copied == TRUE;
}

HBITMAP CaptureDesktopBitmap(int left, int top, int width, int height) {
  HDC screen_dc = ::GetDC(nullptr);
  HDC memory_dc = ::CreateCompatibleDC(screen_dc);
  HBITMAP bitmap = ::CreateCompatibleBitmap(screen_dc, width, height);
  if (screen_dc == nullptr || memory_dc == nullptr || bitmap == nullptr) {
    if (bitmap != nullptr) ::DeleteObject(bitmap);
    if (memory_dc != nullptr) ::DeleteDC(memory_dc);
    if (screen_dc != nullptr) ::ReleaseDC(nullptr, screen_dc);
    return nullptr;
  }
  HGDIOBJ previous = ::SelectObject(memory_dc, bitmap);
  const BOOL copied = ::BitBlt(memory_dc, 0, 0, width, height, screen_dc, left,
                               top, SRCCOPY | CAPTUREBLT);
  ::SelectObject(memory_dc, previous);
  ::DeleteDC(memory_dc);
  ::ReleaseDC(nullptr, screen_dc);
  if (!copied) {
    ::DeleteObject(bitmap);
    return nullptr;
  }
  return bitmap;
}

SelectionState* StateFor(HWND window) {
  return reinterpret_cast<SelectionState*>(
      ::GetWindowLongPtrW(window, GWLP_USERDATA));
}

LRESULT CALLBACK SelectionWindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  SelectionState* state = StateFor(window);
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC dc = ::BeginPaint(window, &paint);
      if (state != nullptr && state->desktop_bitmap != nullptr) {
        HDC source_dc = ::CreateCompatibleDC(dc);
        HGDIOBJ previous =
            ::SelectObject(source_dc, state->desktop_bitmap);
        ::BitBlt(dc, 0, 0, state->desktop_width, state->desktop_height,
                 source_dc, 0, 0, SRCCOPY);
        ::SelectObject(source_dc, previous);
        ::DeleteDC(source_dc);
        if (state->dragging) {
          const auto rect =
              pythia::NormalizeSelection(state->anchor, state->cursor);
          HPEN pen = ::CreatePen(PS_SOLID, 3, RGB(128, 184, 71));
          HGDIOBJ old_pen = ::SelectObject(dc, pen);
          HGDIOBJ old_brush = ::SelectObject(dc, ::GetStockObject(NULL_BRUSH));
          ::Rectangle(dc, rect.left - state->virtual_left,
                      rect.top - state->virtual_top,
                      rect.right - state->virtual_left,
                      rect.bottom - state->virtual_top);
          ::SelectObject(dc, old_brush);
          ::SelectObject(dc, old_pen);
          ::DeleteObject(pen);
        }
      }
      ::EndPaint(window, &paint);
      return 0;
    }
    case WM_LBUTTONDOWN:
      if (state != nullptr) {
        state->dragging = true;
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ::ClientToScreen(window, &point);
        state->anchor = {point.x, point.y};
        state->cursor = state->anchor;
        ::SetCapture(window);
      }
      return 0;
    case WM_MOUSEMOVE:
      if (state != nullptr && state->dragging) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ::ClientToScreen(window, &point);
        state->cursor = {point.x, point.y};
        ::InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (state != nullptr && state->dragging) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ::ClientToScreen(window, &point);
        state->cursor = {point.x, point.y};
        state->dragging = false;
        state->done = true;
        ::ReleaseCapture();
        ::DestroyWindow(window);
      }
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE && state != nullptr) {
        state->cancelled = true;
        state->done = true;
        ::DestroyWindow(window);
        return 0;
      }
      break;
    case WM_RBUTTONDOWN:
      if (state != nullptr) {
        state->cancelled = true;
        state->done = true;
        ::DestroyWindow(window);
      }
      return 0;
    case WM_DESTROY:
      if (state != nullptr && !state->done) {
        state->cancelled = true;
        state->done = true;
      }
      return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

bool EnsureSelectionWindowClass() {
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = SelectionWindowProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.hCursor = ::LoadCursor(nullptr, IDC_CROSS);
  window_class.lpszClassName = kSelectionWindowClass;
  if (::RegisterClassExW(&window_class) != 0) return true;
  return ::GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::optional<pythia::ScreenRect> SelectScreenRegion(HWND owner,
                                                      bool* cancelled) {
  if (cancelled != nullptr) *cancelled = false;
  if (!EnsureSelectionWindowClass()) return std::nullopt;

  SelectionState state;
  state.virtual_left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  state.virtual_top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  state.desktop_width = ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  state.desktop_height = ::GetSystemMetrics(SM_CYVIRTUALSCREEN);

  ::ShowWindow(owner, SW_HIDE);
  ::Sleep(120);
  state.desktop_bitmap = CaptureDesktopBitmap(
      state.virtual_left, state.virtual_top, state.desktop_width,
      state.desktop_height);
  if (state.desktop_bitmap == nullptr) {
    ::ShowWindow(owner, SW_SHOWNORMAL);
    return std::nullopt;
  }

  HWND overlay = ::CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kSelectionWindowClass, L"Pythia OCR",
      WS_POPUP, state.virtual_left, state.virtual_top, state.desktop_width,
      state.desktop_height, nullptr, nullptr, ::GetModuleHandleW(nullptr),
      &state);
  if (overlay == nullptr) {
    ::DeleteObject(state.desktop_bitmap);
    ::ShowWindow(owner, SW_SHOWNORMAL);
    return std::nullopt;
  }
  ::ShowWindow(overlay, SW_SHOW);
  ::SetForegroundWindow(overlay);
  ::SetFocus(overlay);

  MSG message = {};
  while (!state.done && ::GetMessageW(&message, nullptr, 0, 0) > 0) {
    ::TranslateMessage(&message);
    ::DispatchMessageW(&message);
  }
  ::DeleteObject(state.desktop_bitmap);

  if (cancelled != nullptr) *cancelled = state.cancelled;
  if (state.cancelled) {
    ::ShowWindow(owner, SW_SHOWNORMAL);
    ::SetForegroundWindow(owner);
    return std::nullopt;
  }
  return pythia::NormalizeSelection(state.anchor, state.cursor);
}

ScreenshotOcrResult RecognizePixels(PixelBuffer pixels) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    using namespace winrt::Windows::Graphics::Imaging;
    using namespace winrt::Windows::Media::Ocr;

    SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8, pixels.width,
                          pixels.height, BitmapAlphaMode::Ignore);
    BitmapBuffer buffer = bitmap.LockBuffer(BitmapBufferAccessMode::Write);
    const auto plane = buffer.GetPlaneDescription(0);
    auto reference = buffer.CreateReference();
    uint8_t* destination = nullptr;
    uint32_t capacity = 0;
    winrt::check_hresult(reference.as<IMemoryBufferByteAccess>()->GetBuffer(
        &destination, &capacity));
    const size_t source_stride = static_cast<size_t>(pixels.width) * 4;
    for (int row = 0; row < pixels.height; ++row) {
      const size_t destination_offset =
          static_cast<size_t>(plane.StartIndex) +
          static_cast<size_t>(row) * plane.Stride;
      if (destination_offset + source_stride > capacity) {
        return {{}, "ocr_buffer", "Windows OCR pixel buffer is invalid."};
      }
      std::memcpy(destination + destination_offset,
                  pixels.bgra.data() + row * source_stride, source_stride);
    }

    OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
    if (engine == nullptr) {
      return {{}, "ocr_language_missing",
              "Install a Windows OCR language pack for the source text."};
    }
    const OcrResult result = engine.RecognizeAsync(bitmap).get();
    std::wstring text;
    for (const auto& line : result.Lines()) {
      if (!text.empty()) text.push_back(L'\n');
      text.append(line.Text().c_str());
    }
    if (text.empty()) {
      return {{}, "ocr_empty", "Windows OCR did not detect any text."};
    }
    return {WideToUtf8(text), {}, {}};
  } catch (const winrt::hresult_error& error) {
    return {{}, "ocr_failed", WideToUtf8(error.message().c_str())};
  } catch (...) {
    return {{}, "ocr_failed", "Windows OCR failed unexpectedly."};
  }
}

}  // namespace

ScreenshotOcrResult CaptureSelectionAndRecognize(HWND owner) {
  bool cancelled = false;
  const auto selection = SelectScreenRegion(owner, &cancelled);
  if (!selection.has_value()) {
    return {{}, cancelled ? "ocr_cancelled" : "capture_failed",
            cancelled ? "Screenshot selection was cancelled."
                      : "Unable to start screenshot selection."};
  }
  if (!selection->is_usable()) {
    ::ShowWindow(owner, SW_SHOWNORMAL);
    ::SetForegroundWindow(owner);
    return {{}, "selection_too_small",
            "Drag a larger region for screenshot OCR."};
  }
  PixelBuffer pixels;
  const bool captured = CapturePixels(*selection, &pixels);
  ::ShowWindow(owner, SW_SHOWNORMAL);
  ::SetForegroundWindow(owner);
  if (!captured) {
    return {{}, "capture_failed", "Unable to capture the selected region."};
  }
  return std::async(std::launch::async, RecognizePixels, std::move(pixels))
      .get();
}
