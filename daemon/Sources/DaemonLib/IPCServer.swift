import Foundation
import Core
#if canImport(Darwin)
import Darwin
#endif

/// Unix Domain Socket ベースの IPC サーバー。
/// GUI からのリクエストを受け付け、ヘルパーの機能を提供する。
public final class IPCServer: @unchecked Sendable {
    private let scheduler: TaskScheduler
    private let logStore: LogStore
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var clientFDs: [Int32] = []
    private var subscriberFDs: [Int32] = []
    private let lock = NSLock()
    public private(set) var isShutdown = false

    /// Shutdown wake pipe: writing to wakeWriteFD unblocks the accept loop.
    private var wakeReadFD: Int32 = -1
    private var wakeWriteFD: Int32 = -1

    public init(scheduler: TaskScheduler, logStore: LogStore, socketPath: String = ConfigPaths.socketPath) {
        self.scheduler = scheduler
        self.logStore = logStore
        self.socketPath = socketPath
    }

    // MARK: - 起動

    public func start() {
        // 既存ソケットファイルを削除
        unlink(socketPath)

        // Create wake pipe for shutdown signaling
        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else {
            Log.info("IPC", "パイプ作成に失敗: \(String(cString: strerror(errno)))")
            return
        }
        wakeReadFD = pipeFDs[0]
        wakeWriteFD = pipeFDs[1]

        // ソケット作成
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            Log.info("IPC", "ソケット作成に失敗: \(String(cString: strerror(errno)))")
            close(wakeReadFD)
            close(wakeWriteFD)
            wakeReadFD = -1
            wakeWriteFD = -1
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

    /// Graceful shutdown: クライアント切断・ソケットファイル削除。
    public func shutdown() {
        lock.lock()
        isShutdown = true

        // Wake the accept loop so it can observe the shutdown flag
        if wakeWriteFD >= 0 {
            var byte: UInt8 = 1
            _ = Darwin.write(wakeWriteFD, &byte, 1)
        }

        // 全クライアント接続を閉じる
        let allFDs = clientFDs + subscriberFDs
        let uniqueFDs = Array(Set(allFDs))
        for fd in uniqueFDs {
            close(fd)
        }
        clientFDs.removeAll()
        subscriberFDs.removeAll()

        // サーバーソケットを閉じる
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }

        // Close wake pipe FDs
        if wakeReadFD >= 0 {
            close(wakeReadFD)
            wakeReadFD = -1
        }
        if wakeWriteFD >= 0 {
            close(wakeWriteFD)
            wakeWriteFD = -1
        }

        lock.unlock()

        // ソケットファイルを削除
        unlink(socketPath)
        Log.info("IPC", "シャットダウン完了: ソケットファイルを削除しました")
    }

    // MARK: - 接続管理

    private func acceptConnections() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                let shutdown = self.isShutdown
                let currentServerFD = self.serverFD
                let currentWakeReadFD = self.wakeReadFD
                self.lock.unlock()

                guard !shutdown, currentServerFD >= 0 else {
                    Log.info("IPC", "サーバーソケットが閉じられました。接続受付を終了します")
                    return
                }

                // Use poll() to wait on both the server socket and the wake pipe
                var pollFDs: [pollfd] = [
                    pollfd(fd: currentServerFD, events: Int16(POLLIN), revents: 0),
                ]
                if currentWakeReadFD >= 0 {
                    pollFDs.append(pollfd(fd: currentWakeReadFD, events: Int16(POLLIN), revents: 0))
                }
                let pollResult = poll(&pollFDs, nfds_t(pollFDs.count), -1)

                guard pollResult > 0 else {
                    // poll interrupted or error
                    if errno == EINTR { continue }
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }

                // Check if wake pipe was signaled (shutdown)
                if pollFDs.count > 1 && (pollFDs[1].revents & Int16(POLLIN)) != 0 {
                    Log.info("IPC", "サーバーソケットが閉じられました。接続受付を終了します")
                    return
                }

                // Check for new connection on the server socket
                guard (pollFDs[0].revents & Int16(POLLIN)) != 0 else { continue }

                var clientAddr = sockaddr_un()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(currentServerFD, sockPtr, &clientAddrLen)
                    }
                }
                guard clientFD >= 0 else {
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
