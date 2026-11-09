# Apple Developer / App Store Connect 配置

工程已可在模拟器本地签名运行。以下操作由你在自己的 Apple 账号下完成，用户已提供注册使用的 App ID 与 App Group，工程已同步；未通过后台核验关联或上传构建。

## 1. Apple Developer：创建两个明确 App ID

进入 Certificates, Identifiers & Profiles → Identifiers → + → App IDs → App。

| 用途 | 当前工程配置 |
| --- | --- |
| 主应用 | `xyz.040905.share` |
| 系统分享扩展 | `xyz.040905.share.ShareExtension` |

两个 App ID 都属于同一个开发团队，均启用 **App Groups**。如果这些标识符不可用或你希望使用其他前缀，先同步修改 `Config.xcconfig` 的两项 Bundle ID 与下一节的 App Group，再注册。扩展 Bundle ID 必须以主应用 Bundle ID 加 `.` 为前缀。

## 2. Apple Developer：创建一个共享 App Group

Identifiers → + → App Groups，注册：

`group.xyz.040905.share`

回到上述两个 App ID 的配置，分别编辑 App Groups，将同一个 group 勾选并保存。

本步骤使系统分享扩展和主应用能够访问同一待发送目录，不能只给主应用配置。旧 Listen1 应用不需要加入此 App Group；它通过网络协议通信。

官方说明：[注册 App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)、[注册 App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group/)、[配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

## 3. 本地 Xcode：选择团队与真机签名

1. 打开 `share_xuan.xcodeproj`。
2. 分别选择 `share_xuan` 与 `ShareExtension` 两个 target，在 Signing & Capabilities 中选择同一个 Team，开启 Automatically manage signing。
3. 确认两者的 App Groups 均为 `group.xyz.040905.share`。entitlements 已写入工程；也可由 Xcode 的 capability 面板检查。
4. 连接 iPhone 并选择该设备，必要时在手机开启 Developer Mode，然后 Run。
5. 若手动维护 profiles，需为两个 App ID 分别生成/更新包含 App Group entitlement 的 provisioning profile。自动签名通常可由 Xcode 处理。

使用具备 App Groups 能力的 Apple Developer Program 团队。不要以为主应用能够启动就代表扩展签名已正确；必须从“文件”或“照片”等 App 分享一次进行验证。

## 4. App Store Connect：仅为主应用新建记录

这一步在准备 TestFlight/上架时才需要，真机本地开发不需要先创建商店记录。

Apps → + → New App：

- Platform：iOS
- Name：`share_xuan`（以后台可用性为准）
- Primary Language：简体中文或你计划使用的语言
- Bundle ID：`xyz.040905.share`
- SKU：例如 `share_xuan_ios`

**不要为 ShareExtension 单独创建 App Store Connect 应用记录。** 它随主应用一并打包。

官方说明：[添加新 App](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)。

## 5. 当前不需要开启的服务

本版本不需要 Push Notifications、iCloud、Associated Domains、Sign in with Apple 或后台音频。局域网权限说明与 Bonjour 服务类型已经在主应用 Info.plist 中配置，由系统首次使用时询问；它们不是 App Store Connect 的开关。

## 准备提交前

还需要正式图标/截图、隐私政策链接、App Privacy 声明、年龄分级、出口合规问卷，以及真实设备上的传输测试。隐私说明应描述局域网文件传输、共享目录及旧协议未加密的事实；若后续加入分析 SDK、云服务或新权限，需要重新评估。

当前工程未替你填写这些声明或提交审核。正式 Archive/上传前需复核 privacy manifest、依赖、ATS 兼容配置和签名；不应把本次 Debug 构建视作已可直接发布的正式包。
