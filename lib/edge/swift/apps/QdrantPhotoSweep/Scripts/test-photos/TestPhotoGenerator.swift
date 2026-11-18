// Generates a large, reproducible set of fake photos for PhotoSweep scale testing.
//
// Every photo is a procedural scene (gradient, shapes, texture) derived from a seed. A share
// of the photos belongs to near-duplicate groups: variants of one scene with small shifts,
// crops, brightness and JPEG-quality changes, taken seconds apart. Capture dates are written
// as EXIF `DateTimeOriginal` and spread over the last N years, so date presets filter them.
//
// Build and run through `generate.sh`; see `--help`.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - Options

struct Options {
    var count = 1_000
    var output = URL(fileURLWithPath: "TestPhotos")
    var duplicateShare = 0.3
    var maxGroupSize = 5
    var years = 6
    var width = 800
    var height = 600
    var seed: UInt64 = 42
    var verifySample = 0

    static let usage = """
    Usage: generate.sh [options]
      --count N            photos to generate (default 1000)
      --out DIR            output folder (default ./TestPhotos)
      --duplicates F       share of photos in near-duplicate groups, 0...1 (default 0.3)
      --max-group N        largest group size, at least 2 (default 5)
      --years N            spread capture dates over the last N years (default 6)
      --size WxH           pixel size (default 800x600; ~40-80 KB per photo)
      --seed N             random seed; the same seed gives the same photos (default 42)
      --verify N           after generating, compare Vision feature prints for N groups
      --import-simulator   add the photos to the booted simulator's library (generate.sh)
    """

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        func value(_ name: String) -> String {
            guard let value = iterator.next() else { fail("Missing value for \(name)") }
            return value
        }
        func number<T: LosslessStringConvertible>(_ name: String) -> T {
            guard let parsed = T(value(name)) else { fail("Invalid \(name)") }
            return parsed
        }
        while let argument = iterator.next() {
            switch argument {
            case "--count": options.count = number(argument)
            case "--out": options.output = URL(fileURLWithPath: value(argument))
            case "--duplicates": options.duplicateShare = number(argument)
            case "--max-group": options.maxGroupSize = max(2, number(argument) as Int)
            case "--years": options.years = max(1, number(argument) as Int)
            case "--size":
                let parts = value(argument).split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2, parts.allSatisfy({ $0 >= 64 }) else { fail("Invalid --size, use WxH") }
                options.width = parts[0]
                options.height = parts[1]
            case "--seed": options.seed = number(argument)
            case "--verify": options.verifySample = number(argument)
            case "--help", "-h": print(usage); exit(0)
            default: fail("Unknown option \(argument)\n\n\(usage)")
            }
        }
        options.duplicateShare = min(max(options.duplicateShare, 0), 1)
        return options
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Deterministic randomness

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Plan

/// One photo to render: which scene, which variant of it, and when it was "taken".
struct PhotoPlan {
    let index: Int
    let sceneSeed: UInt64
    let variant: Int
    let groupID: Int?
    let date: Date
}

func makePlan(_ options: Options) -> [PhotoPlan] {
    var rng = SplitMix64(seed: options.seed)
    let now = Date()
    let span = Double(options.years) * 365 * 86_400
    var plans: [PhotoPlan] = []
    plans.reserveCapacity(options.count)
    var groupCount = 0
    while plans.count < options.count {
        let sceneSeed = rng.next()
        let base = now.addingTimeInterval(-Double.random(in: 0..<span, using: &rng))
        let remaining = options.count - plans.count
        if remaining >= 2, Double.random(in: 0..<1, using: &rng) < options.duplicateShare {
            let size = min(Int.random(in: 2...options.maxGroupSize, using: &rng), remaining)
            for variant in 0..<size {
                plans.append(PhotoPlan(
                    index: plans.count, sceneSeed: sceneSeed, variant: variant, groupID: groupCount,
                    date: base.addingTimeInterval(Double(variant) * Double.random(in: 1...8, using: &rng))
                ))
            }
            groupCount += 1
        } else {
            plans.append(PhotoPlan(index: plans.count, sceneSeed: sceneSeed, variant: 0, groupID: nil, date: base))
        }
    }
    return plans
}

// MARK: - Rendering

func color(_ rng: inout SplitMix64) -> CGColor {
    CGColor(
        srgbRed: .random(in: 0...1, using: &rng), green: .random(in: 0...1, using: &rng),
        blue: .random(in: 0...1, using: &rng), alpha: 1
    )
}

/// Draws a scene. Variant 0 is the original; later variants shift, crop and relight it
/// slightly, as burst shots or retakes would.
func render(_ plan: PhotoPlan, width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    let w = CGFloat(width), h = CGFloat(height)
    var variantRNG = SplitMix64(seed: plan.sceneSeed ^ UInt64(plan.variant + 1) &* 0xA24B_AED4_963E_E407)
    if plan.variant > 0 {
        // Small crop/zoom and shift, like a hand-held retake.
        let zoom = 1 + CGFloat.random(in: 0.01...0.04, using: &variantRNG)
        let dx = CGFloat.random(in: -0.02...0.02, using: &variantRNG) * w
        let dy = CGFloat.random(in: -0.02...0.02, using: &variantRNG) * h
        context.translateBy(x: w / 2 + dx, y: h / 2 + dy)
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -w / 2, y: -h / 2)
    }

