import SwiftUI
import UniformTypeIdentifiers

@main struct ShareXuanApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: phase) { value in
                    if value == .active { model.refresh(); model.discovery.start() }
                    if value == .background { model.background() }
                }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectingFiles = false
    var body: some View {
        TabView {
            NavigationStack {
                Form {
                    Section {
                        Label(model.status, systemImage: model.canSend ? "checkmark.circle.fill" : "network")
                            .foregroundStyle(model.canSend ? .green : .secondary)
                    }
                    Section("连接 Listen1 / share_xuan 服务端") {
                        TextField("192.168.1.2:25917", text: $model.address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityIdentifier("peerAddress")
                        HStack {
                            Button("连接") { model.connect() }.disabled(model.serverRunning || model.changingConnection || model.connected)
                                .accessibilityIdentifier("connect")
                            Spacer()
                            Button("断开") { model.disconnect() }.disabled(model.clientUnavailable)
                        }
                        DiscoveryView(discovery: model.discovery) { address in model.address = address; model.connect() }
                            .disabled(model.serverRunning || model.changingConnection || model.connected)
                    }
                    Section("让 Listen1 连接此 iPhone") {
                        TextField("端口", text: $model.port).keyboardType(.numberPad).disabled(model.serverRunning)
                        Button(model.serverRunning ? "停止服务端" : "启动服务端") {
                            if model.serverRunning { model.stopServer() } else { model.startServer() }
                        }.disabled(model.changingConnection || model.connected)
                        if model.serverRunning {
                            Text("已连接 \(model.clientCount) 台客户端")
                            ForEach(model.localAddresses, id: \.self) { address in
                                HStack { Text(address).font(.footnote).textSelection(.enabled); Spacer(); Button { UIPasteboard.general.string = address } label: { Image(systemName: "doc.on.doc") } }
                            }
                        }
                    }
                    Section("兼容模式") {
                        Text("与现有 Listen1 使用相同的局域网协议，未加密且无配对鉴权。仅在可信网络开启；收到的文件保存在收件箱。")
                        Text("传输时保持应用前台。切到后台会停止服务端并断开连接。")
                    }.font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("share_xuan")
            }.tabItem { Label("连接", systemImage: "network") }
            NavigationStack {
                List {
                    Section("发送文本") {
                        TextField("输入或粘贴文本、链接", text: $model.draft, axis: .vertical).lineLimit(3...6)
                        Button("发送文本") { model.sendText() }.disabled(!model.canSend || model.sending || model.draft.isEmpty)
                    }
                    Section {
                        Button { selectingFiles = true } label: { Label("选择文件", systemImage: "doc.badge.plus") }.disabled(model.sending)
                        if model.sending { ProgressView("正在处理，请保持前台…") }
                        if model.jobs.isEmpty { Text("从其他 App 的系统分享菜单选择 share_xuan，或在此选择文件。") .foregroundStyle(.secondary) }
                        ForEach(model.jobs) { job in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(job.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                ForEach(job.files, id: \.self) { Text($0).lineLimit(2) }
                                ForEach(Array(job.texts.enumerated()), id: \.offset) { _, text in Text(text).lineLimit(3) }
                                HStack {
                                    Button("发送") { model.send(job) }.disabled(!model.canSend || model.sending)
                                    Spacer()
                                    Button("删除", role: .destructive) { model.remove(job) }.disabled(model.sending)
                                }.buttonStyle(.borderless)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("待发送") } footer: { Text("服务端发送后，请等待对端完成下载再发送下一批。记录不会自动删除。") }
                }.navigationTitle("发送").refreshable { model.refresh() }
                    .onAppear { model.refresh() }
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") } } }
            }.tabItem { Label("发送", systemImage: "paperplane") }
            NavigationStack {
                List {
                    if model.received.isEmpty && model.receivedTexts.isEmpty { Text("收到的文件和文本会显示在这里").foregroundStyle(.secondary) }
                    Section("文本（本次打开期间）") {
                        ForEach(Array(model.receivedTexts.enumerated()), id: \.offset) { _, text in
                            VStack(alignment: .leading) {
                                Text(text).lineLimit(5).textSelection(.enabled)
                                Button("复制") { UIPasteboard.general.string = text }
                            }
                        }
                    }
                    Section("文件") {
                        ForEach(model.received, id: \.path) { file in
                            ShareLink(item: file) { Label(file.lastPathComponent, systemImage: "doc") }
                        }
                    }
                }.navigationTitle("收件箱").refreshable { model.refresh() }
                    .onAppear { model.refresh() }
            }.tabItem { Label("收件箱", systemImage: "tray") }
        }
        .fileImporter(isPresented: $selectingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): model.importFiles(urls); case .failure(let error): model.error = error.localizedDescription }
        }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private extension AppModel { var clientUnavailable: Bool { !connected && !changingConnection } }

struct DiscoveryView: View {
    @ObservedObject var discovery: Discovery
    var select: (String) -> Void
    var body: some View {
        ForEach(discovery.peers) { peer in
            Button { select(peer.address) } label: { VStack(alignment: .leading) { Text(peer.name); Text(peer.address).font(.caption).foregroundStyle(.secondary) } }
        }
        HStack {
            Text(discovery.message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { discovery.start() } label: { Image(systemName: "arrow.clockwise") }
        }
    }
}
