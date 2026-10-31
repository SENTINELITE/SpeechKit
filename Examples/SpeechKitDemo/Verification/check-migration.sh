#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
swift build
bin_path="$(swift build --show-bin-path)"
check_directory="$(mktemp -d)"
trap 'rm -rf "$check_directory"' EXIT
demo="$repo_root/Examples/SpeechKitDemo/SpeechKitDemo"
sdk_link=("$bin_path/libSpeechKit.a")
if [[ ! -f "${sdk_link[0]}" ]]; then
  sdk_link=("$bin_path"/SpeechKit.build/*.swift.o)
fi
swiftc -swift-version 6 -warnings-as-errors -target "$(uname -m)-apple-macosx26.0" \
  -I "$bin_path" -I "$bin_path/Modules" \
  "$demo/Configuration/DemoConfiguration.swift" \
  "$demo/Configuration/DemoKeychainStore.swift" \
  "$demo/Configuration/DemoPrivateTextPreferences.swift" \
  "$repo_root/Examples/SpeechKitDemo/Verification/MigrationChecks.swift" \
  "${sdk_link[@]}" -o "$check_directory/migration-checks"
"$check_directory/migration-checks"