    var rng = SplitMix64(seed: plan.sceneSeed)
    drawScene(in: context, width: w, height: h, rng: &rng)
    // A second family inside a random region, so two scenes rarely share their structure.
    context.saveGState()
    let region = CGRect(
        x: .random(in: 0...0.5, using: &rng) * w, y: .random(in: 0...0.5, using: &rng) * h,
        width: .random(in: 0.3...0.6, using: &rng) * w, height: .random(in: 0.3...0.6, using: &rng) * h
    )
    if Bool.random(using: &rng) {
        context.addEllipse(in: region)
    } else {
        context.addRect(region)
    }
    context.clip()
    drawScene(in: context, width: w, height: h, rng: &rng)
    context.restoreGState()
    if plan.variant > 0 {
        // Slight exposure change.
        let brighter = Bool.random(using: &variantRNG)
        context.resetClip()
        context.setFillColor(CGColor(gray: brighter ? 1 : 0, alpha: .random(in: 0.02...0.06, using: &variantRNG)))
        context.fill(CGRect(x: -w, y: -h, width: 3 * w, height: 3 * h))
    }
    return context.makeImage()
}

/// Scenes come from several structurally different families, because Vision sees
/// variations of one abstract style as similar. Each family has its own palette, layout and
/// frequency, so unrelated scenes stay well below the app's similarity thresholds.
func drawScene(in context: CGContext, width w: CGFloat, height h: CGFloat, rng: inout SplitMix64) {
    let palette = (0..<5).map { _ in color(&rng) }
    func pick() -> CGColor { palette[Int.random(in: 0..<palette.count, using: &rng)] }
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // Background: linear or radial gradient.
    let gradient = CGGradient(colorsSpace: sRGB, colors: [pick(), pick(), pick()] as CFArray, locations: [0, 0.5, 1])!
    if Bool.random(using: &rng) {
        context.drawLinearGradient(gradient, start: CGPoint(x: .random(in: 0...w, using: &rng), y: 0),
                                   end: CGPoint(x: .random(in: 0...w, using: &rng), y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    } else {
        let center = CGPoint(x: .random(in: 0...w, using: &rng), y: .random(in: 0...h, using: &rng))
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(w, h), options: [.drawsAfterEndLocation])
    }

    switch Int.random(in: 0..<6, using: &rng) {
    case 0: // Stripes at a random angle and frequency.
        context.saveGState()
        context.translateBy(x: w / 2, y: h / 2)
        context.rotate(by: .random(in: 0..<CGFloat.pi, using: &rng))
        let band = CGFloat.random(in: 6...80, using: &rng)
        var x = -max(w, h)
        while x < max(w, h) {
            context.setFillColor(pick())
            context.fill(CGRect(x: x, y: -max(w, h), width: band * .random(in: 0.3...1, using: &rng), height: 2 * max(w, h)))
            x += band * 2
        }
        context.restoreGState()
    case 1: // Checkerboard with random cell size.
        let cell = CGFloat.random(in: 12...120, using: &rng)
        for row in 0...Int(h / cell) {
            for column in 0...Int(w / cell) where (row + column) % 2 == 0 {
                context.setFillColor(pick())
                context.fill(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
            }
        }
    case 2: // Many circles of one size class.
        let radius = CGFloat.random(in: 4...90, using: &rng)
        for _ in 0..<Int(min(2_000, w * h / (radius * radius * 3))) {
            context.setFillColor(pick().copy(alpha: .random(in: 0.4...1, using: &rng))!)
            let r = radius * .random(in: 0.5...1.5, using: &rng)
            context.fillEllipse(in: CGRect(x: .random(in: -r...w, using: &rng), y: .random(in: -r...h, using: &rng), width: 2 * r, height: 2 * r))
        }
    case 3: // Large overlapping polygons.
        for _ in 0..<Int.random(in: 3...9, using: &rng) {
            context.setFillColor(pick())
            context.move(to: CGPoint(x: .random(in: 0...w, using: &rng), y: .random(in: 0...h, using: &rng)))
            for _ in 0..<Int.random(in: 3...7, using: &rng) {
                context.addLine(to: CGPoint(x: .random(in: -0.2...1.2, using: &rng) * w, y: .random(in: -0.2...1.2, using: &rng) * h))
            }
            context.closePath()
            context.fillPath()
        }
    case 4: // Letter collage.
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&@#%?!")
        for _ in 0..<Int.random(in: 8...40, using: &rng) {
            let size = CGFloat.random(in: 24...min(w, h) * 0.6, using: &rng)
            let font = CTFontCreateWithName(["Helvetica-Bold", "Georgia", "Courier-Bold", "Menlo-Regular"][Int.random(in: 0..<4, using: &rng)] as CFString, size, nil)
            let text = String(letters[Int.random(in: 0..<letters.count, using: &rng)])
            let attributed = CFAttributedStringCreate(nil, text as CFString, [
                kCTFontAttributeName: font, kCTForegroundColorAttributeName: pick(),
            ] as CFDictionary)!
            context.saveGState()
            context.textPosition = CGPoint(x: .random(in: 0...w, using: &rng), y: .random(in: 0...h, using: &rng))
            context.rotate(by: .random(in: -0.4...0.4, using: &rng))
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            context.restoreGState()
        }
    default: // Blocky noise at a random block size.
        let block = CGFloat.random(in: 4...48, using: &rng)
        for row in 0...Int(h / block) {
            for column in 0...Int(w / block) {
                context.setFillColor(pick().copy(alpha: .random(in: 0.3...1, using: &rng))!)
                context.fill(CGRect(x: CGFloat(column) * block, y: CGFloat(row) * block, width: block, height: block))
            }
        }
    }
}

let exifFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter
}()

func write(_ image: CGImage, plan: PhotoPlan, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
    let stamp = exifFormatter.string(from: plan.date)
    var quality = SplitMix64(seed: plan.sceneSeed &+ UInt64(plan.variant))
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: Double.random(in: 0.8...0.92, using: &quality),
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    return CGImageDestinationFinalize(destination)
}

func fileName(_ plan: PhotoPlan) -> String {
    let group = plan.groupID.map { String(format: "g%06d-%d", $0, plan.variant) } ?? "single"
    return String(format: "IMG_%07d_%@.jpg", plan.index, group)
}

// MARK: - Verification

/// Cosine similarity of Vision feature prints, the same measure PhotoSweep uses.
func featurePrint(_ url: URL) -> [Float]? {
    let request = VNGenerateImageFeaturePrintRequest()
    guard (try? VNImageRequestHandler(url: url).perform([request])) != nil,
          let observation = request.results?.first else { return nil }
    return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return dot / max((na * nb).squareRoot(), .ulpOfOne)
}

func summary(_ values: [Float]) -> String {
    guard !values.isEmpty else { return "n/a" }
    let sorted = values.sorted()
    func at(_ q: Double) -> Float { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))] }
    return String(format: "min %.3f · p10 %.3f · median %.3f · p90 %.3f · max %.3f (n=%d)", sorted[0], at(0.1), at(0.5), at(0.9), sorted.last!, sorted.count)
}

