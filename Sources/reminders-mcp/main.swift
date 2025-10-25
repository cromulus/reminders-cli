
import ArgumentParser
import Foundation
import Hummingbird
import MCP
import RemindersLibrary

@main
struct RemindersMCP: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reminders-mcp",
        abstract: "MCP server for Apple Reminders",
        discussion: "Provides MCP protocol access to your macOS Reminders data."
    )

    enum TransportKind: String, ExpressibleByArgument {
        case stdio
        case http
    }

    @Option(name: [.customLong("transport")], help: "Transport type (stdio or http)")
    var transport: TransportKind = .stdio

    @Option(name: [.customShort("p"), .customLong("port")], help: "Port for HTTP transport")
    var port: Int = 8090

    @Option(name: [.customLong("host")], help: "Hostname for HTTP transport")
    var hostname: String = "127.0.0.1"

    @Flag(name: [.customLong("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    func run() async throws {
        print("Requesting Reminders access...")
        let (granted, error) = Reminders.requestAccess()

        guard granted else {
            print("Error: Reminders access denied")
            if let error {
                print("Error: \(error.localizedDescription)")
            }
            print("Grant access in System Preferences > Privacy & Security > Reminders")
            throw ExitCode.failure
        }

        print("Reminders access granted")
        let reminders = Reminders()

        switch transport {
        case .stdio:
            try await runStdio(reminders: reminders)
        case .http:
            try await runHTTP(reminders: reminders)
        }
    }

    private func runStdio(reminders: Reminders) async throws {
        let (server, notifier) = await RemindersMCPServerFactory.makeServer(reminders: reminders, verbose: verbose)
        let transport = MCP.StdioTransport()
        defer { notifier.stop() }
        try await server.start(transport: transport)
        print("reminders-mcp running with stdio transport")
        await server.waitUntilCompleted()
    }

    private func runHTTP(reminders: Reminders) async throws {
        let handler = RemindersMCPHTTPHandler(reminders: reminders, verbose: verbose)
        let configuration = HBApplication.Configuration(
            address: .hostname(hostname, port: port),
            serverName: "RemindersMCP"
        )
        let app = HBApplication(configuration: configuration)

        app.middleware.add(
            HBCORSMiddleware(
                allowOrigin: .all,
                allowHeaders: ["Content-Type", "Mcp-Session-Id"],
                allowMethods: [.GET, .POST]
            )
        )

        app.router.post("mcp") { request in
            try await handler.handlePost(request)
        }

        app.router.get("mcp") { request in
            try await handler.handleStream(request)
        }

        try app.start()
        print("reminders-mcp HTTP transport running at http://\(hostname):\(port)/mcp")
        app.wait()
    }
}
