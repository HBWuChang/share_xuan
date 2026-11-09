import XCTest
@testable import TransferCore

final class TransferCoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileTools.directory(root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func testAddressCompatibility() throws {
        XCTAssertEqual(try PeerAddress("192.168.1.2:25917").websocket.absoluteString, "ws://192.168.1.2:25917/ws")
        XCTAssertEqual(try PeerAddress("ws://[::1]:25917/ws").http("/onPasteFile").absoluteString, "http://[::1]:25917/onPasteFile")
        for value in ["localhost", "http://localhost:80", "ws://user:password@localhost:80", "localhost:70000", "localhost:80/path", "localhost:80?token=x"] { XCTAssertThrowsError(try PeerAddress(value), value) }
    }
    func testWireUsesStringContent() throws {
        let message = WireMessage("reqToGetFile", WireMessage.json(["中文.zip", "b.txt"]))
        let decoded = try WireMessage.decode(message.encoded())
        XCTAssertEqual(decoded.content, "[\"中文.zip\",\"b.txt\"]")
        XCTAssertEqual(decoded.type, "reqToGetFile")
    }
    func testMultipartAcrossEveryByteBoundaryAndUnicode() throws {
        let fixture = root.appendingPathComponent("测试 😀.bin")
        var data = Data((0...255).map(UInt8.init)); data.append(Data("\r\n--not-a-boundary".utf8))
        try data.write(to: fixture)
        let body = try MultipartBody(files: [fixture, fixture], directory: root)
        let bytes = try Data(contentsOf: body.url)
        for chunkSize in [1, 2, 7, 31, 256, 65536] {
            let parser = try MultipartReceiver(boundary: body.boundary, temporaryDirectory: root)
            for offset in stride(from: 0, to: bytes.count, by: chunkSize) { try parser.append(bytes.subdata(in: offset..<min(bytes.count, offset + chunkSize))) }
            let files = try parser.finish(into: root.appendingPathComponent("Inbox"))
            XCTAssertEqual(files.count, 2); XCTAssertEqual(files[0].lastPathComponent, fixture.lastPathComponent)
            XCTAssertNotEqual(files[0], files[1]); XCTAssertEqual(try Data(contentsOf: files[0]), data); XCTAssertEqual(try Data(contentsOf: files[1]), data)
        }
    }
    func testBoundaryLikeBytesArePreserved() throws {
        let content = Data("hello\r\n--abcXXworld".utf8)
        let body = Data("--abc\r\nContent-Disposition: attachment; filename=\"x\"\r\n\r\n".utf8) + content + Data("\r\n--abc--\r\n".utf8)
        let parser = try MultipartReceiver(boundary: "abc", temporaryDirectory: root)
        for byte in body { try parser.append(Data([byte])) }
        let file = try XCTUnwrap(parser.finish(into: root.appendingPathComponent("Inbox")).first)
        XCTAssertEqual(try Data(contentsOf: file), content)
    }
    func testTruncatedBatchIsNeverPublished() throws {
        let parser = try MultipartReceiver(boundary: "abc", temporaryDirectory: root)
        try parser.append(Data("--abc\r\nContent-Disposition: attachment; filename=\"x\"\r\n\r\npartial".utf8))
        let inbox = root.appendingPathComponent("Inbox")
        XCTAssertThrowsError(try parser.finish(into: inbox))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    }
    func testDeclaredLengthMismatchAndLimits() throws {
        let parser = try MultipartReceiver(boundary: "abc", temporaryDirectory: root)
        XCTAssertThrowsError(try parser.append(Data("--abc\r\nContent-Disposition: attachment; filename=\"x\"\r\nContent-Length: 20\r\n\r\nshort\r\n--abc--\r\n".utf8)))
        let limited = try MultipartReceiver(boundary: "abc", temporaryDirectory: root, limit: 3)
        XCTAssertThrowsError(try limited.append(Data("1234".utf8)))
    }
    func testQuotedDispositionFilename() throws {
        XCTAssertEqual(FileTools.dispositionName(#"form-data; name="files"; filename="semi;colon.txt""#), "semi;colon.txt")
        XCTAssertEqual(FileTools.dispositionName(#"attachment; filename="quote\"name.txt""#), "quote\"name.txt")
        XCTAssertEqual(FileTools.dispositionName("attachment; FILENAME = plain.txt"), "plain.txt")
    }
    func testFilenameTraversalIsSanitized() throws {
        XCTAssertEqual(try FileTools.safeName("../../hello.txt"), "hello.txt")
        XCTAssertEqual(try FileTools.safeName("C:\\folder\\hello.txt"), "hello.txt")
        for name in ["", "..", "a\nb", "\u{0}"] { XCTAssertThrowsError(try FileTools.safeName(name)) }
    }
}
