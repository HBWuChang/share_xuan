import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket

public final class TransferServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var listener: Channel?
    private let lock = NSLock()
    private var peers: [ObjectIdentifier: Channel] = [:]
    private var connections: [ObjectIdentifier: Channel] = [:]
    private var offered: [URL] = []
    public let inbox: URL
    public let temporary: URL
    public let deviceID: String
    public var onText: ((String) -> Void)?
    public var onFiles: (([URL]) -> Void)?
    public var onPeers: ((Int) -> Void)?
    public var onError: ((String) -> Void)?
    public init(inbox: URL, temporary: URL, deviceID: String) {
        self.inbox = inbox; self.temporary = temporary; self.deviceID = deviceID
    }
    deinit { group.shutdownGracefully { _ in } }
    public func start(port: Int) async throws {
        guard listener == nil else { return }
        try FileTools.directory(inbox); try FileTools.directory(temporary)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 32)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self else { return channel.close() }
                self.lock.lock(); self.connections[ObjectIdentifier(channel)] = channel; self.lock.unlock()
                channel.closeFuture.whenComplete { [weak self, weak channel] _ in
                    guard let self, let channel else { return }
                    self.lock.lock(); self.connections.removeValue(forKey: ObjectIdentifier(channel)); self.lock.unlock()
                }
                let http = HTTPTransferHandler(server: self)
                let upgrader = NIOWebSocketServerUpgrader(maxFrameSize: 1024 * 1024, automaticErrorHandling: true,
                    shouldUpgrade: { channel, head in
                        channel.eventLoop.makeSucceededFuture(["/", "/ws"].contains(head.uri) ? HTTPHeaders() : nil)
                    }, upgradePipelineHandler: { channel, _ in
                        channel.pipeline.addHandler(SocketHandler(server: self))
                    })
                let configuration: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader], completionHandler: { context in
                        context.pipeline.syncOperations.removeHandler(http, promise: nil)
                    })
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: configuration).flatMap {
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandlers(IdleStateHandler(readTimeout: .seconds(120)), http)
                    }
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
        // The IPv6 listener accepts IPv4-mapped connections on Apple platforms.
        do { listener = try await bootstrap.bind(host: "::", port: port).get() }
        catch { listener = try await bootstrap.bind(host: "0.0.0.0", port: port).get() }
    }
    public func stop() async {
        let channel = listener; listener = nil
        try? await channel?.close().get()
        for connection in allConnections() { try? await connection.close().get() }
        lock.withLock { offered = [] }
    }
    private func allConnections() -> [Channel] { lock.withLock { Array(connections.values) } }
    fileprivate func register(_ channel: Channel) {
        let count = lock.withLock { peers[ObjectIdentifier(channel)] = channel; return peers.count }
        onPeers?(count)
    }
    fileprivate func unregister(_ channel: Channel) {
        let count = lock.withLock { peers.removeValue(forKey: ObjectIdentifier(channel)); return peers.count }
        onPeers?(count)
    }
    fileprivate func files() -> [URL] { lock.withLock { offered } }
    public func offer(files: [URL]) throws {
        guard !files.isEmpty else { throw TransferError.invalid("请选择文件") }
        let channels: [Channel] = lock.withLock { offered = files; return Array(peers.values) }
        guard !channels.isEmpty else { throw TransferError.invalid("尚无客户端连接") }
        let message = WireMessage("reqToGetFile", WireMessage.json(files.map(\.lastPathComponent)))
        for channel in channels { Self.send(message, to: channel) }
    }
    public func send(text: String) throws {
        let channels = lock.withLock { Array(peers.values) }
        guard !channels.isEmpty else { throw TransferError.invalid("尚无客户端连接") }
        for channel in channels { Self.send(WireMessage("sendPasteText", text), to: channel) }
    }
    fileprivate static func send(_ message: WireMessage, to channel: Channel) {
        guard let text = try? message.encoded() else { return }
        channel.eventLoop.execute {
            let data = channel.allocator.buffer(string: text)
            channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .text, data: data), promise: nil)
        }
    }
}

