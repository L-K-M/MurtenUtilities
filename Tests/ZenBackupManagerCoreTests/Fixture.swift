import Foundation
import Compression
@testable import ZenBackupManager

enum Fixture {
    static func compressed(_ text: String) -> Data {
        let source = Data(text.utf8)
        var output = Data(count: source.count * 2 + 1024)
        let size = output.withUnsafeMutableBytes { dst in
            source.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, outputCapacity(source.count),
                    src.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        precondition(size > 0)
        var length = UInt32(source.count).littleEndian
        return MozillaLZ4.magic + withUnsafeBytes(of: &length) { Data($0) } + output.prefix(size)
    }
    private static func outputCapacity(_ count: Int) -> Int { count * 2 + 1024 }
    static let modernJSON = """
    {"tabs":[
      {"entries":[{"url":"https://old.example","title":"Old"},{"url":"https://swift.org","title":"Swift"}],"index":2,"zenWorkspace":"work","pinned":true},
      {"entries":[{"url":"https://example.org","title":"Example"}],"index":1,"zenEssential":true}
    ],"spaces":[{"uuid":"work","name":"Work","icon":"🚀"}],"folders":[{}],"splitViewData":[{}],"lastCollected":1789128000000}
    """
    static let legacyJSON = """
    {"windows":[{"tabs":[{"entries":[{"url":"https://legacy.example","title":"Legacy"}],"index":1}],"spaces":[]}]}
    """
    static var modern: Data { compressed(modernJSON) }
    static var legacy: Data { compressed(legacyJSON) }
}
