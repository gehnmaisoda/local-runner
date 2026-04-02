import Foundation
import Core
import DaemonLib

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

// MARK: - Graceful shutdown

/// シグナルソースを保持する（GC されないようにグローバルで参照を持つ）。
nonisolated(unsafe) var signalSources: [any DispatchSourceSignal] = []

/// シグナルをディスパッチソースで受け取り、安全にシャットダウンする。
func installSignalHandler(signal sig: Int32) {
    // シグナルのデフォルト動作を無効化
    Foundation.signal(sig, SIG_IGN)

    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        Log.info("main", "シグナル \(sig) を受信。シャットダウンを開始します...")
        scheduler.shutdown()
        ipcServer.shutdown()
        Log.info("main", "シャットダウン完了。終了します")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

installSignalHandler(signal: SIGTERM)
installSignalHandler(signal: SIGINT)

Log.info("main", "起動しました v\(AppVersion.current) (PID: \(ProcessInfo.processInfo.processIdentifier))")

// プロセスを維持（RunLoop で Timer を駆動する）
RunLoop.main.run()
