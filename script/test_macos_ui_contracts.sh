#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
controls="$root/Pythia/Views/Controls.swift"
settings="$root/Pythia/Views/SettingsWindowController.swift"
translator="$root/Pythia/Views/TranslatorWindowController.swift"
checker="$root/Pythia/Services/PythiaUpdateChecker.swift"
plugins="$root/Pythia/Services/PluginManager.swift"

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
grep -q 'preserveOriginalPackage: false' "$plugins"
grep -q 'migrationPolicy.*legacy-package-not-retained' "$plugins"
grep -q 'removeItem(at: retainedLegacy)' "$plugins"
grep -q 'Pythia 不保留旧插件或 .potext 备份' "$settings"

echo "macOS UI contracts passed"
