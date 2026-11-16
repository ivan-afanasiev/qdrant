#!/usr/bin/env python3
"""Add English source strings to the design-system string catalog.

Usage: python3 Scripts/add-strings.py strings.json
where strings.json maps catalog keys to English values. Existing keys are left untouched;
other languages are added later by translation.
"""
import json
import sys
from pathlib import Path

catalog_path = Path(__file__).resolve().parents[1] / "Packages/PhotoSweep/Sources/SweepDesignSystem/Resources/Localizable.xcstrings"
additions = json.loads(Path(sys.argv[1]).read_text())
catalog = json.loads(catalog_path.read_text())
added = []
for key, value in additions.items():
    if key in catalog["strings"]:
        continue
    catalog["strings"][key] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": value}}}}
    added.append(key)
catalog["strings"] = dict(sorted(catalog["strings"].items()))
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")
print(f"added {len(added)} keys: {', '.join(added)}")
