import Foundation
import Hummingbird
import HummingbirdCore
import MCP
import NIOCore

actor MCPHTTPSession {
    let id: String

    private let server: Server
    private let transport: HTTPServerTransport
    private let notifier: ReminderResourceNotifier
    private let verbose: Bool

    private var serverTask: Task<Void, Never>?
    private var pendingResponses: [Data] = []
    private var responseContinuations: [CheckedContinuation<Data, Error>] = []
    private var pendingSSEPayloads: [Data] = []
    private var streamer: HBByteBufferStreamer?
    private let allocator = ByteBufferAllocator()

    init(id: String, server: Server, transport: HTTPServerTransport, notifier: ReminderResourceNotifier, verbose: Bool) {
        self.id = id
        self.server = server
        self.transport = transport
        self.notifier = notifier
        self.verbose = verbose
    }

    func start() async throws {
        try await transport.connect()

        await transport.setOutboundHandler { data in
            await self.handleOutbound(data)
        }

        serverTask = Task {
            do {
                try await server.start(transport: transport)
            } catch {
                await self.handleServerError(error)
            }
        }
    }

    func enqueueRequest(_ data: Data) async {
        await transport.enqueue(data)
    }

    func waitForResponse() async throws -> Data {
        if let next = pendingResponses.first {
            pendingResponses.removeFirst()
            return next
        }

        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations.append(continuation)
        }
    }

    func attachStreamer(_ streamer: HBByteBufferStreamer) {
        self.streamer = streamer
        sendComment(": connected\n\n")

        if !pendingSSEPayloads.isEmpty {
            for payload in pendingSSEPayloads {
                sendSSE(payload)
            }
            pendingSSEPayloads.removeAll()
        }
    }

    func close() async {
        await transport.disconnect()
        await server.stop()
        notifier.stop()
        serverTask?.cancel()
        serverTask = nil

        let error = MCPError.connectionClosed
        responseContinuations.forEach { $0.resume(throwing: error) }
        responseContinuations.removeAll()
        pendingResponses.removeAll()
        pendingSSEPayloads.removeAll()
        streamer = nil
    }

    private func handleOutbound(_ data: Data) async {
        if let continuation = responseContinuations.first {
            responseContinuations.removeFirst()
            continuation.resume(returning: data)
        } else {
            pendingResponses.append(data)
        }

        sendSSE(data)
    }

    private func sendSSE(_ data: Data) {
        guard let streamer = streamer else {
            pendingSSEPayloads.append(data)
            return
        }

        var buffer = allocator.buffer(capacity: data.count + 16)
        if let string = String(data: data, encoding: .utf8) {
            buffer.writeString("data: ")
            buffer.writeString(string)
        } else {
            buffer.writeString("data: ")
            buffer.writeString(data.base64EncodedString())
        }
        buffer.writeString("\n\n")
        _ = streamer.feed(buffer: buffer)
    }

    private func sendComment(_ text: String) {
        guard let streamer = streamer else { return }
        var buffer = allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        _ = streamer.feed(buffer: buffer)
    }

    private func handleServerError(_ error: Error) async {
        if verbose {
            fputs("[RemindersMCP] server error: \(error)\n", stderr)
        }

        responseContinuations.forEach { $0.resume(throwing: error) }
        responseContinuations.removeAll()
    }
}

public final actor RemindersMCPHTTPHandler {
    private var sessions: [String: MCPHTTPSession] = [:]
    private let reminders: Reminders
    private let verbose: Bool

    public init(reminders: Reminders = Reminders(), verbose: Bool = false) {
        self.reminders = reminders
        self.verbose = verbose
    }

    public func handlePost(_ request: HBRequest) async throws -> HBResponse {
        let body = try await readBody(from: request)
        let suppliedSessionID = request.headers.first(name: "Mcp-Session-Id")

        let session: MCPHTTPSession
        if let suppliedSessionID {
            guard let existing = sessions[suppliedSessionID] else {
                throw HBHTTPError(.notFound, message: "Unknown MCP session")
            }
            session = existing
        } else {
            session = try await createSession()
        }

        await session.enqueueRequest(body)
        let responsePayload: Data

        do {
            responsePayload = try await session.waitForResponse()
        } catch let error as MCPError {
            throw HBHTTPError(.internalServerError, message: error.errorDescription ?? "MCP error")
        } catch {
            throw HBHTTPError(.internalServerError, message: error.localizedDescription)
        }

        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json")
        headers.add(name: "cache-control", value: "no-cache")
        headers.add(name: "Mcp-Session-Id", value: session.id)

        var buffer = request.allocator.buffer(capacity: responsePayload.count)
        buffer.writeBytes(responsePayload)

        return HBResponse(status: .ok, headers: headers, body: .byteBuffer(buffer))
    }

    public func handleStream(_ request: HBRequest) async throws -> HBResponse {
        guard let sessionID = request.headers.first(name: "Mcp-Session-Id") else {
            throw HBHTTPError(.badRequest, message: "Mcp-Session-Id header is required")
        }

        guard let session = sessions[sessionID] else {
            throw HBHTTPError(.notFound, message: "Unknown MCP session")
        }

        let streamer = HBByteBufferStreamer(
            eventLoop: request.eventLoop,
            maxSize: .max,
            maxStreamingBufferSize: 1 << 20
        )
        await session.attachStreamer(streamer)

        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "text/event-stream")
        headers.add(name: "cache-control", value: "no-cache")
        headers.add(name: "connection", value: "keep-alive")
        headers.add(name: "Mcp-Session-Id", value: sessionID)

        return HBResponse(status: .ok, headers: headers, body: .stream(streamer))
    }

    private func createSession() async throws -> MCPHTTPSession {
        let identifier = UUID().uuidString.lowercased()
        let (server, notifier) = await RemindersMCPServerFactory.makeServer(reminders: reminders, verbose: verbose)
        let transport = HTTPServerTransport()
        let session = MCPHTTPSession(
            id: identifier,
            server: server,
            transport: transport,
            notifier: notifier,
            verbose: verbose
        )
        sessions[identifier] = session
        do {
            try await session.start()
        } catch {
            sessions.removeValue(forKey: identifier)
            notifier.stop()
            throw error
        }
        return session
    }

    private func readBody(from request: HBRequest) async throws -> Data {
        if var buffer = request.body.buffer {
            return buffer.readData(length: buffer.readableBytes) ?? Data()
        }

        if var buffer = try await request.body.consumeBody(maxSize: 1 << 20) {
            return buffer.readData(length: buffer.readableBytes) ?? Data()
        }

        return Data()
    }
}
