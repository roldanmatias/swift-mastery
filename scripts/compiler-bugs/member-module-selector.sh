#!/bin/bash
# Swift 6.3.2 / 6.4.2: `value.Module::member` compiles but calls the wrong
# module's extension member (found while doing Ex 05). Top-level selectors and
# nested-type selectors (`Ship.A::Engine`) work.
set -euo pipefail
dir=$(mktemp -d)
mkdir -p "$dir/Sources/A" "$dir/Sources/B" "$dir/Sources/App"
cat > "$dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "repro", targets: [
    .target(name: "A"), .target(name: "B"),
    .executableTarget(name: "App", dependencies: ["A", "B"]),
])
SWIFT
echo 'extension String { public var slug: String { "a-" + self } }' > "$dir/Sources/A/a.swift"
echo 'extension String { public var slug: String { "b-" + self } }' > "$dir/Sources/B/b.swift"
printf 'import A\nimport B\nprint("x".A::slug, "x".B::slug)   // expected: a-x b-x\n' > "$dir/Sources/App/main.swift"
cd "$dir" && swift run -q App
