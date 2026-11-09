# iPhone Air 真实截图

2026-11-09，从已有 iPhone Air / iOS 26.5 模拟器截取，运行 Bundle ID `xyz.040905.share`，深色模式。未生成或重绘界面、未添加营销文案、未缩放。

- `iphone-air/`：simctl 导出的原始 PNG，1260×2736（有 alpha 通道）。
- `app-store-iphone-air/`：同尺寸高质量 JPEG，无 alpha，可用于对应的 App Store Connect iPhone 截图槽位；不包含模拟器外框。
- 演示内容通过本机回环地址上的真实 HTTP/WS 测试对端接收。文件为本次创建的「传输说明.txt」和新图标，未使用私人文件。
- 待发送文件通过实际系统分享扩展导入，发送框文字仅为演示草稿，没有发送至用户的 Listen1 实例。
- 连接页保留了当时 Bonjour 发现的局域网设备名称。截图反映真实状态，没有修图替换地址。
- 当前只有 iPhone 截图；如保留 iPad 支持，上架时还需采集 iPad 对应尺寸素材。

| 连接与设备发现 | 文本与文件发送 |
| --- | --- |
| ![连接](app-store-iphone-air/01-connection.jpg) | ![发送](app-store-iphone-air/02-send.jpg) |

| 收件箱 | 系统分享扩展 |
| --- | --- |
| ![收件箱](app-store-iphone-air/03-inbox.jpg) | ![分享扩展](app-store-iphone-air/04-share-extension.jpg) |

尺寸参考：[Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。最终以 App Store Connect 对当前应用显示的截图槽位要求为准。
