# share_xuan

独立 iOS 文件/文本传输应用。SwiftUI 主应用 + 原生 Share Extension + SwiftNIO 传输核心。最低 iOS 16，当前使用 Xcode 26.6 / Swift 5 语言模式开发。

## 打开与运行

打开 `share_xuan.xcodeproj`，选择 `share_xuan` scheme。Swift Package Manager 自动解析固定版本 SwiftNIO 2.90.0。

模拟器无需 Apple Developer 配置。请保留模拟器的本地签名（Sign to Run Locally），不要设置 `CODE_SIGNING_ALLOWED=NO` 后直接安装：未签名应用无法访问 App Group。

```sh
xcodebuild -project share_xuan.xcodeproj -scheme share_xuan \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
```

真机所需的 Bundle ID、App Group 和签名步骤见 [Apple 配置](docs/APPLE_SETUP.md)。标识符集中在 `Config.xcconfig`；当前标识符已同步为用户提供的 `xyz.040905.share`、`xyz.040905.share.ShareExtension` 和 `group.xyz.040905.share`。

## 使用

1. 两端连接同一可互访的局域网。首次允许本地网络访问。
2. **iPhone 为客户端**：在 Listen1 启动 WS 服务端，在 share_xuan 发现列表点击设备，或输入 `IP:端口`（默认 25917）。支持 `ws://主机:端口/ws` 与 `[IPv6]:端口`。
3. **iPhone 为服务端**：在 share_xuan 启动服务端，在 Listen1 的客户端页面输入显示的 `IP:端口`（该输入框不要加 `/ws`）。同一台 Mac 上的模拟器与桌面 Listen1 若均启动服务器，须使用不同端口。
4. 其他应用系统分享菜单 → share_xuan → 等待“已保存” → 完成 → 打开 share_xuan 的“发送”页面。
5. “发送”页也可直接选择文件、输入文本。选择待发送记录并发送。收件箱中的文件可再次通过系统分享保存到“文件”或交给其他 App。
6. 记录不会自动删除，避免服务端仅发出通知而对端未下载完成时丢失源文件。客户端上传 HTTP 200 表示对端保存成功；服务端发送仅表示已经通知对端，需在对端确认结果。

## 已实现

- WS 客户端和服务端、Listen1 JSON 字符串 content 格式、welcome、应用层 ping/pong、WS 控制帧。
- Bonjour `_listen1xuan._tcp` 发现和广播；兼容 Listen1 将实际监听端口放在 TXT `port` 的行为。
- 文本双向收发；收到文本由用户点击复制，不自动覆盖本机剪贴板。
- 文件双向收发、多文件、Unicode 文件名、图片下载/上传兼容。
- 流式 multipart 解析、文件名净化、截断检查、单批次发布、同名文件保留。
- Share Extension 接收文件、图片/视频、URL、文本，保存到双方共享的 App Group；扩展不加载 Flutter 或网络服务。
- 待发送队列持久化、收件箱文件持久化、系统文件选择与分享导出。

## 本版边界

- **仅前台网络传输**。切入后台会断开 WS 并停止服务端；不是后台常驻服务器，没有后台 URLSession/断点续传。下一次连接需手动操作。
- **旧版兼容协议没有配对鉴权与 TLS**。仅在可信局域网使用，服务端只在用户主动开启期间监听。没有音乐、缓存库、Cookie 导出接口。
- 旧协议是“最新一批文件”，不提供稳定任务 ID 和下载确认。请完成一批后再发送下一批；多个客户端会收到相同文件通知。
- 进度显示为处理中，没有精确百分比。单批服务端接收上限 20 GiB / 1000 个文件；分享扩展入口限 100 文件或图片 / 20 视频或 URL。
- multipart 上传/服务端下载为兼容旧协议会预生成磁盘请求体；下载也先由 URLSession 落盘再解析，须保留足够额外空间。内存按块处理，但并不表示没有额外磁盘复制。
- 大文件分享仍须在扩展有效执行时间内完成导入；不保证任意大小文件都能从所有文件提供方导入。不支持文件夹，先压缩为 ZIP。
- 传输临时文件在正常完成后或主应用下次启动时清理；待发送文件/收件箱不会被此清理删除。服务端发送快照保留到下次启动，以避免正在下载时被删除。
- 收到的文本仅在本次进程内保留。分享导入的文本持久保存于待发送记录。
- 真机、大文件压力、网络断开/锁屏、所有第三方分享来源仍需要进一步验证。当前不是已经完成 App Store 上架审查的版本。

## 工程结构

- `App/`：SwiftUI、连接状态、Bonjour。
- `ShareExtension/`：系统分享入口，提供方 URL 在回调有效期内复制。
- `Shared/`：App Group 待发送 manifest；先写入隐藏 staging，最后 rename 发布，避免半成品任务。
- `TransferCore/`：独立 Swift Package，协议、multipart、HTTP/WS 服务端与客户端；可在 macOS 运行测试。
- `scripts/generate_project.rb`：可选工程生成器（需要 Ruby xcodeproj 1.27）；工程文件已生成，不要求用户安装生成器。再次生成会覆盖 Xcode 工程内手动调整的签名设置。
- `scripts/interop_test.dart`：与相邻 Listen1 工程的实际 `PasteFileTransfer` 接收代码互操作测试。

## 验证

```sh
swift test --package-path TransferCore
swift build --package-path TransferCore
# 从 share_xuan 目录运行；使用现有 Listen1 依赖环境，无需修改原工程。
dart --packages=../listen1_xuan/.dart_tool/package_config.json scripts/interop_test.dart
```

互操作脚本使用临时目录和随机端口，启动原生测试端与 Dart 测试端，验证 WS、文本、心跳、文件/图片、Unicode 文件名及二进制内容。不会连接实际用户设备。

详细当前验证结果见 [验证记录](docs/VALIDATION.md)。
