import Foundation
import Compression

/// Mozilla's mozLz40 header + little-endian length + a raw LZ4 block.
/// Uses the system codec; no Homebrew or third-party runtime is required.
enum MozillaLZ4 {
    static let maximumSize = 256 * 1024 * 1024
    static let magic = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0])

    static func decode(_ data: Data) throws -> Data {
        guard data.count > 12, data.count <= maximumSize, data.prefix(8) == magic else {
            throw BackupError.invalid("This is not a Mozilla JSONLZ4 session file.")
        }
        let size = (0..<4).reduce(0) { $0 | (Int(data[8 + $1]) << (8 * $1)) }
        guard size > 0, size <= maximumSize else {
            throw BackupError.invalid("The session's uncompressed size exceeds the 256 MB safety limit.")
        }
        // An extra byte makes overlong output distinguishable from a full buffer.
        var output = Data(count: size + 1)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationPointer = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourcePointer = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationPointer, size + 1,
                    sourcePointer.advanced(by: 12), data.count - 12,
                    nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard count == size else { throw BackupError.invalid("The compressed session is damaged or incomplete.") }
        output.count = size
        return output
    }
}
