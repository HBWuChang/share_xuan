import Foundation
import TransferCore

@main struct Probe {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "client" {
            let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PROBE_ROOT"] ?? "/tmp/share-xuan-probe-client")
            let client = TransferClient(address: try PeerAddress(CommandLine.arguments[2]), inbox: root.appendingPathComponent("Inbox"), temporary: root.appendingPathComponent("Temporary"))
            client.onStatus = { print("STATUS:\($0):\($1)"); fflush(stdout) }
            client.onFiles = { print("FILES:\($0.map(\.path))"); fflush(stdout) }
            client.onText = { print("TEXT:\($0)"); fflush(stdout) }
            client.onError = { print("ERROR:\($0)"); fflush(stdout) }
            client.connect()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await client.send(WireMessage("sendPasteText", "来自原生客户端"))
            if CommandLine.arguments.count > 3 { try await client.upload(files: [URL(fileURLWithPath: CommandLine.arguments[3])]); print("UPLOADED"); fflush(stdout) }
            try await Task.sleep(nanoseconds: 5_000_000_000)
            client.disconnect()
            return
        }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PROBE_ROOT"] ?? "/tmp/share-xuan-probe")
        let server = TransferServer(inbox: root.appendingPathComponent("Inbox"), temporary: root.appendingPathComponent("Temporary"), deviceID: "share-xuan-probe")
        server.onText = { print("TEXT:\($0)"); fflush(stdout) }
        server.onFiles = { print("FILES:\($0.map(\.path))"); fflush(stdout) }
        server.onError = { print("ERROR:\($0)"); fflush(stdout) }
        server.onPeers = { print("PEERS:\($0)"); fflush(stdout) }
        try await server.start(port: Int(ProcessInfo.processInfo.environment["PROBE_PORT"] ?? "25918")!)
        print("READY"); fflush(stdout)
        if CommandLine.arguments.count > 1 {
            let file = URL(fileURLWithPath: CommandLine.arguments[1])
            Task { try await Task.sleep(nanoseconds: 2_000_000_000); try server.offer(files: [file]); try server.send(text: "来自 share_xuan") }
        }
        while !Task.isCancelled { try await Task.sleep(nanoseconds: 1_000_000_000) }
    }
}
