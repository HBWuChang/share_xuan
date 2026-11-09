---
layout: default
title: share_xuan 隐私政策 / Privacy Policy
permalink: /privacy.html
---

# share_xuan 隐私政策

生效日期：2026-11-09

## 1. 概要

share_xuan（以下简称“本应用”）是一款局域网文件与文本传输工具，用于在 iPhone 与同一局域网内的其他设备（如运行 Listen1 的电脑或其他安装本应用的设备）之间直接传输你选择的文件和文本。

- 本应用没有账号系统，无需注册或登录。
- 我们（开发者）不运营任何用于收集你数据的服务器。本应用不会把文件、文本或个人信息上传到我们或任何第三方的服务器。
- 本应用不含广告、不含行为分析、不含第三方追踪 SDK，也不做崩溃日志上传。
- 传输在你的设备与你主动选择的对端设备之间通过局域网直连完成。

## 2. 我们不收集的数据

我们不会收集、读取、上传或出售以下任何信息：

- 姓名、手机号、电子邮箱、邮寄地址等身份信息；
- 通讯录、短信、通话记录、照片库全量内容；
- 精确或粗略位置信息；
- 广告标识符（IDFA）、设备指纹、IMEI、MAC 地址；
- 使用行为统计、页面埋点、会话录制、崩溃报告；
- 你在本应用内收发的文件内容与文本内容（详见第 3 节，这些内容始终留在你的设备上）。

## 3. 本应用在本机处理的数据

以下数据仅保存在你的设备上，或在你主动发起传输时经局域网发送给你选择的对端设备：

| 数据 | 用途 | 存放位置 | 是否发送给开发者 |
| --- | --- | --- | --- |
| 你选择待发送的文件与文本 | 排队并发送 | 应用与分享扩展共用的 App Group 容器 `group.xyz.040905.share` | 否 |
| 接收到的文件 | 供你查看、再次分享或保存到“文件” | 同上 App Group 容器 | 否 |
| 传输临时文件（上传请求体、下载缓存） | 完成一次传输 | 应用临时目录 | 否 |
| 随机生成的设备标识（UUID） | 在对端设备列表中区分并显示本机 | 本机偏好设置 | 否（仅在局域网内随连接握手发送给对端） |
| 最近一次连接的对端地址（IP:端口） | 免去每次手动重新输入 | 本机偏好设置 | 否 |
| 服务端监听端口等设置 | 保持你的配置 | 本机内存与偏好设置 | 否 |

说明：

- 应用内“复制”按钮会写入系统剪贴板，且仅在你自己点击时发生。本应用不会读取你的剪贴板内容。
- 收到的文本默认只保留在当前运行期间，不会自动覆盖你的剪贴板，也不会写入任何远程位置。

## 4. 系统权限说明

- **本地网络**：用于通过 Bonjour 服务类型 `_listen1xuan._tcp` 发现同一局域网内的对端设备，以及建立传输连接。拒绝该权限将无法发现或连接设备。
- **文件与照片访问**：仅在你通过系统文件选择器或系统分享菜单主动选择文件、图片、视频时发生。本应用不会扫描或遍历你的相册与文件目录。分享扩展会把选中的项目复制到上述 App Group 容器，以便你在主应用中发送。
- 本应用不申请麦克风、摄像头、定位、通讯录、健康等权限。

## 5. 安全与传输方式

- 本应用为兼容旧版 Listen1 协议，使用未加密的 HTTP/WebSocket 在局域网内传输数据，当前版本**不提供 TLS 加密，也不提供配对鉴权**。
- 因此，同一局域网内的其他设备在技术上可能观察到这些流量。请仅在你自己信任的局域网中使用本应用，不要用它传输密码、密钥、证件扫描件等敏感内容。
- 传输只在应用处于前台、且你主动开启或发起时进行；切入后台即断开监听。

## 6. 数据保留与删除

- 待发送文件与收件箱文件会一直保留，直到你在应用内删除它们。这是为了避免仅在通知对端后就丢失源文件。
- 传输产生的临时文件在传输正常完成后、或主应用下次启动时被清理。
- 删除本应用会同时删除 App Group 容器内的待发送文件、收件箱文件与本地设置。系统可能根据你的 iCloud 备份设置将应用数据包含在设备备份中——该备份由 Apple 提供与加密，开发者无法访问。
- 由于我们从未获得你的数据，我们也没有可供删除、导出或更正的数据副本。

## 7. 第三方组件

