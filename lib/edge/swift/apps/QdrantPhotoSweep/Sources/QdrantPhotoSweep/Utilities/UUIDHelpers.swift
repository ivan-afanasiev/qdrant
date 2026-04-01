import Foundation

func deterministicUUID(from localIdentifier: String) -> String {
    let data = Data(localIdentifier.utf8)
    var hash = [UInt8](repeating: 0, count: 16)
    data.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for i in 0..<data.count {
            hash[i % 16] ^= bytes[i]
        }
    }
    // Set UUID version 4 and variant bits for RFC 4122 compliance
    hash[6] = (hash[6] & 0x0F) | 0x40
    hash[8] = (hash[8] & 0x3F) | 0x80
    let uuid = UUID(uuid: (
        hash[0], hash[1], hash[2], hash[3],
        hash[4], hash[5], hash[6], hash[7],
        hash[8], hash[9], hash[10], hash[11],
        hash[12], hash[13], hash[14], hash[15]
    ))
    return uuid.uuidString.lowercased()
}
