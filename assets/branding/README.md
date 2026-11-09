# share_xuan Wi-Fi 图标

- 原图：相邻 `listen1_xuan/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`。
- 使用内置 image_gen 编辑，保留灰发猫耳人物、蓝色背景与总体布局，右下角音乐音符替换为深蓝 Wi-Fi 符号。
- `share-xuan-wifi-source.png` 为生成原图。
- 工程使用 `../../App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`，1024×1024 RGB PNG、无 alpha。仅用 sips 做尺寸适配，未对图像进行其他手工重绘。
- 主 target 的 App Icons Source 为 `AppIcon`；模拟器桌面和系统分享菜单已验证显示。

最终编辑提示词（内置工具模式）：

> Use case: precise-object-edit. Edit target: attached existing Listen1 Xuan iOS app icon. Produce a square 1024x1024 opaque iOS app icon. Replace ONLY the large dark royal blue music-note symbol overlapping the lower-right corner with a recognizable dark royal blue Wi-Fi symbol: three clean nested curved signal arcs above a small circular dot, similar overall visual weight and placement as the original music note, contained within the canvas. Remove every trace of the music note and reconstruct the small obscured area of the character naturally. Preserve the existing pixel-art gray-haired cat-eared girl's identity, pose, cyan eyes, pink ears, black cat hair accessory, clothing, pixel outlines, background blue color, scale and composition as closely as possible. Do not redraw or redesign the character. Wi-Fi symbol should read clearly at small app-icon sizes. No text, no extra badges, no phone frame. Fill any white/transparent outer corner cutouts with matching light blue so the background reaches all four edges; iOS will apply its own corner mask. No transparent pixels.
