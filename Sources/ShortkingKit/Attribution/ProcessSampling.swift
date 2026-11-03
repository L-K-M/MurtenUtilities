import Foundation

enum ProcessSampling {
    static let initialPIDCapacity = 4_096

    static func cpuTimes(
        pids: [Int32],
        reportedCount: Int32,
        sample: (Int32) -> UInt64?
    ) -> [Int32: UInt64] {
        // proc_listallpids returns a PID count, although its buffer size is bytes.
        let count = min(max(0, Int(reportedCount)), pids.count)
        var result: [Int32: UInt64] = [:]
        for pid in pids.prefix(count) where pid > 0 {
            if let time = sample(pid) { result[pid] = time }
        }
        return result
    }
}
