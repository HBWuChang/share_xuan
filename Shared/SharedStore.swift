import Foundation

struct SharedJob: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let files: [String]
    let texts: [String]
}

struct SharedStore {
    let root: URL
    var pending: URL { root.appendingPathComponent("Pending", isDirectory: true) }
    var inbox: URL { root.appendingPathComponent("Inbox", isDirectory: true) }
    var temporary: URL { root.appendingPathComponent("Temporary", isDirectory: true) }
    init() throws {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "share_xuan", code: 1, userInfo: [NSLocalizedDescriptionKey: "共享容器不可用，请为主应用和分享扩展配置相同的 App Group 与签名。"])
        }
        self.root = root
        for directory in [pending, inbox, temporary] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }
    func jobs() throws -> [SharedJob] {
        try FileManager.default.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil).compactMap { directory in
            guard !directory.lastPathComponent.hasPrefix(".") else { return nil }
            return try? JSONDecoder().decode(SharedJob.self, from: Data(contentsOf: directory.appendingPathComponent("job.json")))
        }.sorted { $0.createdAt > $1.createdAt }
    }
    func files(for job: SharedJob) -> [URL] {
        job.files.map { pending.appendingPathComponent(job.id.uuidString).appendingPathComponent($0) }
    }
    func remove(_ job: SharedJob) throws { try FileManager.default.removeItem(at: pending.appendingPathComponent(job.id.uuidString)) }
    func receivedFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: inbox, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return (enumerator?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    /// Publish a manifest last. Readers never see an incomplete import.
    func publish(id: UUID, staging: URL, files: [String], texts: [String]) throws {
        let job = SharedJob(id: id, createdAt: Date(), files: files, texts: texts)
        try JSONEncoder().encode(job).write(to: staging.appendingPathComponent("job.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: pending.appendingPathComponent(id.uuidString))
    }
}
