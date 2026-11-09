import Foundation

/// A connection owns its URLSession. Closing it cancels pending uploads/downloads too.
public final class TransferClient: @unchecked Sendable {
    public let address: PeerAddress
    private let inbox: URL
    private let temporary: URL
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var downloads: [UUID: Task<Void, Never>] = [:]
    public var onText: ((String) -> Void)?
    public var onFiles: (([URL]) -> Void)?
    public var onStatus: ((Bool, String) -> Void)?
    public var onError: ((String) -> Void)?
    public init(address: PeerAddress, inbox: URL, temporary: URL) {
        self.address = address; self.inbox = inbox; self.temporary = temporary
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 24 * 3600
        session = URLSession(configuration: config)
    }
    /// Invoke client control methods on the main actor, also used for receive callbacks.
    @MainActor public func connect() {
        let task = session.webSocketTask(with: address.websocket)
        task.maximumMessageSize = 1024 * 1024; socket = task; task.resume()
        onStatus?(false, "连接中…")
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let item = try await task.receive()
                    guard let self else { return }
                    let text: String
                    switch item { case .string(let value): text = value; case .data(let data): text = String(decoding: data, as: UTF8.self); @unknown default: continue }
                    let message = try WireMessage.decode(text)
                    switch message.type {
                    case "welcome": self.onStatus?(true, "已连接")
                    case "ping": try await self.send(WireMessage("pong", message.content))
                    case "sendPasteText": self.onText?(message.content)
                    case "reqToGetFile": self.download(imageName: nil)
                    case "reqToGetImage": self.download(imageName: message.content)
                    case "error": self.onError?(message.content)
                    default: break
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.onStatus?(false, "连接断开：\(error.localizedDescription)")
                self?.disconnect()
            }
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                    try Task.checkCancellation()
                    try await self?.send(WireMessage("ping", WireMessage.json(["timestamp": Int(Date().timeIntervalSince1970 * 1000)])))
                } catch { return }
            }
        }
    }
    @MainActor public func disconnect() {
        receiver?.cancel(); heartbeat?.cancel()
        for task in downloads.values { task.cancel() }; downloads.removeAll()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session.invalidateAndCancel()
    }
    public func send(_ message: WireMessage) async throws {
        guard let socket else { throw TransferError.invalid("未连接") }
        try await socket.send(.string(message.encoded()))
    }
    public func upload(files: [URL]) async throws {
        let body = try MultipartBody(files: files, directory: temporary)
        defer { try? FileManager.default.removeItem(at: body.url) }
        var request = URLRequest(url: address.http("/onPasteFile"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: body.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TransferError.invalid("对端拒绝接收文件") }
    }
    @MainActor private func download(imageName: String?) {
        // Legacy offers identify the latest batch rather than a stable transfer ID.
        guard downloads.isEmpty else { onError?("上一批文件仍在接收，请完成后重新发送下一批"); return }
        let id = UUID()
        downloads[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.downloads.removeValue(forKey: id) }
            do {
                let (temporaryFile, response) = try await self.session.download(from: self.address.http(imageName == nil ? "/getPasteFile" : "/getPasteImage"))
                defer { try? FileManager.default.removeItem(at: temporaryFile) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw TransferError.invalid("下载失败") }
                let inbox = self.inbox, temporary = self.temporary
                let files = try await Task.detached(priority: .utility) {
                    if let imageName {
                        let name = try FileTools.safeName(FileTools.dispositionName(http.value(forHTTPHeaderField: "Content-Disposition") ?? "") ?? imageName)
                        let batch = inbox.appendingPathComponent(UUID().uuidString)
                        try FileTools.directory(batch)
                        let target = batch.appendingPathComponent(name)
                        try FileManager.default.moveItem(at: temporaryFile, to: target)
                        return [target]
                    }
                    let parser = try MultipartReceiver(boundary: MultipartReceiver.boundary(http.value(forHTTPHeaderField: "Content-Type") ?? ""), temporaryDirectory: temporary)
                    let input = try FileHandle(forReadingFrom: temporaryFile)
                    defer { try? input.close() }
                    while let bytes = try input.read(upToCount: 256 * 1024), !bytes.isEmpty { try parser.append(bytes) }
                    return try parser.finish(into: inbox)
                }.value
                self.onFiles?(files)
            } catch { if !Task.isCancelled { self.onError?(error.localizedDescription) } }
        }
    }
}
