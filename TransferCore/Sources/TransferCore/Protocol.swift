import Foundation

public struct WireMessage: Codable, Sendable {
    public let type: String
    public let content: String
    public init(_ type: String, _ content: String = "") { self.type = type; self.content = content }
    public func encoded() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    public static func decode(_ text: String) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(text.utf8)) }
    public static func json(_ object: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
}

public struct PeerAddress: Sendable {
    public let websocket: URL
    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: text.contains("://") ? text : "ws://" + text),
              c.scheme == "ws", let host = c.host, !host.isEmpty,
              let port = c.port, (1...65535).contains(port), c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, ["", "/", "/ws"].contains(c.path) else {
            throw TransferError.invalid("请输入 主机:端口 或 [IPv6]:端口")
        }
        c.path = "/ws"
        guard let url = c.url else { throw TransferError.invalid("无效地址") }
        websocket = url
    }
    public func http(_ path: String) -> URL {
        var c = URLComponents(url: websocket, resolvingAgainstBaseURL: false)!
        c.scheme = "http"; c.path = path
        return c.url!
    }
}

public enum TransferError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

public enum FileTools {
    public static func safeName(_ input: String) throws -> String {
        let name = input.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        guard !name.isEmpty, name != ".", name != "..", !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw TransferError.invalid("无效文件名")
        }
        return name
    }
    public static func directory(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    public static func unique(_ name: String, in directory: URL) -> URL {
        let source = URL(fileURLWithPath: name)
        var url = directory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension
            url = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)(\(index))\(ext)")
            index += 1
        }
        return url
    }
    public static func copy(_ source: URL, to directory: URL) throws -> URL {
        try self.directory(directory)
        let target = unique(try safeName(source.lastPathComponent), in: directory)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
    public static func encodedName(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file"
    }
    public static func dispositionName(_ value: String) -> String? {
        if let range = value.range(of: "filename*=UTF-8''", options: .caseInsensitive) {
            return String(value[range.upperBound...].split(separator: ";", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces).removingPercentEncoding
        }
        let pattern = #"(?:^|;)\s*filename\s*=\s*(?:"((?:\\.|[^"])*)"|([^;]*))"#
        if let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) {
            if let range = Range(match.range(at: 1), in: value) {
                let quoted = String(value[range])
                var unescaped = "", escaping = false
                for character in quoted {
                    if escaping { unescaped.append(character); escaping = false }
                    else if character == "\\" { escaping = true }
                    else { unescaped.append(character) }
                }
                return unescaped
            }
            if let range = Range(match.range(at: 2), in: value) { return String(value[range]).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}
