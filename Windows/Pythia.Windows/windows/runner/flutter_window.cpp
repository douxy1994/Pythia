#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "pythia_credential_channel.h"
#include "pythia_platform_channel.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() = default;

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterPythiaCredentialChannel(flutter_controller_->engine()->messenger());
  RegisterPythiaPlatformChannel(flutter_controller_->engine()->messenger(),
                                GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}
