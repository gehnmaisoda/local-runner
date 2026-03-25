import Foundation
import Core

/// local-runner daemon のエントリーポイント。
/// LaunchAgent として常時起動し、タスクのスケジューリング・実行・ログ記録を担当する。
let logStore = LogStore()
let taskStore = TaskStore()
let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
let ipcServer = IPCServer(scheduler: scheduler, logStore: logStore)

// IPC サーバー起動
ipcServer.start()

// スケジューラ起動
scheduler.start()

// スリープ復帰検知
let wakeDetector = WakeDetector { lastAwake in
    scheduler.handleWake(lastSleepDate: lastAwake)
}
wakeDetector.start()

print("[local-runner] Started (PID: \(ProcessInfo.processInfo.processIdentifier))")

// プロセスを維持
dispatchMain()
