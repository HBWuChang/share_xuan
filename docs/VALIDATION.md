# 验证记录 — 2026-11-09

## 已完成

- Xcode 26.6：iOS Simulator Debug 构建通过（arm64/x86_64），包含 ShareExtension；使用本地 ad-hoc 签名。
- iPhoneOS arm64 Debug 无签名构建通过；未执行 Archive、Release 打包、上传或真机安装。
- `swift test --package-path TransferCore`：8 项 XCTest 通过。
  - IPv4/IPv6 地址及不合法地址拒绝。
  - Listen1 的字符串 content 消息格式。
  - multipart 按单字节等不同块大小解析。
  - Unicode、重复文件名、二进制及类似 boundary 的文件内容。
  - 截断批次不发布、声明长度校验、接收限制。
  - 路径净化、带分号/转义引号的 Content-Disposition 文件名。
- `scripts/interop_test.dart` 双向通过：
  - Swift 服务端 ↔ Dart WebSocket/HttpClient，并直接使用相邻 Listen1 项目的 `PasteFileTransfer.receive` 验证服务端输出。
  - Swift 客户端 ↔ Dart HttpServer，按 Listen1 的 welcome/ping/pong、sendPasteText、reqToGetFile/reqToGetImage、HTTP 接口模拟对端。
  - 约 1 MiB 二进制文件逐字节等价校验、中文文件名、文本、文件与原始图片。
- iPhone Air / iOS 26.5 模拟器交互验证：
  - Bonjour 实际发现当前局域网运行的 Listen1，并成功显示“已连接”。没有向该真实实例发送测试文件或覆盖其剪贴板。
  - share_xuan 以独立端口启动服务端，通过本地 HTTP 上传测试文件后显示“收到 1 个文件”。
  - 收件箱系统分享菜单出现 share_xuan 扩展；扩展显示已保存 1 个文件。
  - 重启主应用后，待发送列表仍显示该测试文件，验证 App Group 跨进程持久化。
- 新工程 `git diff --check` 通过；原 Listen1 工作目录保持干净。

## 验证中修正

- 模拟器不能用完全禁用签名的安装包访问 App Group，改用正常的模拟器本地签名。
- 分享返回后的队列刷新：进入发送/收件箱页面刷新，并增加发送页刷新按钮。
- iPad 补全四个方向声明。
- multipart 引号内分号和转义引号解析。

## 未验证 / 不作保证

- 实际 iPhone 签名与 App Group provisioning：等待用户 Apple Developer 配置。
- 真机到真机/Android/Windows 的完整传输、IPv6 真实网络、多网络切换、数 GiB 文件压力和空间不足。
- 系统分享入口目前实际操作验证的是文件；照片、视频、文本、URL、iCloud 文件提供方虽有实现，尚未逐个在真机验证。
- 精确进度、后台传输、断点续传、加密与配对不属于当前已实现范围。
- 本次没有提交 Apple 审核，不代表已经满足完整上架要求。

SwiftNIO 的 `NIOFileHandle(path:)` 有弃用提示，当前用于已完成的临时文件通过 FileRegion 发送，句柄在发送完成/失败时关闭。后续升级应迁移至新版文件系统 API。AppIntents 元数据跳过提示因工程没有使用 AppIntents，未影响编译。
