#!/usr/bin/env bash
# Build the Go backend XCFramework used by SpotiFLAC Mobile on iOS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_BACKEND_DIR="$PROJECT_DIR/go_backend"
OUTPUT_DIR="$PROJECT_DIR/ios/Frameworks"

echo "SpotiFLAC Mobile iOS backend build"
echo "Project: $PROJECT_DIR"
echo "Output:  $OUTPUT_DIR"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: this script must run on macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "Error: Go is not installed." >&2
  exit 1
fi

cd "$GO_BACKEND_DIR"
go mod download

# Running inside the module installs the x/mobile revision pinned by go.mod.
go install golang.org/x/mobile/cmd/gomobile
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init

mkdir -p "$OUTPUT_DIR"
gomobile bind \
  -target=ios \
  -tags ios \
  -o "$OUTPUT_DIR/Gobackend.xcframework" \
  .

if [[ ! -d "$OUTPUT_DIR/Gobackend.xcframework" ]]; then
  echo "Error: Gobackend.xcframework was not created." >&2
  exit 1
fi

echo "Built $OUTPUT_DIR/Gobackend.xcframework"
