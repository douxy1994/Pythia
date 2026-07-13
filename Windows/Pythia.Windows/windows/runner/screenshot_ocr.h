#ifndef RUNNER_SCREENSHOT_OCR_H_
#define RUNNER_SCREENSHOT_OCR_H_

#include <windows.h>

#include <string>

struct ScreenshotOcrResult {
  std::string text;
  std::string error_code;
  std::string error_message;

  bool succeeded() const { return error_code.empty(); }
};

ScreenshotOcrResult CaptureSelectionAndRecognize(HWND owner);

#endif  // RUNNER_SCREENSHOT_OCR_H_
