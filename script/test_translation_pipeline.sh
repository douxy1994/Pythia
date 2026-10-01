#!/usr/bin/env bash
# Exercise the production dispatcher with an offline provider that intentionally
# flattens newlines. No user preferences, clipboard, credentials or APIs are used.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source="${1:-$root/Pythia/Services/TranslationService.swift}"
mode="${2:-modified}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
python3 - "$root" "$source" "$tmp" "$mode" <<'PY'
import re, sys
from pathlib import Path
root, source, tmp, mode = map(Path, sys.argv[1:])
service = source.read_text()
properties = sorted(set(re.findall(r'(?:preferences|Preferences.shared)\.([A-Za-z0-9_]+)', service)) | {'translateDeleteNewline'})
stubs = 'import Foundation\nimport CFNetwork\n'
stubs += 'final class Preferences { static let shared = Preferences()\n'
for prop in properties:
    value = 'false' if prop in ['proxyEnabled', 'translateDeleteNewline'] else '""'
    stubs += f'var {prop} = {value}\n'
stubs += '}\n'
models = (root/'Pythia/Models/PythiaModels.swift').read_text()
stubs += models[models.index('enum PythiaProvider'):models.index('typealias TranslationRecord')]
stubs += models[models.index('enum TranslationError'):]
stubs += '''
final class PluginManager {
    static let shared = PluginManager()
    let lock = NSLock()
    var calls = 0
    var active = 0
    var peak = 0
    func reset() { lock.lock(); calls = 0; active = 0; peak = 0; lock.unlock() }
    func translate(serviceIdentifier: String = "", text: String, sourceLanguage: String,
                   targetLanguage: String, completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock(); calls += 1; active += 1; peak = max(peak, active); lock.unlock()
        // Different delays force completion order to differ from source order.
        let delay = text.hasPrefix("First") ? 0.12 : 0.04
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self.lock.lock(); self.active -= 1; self.lock.unlock()
            if text.contains("FAIL") { completion(.failure(TranslationError.invalidResponse)); return }
            completion(.success(text.replacingOccurrences(of: "\\r\\n", with: " ")
                .replacingOccurrences(of: "\\n", with: " ").uppercased()))
        }
    }
}
'''
(tmp/'Stubs.swift').write_text(stubs)
# The main file is generated below; baseline only excludes the new session API.
PY
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func run(_ input: String, cancel: Bool = false) -> (Result<String, Error>, Double) {
    let done = DispatchSemaphore(value: 0)
    let start = Date()
    var value: Result<String, Error>!
    var completions = 0
    let cancellation = TranslationService.shared.translateService(identifier: "plugin:fixture", text: input,
        sourceLanguage: "en", targetLanguage: "zh-CN") { result in
            completions += 1; value = result; done.signal()
        }
    if cancel { cancellation?.cancel() }
    precondition(done.wait(timeout: .now() + 5) == .success, "translation timed out")
    let elapsed = Date().timeIntervalSince(start)
    Thread.sleep(forTimeInterval: 0.2)
    precondition(completions == 1, "completion called more than once")
    return (value, elapsed)
}
let baseline = CommandLine.arguments.contains("baseline")
let input = "First paragraph.\r\n\r\n  Second paragraph.\nThird paragraph."
Preferences.shared.translateDeleteNewline = false
let (value, _) = run(input)
let output = try value.get()
print("newline input=\(String(reflecting: input))")
print("newline output=\(String(reflecting: output))")
if baseline {
    precondition(!output.contains("\n"))
    print("BASELINE: provider flattened paragraph breaks despite disabled preference")
} else {
    precondition(output == input.uppercased())
    precondition(PluginManager.shared.peak == 2)
    print("PASS: disabled preference preserves CRLF, blank lines, indentation and output order; peak=2")
    Preferences.shared.translateDeleteNewline = true
    let (compact, _) = run(input)
    let compactOutput = try compact.get()
    precondition(!compactOutput.contains("\n"))
    print("PASS: enabled preference retains compact provider behavior")
    Preferences.shared.translateDeleteNewline = false
    let (cancelled, _) = run("First\nSecond\nThird", cancel: true)
    guard case .failure(let error) = cancelled, case TranslationError.cancelled = error else {
        fatalError("cancellation did not propagate")
    }
    print("PASS: cancellation completes once and ignores late provider responses")
    let (failed, _) = run("First\nFAIL\nThird")
    guard case .failure = failed else { fatalError("failure was swallowed") }
    print("PASS: failure completes once and ignores late provider responses")
}
PluginManager.shared.reset()
let longInput = (0..<4).map { "First \($0) " + String(repeating: "a", count: 1_000) }.joined(separator: "\n\n")
let (_, elapsed) = run(longInput)
print(String(format: "mock long-selection elapsed=%.3fs calls=%d peak=%d", elapsed,
    PluginManager.shared.calls, PluginManager.shared.peak))
precondition(PluginManager.shared.calls == 4)
precondition(PluginManager.shared.peak == (baseline ? 1 : 2))
SWIFT
if [[ "$mode" != "baseline" ]]; then
cat >> "$tmp/main.swift" <<'SWIFT'
let config = PythiaNetworkSession.configuration(for: URL(string: "https://example.test"))
let a = PythiaNetworkSession.reusableSession(configuration: config)
let b = PythiaNetworkSession.reusableSession(configuration: config)
precondition(a === b)
let timeoutConfig = PythiaNetworkSession.configuration(for: nil, requestTimeout: 300, resourceTimeout: 300)
precondition(a !== PythiaNetworkSession.reusableSession(configuration: timeoutConfig))
Preferences.shared.proxyEnabled = true
Preferences.shared.proxyHost = "localhost"
Preferences.shared.proxyPort = "8888"
let proxyConfig = PythiaNetworkSession.configuration(for: URL(string: "https://example.test"))
precondition(a !== PythiaNetworkSession.reusableSession(configuration: proxyConfig))
Preferences.shared.noProxy = "example.test"
let bypass = PythiaNetworkSession.configuration(for: URL(string: "https://example.test"))
precondition(a === PythiaNetworkSession.reusableSession(configuration: bypass))
print("PASS: session reuse isolates timeout/proxy changes and respects noProxy")
SWIFT
fi
xcrun swiftc -swift-version 5 "$tmp/Stubs.swift" \
  "$root/Core/PythiaCore/Sources/PythiaCore/TranslationChunkPolicy.swift" \
  "$root/Core/PythiaCore/Sources/PythiaCore/AutomaticLanguagePolicy.swift" \
  "$source" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test" "$mode"
