import ArgumentParser
import Foundation
import RemindersLibrary
import RemindersMCPKit
import SwiftMCP

@main
struct RemindersMCP: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reminders-mcp",
        abstract: "MCP server for Apple Reminders",
        discussion: "Provides MCP protocol access to your macOS Reminders data via SwiftMCP framework."
    )

    enum TransportKind: String, ExpressibleByArgument {
        case stdio
        case httpsse
    }

    @Option(name: [.customLong("transport")], help: "Transport type (stdio or httpsse)")
    var transport: TransportKind = .stdio

    @Option(name: [.customShort("p"), .customLong("port")], help: "Port for HTTP+SSE transport")
    var port: Int = 8090

    @Option(name: [.customLong("host")], help: "Hostname for HTTP+SSE transport")
    var hostname: String = "127.0.0.1"

    @Flag(name: [.customLong("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    @Option(name: [.customLong("token")], help: "Bearer token for HTTP+SSE authentication")
    var token: String?

    func run() async throws {
        // Suppress startup chatter for stdio (MCP transports interpret stdout/stderr strictly)
        // Allow verbose logging everywhere else, or when explicitly requested.
        let transportMode = transport
        let log: (String) -> Void = { message in
            guard self.verbose || transportMode != .stdio else { return }
            fputs("\(message)\n", stderr)
        }
        let criticalLog: (String) -> Void = { message in
            fputs("\(message)\n", stderr)
        }

        log("Requesting Reminders access...")
        let (granted, error) = Reminders.requestAccess()

        guard granted else {
            criticalLog("Error: Reminders access denied")
            if let error {
                criticalLog("Error: \(error.localizedDescription)")
            }
            criticalLog("Grant access in System Preferences > Privacy & Security > Reminders")
            throw ExitCode.failure
        }

        log("Reminders access granted")

        // Create MCP server
        let server = RemindersMCPServer(verbose: verbose)

        // Start appropriate transport
        switch transport {
        case .stdio:
            log("Starting MCP server with stdio transport...")
            let transport = StdioTransport(server: server)
            try await transport.run()

        case .httpsse:
            log("Starting MCP server with HTTP+SSE transport on \(hostname):\(port)...")
            let transport = HTTPSSETransport(server: server, host: hostname, port: port)

            if let token = token {
                transport.authorizationHandler = { providedToken in
                    guard let providedToken, providedToken == token else {
                        return .unauthorized("Invalid token")
                    }
                    return .authorized
                }
                log("Bearer token authentication enabled")
            }

            try await transport.run()
        }
    }
}
