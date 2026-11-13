import Foundation
import SweepDomain
import SweepTestSupport

func asset(_ name: String) -> AssetID {
    AssetID(name)
}

func groupID(_ value: UInt64) -> GroupID {
    GroupID(SequentialIDGenerator.uuid(value))
}

func passID(_ value: UInt64) -> VectorizationPassID {
    VectorizationPassID(SequentialIDGenerator.uuid(value))
}

func date(_ day: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
}

func threshold(_ value: Float) throws -> SimilarityThreshold {
    guard let threshold = SimilarityThreshold(value) else {
        throw FixtureError.invalidThreshold(value)
    }
    return threshold
}

enum FixtureError: Error {
    case invalidThreshold(Float)
}

let januaryScope = DateRange(start: date(0), end: date(30))
