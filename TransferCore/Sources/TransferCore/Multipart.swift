import Foundation

/// Incremental parser: retains only a boundary-sized tail and writes each part to disk.
/// A whole batch becomes visible only after its closing boundary has been validated.
public final class MultipartReceiver {
    private enum State { case start, headers, body, suffix, done }
    private var state = State.start
    private var buffer = Data()
    private let marker: Data
    private let first: Data
    private let staging: URL
    private var handle: FileHandle?
    private var parts: [(URL, String)] = []
    private var partLength = 0
    private var expectedLength: Int?
    private var total: Int64 = 0
    private let limit: Int64
    public init(boundary: String, temporaryDirectory: URL, limit: Int64 = 20 * 1024 * 1024 * 1024) throws {
        guard !boundary.isEmpty, boundary.utf8.count <= 70, !boundary.contains("\r"), !boundary.contains("\n") else { throw TransferError.invalid("无效 multipart boundary") }
        marker = Data(("\r\n--" + boundary).utf8)
        first = Data(("--" + boundary + "\r\n").utf8)
        staging = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.limit = limit
        try FileTools.directory(staging)
    }
    deinit { try? handle?.close(); try? FileManager.default.removeItem(at: staging) }
    public static func boundary(_ contentType: String) throws -> String {
        guard contentType.lowercased().hasPrefix("multipart/") else { throw TransferError.invalid("响应不是 multipart 文件") }
        for component in contentType.components(separatedBy: ";").dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 && pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "boundary" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            }
        }
        throw TransferError.invalid("缺少 multipart boundary")
    }
    public func append(_ data: Data) throws {
        total += Int64(data.count)
        guard total <= limit else { throw TransferError.invalid("超过单次接收上限") }
        buffer.append(data)
        while true {
            switch state {
            case .start:
                guard buffer.count >= first.count else { return }
                guard buffer.starts(with: first) else { throw TransferError.invalid("multipart 起始标记错误") }
                buffer.removeFirst(first.count); state = .headers
            case .headers:
                guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    guard buffer.count <= 16384 else { throw TransferError.invalid("文件头过长") }; return
                }
                let text = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                var headers: [String: String] = [:]
                for line in text.components(separatedBy: "\r\n") {
                    let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
                    if pair.count == 2 { headers[pair[0].lowercased()] = pair[1].trimmingCharacters(in: .whitespaces) }
                }
                guard let name = FileTools.dispositionName(headers["content-disposition"] ?? ""), parts.count < 1000 else { throw TransferError.invalid("文件名缺失或文件过多") }
                let safe = try FileTools.safeName(name)
                let path = staging.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: path.path, contents: nil)
                handle = try FileHandle(forWritingTo: path)
                parts.append((path, safe)); partLength = 0
                expectedLength = headers["content-length"].flatMap(Int.init)
                buffer.removeSubrange(..<range.upperBound); state = .body
            case .body:
                if let range = buffer.range(of: marker) {
                    // A boundary-like byte sequence inside a file is not a delimiter.
                    guard buffer.distance(from: range.upperBound, to: buffer.endIndex) >= 2 else {
                        try write(Data(buffer[..<range.lowerBound])); buffer.removeSubrange(..<range.lowerBound); return
                    }
                    let suffix = Data(buffer[range.upperBound..<buffer.index(range.upperBound, offsetBy: 2)])
                    if suffix != Data("--".utf8) && suffix != Data("\r\n".utf8) {
                        let end = buffer.index(after: range.lowerBound)
                        try write(Data(buffer[..<end])); buffer.removeSubrange(..<end); continue
                    }
                    try write(Data(buffer[..<range.lowerBound]))
                    if let expectedLength, expectedLength != partLength { throw TransferError.invalid("文件长度不完整") }
                    try handle?.close(); handle = nil
                    buffer.removeSubrange(..<range.upperBound); state = .suffix
                } else {
                    let count = max(0, buffer.count - marker.count - 2)
                    if count > 0 { try write(Data(buffer.prefix(count))); buffer.removeFirst(count) }
                    return
                }
            case .suffix:
                guard buffer.count >= 2 else { return }
                if buffer.starts(with: Data("--".utf8)) { state = .done }
                else if buffer.starts(with: Data("\r\n".utf8)) { state = .headers }
                else { throw TransferError.invalid("multipart 结束标记错误") }
                buffer.removeFirst(2)
            case .done:
                guard buffer.count <= 2, Data("\r\n".utf8).starts(with: buffer) else { throw TransferError.invalid("multipart 尾部无效") }
                return
            }
        }
    }
    private func write(_ bytes: Data) throws { try handle?.write(contentsOf: bytes); partLength += bytes.count }
    public func finish(into directory: URL) throws -> [URL] {
        guard state == .done, !parts.isEmpty else { throw TransferError.invalid("文件传输中断，未保存不完整文件") }
        try FileTools.directory(directory)
        // Each batch owns a directory, avoiding cross-process name collisions.
        let batch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileTools.directory(batch)
        do {
            var result: [URL] = []
            for (source, name) in parts {
                let target = FileTools.unique(name, in: batch)
                try FileManager.default.moveItem(at: source, to: target); result.append(target)
            }
            parts.removeAll()
            return result
        } catch { try? FileManager.default.removeItem(at: batch); throw error }
    }
}

public struct MultipartBody {
    public let url: URL
    public let boundary: String
    public init(files: [URL], directory: URL) throws {
        guard !files.isEmpty else { throw TransferError.invalid("请选择文件") }
        try FileTools.directory(directory)
        boundary = "ShareXuan" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        url = directory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        do {
            for file in files {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename*=UTF-8''\(FileTools.encodedName(file.lastPathComponent))\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\n\r\n"
                try output.write(contentsOf: Data(header.utf8))
                let input = try FileHandle(forReadingFrom: file)
                do {
                    while let data = try input.read(upToCount: 256 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
                    try input.close()
                } catch { try? input.close(); throw error }
                try output.write(contentsOf: Data("\r\n".utf8))
            }
            try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8)); try output.close()
        } catch { try? output.close(); try? FileManager.default.removeItem(at: url); throw error }
    }
}
