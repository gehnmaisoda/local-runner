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

// 起動時ギャップ検出（デーモン再起動・長時間停止への対応）
if let gapStart = wakeDetector.detectStartupGap() {
    Log.info("main", "起動時ギャップを検出 (最終稼働: \(Log.formatDate(gapStart)))。キャッチアップを実行します")
    scheduler.handleWake(lastSleepDate: gapStart)
}

wakeDetector.start()

Log.info("main", "起動しました (PID: \(ProcessInfo.processInfo.processIdentifier))")

// プロセスを維持（RunLoop で Timer を駆動する）
RunLoop.main.run()
