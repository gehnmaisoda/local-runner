import Foundation
import Core

public struct QueueMessage: Sendable, Equatable {
    public let body: String
    public let id: String
    public let attempts: Int
    public let leaseId: String
    public let contentType: String?
}

public protocol QueueTransporting: Sendable {
    func pull(completion: @escaping @Sendable (Result<[QueueMessage], Error>) -> Void)
    func acknowledge(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void)
    func retry(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void)
}

public enum QueueTransportError: Error, CustomStringConvertible {
    case invalidResponse
    case api(status: Int, message: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "Cloudflare Queues から不正なレスポンスを受信しました"
        case .api(let status, let message):
            return "Cloudflare Queues API error (HTTP \(status)): \(message)"
        }
    }
}

/// Cloudflare Queues REST API の HTTP Pull / ack だけを扱う薄いクライアント。
public final class CloudflareQueueTransport: QueueTransporting, @unchecked Sendable {
    private let configuration: QueueConfiguration
    private let session: URLSession

    public init(configuration: QueueConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func pull(completion: @escaping @Sendable (Result<[QueueMessage], Error>) -> Void) {
        let body: [String: Any] = [
            "visibility_timeout_ms": configuration.effectiveVisibilityTimeoutMilliseconds,
            "batch_size": 1,
        ]
        request(path: "pull", body: body) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(PullResponse.self, from: data)
                    guard response.success else {
                        completion(.failure(QueueTransportError.api(status: 200, message: response.errorMessage)))
                        return
                    }
                    completion(.success(response.result?.messages.map { $0.message } ?? []))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    public func acknowledge(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        acknowledge(acks: [["lease_id": leaseId]], retries: [], completion: completion)
    }

    public func retry(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        let retry: [String: Any] = [
            "lease_id": leaseId,
            "delay_seconds": configuration.effectiveRetryDelay,
        ]
        acknowledge(acks: [], retries: [retry], completion: completion)
    }

    private func acknowledge(
        acks: [[String: Any]],
        retries: [[String: Any]],
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        request(path: "ack", body: ["acks": acks, "retries": retries]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(BasicResponse.self, from: data)
                    if response.success {
                        completion(.success(()))
                    } else {
                        completion(.failure(QueueTransportError.api(status: 200, message: response.errorMessage)))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func request(
        path: String,
        body: [String: Any],
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(configuration.accountId)/queues/\(configuration.queueId)/messages/\(path)") else {
            completion(.failure(QueueTransportError.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(QueueTransportError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown"
                completion(.failure(QueueTransportError.api(status: http.statusCode, message: message)))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

private struct PullResponse: Decodable {
    let success: Bool
    let errors: [APIError]?
    let result: PullResult?

    var errorMessage: String { errors?.map(\.message).joined(separator: ", ") ?? "unknown" }
}

private struct PullResult: Decodable {
    let messages: [PulledMessage]
}

private struct PulledMessage: Decodable {
    let body: String
    let id: String
    let attempts: Int
    let leaseId: String
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case body, id, attempts, metadata
        case leaseId = "lease_id"
    }

    var message: QueueMessage {
        QueueMessage(
            body: body,
            id: id,
            attempts: attempts,
            leaseId: leaseId,
            contentType: metadata?["CF-Content-Type"]
        )
    }
}

private struct BasicResponse: Decodable {
    let success: Bool
    let errors: [APIError]?

    var errorMessage: String { errors?.map(\.message).joined(separator: ", ") ?? "unknown" }
}

private struct APIError: Decodable {
    let message: String
}
