#!/usr/bin/env bash
# Compile the actual acquisition method with fake AX/copy boundaries. No GUI,
# user clipboard, preferences, credentials or network are touched.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source="${1:-$root/Pythia/Services/SelectionReader.swift}"
mode="${2:-modified}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
python3 - "$source" "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('    func selectedText(targetApplication:')
end = source.index('\n    func accessibilityTrusted', start)
method = source[start:end]
Path(sys.argv[2]).write_text('''import Foundation
final class NSRunningApplication { var isActive = true }
final class FixtureReader {
    var ax: String? = nil
    var copied = ""
    var copies = 0
    func accessibilityTrusted() -> Bool { true }
    func validExternalApplication(_ app: NSRunningApplication?) -> NSRunningApplication? { app }
    func prefersClipboardCopy(for app: NSRunningApplication?) -> Bool { false }
    func readAccessibilitySelection(targetApplication: NSRunningApplication?) -> String? { ax }
    func readClipboardFallback(targetApplication: NSRunningApplication?, completion: @escaping (String) -> Void) {
        copies += 1; completion(copied)
    }
    func activate(_ app: NSRunningApplication) {}
''' + method + '''
}
let baseline = CommandLine.arguments.contains("baseline")
let copied = "Title\\n\\nFirst paragraph.\\n\\nSecond paragraph.\\n\\nThird paragraph."
let cases: [(String?, String)] = [
    ("Title\\n\\nFirst paragraph. Second paragraph. Third paragraph.", copied),
    ("Title First paragraph. Second paragraph. Third paragraph.", copied),
    ("First\\nSecond", ""),
    (nil, "First\\nSecond"),
    ("First\\n\\nSecond", "First Second"),
    (nil, ""),
    ("Old\\n\\nText", "Fresh selection"),
]
for (index, fixture) in cases.enumerated() {
    let reader = FixtureReader(); reader.ax = fixture.0; reader.copied = fixture.1
    var result: String?
    reader.selectedText(targetApplication: NSRunningApplication()) { result = $0 }
    let deadline = Date().addingTimeInterval(3)
    while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    guard let result else { fatalError("selection timed out") }
    let chunks = TranslationChunkPolicy.linePreservingChunks(for: result)
    // Simulate a provider that removes every newline from every request.
    let outputs = chunks.map { $0.body.components(separatedBy: .newlines).joined(separator: " ").uppercased() }
    let translated = TranslationChunkPolicy.reassemble(chunks, translations: outputs)
    if baseline && index < 2 {
        precondition(result == fixture.0)
        precondition(reader.copies == 0)
        print("BASELINE case=\\(index) paragraphs=\\(chunks.filter { !$0.body.isEmpty }.count) copies=0")
    } else if !baseline {
        let expected = SelectionTextPolicy.preferredText(accessibilityText: fixture.0, copiedText: fixture.1)
        precondition(result == expected && translated == expected.uppercased())
        precondition(reader.copies == 1)
        print("PASS case=\\(index) paragraphs=\\(chunks.filter { !$0.body.isEmpty }.count) copies=1 output=\\(String(reflecting: translated))")
    }
}
''')
PY
xcrun swiftc "$root/Core/PythiaCore/Sources/PythiaCore/SelectionTextPolicy.swift" \
    "$root/Core/PythiaCore/Sources/PythiaCore/TranslationChunkPolicy.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test" "$mode"
if [[ "$mode" == baseline ]]; then exit 0; fi
# Exercise the production pasteboard decoder on a private named pasteboard.
cat > "$tmp/main.swift" <<'SWIFT'
import AppKit
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
let rich = "First\n\nSecond\n\nThird"
let rtf = try NSAttributedString(string: rich).data(from: NSRange(location: 0, length: rich.utf16.count), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
board.declareTypes([.string, .rtf], owner: nil)
board.setString("First Second Third", forType: .string)
board.setData(rtf, forType: .rtf)
precondition(SelectionReader.selectionText(from: board) == rich)
print("PASS: production RTF decoder restores three paragraphs from flattened plain text")
board.setString("Different selection", forType: .string)
precondition(SelectionReader.selectionText(from: board) == "Different selection")
print("PASS: unrelated RTF does not replace copied words")
board.clearContents()
precondition(SelectionReader.selectionText(from: board).isEmpty)
print("PASS: empty clipboard is not reused as a selection")
let monitor = ClipboardMonitor(pasteboard: board)
var received: [String] = []
monitor.onText = { received.append($0) }
monitor.beginSelectionRead()
monitor.beginSelectionRead()
board.declareTypes([.string], owner: nil)
board.setString("Temporary copied selection", forType: .string)
monitor.tick()
monitor.endSelectionRead()
monitor.tick()
precondition(received.isEmpty)
board.declareTypes([.string], owner: nil)
board.setString("Restored clipboard", forType: .string)
monitor.endSelectionRead()
monitor.tick()
precondition(received.isEmpty)
board.declareTypes([.string], owner: nil)
board.setString("User's next copy", forType: .string)
monitor.tick()
precondition(received == ["User's next copy"])
print("PASS: nested selection reads and restoration do not trigger clipboard translation; next user copy does")
SWIFT
xcrun swiftc "$root/Core/PythiaCore/Sources/PythiaCore/SelectionTextPolicy.swift" \
    "$source" "$root/Pythia/Services/ClipboardMonitor.swift" "$tmp/main.swift" -o "$tmp/pasteboard-test"
"$tmp/pasteboard-test"
