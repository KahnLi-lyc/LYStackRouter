# 最小公开 API 消费宿主

这个独立 UIKit App 不使用 `@testable` 或 XCTest，部署目标保持 iOS 16。两个 Release scheme 使用同一组真实导航断言：

| Scheme | 产品 | 装配方式 |
| --- | --- | --- |
| LYRouterCoreCompatibility | LYStackRouter | 显式模块；用于 Swift 6.1 配套 Xcode/SDK 验收 |
| LYRouterDiscoveryCompatibility | LYStackRouterDiscovery | 宏发现，无显式后备；用于 Swift 6.3 配套 Xcode/SDK 及 Release 链接验收 |

断言包含模块注册、页面创建、身份复用、移出清理一次、旧客户端撤销、新客户端可用、不响应取消的准备任务、动作结果、模态关闭和返回。启动期间 `isReady=false`，根页真实出现后通知稳定。报告显示在根页面，同时写到 App 沙盒 `Documents/compatibility-report.json`。一次失败不会被自动重试成成功。

修改 `project.yml` 后运行 `xcodegen generate --spec Examples/CompatibilityHost/project.yml`。工具链只通过命令指定，不执行全局 `xcode-select`。

## 模拟器

在仓库根目录，用生命周期 `run` 包装下面的命令，传入该任务独立 evidence 子目录；脚本负责启动所指定的已有模拟器。生产验收必须使用实际的目标运行时，不能仅设置 deployment target。

```bash
DEVELOPER_DIR=/Applications/Xcode_16.3.app/Contents/Developer \
python3 Examples/CompatibilityHost/verify-simulator.py \
  --scheme LYRouterCoreCompatibility --device "$IOS16_UDID" \
  --derived-data "$CODEX_CACHE_DIR/compatibility-61" \
  --packages "$CODEX_DEPENDENCIES_DIR/packages" \
  --evidence "$CODEX_EVIDENCE_DIR/ios16-core"

DEVELOPER_DIR=/Applications/Xcode_26.4.app/Contents/Developer \
python3 Examples/CompatibilityHost/verify-simulator.py \
  --scheme LYRouterDiscoveryCompatibility --device "$IOS17_UDID" \
  --derived-data "$CODEX_CACHE_DIR/compatibility-63" \
  --packages "$CODEX_DEPENDENCIES_DIR/packages" \
  --evidence "$CODEX_EVIDENCE_DIR/discovery-release"
```

Xcode 16.3 / 26.4 分别是官方 Swift 发布元数据列出的 Swift 6.1 / 6.3 配套版本。安装后先记录实际 `xcrun swift --version`、`xcodebuild -version` 和 SDK 版本。最低工具链检查与最低系统运行是两个维度；若不能组合，在各自支持的宿主上分别验收。

iOS 17 完整示例还需运行：

```bash
xcodebuild test -project Examples/LYStackRouterExamples.xcodeproj \
  -scheme LYStackRouterExamples -destination "platform=iOS Simulator,id=$IOS17_UDID" \
  -derivedDataPath "$CODEX_CACHE_DIR/examples-ios17" \
  -clonedSourcePackagesDirPath "$CODEX_DEPENDENCIES_DIR/packages" \
  -resultBundlePath "$CODEX_EVIDENCE_DIR/examples-ios17.xcresult" \
  SWIFT_STRICT_CONCURRENCY=complete CODE_SIGNING_ALLOWED=NO
```

## 真机与签名

在 Xcode 选定自己有权使用的 Team，为两个 bundle ID 配置有效 profile；本工程不预设组织。连接并解锁 iPhone/iPad，打开开发者模式。分别安装两个 Release App，确认屏幕 PASS、检查 JSON 的 passed/checks/systemVersion，并保存设备型号、系统、签名身份和源码 SHA。继续手动验证动画 push/back、侧滑完成/取消、模态关闭、后台恢复及多窗口（支持时）。

```bash
xcodebuild archive -project Examples/CompatibilityHost/LYRouterCompatibility.xcodeproj \
  -scheme LYRouterCoreCompatibility -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$CODEX_CACHE_DIR/device-archive" \
  -clonedSourcePackagesDirPath "$CODEX_DEPENDENCIES_DIR/packages" \
  -archivePath "$CODEX_DELIVERIES_DIR/LYRouterCoreCompatibility.xcarchive" \
  DEVELOPMENT_TEAM="$SIGNING_TEAM" SWIFT_STRICT_CONCURRENCY=complete
```

再以 Discovery scheme 执行同样的签名 Archive，并核查包内签名与架构。无签名 Archive 只能证明编译/链接，不能替代有效签名或真机运行。环境及未完成项目见 [生产准备记录](../../Docs/Production-Readiness-0.3.0.zh-Hans.md)。
