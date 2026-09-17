#!/bin/bash
# Run the input tests without native FFI libraries or generated bridge files.
set -euo pipefail
flutter_dir="$(cd "$(dirname "$0")/.." && pwd)"
flutter_bin="${1:-$(command -v flutter)}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cuberemote-input.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/flutter/lib/models" "$test_dir/flutter/test" "$test_dir/src"
for module in mobile_pointer_router remote_shortcuts input_modifier_utils; do
    cp "$flutter_dir/lib/models/$module.dart" "$test_dir/flutter/lib/models/"
    cp "$flutter_dir/test/${module}_test.dart" "$test_dir/flutter/test/"
done
cp "$flutter_dir/../src/client.rs" "$test_dir/src/"
cat > "$test_dir/flutter/pubspec.yaml" <<'YAML'
name: cuberemote_input_regression
environment:
  sdk: ">=3.1.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
YAML
cd "$test_dir/flutter"
"$flutter_bin" test --reporter expanded
