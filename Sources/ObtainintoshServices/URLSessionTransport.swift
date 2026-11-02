#if canImport(Darwin)
import Foundation
import ObtainintoshCore

/// The live transport: one ephemeral URLSession whose delegate streams each
/// response body in the chunks the network delivers, so downloads report
/// progress, range reads stop early and cancelling the consuming task
/// cancels the request.
///
/// No cookies, no credential store and no cache: every request carries
/// exactly the headers its client set. A redirect that leaves the request's
/// origin loses its `Authorization` header, so a forge credential never
/// reaches a CDN or another host.
public final class URLSessionTransport: NSObject, HTTPTransport, URLSessionDataDelegate, @unchecked Sendable {
    public static let shared = URLSessionTransport()

    private struct Pending {
        var head: CheckedContinuation<HTTPURLResponse, Error>?
        let body: AsyncThrowingStream<Data, Error>.Continuation
    }

    private let lock = NSLock()
    /// Tasks in flight by identifier. Guarded by `lock`.
    private var pending: [Int: Pending] = [:]
    private var session: URLSession!

    override public init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func stream(_ request: URLRequest) async throws -> HTTPStream {
        let (body, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let task = session.dataTask(with: request)
        continuation.onTermination = { @Sendable _ in task.cancel() }

        let response: HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { head in
                lock.withLock { pending[task.taskIdentifier] = Pending(head: head, body: continuation) }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HTTPStream(status: response.statusCode, headers: headers, body: body, cancel: { task.cancel() })
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let head = lock.withLock { () -> CheckedContinuation<HTTPURLResponse, Error>? in
            let head = pending[dataTask.taskIdentifier]?.head
            pending[dataTask.taskIdentifier]?.head = nil
            return head
        }
        guard let http = response as? HTTPURLResponse else {
            head?.resume(throwing: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        head?.resume(returning: http)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let body = lock.withLock { pending[dataTask.taskIdentifier]?.body }
        body?.yield(data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let finished = lock.withLock { pending.removeValue(forKey: task.taskIdentifier) }
        finished?.head?.resume(throwing: error ?? URLError(.badServerResponse))
        if let error {
            finished?.body.finish(throwing: error)
        } else {
            finished?.body.finish()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        let origin = task.originalRequest?.url?.absoluteString ?? ""
        if let target = request.url?.absoluteString, !RepositoryURL.sameOrigin(target, origin) {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}
#endif
