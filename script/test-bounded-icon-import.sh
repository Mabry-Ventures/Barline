#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir=".artifacts/tests/bounded-icon-import"
mkdir -p "$artifact_dir"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -parse-as-library Barline/Utilities/BoundedIconImporter.swift \
  script/test-bounded-icon-import.swift -o "$artifact_dir/check"
"$artifact_dir/check" | tee "$artifact_dir/result.txt"
