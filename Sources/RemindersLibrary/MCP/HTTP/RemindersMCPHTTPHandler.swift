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
    private var clientSessionMap: [String: String] = [:]
    private let reminders: Reminders
    private let verbose: Bool
    private var nextGeneratedRequestID: Int = 1

    public init(reminders: Reminders = Reminders(), verbose: Bool = false) {
        self.reminders = reminders
        self.verbose = verbose
    }

    public func handlePost(_ request: HBRequest) async throws -> HBResponse {
        let body = try await readBody(from: request)
        guard let normalization = normalizeJSONRPCPayload(body) else {
            return makeErrorResponse(
                id: nil,
                code: -32700,
                message: "Parse error: Invalid JSON",
                querySessionID: request.uri.queryParameters.get("sessionId")
            )
        }

        let normalizedBody = normalization.data
        guard let methodName = normalization.method else {
            return makeErrorResponse(
                id: normalization.id,
                code: -32600,
                message: "Invalid Request: missing method",
                querySessionID: request.uri.queryParameters.get("sessionId")
            )
        }
        let requestID = normalization.id
        let suppliedSessionID = request.headers.first(name: "Mcp-Session-Id")
        let querySessionID = request.uri.queryParameters.get("sessionId")
        var resolvedSessionID = resolveSessionIdentifier(header: suppliedSessionID, query: querySessionID)

        if resolvedSessionID == nil {
            if methodName == Ping.name {
                return makeImmediateResponse(id: requestID, querySessionID: querySessionID)
            }

            if methodName != Initialize.name {
                return makeErrorResponse(
                    id: requestID,
                    code: -32600,
                    message: "Invalid Request: session not initialized",
                    querySessionID: querySessionID
                )
            }
        }

        let session: MCPHTTPSession
        if let existingID = resolvedSessionID {
            guard let existing = sessions[existingID] else {
                throw HBHTTPError(.notFound, message: "Unknown MCP session")
            }
            session = existing
        } else {
            session = try await createSession()
            resolvedSessionID = session.id
            if let querySessionID {
                clientSessionMap[querySessionID] = session.id
            }
        }

        await session.enqueueRequest(normalizedBody)
        let responsePayload: Data

        do {
            responsePayload = try await session.waitForResponse()
        } catch let error as MCPError {
            throw HBHTTPError(.internalServerError, message: error.errorDescription ?? "MCP error")
        } catch {
            throw HBHTTPError(.internalServerError, message: error.localizedDescription)
        }

        return makeSuccessResponse(
            payload: responsePayload,
            sessionID: resolvedSessionID ?? session.id,
            querySessionID: querySessionID,
            allocator: request.allocator
        )
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

    public func handleDelete(_ request: HBRequest) async throws -> HBResponse {
        let sessionID = request.headers.first(name: "Mcp-Session-Id")
            ?? request.uri.queryParameters.get("sessionId")

        guard let sessionID else {
            throw HBHTTPError(.notFound, message: "Unknown MCP session")
        }

        let resolvedSessionID = sessions[sessionID] != nil
            ? sessionID
            : clientSessionMap[sessionID]

        guard let resolvedSessionID, let session = sessions.removeValue(forKey: resolvedSessionID) else {
            throw HBHTTPError(.notFound, message: "Unknown MCP session")
        }

        clientSessionMap = clientSessionMap.filter { $0.value != resolvedSessionID }

        await session.close()

        var headers = HTTPHeaders()
        headers.add(name: "Mcp-Session-Id", value: resolvedSessionID)
        return HBResponse(status: .noContent, headers: headers, body: .empty)
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

    private func normalizeJSONRPCPayload(_ body: Data) -> (data: Data, method: String?, id: Any?)? {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body),
              var payload = object as? [String: Any]
        else {
            return nil
        }

        let method = payload["method"] as? String
        var requestID = payload["id"]

        if payload["jsonrpc"] == nil {
            payload["jsonrpc"] = "2.0"
        }

        if payload["id"] == nil {
            payload["id"] = nextGeneratedRequestID
            nextGeneratedRequestID += 1
            requestID = payload["id"]
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            return (data, method, requestID)
        }

        return nil
    }

    private func makeImmediateResponse(id: Any?, querySessionID: String?) -> HBResponse {
        let headers = commonHeaders(sessionID: nil, querySessionID: querySessionID)
        let identifier: Any
        if let id {
            identifier = id
        } else {
            identifier = nextGeneratedRequestID
            nextGeneratedRequestID += 1
        }
        let responseObject: [String: Any] = [
            "jsonrpc": "2.0",
            "id": identifier,
            "result": [:]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: responseObject)) ?? Data()
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return HBResponse(status: .ok, headers: headers, body: .byteBuffer(buffer))
    }

    private func makeSuccessResponse(
        payload: Data,
        sessionID: String,
        querySessionID: String?,
        allocator: ByteBufferAllocator
    ) -> HBResponse {
        let headers = commonHeaders(sessionID: sessionID, querySessionID: querySessionID)
        var buffer = allocator.buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        return HBResponse(status: .ok, headers: headers, body: .byteBuffer(buffer))
    }

    private func commonHeaders(sessionID: String?, querySessionID: String?) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "content-type", value: "application/json")
        headers.add(name: "cache-control", value: "no-cache")
        if let sessionID {
            headers.add(name: "Mcp-Session-Id", value: sessionID)
        }
        if let querySessionID {
            headers.add(name: "Mcp-Client-Session-Id", value: querySessionID)
        }
        return headers
    }

    private func makeErrorResponse(
        id: Any?,
        code: Int,
        message: String,
        querySessionID: String?
    ) -> HBResponse {
        let headers = commonHeaders(sessionID: nil, querySessionID: querySessionID)
        let responseObject: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: responseObject)) ?? Data()
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return HBResponse(status: .ok, headers: headers, body: .byteBuffer(buffer))
    }

    private func resolveSessionIdentifier(header: String?, query: String?) -> String? {
        if let header {
            if sessions[header] != nil {
                return header
            }
            if let mapped = clientSessionMap[header] {
                return mapped
            }
        }

        if let query {
            if sessions[query] != nil {
                return query
            }
            if let mapped = clientSessionMap[query] {
                return mapped
            }
        }

        return nil
    }
}