func verify(_ plans: [PhotoPlan], sample: Int, folder: URL) {
    print("Verifying with Vision feature prints…")
    let groups = Dictionary(grouping: plans.filter { $0.groupID != nil }, by: { $0.groupID! }).values.prefix(sample)
    var within: [Float] = []
    for group in groups {
        let prints = group.compactMap { featurePrint(folder.appending(path: fileName($0))) }
        for i in 0..<prints.count { for j in (i + 1)..<prints.count { within.append(cosine(prints[i], prints[j])) } }
    }
    var rng = SplitMix64(seed: 7)
    var across: [Float] = []
    for _ in 0..<(sample * 4) {
        let a = plans[Int.random(in: 0..<plans.count, using: &rng)]
        let b = plans[Int.random(in: 0..<plans.count, using: &rng)]
        guard a.sceneSeed != b.sceneSeed,
              let fa = featurePrint(folder.appending(path: fileName(a))),
              let fb = featurePrint(folder.appending(path: fileName(b))) else { continue }
        across.append(cosine(fa, fb))
    }
    print("Within groups:   \(summary(within))")
    print("Across scenes:   \(summary(across))")
    for (name, threshold) in [("Strict", Float(0.96)), ("Balanced", 0.92), ("Loose", 0.85)] {
        let found = within.isEmpty ? 0 : Double(within.filter { $0 >= threshold }.count) / Double(within.count)
        let false_ = across.isEmpty ? 0 : Double(across.filter { $0 >= threshold }.count) / Double(across.count)
        print(String(format: "%-9@ ≥ %.2f: %5.1f%% of duplicate pairs match, %5.1f%% of unrelated pairs match", name as NSString, threshold, found * 100, false_ * 100))
    }
}