private final class SocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let server: TransferServer
    private var fragmented = Data()
    private var hasFragment = false
    init(server: TransferServer) { self.server = server }
    func handlerAdded(context: ChannelHandlerContext) {
        server.register(context.channel)
        TransferServer.send(WireMessage("welcome", WireMessage.json(["message": "share_xuan", "clientId": UUID().uuidString, "deviceId": server.deviceID, "timestamp": Int(Date().timeIntervalSince1970 * 1000)])), to: context.channel)
    }
    func channelInactive(context: ChannelHandlerContext) { server.unregister(context.channel); context.fireChannelInactive() }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .ping:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)), promise: nil)
        case .connectionClose:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData))).whenComplete { _ in context.close(promise: nil) }
        case .text, .continuation:
            if frame.opcode == .text {
                guard !hasFragment else { context.close(promise: nil); return }
                fragmented.removeAll(); hasFragment = true
            } else if !hasFragment { context.close(promise: nil); return }
            fragmented.append(contentsOf: frame.unmaskedData.readableBytesView)
            guard fragmented.count <= 1024 * 1024 else { context.close(promise: nil); return }
            if frame.fin {
                hasFragment = false
                defer { fragmented.removeAll() }
                do {
                    let message = try WireMessage.decode(String(decoding: fragmented, as: UTF8.self))
                    switch message.type {
                    case "ping": TransferServer.send(WireMessage("pong", message.content), to: context.channel)
                    case "sendPasteText": server.onText?(message.content)
                    case "getStatus": break // Music playback is intentionally not part of this app.
                    default: break
                    }
                } catch { TransferServer.send(WireMessage("error", WireMessage.json(["error": "Invalid message"])), to: context.channel) }
            }
        case .pong: break
        default: context.close(promise: nil)
        }
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent { context.close(promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

private final class HTTPTransferHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let server: TransferServer
    private var head: HTTPRequestHead?
    private var parser: MultipartReceiver?
    private var rawFile: URL?
    private var rawHandle: FileHandle?
    private var count: Int64 = 0
    private var failed = false
    private var responding = false
    init(server: TransferServer) { self.server = server }
    deinit { cleanup() }
    private func cleanup() {
        try? rawHandle?.close(); rawHandle = nil
        if let rawFile { try? FileManager.default.removeItem(at: rawFile) }
        rawFile = nil; parser = nil
    }
    func channelInactive(context: ChannelHandlerContext) { cleanup(); context.fireChannelInactive() }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !failed, !responding else { return }
        do {
            switch unwrapInboundIn(data) {
            case .head(let request):
                head = request
                if request.uri == "/onPasteFile" || request.uri == "/onPasteImage" {
                    guard request.method == .POST else { respond(context, .methodNotAllowed, "POST required"); return }
                    if let length = request.headers.first(name: "content-length").flatMap(Int64.init), length > 20 * 1024 * 1024 * 1024 {
                        respond(context, .payloadTooLarge, "20 GiB limit"); return
                    }
                    if request.uri == "/onPasteFile" {
                        parser = try MultipartReceiver(boundary: MultipartReceiver.boundary(request.headers.first(name: "content-type") ?? ""), temporaryDirectory: server.temporary)
                    } else {
                        let file = server.temporary.appendingPathComponent(UUID().uuidString)
                        FileManager.default.createFile(atPath: file.path, contents: nil)
                        rawFile = file; rawHandle = try FileHandle(forWritingTo: file)
                    }
                }
            case .body(let bytes):
                count += Int64(bytes.readableBytes)
                guard count <= 20 * 1024 * 1024 * 1024 else { throw TransferError.invalid("20 GiB limit") }
                let chunk = Data(bytes.readableBytesView)
                if let parser { try parser.append(chunk) }
                else if let rawHandle { try rawHandle.write(contentsOf: chunk) }
                else if count > 16384 { throw TransferError.invalid("Unexpected request body") }
            case .end:
                guard let head else { return }
                if let length = head.headers.first(name: "content-length").flatMap(Int64.init), count != length { throw TransferError.invalid("Incomplete request") }
                switch (head.method, head.uri) {
                case (.POST, "/onPasteFile"):
                    guard let parser else { throw TransferError.invalid("Missing multipart") }
                    let files = try parser.finish(into: server.inbox)
                    self.parser = nil; server.onFiles?(files)
                    respond(context, .ok, WireMessage.json(["saved": files.count]))
                case (.POST, "/onPasteImage"):
                    guard let rawFile, count > 0 else { throw TransferError.invalid("Empty image") }
                    try rawHandle?.close(); rawHandle = nil
                    let name = try FileTools.safeName((head.headers.first(name: "x-filename") ?? "image.png").removingPercentEncoding ?? "image.png")
                    let batch = server.inbox.appendingPathComponent(UUID().uuidString)
                    try FileTools.directory(batch)
                    let destination = batch.appendingPathComponent(name)
                    try FileManager.default.moveItem(at: rawFile, to: destination); self.rawFile = nil
                    server.onFiles?([destination]); respond(context, .ok, "{\"saved\":1}")
                case (.GET, "/getPasteFile"):
                    let files = server.files()
                    guard !files.isEmpty else { respond(context, .notFound, "No files offered"); return }
                    responding = true
                    let temporary = server.temporary
                    DispatchQueue.global(qos: .utility).async {
                        let result = Result { try MultipartBody(files: files, directory: temporary) }
                        context.eventLoop.execute {
                            do {
                                let body = try result.get()
                                guard context.channel.isActive else { try? FileManager.default.removeItem(at: body.url); return }
                                try self.respondFile(context, file: body.url, contentType: "multipart/mixed; boundary=\(body.boundary)")
                            } catch { self.respond(context, .internalServerError, "Failed to prepare files") }
                        }
                    }
                case (.GET, "/"), (.GET, "/status"):
                    respond(context, .ok, "{\"running\":true,\"app\":\"share_xuan\"}")
                default: respond(context, .notFound, "Unknown endpoint")
                }
            }
        } catch {
            cleanup(); server.onError?(error.localizedDescription)
            respond(context, .badRequest, "Invalid or incomplete transfer"); failed = true
        }
    }
    private func respond(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus, _ text: String) {
        responding = true
        let bytes = context.channel.allocator.buffer(string: text)
        let headers = HTTPHeaders([("Content-Type", "application/json; charset=utf-8"), ("Content-Length", "\(bytes.readableBytes)"), ("Connection", "close")])
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in context.close(promise: nil) }
    }
    private func respondFile(_ context: ChannelHandlerContext, file: URL, contentType: String) throws {
        let handle = try NIOFileHandle(path: file.path)
        let region = try FileRegion(fileHandle: handle)
        responding = true
        let headers = HTTPHeaders([("Content-Type", contentType), ("Content-Length", "\(region.readableBytes)"), ("Connection", "close")])
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
        context.write(wrapOutboundOut(.body(.fileRegion(region))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            try? handle.close(); try? FileManager.default.removeItem(at: file)
            context.close(promise: nil)
        }
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent { context.close(promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { cleanup(); context.close(promise: nil) }
}
