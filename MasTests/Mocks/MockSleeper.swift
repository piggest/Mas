import Foundation
@testable import Mas

/// sleep 呼び出しを記録し、実際にはスリープしない Mock。
final class MockSleeper: SleepProviding {

    /// sleep が呼ばれた回数。
    private(set) var sleepCallCount: Int = 0

    /// 各 sleep 呼び出しの ns 引数履歴。
    private(set) var sleepNanoseconds: [UInt64] = []

    /// sleep 呼び出しの ns 合計。
    var totalSleepNanoseconds: UInt64 {
        sleepNanoseconds.reduce(0, +)
    }

    func sleep(nanoseconds: UInt64) async {
        sleepCallCount += 1
        sleepNanoseconds.append(nanoseconds)
        // 実際にはスリープしない（テスト即時化）
    }
}
