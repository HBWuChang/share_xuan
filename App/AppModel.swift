import SwiftUI
import UIKit
import TransferCore

@MainActor final class AppModel: ObservableObject {
    @Published var address: String = UserDefaults.standard.string(forKey: "peerAddress") ?? ""
    @Published var port = "25917"
    @Published var connected = false
    @Published var serverRunning = false
    @Published var changingConnection = false
    @Published var clientCount = 0
    @Published var status = "未连接"
    @Published var error: String?
    @Published var jobs: [SharedJob] = []
    @Published var received: [URL] = []
    @Published var receivedTexts: [String] = []
    @Published var sending = false
    @Published var draft = ""
    @Published var localAddresses: [String] = []
    let discovery: Discovery
    private(set) var store: SharedStore?
    private var client: TransferClient?
    private var server: TransferServer?
    private var sendTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private let deviceID: String
    var canSend: Bool { connected || (serverRunning && clientCount > 0) }
    init() {
        let id = UserDefaults.standard.string(forKey: "deviceID") ?? UUID().uuidString
        deviceID = id; UserDefaults.standard.set(id, forKey: "deviceID")
        discovery = Discovery(ownID: id)
        do {
            let store = try SharedStore()
            // Only the main app owns Temporary; extensions stage imports under Pending.
            // On process launch no previous transfer can still own these scratch files.
            for file in try FileManager.default.contentsOfDirectory(at: store.temporary, includingPropertiesForKeys: nil) {
                try? FileManager.default.removeItem(at: file)
            }
            self.store = store
        } catch { self.error = error.localizedDescription }
        refresh()
    }
    func refresh() {
        do { jobs = try store?.jobs() ?? []; received = try store?.receivedFiles() ?? [] }
        catch { self.error = error.localizedDescription }
    }
    func connect() {
        guard !serverRunning, !changingConnection, let store else { return }
        disconnect()
        do {
            let peer = try PeerAddress(address)
            let client = TransferClient(address: peer, inbox: store.inbox, temporary: store.temporary)
            self.client = client; changingConnection = true; status = "连接中…"
            client.onStatus = { [weak self, weak client] connected, text in
                Task { @MainActor in
                    guard let self, self.client === client else { return }
                    self.connected = connected; self.status = text
                    if connected || text != "连接中…" { self.changingConnection = false }
                    UIApplication.shared.isIdleTimerDisabled = connected
                }
            }
            client.onText = { [weak self] text in Task { @MainActor in self?.recordText(text) } }
            client.onFiles = { [weak self] files in Task { @MainActor in self?.status = "收到 \(files.count) 个文件"; self?.refresh() } }
            client.onError = { [weak self] text in Task { @MainActor in self?.error = text } }
            client.connect(); UserDefaults.standard.set(address, forKey: "peerAddress")
        } catch { self.error = error.localizedDescription; changingConnection = false }
    }
    func disconnect() {
        sendTask?.cancel(); client?.disconnect(); client = nil
        connected = false; changingConnection = false
        UIApplication.shared.isIdleTimerDisabled = serverRunning
        if !serverRunning { status = "未连接" }
    }
    func startServer() {
        guard !changingConnection, !serverRunning, let store else { return }
        guard let port = Int(port), (1024...65535).contains(port) else { error = "端口应为 1024–65535"; return }
        disconnect(); changingConnection = true; status = "启动服务端…"
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let server = TransferServer(inbox: store.inbox, temporary: store.temporary, deviceID: deviceID)
        self.server = server
        server.onText = { [weak self] text in Task { @MainActor in self?.recordText(text) } }
        server.onFiles = { [weak self] files in Task { @MainActor in self?.status = "收到 \(files.count) 个文件"; self?.refresh() } }
        server.onPeers = { [weak self] count in Task { @MainActor in self?.clientCount = count } }
        server.onError = { [weak self] text in Task { @MainActor in self?.error = text } }
        Task {
            do {
                try await server.start(port: port)
                guard generation == lifecycleGeneration else { await server.stop(); return }
                serverRunning = true; changingConnection = false
                status = "服务端运行中，等待连接"
                localAddresses = Discovery.localAddresses(port: port)
                discovery.publish(port: port)
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                guard generation == lifecycleGeneration else { return }
                self.error = error.localizedDescription; self.server = nil; changingConnection = false; status = "服务端启动失败"
            }
        }
    }
    func stopServer() {
        lifecycleGeneration += 1
        let previous = server; server = nil
        serverRunning = false; clientCount = 0; changingConnection = false
        discovery.unpublish(); UIApplication.shared.isIdleTimerDisabled = connected
        status = "服务端已停止"
        if let previous { Task { await previous.stop() } }
    }
    func background() {
        disconnect(); stopServer(); discovery.stop()
        status = "已暂停连接，回到前台后请重新连接"
    }
    private func recordText(_ text: String) {
        receivedTexts.insert(text, at: 0)
        if receivedTexts.count > 100 { receivedTexts.removeLast() }
        status = "收到文本，可在收件箱复制"
    }
    func sendText() {
        let text = draft
        guard !text.isEmpty, canSend, !sending else { return }
        runSend { [self] in
            if let client, connected { try await client.send(WireMessage("sendPasteText", text)) }
            else if let server, serverRunning { try server.send(text: text) }
            else { throw TransferError.invalid("未连接") }
            status = "文本已发送"
        }
    }
    func send(_ job: SharedJob) {
        guard let store, canSend, !sending else { return }
        runSend { [self] in
            if let client, connected {
                let files = store.files(for: job)
                if !files.isEmpty { try await client.upload(files: files) }
                for text in job.texts { try await client.send(WireMessage("sendPasteText", text)) }
                status = "已发送；待发送记录保留，可手动删除"
            } else if let server, serverRunning {
                if !job.files.isEmpty {
                    let sources = store.files(for: job)
                    // Keep an owned snapshot even if the user removes the queued job.
                    let snapshot = try await Task.detached(priority: .utility) {
                        let directory = store.temporary.appendingPathComponent("offer-" + UUID().uuidString)
                        return try sources.map { try FileTools.copy($0, to: directory) }
                    }.value
                    try Task.checkCancellation()
                    try server.offer(files: snapshot)
                }
                for text in job.texts { try server.send(text: text) }
                status = "已通知客户端下载；请在对端确认接收完成"
            } else { throw TransferError.invalid("未连接") }
        }
    }
    private func runSend(_ operation: @escaping () async throws -> Void) {
        sending = true
        sendTask = Task {
            defer { sending = false; sendTask = nil }
            do { try await operation() }
            catch { self.error = error.localizedDescription }
        }
    }
    func importFiles(_ urls: [URL]) {
        guard let store, !sending else { return }
        runSend { [self] in
            try await Task.detached(priority: .utility) {
                let id = UUID()
                let staging = store.pending.appendingPathComponent(".import-" + id.uuidString)
                try FileTools.directory(staging)
                defer { try? FileManager.default.removeItem(at: staging) }
                var names: [String] = []
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw TransferError.invalid("请选择文件，文件夹请先压缩") }
                    var coordinationError: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                        do {
                            var target = FileTools.unique(source.lastPathComponent, in: staging)
                            if target.lastPathComponent == "job.json" { target = FileTools.unique("file-job.json", in: staging) }
                            try FileManager.default.copyItem(at: source, to: target); names.append(target.lastPathComponent)
                        } catch { copyError = error }
                    }
                    if let coordinationError { throw coordinationError }; if let copyError { throw copyError }
                }
                try store.publish(id: id, staging: staging, files: names, texts: [])
            }.value
            refresh(); status = "文件已加入待发送"
        }
    }
    func remove(_ job: SharedJob) {
        do { try store?.remove(job); refresh() } catch { self.error = error.localizedDescription }
    }
}
