import Foundation
import Network

/// ネットワーク接続状態の抽象インターフェース。テスト時にモック差し替え可能。
public protocol NetworkChecking: Sendable {
    var isConnected: Bool { get }
    var onRestore: (() -> Void)? { get set }
    func start()
    func stop()
}

/// NWPathMonitor をラップし、ネットワーク接続状態をイベント駆動で監視する。
public final class NetworkMonitor: NetworkChecking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gehnmaisoda.local-runner.network")
    private let lock = NSLock()
    private var _isConnected = true
    private var _onRestore: (() -> Void)?

    public init() {}

    /// 現在のネットワーク接続状態。
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    /// ネットワーク復帰時に呼ばれるコールバック。
    public var onRestore: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRestore }
        set { lock.lock(); _onRestore = newValue; lock.unlock() }
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let wasDisconnected: Bool
            self.lock.lock()
            wasDisconnected = !self._isConnected
            self._isConnected = connected
            let callback = self._onRestore
            self.lock.unlock()

            if connected {
                if wasDisconnected {
                    Log.info("Network", "ネットワーク接続が復帰しました")
                    callback?()
                }
            } else {
                Log.info("Network", "ネットワーク接続が切断されました")
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}
