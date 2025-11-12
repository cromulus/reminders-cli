import AsyncHTTPClient
import Hummingbird
import Logging
import NIOCore
import NIOHTTP1

struct MCPProxy {
    private let prefixes: [String]
    private let baseURL: String
    private let hostHeader: String
    private let httpClient: HTTPClient
    private let logger: Logger
    private let maxBodySize: Int

    init(
        baseURL: String,
        hostHeader: String,
        serverPath: String?,
        httpClient: HTTPClient,
        logger: Logger,
        maxBodySize: Int = 5 * 1024 * 1024
    ) {
        self.baseURL = baseURL.dropSuffix("/")
        self.hostHeader = hostHeader
        self.httpClient = httpClient
        self.logger = logger
        self.maxBodySize = maxBodySize

        var paths = [
            "/mcp",
            "/messages",
            "/sse",
            "/.well-known",
            "/oauth",
            "/authorize",
            "/userinfo",
            "/openapi.json"
        ]

        if let serverPath = serverPath {
            paths.append(serverPath)
        }

        self.prefixes = paths
    }

    func shouldHandle(path: String) -> Bool {
        for prefix in prefixes {
            if path == prefix || path.hasPrefix(prefix.appendingSlashIfNeeded()) {
                return true
            }
        }
        return false
    }

    func forward(_ request: HBRequest) async throws -> HBResponse {
        let targetURL = "\(baseURL)\(request.uri.string)"

        var clientRequest = HTTPClientRequest(url: targetURL)
        clientRequest.method = request.method
        clientRequest.headers = request.headers
        clientRequest.headers.replaceOrAdd(name: "Host", value: hostHeader)

        if let bodyBuffer = try await request.body.consumeBody(maxSize: maxBodySize) {
            clientRequest.body = .bytes(bodyBuffer)
        }

        logger.debug("Proxying MCP request \(request.method) \(request.uri.path)")
        let response = try await httpClient.execute(clientRequest, timeout: .seconds(120))

        var headers = response.headers
        headers.remove(name: "connection")
        headers.remove(name: "keep-alive")

        let status = HTTPResponseStatus(statusCode: Int(response.status.code))
        let responseBody = HBResponseBody.streaming(from: response.body)
        return HBResponse(status: status, headers: headers, body: responseBody)
    }
}

struct MCPProxyMiddleware: HBMiddleware {
    let proxy: MCPProxy

    func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
        guard proxy.shouldHandle(path: request.uri.path) else {
            return next.respond(to: request)
        }

        return request.eventLoop.makeFutureWithTask {
            try await proxy.forward(request)
        }
    }
}

private final class HTTPClientBodyStreamer: HBStreamerProtocol {
    private let iterator: HTTPClientBodyIterator

    init(body: HTTPClientResponse.Body) {
        self.iterator = HTTPClientBodyIterator(body: body)
    }

    func consume(on eventLoop: EventLoop) -> EventLoopFuture<HBStreamerOutput> {
        let promise = eventLoop.makePromise(of: HBStreamerOutput.self)
        Task {
            do {
                if let chunk = try await iterator.next() {
                    promise.succeed(.byteBuffer(chunk))
                } else {
                    promise.succeed(.end)
                }
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }

    func consumeAll(on eventLoop: EventLoop, _ process: @escaping (ByteBuffer) -> EventLoopFuture<Void>) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)

        func loop() {
            consume(on: eventLoop).whenComplete { result in
                switch result {
                case .success(.byteBuffer(let buffer)):
                    process(buffer).whenComplete { continuation in
                        switch continuation {
                        case .success:
                            loop()
                        case .failure(let error):
                            promise.fail(error)
                        }
                    }
                case .success(.end):
                    promise.succeed(())
                case .failure(let error):
                    promise.fail(error)
                }
            }
        }

        loop()
        return promise.futureResult
    }

    func consume() async throws -> HBStreamerOutput {
        if let chunk = try await iterator.next() {
            return .byteBuffer(chunk)
        } else {
            return .end
        }
    }
}

private actor HTTPClientBodyIterator {
    var iterator: HTTPClientResponse.Body.AsyncIterator

    init(body: HTTPClientResponse.Body) {
        self.iterator = body.makeAsyncIterator()
    }

    func next() async throws -> ByteBuffer? {
        var localIterator = iterator
        let result = try await localIterator.next()
        iterator = localIterator
        return result
    }
}

private extension HBResponseBody {
    static func streaming(from body: HTTPClientResponse.Body) -> HBResponseBody {
        .stream(HTTPClientBodyStreamer(body: body))
    }
}

private extension EventLoop {
    func makeFutureWithTask<T: Sendable>(
        priority: TaskPriority? = nil,
        _ operation: @escaping @Sendable () async throws -> T
    ) -> EventLoopFuture<T> {
        let promise = makePromise(of: T.self)
        Task(priority: priority) {
            do {
                let result = try await operation()
                promise.succeed(result)
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
}

private extension String {
    func dropSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func appendingSlashIfNeeded() -> String {
        if hasSuffix("/") {
            return self
        } else {
            return self + "/"
        }
    }
}
