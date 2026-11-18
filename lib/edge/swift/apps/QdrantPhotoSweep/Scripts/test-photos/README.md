# Test photos

Generates large, reproducible photo libraries for scale testing: procedural scenes, a share of
near-duplicate groups (2–5 shots seconds apart), and EXIF capture dates over the last N years so
date presets filter them. `manifest.csv` lists every file with its group and date.

```sh
Scripts/test-photos/generate.sh --count 100000 --out ~/PhotoSweepTestPhotos --verify 50
Scripts/test-photos/generate.sh --count 5000 --import-simulator   # into the booted simulator
Scripts/test-photos/generate.sh --help
```

About 80 KB per photo at the default 800×600 (100,000 photos ≈ 8 GB); `--size 640x480` halves
it. Generating 100,000 takes a few minutes.

`--verify N` measures Vision feature-print similarity like the app does. On a sample of 800:
duplicate pairs 0.97–1.00, unrelated pairs median 0.72. Every duplicate matches at all three
presets; unrelated pairs match 0% at Strict and Balanced and about 4% at Loose, which makes Loose
a chaining stress test at scale.

For a device, import the folder into a Mac Photos library synced to the test iPhone, or AirDrop
batches. There is no command-line import for devices.