- 本应用基于 Apple 提供的系统框架（SwiftUI、Network、URLSession 等）构建，并链接开源库 [Swift NIO](https://github.com/apple/swift-nio) 用于网络传输。该库在你的设备本地运行，不包含数据上报功能。
- 本应用不集成任何广告、分析、归因、推送或社交登录 SDK。
- 本应用不包含指向外部网站的跟踪链接（本政策页面与你主动打开的链接除外）。

## 8. 儿童隐私

本应用不收集任何个人信息，也不设有面向儿童的专门内容或功能。我们不会有意收集 13 周岁以下（或你所在司法辖区规定的相应年龄）儿童的任何信息。

## 9. 你的权利

由于本应用不向开发者回传数据，我们侧不存在你的个人数据档案。若你所在地区（如欧盟 GDPR、美国加州 CCPA/CPRA）赋予你访问、更正、删除、限制处理或反对处理个人数据的权利，你可以通过清除应用内数据或卸载本应用，在本机完整实现这些权利。如有疑问，仍可通过第 11 节联系我们。

## 10. 政策变更

若本应用的功能或数据处理方式发生变化（例如新增云同步、分析或账号功能），我们会更新本政策并在此页面公布修订版本与新的生效日期。重大变更会在应用更新说明中提示。

## 11. 联系方式

如对本政策或数据处理有任何疑问，请联系：

- 开发者：EvanChang
- 电子邮箱：evanchang@88vip.site

---

# share_xuan Privacy Policy

Effective date: 2026-11-09

## 1. Summary

share_xuan ("the App") is a local-network file and text transfer tool. It moves the files and text you select directly between your iPhone and other devices on the same local network (for example a computer running Listen1, or another device running this App).

- There are no accounts. No sign-up or sign-in is required.
- We (the developer) do not operate any server that collects your data. The App does not upload your files, text, or personal information to us or to any third party.
- The App contains no advertising, no behavioral analytics, no third-party tracking SDKs, and no crash-report uploads.
- Transfers happen directly over your local network between your device and the peer device you choose.

## 2. Data We Do Not Collect

We do not collect, read, upload, or sell any of the following:

- Identity information such as name, phone number, email address, or postal address;
- Contacts, messages, call logs, or your full photo library;
- Precise or coarse location;
- Advertising identifiers (IDFA), device fingerprints, IMEI, or MAC addresses;
- Usage analytics, event tracking, session recording, or crash reports;
- The content of files or text you send and receive in the App (see Section 3 — this content stays on your devices).

## 3. Data Processed On Your Device

The following data is stored only on your device, or sent over your local network to the peer you choose when you start a transfer:

| Data | Purpose | Location | Sent to the developer? |
| --- | --- | --- | --- |
| Files and text you queue for sending | Queue and send | App Group container `group.xyz.040905.share`, shared by the App and its Share Extension | No |
| Files you receive | View, re-share, or save to Files | Same App Group container | No |
| Temporary transfer files (upload bodies, download caches) | Complete a transfer | App temporary directory | No |
| A randomly generated device identifier (UUID) | Distinguish and display this device in the peer list | Local preferences | No (sent only to the peer over the local network during the connection handshake) |
| Last connected peer address (IP:port) | Avoid re-entering it each time | Local preferences | No |
| Settings such as the server listening port | Preserve your configuration | In-memory and local preferences | No |

Notes:

- The in-app "Copy" button writes to the system clipboard, and only when you tap it. The App does not read your clipboard.
- Received text is kept only for the current run of the App. It never overwrites your clipboard automatically and is never written to a remote location.

## 4. Permissions

- **Local Network**: used to discover peer devices on the same local network via the Bonjour service type `_listen1xuan._tcp` and to establish transfer connections. Denying this permission prevents discovery and connection.
- **Files and Photos**: accessed only when you explicitly pick files, images, or videos through the system file picker or the system share sheet. The App does not scan or enumerate your photo library or file directories. The Share Extension copies the selected items into the App Group container so you can send them from the main App.
- The App does not request microphone, camera, location, contacts, or health permissions.

## 5. Security and Transport

- For compatibility with the legacy Listen1 protocol, the App transfers data over the local network using unencrypted HTTP/WebSocket. This version provides **no TLS encryption and no pairing authentication**.
- As a result, other devices on the same local network may in principle observe this traffic. Use the App only on networks you trust, and do not use it to transfer passwords, keys, or ID documents.
- Transfers occur only while the App is in the foreground and only when you start or enable them; going to the background stops listening.

## 6. Retention and Deletion

- Queued outgoing files and inbox files are retained until you delete them in the App, so that source files are not lost after a peer is merely notified.
- Temporary transfer files are cleaned up after a successful transfer, or on the next launch of the main App.
- Deleting the App removes the queued files, inbox files, and local settings in the App Group container. Depending on your iCloud backup settings, app data may be included in your device backup — that backup is provided and encrypted by Apple and is not accessible to the developer.
- Because we never receive your data, we hold no copy of it to delete, export, or correct.

## 7. Third-Party Components

- The App is built on Apple system frameworks (SwiftUI, Network, URLSession, and others) and links the open-source library [Swift NIO](https://github.com/apple/swift-nio) for network transport. That library runs locally on your device and contains no telemetry.
- The App integrates no advertising, analytics, attribution, push, or social-login SDKs.
- The App contains no third-party tracking links (other than this policy page and links you open yourself).

## 8. Children's Privacy

The App collects no personal information and offers no child-directed content or features. We do not knowingly collect any information from children under 13 (or the equivalent age in your jurisdiction).

## 9. Your Rights

Because the App does not transmit data back to the developer, no personal-data profile about you exists on our side. If your jurisdiction (for example GDPR in the EU, or CCPA/CPRA in California) grants you rights to access, correct, delete, restrict, or object to the processing of personal data, you can fully exercise them on your own device by clearing in-app data or deleting the App. If you have questions, you can still contact us using Section 11.

## 10. Changes to This Policy

If the App's functionality or data practices change (for example adding cloud sync, analytics, or accounts), we will update this policy and publish the revised version and a new effective date on this page. Material changes will be noted in the App's release notes.

## 11. Contact

For any question about this policy or data handling:

- Developer: EvanChang
- Email: evanchang@88vip.site
