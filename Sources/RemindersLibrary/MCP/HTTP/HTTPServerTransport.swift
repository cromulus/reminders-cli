import Foundation
import Logging
import MCP
import NIOCore

actor HTTPServerTransport: Transport {
    nonisolated let logger: Logging.Logger

    private var isConnected = false
    private var messageStream: AsyncThrowingStream<Data, Error>?
    private var streamContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    private var outboundHandler: ((Data) async -> Void)?
    private var bufferedOutbound: [Data] = []

    init(logger: Logging.Logger = Logging.Logger(label: "reminders.mcp.transport.http")) {
        self.logger = logger
    }

    func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        let stream = AsyncThrowingStream<Data, Error> { continuation = $0 }
        self.messageStream = stream
        self.streamContinuation = continuation
        logger.trace("HTTP transport connected")
    }

    func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        streamContinuation?.finish()
        streamContinuation = nil
        messageStream = nil
        bufferedOutbound.removeAll()
        logger.trace("HTTP transport disconnected")
    }

    func send(_ data: Data) async throws {
        if let handler = outboundHandler {
            await handler(data)
        } else {
            bufferedOutbound.append(data)
        }
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        messageStream ?? AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func enqueue(_ data: Data) {
        streamContinuation?.yield(data)
    }

    func setOutboundHandler(_ handler: @escaping (Data) async -> Void) async {
        outboundHandler = handler
        if !bufferedOutbound.isEmpty {
            let pending = bufferedOutbound
            bufferedOutbound.removeAll()
            for data in pending {
                await handler(data)
            }
        }
    }
}
