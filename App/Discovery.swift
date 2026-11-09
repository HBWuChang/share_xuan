import Foundation
import Darwin

struct DiscoveredPeer: Identifiable {
    let id: String
    let name: String
    let address: String
}

@MainActor final class Discovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published var peers: [DiscoveredPeer] = []
    @Published var message = ""
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var advertisement: NetService?
    private let ownID: String
    init(ownID: String) { self.ownID = ownID; super.init(); browser.delegate = self }
    func start() { browser.stop(); services.removeAll(); peers.removeAll(); message = "正在查找局域网设备…"; browser.searchForServices(ofType: "_listen1xuan._tcp.", inDomain: "local.") }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services.removeAll(); peers.removeAll() }
    func publish(port: Int) {
        unpublish()
        let service = NetService(domain: "local.", type: "_listen1xuan._tcp.", name: ownID, port: Int32(port))
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: ["port": Data(String(port).utf8), "app": Data("share_xuan".utf8)]))
        advertisement = service; service.publish()
    }
    func unpublish() { advertisement?.stop(); advertisement = nil }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name != ownID else { return }
        services.append(service); service.delegate = self; service.resolve(withTimeout: 8)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        peers.removeAll { $0.id == service.name }; services.removeAll { $0 == service }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) { message = "设备发现不可用，请检查本地网络权限或手动输入地址" }
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) { message = "Bonjour 广播失败，可以使用 IP 地址连接" }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let record = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        // Listen1 advertises port 3030 but stores its actual listening port in TXT.
        let port = record["port"].flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? sender.port
        guard (1...65535).contains(port) else { return }
        let peer = DiscoveredPeer(id: sender.name, name: String(data: record["app"] ?? Data(), encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } ?? "Listen1 · \(sender.name.prefix(8))", address: "\(host):\(port)")
        peers.removeAll { $0.id == peer.id }; peers.append(peer); message = "找到 \(peers.count) 台设备"
    }
    static func localAddresses(port: Int) -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [String] = []
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr, current.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  current.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                result.append(value.contains(":") ? "[\(value)]:\(port)" : "\(value):\(port)")
            }
        }
        return result.sorted()
    }
}
