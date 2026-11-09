# GitHub Actions → TestFlight

## 当前已配置

- `.github/workflows/ci.yml`：push / pull_request / 手动运行，执行 Swift 测试、iOS 模拟器无签名构建以及签名脚本测试。不读取发布凭据。
- `.github/workflows/testflight.yml`：仅手动触发，且仅允许仓库默认分支。使用 `macos-26` runner 自带 Xcode，归档 Release、分别签名主应用/扩展、导出 IPA，使用 `xcrun altool` 验证并上传。
- 不依赖 fastlane。不会提交外部测试审核，不会创建公开邀请链接，不会发布 App Store 版本。
- 不将 IPA、证书、描述文件或私钥上传到公开的 Actions artifacts。
- 发布构建号为 `run_number / 100 + 1`.`run_number % 100`.`run_attempt`，例如第 1 次运行生成 `1.1.1`。主应用和扩展使用相同构建号，重跑会递增最后一段。请重跑最新任务，勿重跑较旧任务后期待其构建号大于新版本；若 Apple 已有更高构建号需调整该规则。
- 使用临时 keychain，验证描述文件类型、过期时间、团队、Bundle ID、App Group 及是否包含导入证书。退出时恢复 keychain 搜索列表并清理凭据。

本地已验证 YAML/actionlint、Python 签名配置测试；没有使用真实证书执行签名或上传，也未替用户配置 GitHub Secrets。首次远程执行仍需验证 runner 的 Xcode、签名和 Apple 接收结果。

## 1. Apple 侧准备

需要 Apple Developer Program 团队，并已在 App Store Connect 建立主应用记录。

| 项目 | 值 |
| --- | --- |
| 主应用 Bundle ID | `xyz.040905.share` |
| 扩展 Bundle ID | `xyz.040905.share.ShareExtension` |
| 两者共同关联的 App Group | `group.xyz.040905.share` |

### 签名证书

在 macOS「钥匙串访问 → 我的证书」找到 **Apple Distribution** 证书，确认能展开看到对应私钥，再导出为 `.p12`，设置非空导出密码。

只有 `.cer`、只有证书而没有私钥、Apple Development 证书都不能用于这条发布流程。不要为了 CI 撤销现有有效证书。

### 两份分发描述文件

Apple Developer → Certificates, Identifiers & Profiles → Profiles → +，选择 **App Store Connect** 分发类型（旧界面可能称 App Store）：

1. 主应用 `xyz.040905.share`。
2. 扩展 `xyz.040905.share.ShareExtension`。

两份都选择上述 `.p12` 对应的同一个 Distribution 证书。两个 App ID 必须已关联相同 App Group；如果之后才开启 App Groups，需要重新生成 profiles。下载得到两个 `.mobileprovision`，名称任意，CI 读取其 UUID，无需手动填写 profile 名称。

### 上传用 API Key

App Store Connect → Users and Access → Integrations → App Store Connect API，创建 **Team API Key**，使用具有上传权限的角色（Developer 或以上）。保存：

- Key ID
- Issuer ID
- 下载的 `AuthKey_….p8` 私钥（只提供一次下载机会）

这是上传凭据，不代替 `.p12` 和两份描述文件。无需提供 Apple ID 密码或双重验证码。

## 2. GitHub 配置

打开仓库 **Settings → Environments → New environment**，创建名称严格为 `testflight` 的环境。

在该环境配置 Deployment branches and tags，仅允许默认分支。可按团队需要设置 required reviewers。workflow 本身也限制只在默认分支执行，但环境限制能独立约束凭据的使用。

在此环境添加以下 **7 个 Environment secrets**：

| Secret 名称 | 内容 |
| --- | --- |
| `DISTRIBUTION_P12_BASE64` | 带私钥的 Apple Distribution `.p12` 文件的 Base64 |
| `DISTRIBUTION_P12_PASSWORD` | `.p12` 导出时设置的密码，原文 |
| `APP_PROFILE_BASE64` | 主应用 `.mobileprovision` 文件的 Base64 |
| `SHARE_PROFILE_BASE64` | 扩展 `.mobileprovision` 文件的 Base64 |
| `ASC_PRIVATE_KEY_BASE64` | API `.p8` 私钥文件的 Base64 |
| `ASC_KEY_ID` | API Key ID，原文 |
| `ASC_ISSUER_ID` | API Issuer ID，原文 |

再添加 **Environment variable**：

| Variable 名称 | 内容 |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer 的 10 位 Team ID；当前本地工程配置为 `UVC5T2MPT7`，请以你自己的账号 Membership Details 为准 |

在 Mac 终端把文件编码后直接复制到剪贴板，不输出到终端、不提交到仓库：

```sh
base64 -i "/路径/Distribution.p12" | tr -d '\n' | pbcopy
base64 -i "/路径/Main.mobileprovision" | tr -d '\n' | pbcopy
base64 -i "/路径/ShareExtension.mobileprovision" | tr -d '\n' | pbcopy
base64 -i "/路径/AuthKey_你的KeyID.p8" | tr -d '\n' | pbcopy
```

每次执行一条，然后粘贴到对应 Secret。Base64 不是加密，这些内容仍然属于凭据；不要粘贴到 issue、聊天或 workflow 文件中。

## 3. 首次上传前的工程事项

- 已配置 1024×1024、无透明通道的 AppIcon（Listen1 原图标右下音乐符号改为 Wi-Fi）。已取得 iPhone Air 真实截图，见 `assets/screenshots/README.md`；目前尚未采集 iPad 截图。
- 复核 privacy manifest / required-reason API 声明、依赖隐私信息、ATS 兼容配置和出口合规；CI 无法代替产品声明与审核。
- 确认 App Store Connect 主应用记录选择的是 `xyz.040905.share`。
- 版本号来自 `Config.xcconfig` 的 `MARKETING_VERSION`。CI 自动覆盖构建号，不更改版本号。

## 4. 运行

1. 将这些 workflow、脚本和文档提交并推送至仓库默认分支。当前修改不会自动替你提交或推送。
2. 等 `iOS CI` 通过。
3. GitHub → Actions → **TestFlight** → **Run workflow**，选择默认分支。
4. 任务成功表示上传命令已被 Apple 接受，并不表示处理/审核完成。
5. 在 App Store Connect → 应用 → TestFlight 等待处理；按实际加密使用情况回答出口合规问题，选择内部测试组。
6. 外部测试仍可能需要 Beta App Review，且需补充测试信息。该流程不会自动提交审核。

## 常见错误

- `Missing GitHub environment configuration`：环境名、Secret 名称或变量缺失。
- `different team` / `Bundle ID does not match` / `App Group`：profile 对应的 App ID、团队或 group 不一致。
- `does not include the imported Distribution certificate`：重新生成 profile 时选错证书。
- `P12 must include…private key`：导出的是纯证书或开发证书，不是带私钥的 Distribution identity。
- 上传提示图标、隐私、版本号、协议未接受等：属于 Apple 接收条件，需要修复后重新运行；日志成功执行 Archive 不代表上传必然成功。

签名准备脚本仅允许在 GitHub Actions 临时 runner 中运行，避免修改开发机的钥匙串。普通测试不需要 Secrets：

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
actionlint .github/workflows/*.yml
```

官方资料：[GitHub 安装签名证书](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)、[Apple 上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)、[GitHub macOS runner 镜像](https://github.com/actions/runner-images)。