// MARK: - Main

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))
try? FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
let plans = makePlan(options)
let started = Date()
let failures = OSAllocatedCounter()
let progress = OSAllocatedCounter()

DispatchQueue.concurrentPerform(iterations: plans.count) { i in
    let plan = plans[i]
    let url = options.output.appending(path: fileName(plan))
    guard let image = render(plan, width: options.width, height: options.height), write(image, plan: plan, to: url) else {
        failures.increment()
        return
    }
    try? FileManager.default.setAttributes([.creationDate: plan.date, .modificationDate: plan.date], ofItemAtPath: url.path)
    let done = progress.increment()
    if done % 1_000 == 0 { print("  \(done)/\(plans.count)") }
}

let manifest = ["file,group,variant,date"] + plans.map {
    "\(fileName($0)),\($0.groupID.map(String.init) ?? ""),\($0.variant),\(ISO8601DateFormatter().string(from: $0.date))"
}
try? manifest.joined(separator: "\n").write(to: options.output.appending(path: "manifest.csv"), atomically: true, encoding: .utf8)

let groups = Set(plans.compactMap(\.groupID)).count
let grouped = plans.filter { $0.groupID != nil }.count
print(String(format: "Generated %d photos (%d in %d duplicate groups) in %.0f s → %@", plans.count - failures.value, grouped, groups, Date().timeIntervalSince(started), options.output.path))
if failures.value > 0 { print("Failed: \(failures.value)") }
if options.verifySample > 0 { verify(plans, sample: options.verifySample, folder: options.output) }

/// Thread-safe counter for the parallel render loop.
final class OSAllocatedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
}
