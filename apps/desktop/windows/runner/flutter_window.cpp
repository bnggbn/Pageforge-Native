#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  close_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "pageforge/window",
      &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  close_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Defer native destruction until Dart has saved or the user has cancelled.
  if (message == WM_CLOSE && close_channel_ && !close_allowed_) {
    if (!close_pending_) {
      close_pending_ = true;
      auto approve = [this, hwnd]() {
        close_pending_ = false;
        close_allowed_ = true;
        // Destroy on the next event, after the channel's reply callback returns.
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      };
      close_channel_->InvokeMethod(
          "requestClose", nullptr,
          std::make_unique<
              flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [this, approve](const flutter::EncodableValue* value) {
                const bool* allowed = value ? std::get_if<bool>(value) : nullptr;
                if (allowed && *allowed) {
                  approve();
                } else {
                  close_pending_ = false;
                }
              },
              [this](const std::string&, const std::string&,
                     const flutter::EncodableValue*) {
                close_pending_ = false;
              },
              approve));  // No editing is possible before Dart installs its handler.
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
