import AsyncHTTPClient
import Hummingbird
import Logging
import RemindersMCPKit

/// Minimal HTTP proxy that fronts the SwiftMCP HTTPSSE transport so we can
/// strip Streamable HTTP headers for SSE clients (e.g., MCP Inspector).
final class MCPProxyServer {
    private let app: HBApplication
    private let httpClient: HTTPClient
    private let logger: Logger
    private let listenHost: String

    init(
        listenHost: String,
        listenPort: Int,
        backendBaseURL: String,
        backendHostHeader: String,
        logger: Logger,
        maxBodySize: Int = 5 * 1024 * 1024
    ) {
        self.logger = logger
        self.listenHost = listenHost

        let configuration = HBApplication.Configuration(
            address: .hostname(listenHost, port: listenPort),
            serverName: "reminders-mcp-proxy"
        )
        self.app = HBApplication(configuration: configuration)
        self.app.logger = logger

        self.httpClient = HTTPClient(
            eventLoopGroupProvider: .createNew,
            configuration: HTTPClient.Configuration(timeout: .init(connect: .seconds(10)))
        )

        let proxy = MCPProxy(
            baseURL: backendBaseURL,
            hostHeader: backendHostHeader,
            serverPath: nil,
            httpClient: httpClient,
            logger: logger,
            maxBodySize: maxBodySize
        )

        self.app.middleware.add(MCPProxyMiddleware(proxy: proxy))

        // Provide a basic health endpoint for smoke tests.
        self.app.router.get("healthz") { _ in
            return "ok"
        }
    }

    func start() throws {
        try app.start()
        if let port = app.server.port {
            logger.info("Proxy listening on \(listenHost):\(port)")
        }
    }

    func wait() {
        app.wait()
    }

    func shutdown() async {
        app.stop()
        do {
            try await httpClient.shutdown()
        } catch {
            logger.warning("Failed to shut down proxy HTTP client: \(error.localizedDescription)")
        }
    }

    var listeningPort: Int? {
        app.server.port
    }
}
