#!/usr/bin/env python3
"""Check the package dependency graph and source imports without resolving packages."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "Packages/PhotoSweep"
features = {"SweepLibraryFeature", "SweepReviewFeature", "SweepSettingsFeature", "SweepOnboardingFeature"}
adapters = {"SweepQdrant", "SweepPhotos", "SweepEmbeddings", "SweepPersistence", "SweepSystem"}
allowed = {
    "SweepDomain": set(),
    "SweepUseCases": {"SweepDomain"},
    "SweepFeatureState": set(),
    "SweepDesignSystem": set(),
    "SweepTestSupport": {"SweepDomain"},
    **{name: {"SweepDomain"} for name in adapters},
    **{name: {"SweepDomain", "SweepUseCases", "SweepFeatureState", "SweepDesignSystem"} for name in features},
    # The app entry point: it may see everything except test support.
    "SweepComposition": adapters | features | {"SweepDomain", "SweepUseCases", "SweepFeatureState", "SweepDesignSystem"},
}
safe_di_free = {"SweepDomain", "SweepDesignSystem", "SweepFeatureState", "SweepTestSupport"}
platform_free = {"SwiftUI", "UIKit", "Photos", "SwiftData", "QdrantEdge", "Vision"}
feature_forbidden = {"Photos", "SwiftData", "QdrantEdge", "Vision"}

# Matches `import X`, `@testable import X` and `import struct X.Y`.
import_pattern = re.compile(
    r'^\s*(?:@\w+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func|actor)\s+)?(\w+)', re.M)
target_pattern = re.compile(
    r'\.(target|testTarget)\(name: "(\w+)"(.*?)(?=\n\s*\.(?:target|testTarget)\(|\n\s*\],)', re.S)


def imports_of(source):
    return set(import_pattern.findall(source.read_text()))


manifest = (root / "Package.swift").read_text()
targets = {name: (kind, body) for kind, name, body in target_pattern.findall(manifest)}
errors = []

for name, (kind, _) in targets.items():
    if kind == "target" and name not in allowed:
        errors.append(f"Unknown production target {name}: add it to this script's boundary map")

for name, dependencies in allowed.items():
    if name not in targets:
        errors.append(f"Missing target: {name}")
        continue
    body = targets[name][1]
    declared = set(re.findall(r'"(Sweep\w+)"', body))
    if declared - dependencies:
        errors.append(f"{name}: forbidden dependencies {declared - dependencies}")
    if name in safe_di_free and re.search(r'\bsafeDI\b|"SafeDI"', body):
        errors.append(f"{name}: must not depend on SafeDI")
    for source in sorted((root / "Sources" / name).rglob("*.swift")):
        imports = imports_of(source)
        forbidden = (imports & allowed.keys()) - dependencies
        if name in {"SweepUseCases", "SweepFeatureState", "SweepDomain"}:
            forbidden |= imports & platform_free
        if name in features:
            forbidden |= imports & feature_forbidden
        if name in safe_di_free:
            forbidden |= imports & {"SafeDI"}
        if forbidden:
            errors.append(f"{source.relative_to(root)}: forbidden imports {forbidden}")

# Test targets use Swift Testing only and import just the package modules they declare.
test_targets = {name: body for name, (kind, body) in targets.items() if kind == "testTarget"}
for name, body in test_targets.items():
    declared = set(re.findall(r'"(Sweep\w+)"', body))
    for source in sorted((root / "Tests" / name).rglob("*.swift")):
        imports = imports_of(source)
        if "XCTest" in imports:
            errors.append(f"{source.relative_to(root)}: XCTest is not allowed; use Swift Testing")
        undeclared = (imports & allowed.keys()) - declared
        if undeclared:
            errors.append(f"{source.relative_to(root)}: imports undeclared modules {undeclared}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"PASS: {len(allowed)} production/test-support module boundaries, {len(test_targets)} test targets")
