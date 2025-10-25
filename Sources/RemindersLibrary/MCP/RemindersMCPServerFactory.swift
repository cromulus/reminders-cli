import Foundation
import MCP

public enum RemindersMCPServerFactory {
    private static let serverName = "reminders-mcp"
    private static let serverVersion = "0.1.0"

    public static func makeServer(reminders: Reminders = Reminders(), verbose: Bool = false) async -> Server {
        let context = RemindersMCPContext(reminders: reminders, verbose: verbose)
        let capabilities = Server.Capabilities(
            logging: .init(),
            resources: .init(subscribe: false, listChanged: false),
            tools: .init(listChanged: false)
        )

        let server = Server(
            name: serverName,
            version: serverVersion,
            instructions: """
            Access and manage your Apple Reminders, lists, and advanced search capabilities.
            Use the `lists` tool to enumerate lists, `reminders` for CRUD operations,
            and the `search` tool for complex filtering.
            """,
            capabilities: capabilities
        )

        await registerHandlers(server: server, context: context)
        return server
    }

    private static func registerHandlers(server: Server, context: RemindersMCPContext) async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: context.listTools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let contents = try await context.handleToolCall(
                    name: params.name,
                    arguments: params.arguments
                )
                return CallTool.Result(content: contents)
            } catch let error as RemindersMCPError {
                throw error.mcpError
            } catch let error as MCPError {
                throw error
            } catch {
                throw MCPError.internalError(error.localizedDescription)
            }
        }

        await server.withMethodHandler(ListResources.self) { _ in
            do {
                let resources = try context.listResources()
                return ListResources.Result(resources: resources)
            } catch let error as RemindersMCPError {
                throw error.mcpError
            } catch let error as MCPError {
                throw error
            } catch {
                throw MCPError.internalError(error.localizedDescription)
            }
        }

        await server.withMethodHandler(ReadResource.self) { params in
            do {
                let contents = try await context.readResource(uri: params.uri)
                return ReadResource.Result(contents: contents)
            } catch let error as RemindersMCPError {
                throw error.mcpError
            } catch let error as MCPError {
                throw error
            } catch {
                throw MCPError.internalError(error.localizedDescription)
            }
        }
    }
}
