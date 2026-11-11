#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Core -j 1 -Xswiftc -disable-batch-mode
python3 Scripts/audit_project.py
xcodebuild -project LumaSleep.xcodeproj -scheme LumaBasic -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LumaSleep.xcodeproj -scheme LumaHealth -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
