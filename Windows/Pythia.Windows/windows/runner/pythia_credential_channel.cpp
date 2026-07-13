#include "pythia_credential_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincred.h>

#include <memory>
#include <optional>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;
using flutter::StandardMethodCodec;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                      static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size);
  return result;
}

std::wstring TargetName(const std::string& key) {
  return L"Pythia/" + Utf8ToWide(key);
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
  return std::get<std::string>(found->second);
}

std::string LastErrorMessage() {
  return "Windows Credential Manager error: " +
         std::to_string(static_cast<unsigned long>(GetLastError()));
}

void ReadSecret(const MethodCall<EncodableValue>& call,
                std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto key = StringArg(call.arguments(), "key");
  if (!key || key->empty()) {
    result->Error("invalid_key", "Missing credential key.");
    return;
  }

  PCREDENTIALW credential = nullptr;
  if (!CredReadW(TargetName(*key).c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
    if (GetLastError() == ERROR_NOT_FOUND) {
      result->Success(EncodableValue());
      return;
    }
    result->Error("readSecret", LastErrorMessage());
    return;
  }

  std::string value(reinterpret_cast<const char*>(credential->CredentialBlob),
                    credential->CredentialBlobSize);
  CredFree(credential);
  result->Success(EncodableValue(value));
}

void WriteSecret(const MethodCall<EncodableValue>& call,
                 std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto key = StringArg(call.arguments(), "key");
  const auto value = StringArg(call.arguments(), "value");
  if (!key || key->empty()) {
    result->Error("invalid_key", "Missing credential key.");
    return;
  }
  if (!value) {
    result->Error("invalid_value", "Missing credential value.");
    return;
  }

  const auto target = TargetName(*key);
  CREDENTIALW credential = {};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<LPWSTR>(target.c_str());
  credential.CredentialBlob =
      reinterpret_cast<LPBYTE>(const_cast<char*>(value->data()));
  credential.CredentialBlobSize = static_cast<DWORD>(value->size());
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;

  if (!CredWriteW(&credential, 0)) {
    result->Error("writeSecret", LastErrorMessage());
    return;
  }
  result->Success();
}

void DeleteSecret(const MethodCall<EncodableValue>& call,
                  std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto key = StringArg(call.arguments(), "key");
  if (!key || key->empty()) {
    result->Error("invalid_key", "Missing credential key.");
    return;
  }
  if (!CredDeleteW(TargetName(*key).c_str(), CRED_TYPE_GENERIC, 0) &&
      GetLastError() != ERROR_NOT_FOUND) {
    result->Error("deleteSecret", LastErrorMessage());
    return;
  }
  result->Success();
}

}  // namespace

void RegisterPythiaCredentialChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, "pythia/credential_store",
      &StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name() == "readSecret") {
          ReadSecret(call, std::move(result));
        } else if (call.method_name() == "writeSecret") {
          WriteSecret(call, std::move(result));
        } else if (call.method_name() == "deleteSecret") {
          DeleteSecret(call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });

  // Keep the channel alive for the process lifetime.
  static std::unique_ptr<MethodChannel<EncodableValue>> retained_channel;
  retained_channel = std::move(channel);
}
