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
    **{name: {"SweepUseCases", "SweepFeatureState", "SweepDesignSystem"} for name in features},
    "SweepComposition": adapters | features | {"SweepDomain", "SweepUseCases"},
}
manifest = (root / "Package.swift").read_text()
errors = []
for name, dependencies in allowed.items():
    match = re.search(r'\.target\(name: "' + name + r'"(.*?)(?=\n\s*\.(?:target|testTarget)|\n\s*\],)', manifest, re.S)
    if match is None:
        errors.append(f"Missing target: {name}")
        continue
    declared = set(re.findall(r'"(Sweep\w+)"', match.group(1)))
    if declared - dependencies:
        errors.append(f"{name}: forbidden dependencies {declared - dependencies}")
    for source in (root / "Sources" / name).glob("*.swift"):
        imports = set(re.findall(r'^import (\w+)', source.read_text(), re.M))
        forbidden = (imports & allowed.keys()) - dependencies
        if name in {"SweepUseCases", "SweepFeatureState", "SweepDomain"}:
            forbidden |= imports & {"SwiftUI", "UIKit", "Photos", "SwiftData", "QdrantEdge", "Vision"}
        if name in features:
            forbidden |= imports & {"Photos", "SwiftData", "QdrantEdge", "Vision"}
        if name in {"SweepDomain", "SweepDesignSystem", "SweepFeatureState"}:
            forbidden |= imports & {"SafeDI"}
        if forbidden:
            errors.append(f"{source.relative_to(root)}: forbidden imports {forbidden}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"PASS: {len(allowed)} production/test-support module boundaries")
