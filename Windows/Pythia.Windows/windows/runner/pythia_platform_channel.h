#ifndef RUNNER_PYTHIA_PLATFORM_CHANNEL_H_
#define RUNNER_PYTHIA_PLATFORM_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterPythiaPlatformChannel(flutter::BinaryMessenger* messenger,
                                   HWND window);

#endif  // RUNNER_PYTHIA_PLATFORM_CHANNEL_H_
