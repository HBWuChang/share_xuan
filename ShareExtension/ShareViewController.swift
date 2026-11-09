import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let status = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var task: Task<Void, Never>?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "保存到 share_xuan"; title.font = .preferredFont(forTextStyle: .title2)
        status.text = "正在导入分享内容…"; status.numberOfLines = 0; status.textAlignment = .center
        let done = UIButton(type: .system); done.setTitle("完成", for: .normal)
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)
        let cancel = UIButton(type: .system); cancel.setTitle("取消", for: .normal)
        cancel.addTarget(self, action: #selector(cancelImport), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, spinner, status, done, cancel])
        stack.axis = .vertical; stack.spacing = 24; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        done.isEnabled = false; spinner.startAnimating()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let store = try SharedStore()
                let id = UUID()
                let staging = store.pending.appendingPathComponent(".import-" + id.uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                var files: [String] = [], texts: [String] = []
                let items = self.extensionContext?.inputItems as? [NSExtensionItem] ?? []
                let providers = items.flatMap { $0.attachments ?? [] }
                guard !providers.isEmpty else { throw self.failure("没有可导入的内容") }
                for (index, provider) in providers.enumerated() {
                    try Task.checkCancellation()
                    self.status.text = "正在导入 \(index + 1)/\(providers.count)…\n大文件需要等待复制完成。"
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let value = try await self.loadItem(provider, type: UTType.fileURL.identifier)
                        guard let source = value as? URL, source.isFileURL else { throw self.failure("无法读取文件 URL") }
                        let name = try await Task.detached(priority: .utility) { try Self.copy(source, to: staging) }.value
                        files.append(name)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        let value = try await self.loadItem(provider, type: UTType.url.identifier)
                        guard let url = value as? URL else { throw self.failure("无法读取链接") }
                        texts.append(url.absoluteString)
                    } else if let type = provider.registeredTypeIdentifiers.first(where: { identifier in
                        guard let type = UTType(identifier) else { return false }
                        return type.conforms(to: .data) && !type.conforms(to: .text)
                    }) {
                        files.append(try await self.loadFile(provider, type: type, directory: staging))
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                        let value = try await self.loadItem(provider, type: UTType.text.identifier)
                        if let text = value as? String { texts.append(text) }
                        else if let text = value as? NSAttributedString { texts.append(text.string) }
                        else { throw self.failure("无法读取文字") }
                    } else { throw self.failure("暂不支持此分享内容") }
                }
                try Task.checkCancellation()
                try store.publish(id: id, staging: staging, files: files, texts: texts)
                self.status.text = "已保存 \(files.count) 个文件、\(texts.count) 段文本。\n打开 share_xuan，在「待发送」中选择发送。"
                done.isEnabled = true; cancel.isHidden = true
            } catch {
                if !Task.isCancelled { self.status.text = "导入失败：\(error.localizedDescription)"; done.isEnabled = true }
            }
            self.spinner.stopAnimating()
        }
    }
    private func loadItem(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let item { continuation.resume(returning: item) }
                else { continuation.resume(throwing: error ?? NSError(domain: "share_xuan", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取分享内容"])) }
            }
        }
    }
    private func loadFile(_ provider: NSItemProvider, type: String, directory: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                // The provider URL is only valid during this callback: copy before returning.
                do {
                    guard let url else { throw error ?? NSError(domain: "share_xuan", code: 3) }
                    continuation.resume(returning: try Self.copy(url, to: directory))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    nonisolated private static func copy(_ source: URL, to directory: URL) throws -> String {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<String, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            result = Result {
                guard try readable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw NSError(domain: "share_xuan", code: 4, userInfo: [NSLocalizedDescriptionKey: "暂不支持文件夹，请先压缩为 ZIP"])
                }
                var target = directory.appendingPathComponent(readable.lastPathComponent)
                if target.lastPathComponent == "job.json" || FileManager.default.fileExists(atPath: target.path) {
                    target = directory.appendingPathComponent(UUID().uuidString + "-" + readable.lastPathComponent)
                }
                try FileManager.default.copyItem(at: readable, to: target)
                return target.lastPathComponent
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw NSError(domain: "share_xuan", code: 5) }
        return try result.get()
    }
    private func failure(_ text: String) -> Error { NSError(domain: "share_xuan", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }
    @objc private func cancelImport() {
        task?.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
