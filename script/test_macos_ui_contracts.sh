#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
controls="$root/Pythia/Views/Controls.swift"
settings="$root/Pythia/Views/SettingsWindowController.swift"
translator="$root/Pythia/Views/TranslatorWindowController.swift"
checker="$root/Pythia/Services/PythiaUpdateChecker.swift"

grep -q 'attributedTitle = NSAttributedString' "$controls"
grep -q 'foregroundColor: theme' "$controls"
! grep -q 'enhancedGlass' "$controls"
! grep -q 'transparentCheckbox' "$settings"
! grep -q 'backgroundView?.enhancedGlass' "$translator"
grep -q '/releases?per_page=' "$checker"
grep -q 'PythiaReleaseVersionPolicy' "$checker"
grep -q 'isBareReturn && hadMarkedText' "$controls"
grep -q 'AutomaticLanguagePolicy.targetLanguage' "$translator"
grep -q 'let contentSize = NSSize(width: 300' "$controls"
grep -q 'controller.preferredContentSize = contentSize' "$controls"
grep -q 'popover.contentSize = contentSize' "$controls"

echo "macOS UI contracts passed"
