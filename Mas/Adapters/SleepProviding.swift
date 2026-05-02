import Foundation

/// 非同期 sleep を抽象化するプロトコル。テストでは即時化される Mock を注入する。
protocol SleepProviding {
    func sleep(nanoseconds: UInt64) async
}

/// 実本番の Sleep。`Task.sleep` をラップする。
struct RealSleeper: SleepProviding {
    func sleep(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
