import Foundation
import Core
#if canImport(Darwin)
import Darwin
#endif

/// Unix Domain Socket ベースの IPC サーバー。
/// GUI からのリクエストを受け付け、ヘルパーの機能を提供する。
final class IPCServer: @unchecked Sendable {
    private let scheduler: TaskScheduler
    private let logStore: LogStore
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var clientFDs: [Int32] = []
    private var subscriberFDs: [Int32] = []
    private let lock = NSLock()

    init(scheduler: TaskScheduler, logStore: LogStore, socketPath: String = ConfigPaths.socketPath) {
        self.scheduler = scheduler
        self.logStore = logStore
        self.socketPath = socketPath
    }

    // MARK: - 起動

    func start() {
        // 既存ソケットファイルを削除
        unlink(socketPath)

        // ソケット作成
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            Log.info("IPC", "ソケット作成に失敗: \(String(cString: strerror(errno)))")
            return
        }

        // バインド
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let pathPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            socketPath.withCString { cstr in
                _ = strncpy(pathPtr, cstr, pathSize - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Log.info("IPC", "バインドに失敗: \(String(cString: strerror(errno)))")
            return
        }

        // リッスン
        guard Darwin.listen(serverFD, 5) == 0 else {
            Log.info("IPC", "リッスンに失敗: \(String(cString: strerror(errno)))")
            return
        }

        // 通知コールバック設定
        scheduler.onNotification = { [weak self] notification in
            self?.broadcastNotification(notification)
        }

        // 接続受付を開始
        acceptConnections()
        Log.info("IPC", "待ち受け開始: \(socketPath)")
    }

    // MARK: - 接続管理

    private func acceptConnections() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let currentServerFD = self.serverFD
                self.lock.unlock()

                guard currentServerFD >= 0 else {
                    Log.info("IPC", "サーバーソケットが閉じられました。接続受付を終了します")
                    return
                }

                var clientAddr = sockaddr_un()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(currentServerFD, sockPtr, &clientAddrLen)
                    }
                }
                guard clientFD >= 0 else {
                    // accept が失敗した場合、短時間待って再試行
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }

                self.lock.lock()
                self.clientFDs.append(clientFD)
                self.lock.unlock()

                self.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var buffer = Data()
            let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
            defer { readBuffer.deallocate() }

            while true {
                let bytesRead = read(fd, readBuffer, 65536)
                guard bytesRead > 0 else { break }
                buffer.append(readBuffer, count: bytesRead)

                // メッセージ境界でパース
                while let messageData = IPCWireFormat.readMessage(from: &buffer) {
                    guard let request = try? IPCWireFormat.decode(IPCRequest.self, from: messageData) else {
                        continue
                    }
                    let response = self.handleRequest(request, clientFD: fd)
                    if let data = try? IPCWireFormat.encode(response) {
                        let written = data.withUnsafeBytes { ptr in
                            write(fd, ptr.baseAddress!, data.count)
                        }
                        if written <= 0 { break }
                    }
                }
            }

            // 接続終了
            close(fd)
            self.lock.lock()
            self.clientFDs.removeAll { $0 == fd }
            self.subscriberFDs.removeAll { $0 == fd }
            self.lock.unlock()
        }
    }

    // MARK: - リクエスト処理

    private func handleRequest(_ request: IPCRequest, clientFD: Int32) -> IPCResponse {
        switch request.action {
        case "list_tasks":
            let statuses = scheduler.allTaskStatuses()
            return IPCResponse(tasks: statuses)

        case "run_task":
            guard let taskId = request.taskId else {
                return .error("task_id が必要です")
            }
            scheduler.runTaskNow(taskId)
            return .ok

        case "stop_task":
            guard let taskId = request.taskId else {
                return .error("task_id が必要です")
            }
            scheduler.stopTask(taskId)
            return .ok

        case "get_history":
            let limit = request.limit ?? 50
            let history: [ExecutionRecord]
            if let taskId = request.taskId {
                history = logStore.history(taskId: taskId, limit: limit)
            } else {
                history = logStore.timeline(limit: limit)
            }
            return IPCResponse(history: history)

        case "reload":
            scheduler.reloadTasks()
            return .ok

        case "get_settings":
            let settings = scheduler.loadSettings()
            return IPCResponse(settings: settings)

        case "update_settings":
            guard let settings = request.settings else {
                return .error("settings が必要です")
            }
            do {
                try scheduler.saveSettings(settings)
                return .ok
            } catch {
                return .error(error.localizedDescription)
            }

        case "save_task":
            guard let task = request.task else {
                return .error("task が必要です")
            }
            do {
                try scheduler.saveTask(task)
                return .ok
            } catch {
                return .error(error.localizedDescription)
            }

        case "delete_task":
            guard let taskId = request.taskId else {
                return .error("task_id が必要です")
            }
            do {
                try scheduler.deleteTask(taskId)
                return .ok
            } catch {
                return .error(error.localizedDescription)
            }

        case "toggle_task":
            guard let taskId = request.taskId else {
                return .error("task_id が必要です")
            }
            scheduler.toggleTask(taskId)
            return .ok

        case "subscribe":
            lock.lock()
            subscriberFDs.append(clientFD)
            lock.unlock()
            return .ok

        default:
            return .error("不明なアクション: \(request.action)")
        }
    }

    // MARK: - 通知ブロードキャスト

    private func broadcastNotification(_ notification: IPCNotification) {
        guard let data = try? IPCWireFormat.encode(notification) else { return }

        lock.lock()
        let subscribers = subscriberFDs
        lock.unlock()

        var deadFDs: [Int32] = []
        for fd in subscribers {
            let written = data.withUnsafeBytes { ptr in
                write(fd, ptr.baseAddress!, data.count)
            }
            if written <= 0 { deadFDs.append(fd) }
        }

        if !deadFDs.isEmpty {
            lock.lock()
            subscriberFDs.removeAll { deadFDs.contains($0) }
            lock.unlock()
        }
    }
}
