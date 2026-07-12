#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/pythia-tray-action-map-test"
GEOMETRY_OUTPUT="${TMPDIR:-/tmp}/pythia-screenshot-geometry-test"

clang++ -std=c++17 "$ROOT/test/native/tray_action_map_test.cpp" -o "$OUTPUT"
"$OUTPUT"

clang++ -std=c++17 "$ROOT/test/native/screenshot_geometry_test.cpp" -o "$GEOMETRY_OUTPUT"
"$GEOMETRY_OUTPUT"

cmake -P "$ROOT/test/native/x64_guard_accepts_x64.cmake"
if cmake -P "$ROOT/test/native/x64_guard_rejects_win32.cmake" >/dev/null 2>&1; then
  echo "Expected the Pythia x64 guard to reject Win32." >&2
  exit 1
fi

grep -F 'CaptureSelectionAndRecognize(window)' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'UIA_TextPatternId' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'GetSelection' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'Uiautomationcore' \
  "$ROOT/windows/runner/CMakeLists.txt" >/dev/null
grep -F 'set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)' \
  "$ROOT/windows/flutter/CMakeLists.txt" >/dev/null
grep -F 'set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)' \
  "$ROOT/windows/flutter/CMakeLists.txt" >/dev/null
grep -F 'set(AOT_LIBRARY "${PROJECT_DIR}/build/windows/app.so" PARENT_SCOPE)' \
  "$ROOT/windows/flutter/CMakeLists.txt" >/dev/null
grep -F 'add_subdirectory("runner")' \
  "$ROOT/windows/CMakeLists.txt" >/dev/null
grep -F 'install(FILES "${AOT_LIBRARY}"' \
  "$ROOT/windows/CMakeLists.txt" >/dev/null
grep -F '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS' \
  "$ROOT/windows/runner/CMakeLists.txt" >/dev/null
grep -F '#include <winrt/Windows.Foundation.Collections.h>' \
  "$ROOT/windows/runner/screenshot_ocr.cpp" >/dev/null
if grep -F 'ocr_not_implemented' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null; then
  echo "Screenshot OCR channel still contains the unsupported placeholder." >&2
  exit 1
fi

grep -F 'method == "update.launchInstaller"' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'Only Pythia Windows x64 EXE/MSIX installers are allowed.' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'WinVerifyTrust' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'method == "notification.show"' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'method == "app.quit"' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F 'Shell_NotifyIconW(NIM_MODIFY, &data)' \
  "$ROOT/windows/runner/pythia_platform_channel.cpp" >/dev/null
grep -F '$checksum = "$installer.sha256"' \
  "$ROOT/tool/build_windows_installer.ps1" >/dev/null

echo "Pythia native contracts passed (tray actions, notifications, screenshot geometry, updater, and Windows x64 guard)."
