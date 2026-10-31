#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
helper_dir="$repo_root/Examples/SpeechKitDemo/SpeechKitDemo"
checks_dir="$repo_root/Examples/SpeechKitDemo/Verification"
check_binary="$(mktemp -d)"
trap 'rm -rf "$check_binary"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
  "$helper_dir/Configuration/DemoKeychainStore.swift" \
  "$helper_dir/Configuration/DemoPrivateTextPreferences.swift" \
  "$helper_dir/Audio/DemoProtectedStorage.swift" \
  "$checks_dir/HelperChecks.swift" -o "$check_binary/helper-checks"
"$check_binary/helper-checks"
