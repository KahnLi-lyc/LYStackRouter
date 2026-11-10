# LYStackRouter 开发规范

本文件对参与本仓库的人与 AI 代理同等生效。编码细则见 [CODING_STYLE.md](CODING_STYLE.md)。

## 1. 项目事实

- SwiftPM 库，模块：`LYStackRouterCore`（Foundation）、`LYStackRouter`（UIKit 引擎）、`LYStackRouterDiscovery`（可选自动发现）、`LYStackRouterMacros`（宏实现）。
- 平台：iOS 16（引擎）；Core 与宏同时支持 macOS 13，以便 `swift test`。`swift-tools-version: 6.1`，Swift 6 language mode。
- 依赖：`LYStackRouterCore` 与 `LYStackRouter` 零第三方依赖；swift-syntax 只用于宏 target。
- 公开类型统一使用 `LY` 前缀；模块名保持 `LYStackRouter*`。

## 2. 设计原则

1. **类型化路由优先**：接入方用枚举表达路由；URL 只在入口解析成路由。
2. **模块自己注册**：每个业务模块用 `register(into:)` 登记页面、动作与 URL 模式；宿主显式列出模块，或通过可选的自动发现收集。
3. **失败关闭**：漏注册、重复注册、URL 冲突、缺依赖都在 `build()` 时报错，不在运行时悄悄失效。
4. **无单例**：路由器由宿主按窗口创建并注入；依赖经 `LYRouteEnvironment` 传入。
5. **执行引擎语义不降级**：一次导航只结算一次、返回可抢占准备阶段、外部请求只保留最近一个、只清理确实移出的页面、迟到回调用代次拦截。修改这些语义必须先补失败用例。

## 3. 并发规则

1. `-strict-concurrency=complete` 下零警告。
2. 禁止 `@unchecked Sendable`、`nonisolated(unsafe)`。
3. UIKit 相关类型与路由执行一律 `@MainActor`；清理方法显式且幂等，`deinit` 不访问 UIKit。

## 4. 测试与提交

- 任何行为变更都要补测试；修复缺陷先写能复现的失败用例。
- 提交前运行：`swift build`、`swift test`（macOS，含宏展开测试）、iOS Simulator 上的 `xcodebuild test -scheme LYStackRouter-Package -skip-testing:LYStackRouterMacrosTests`（宏测试只能在 macOS 宿主运行）、`swiftformat --lint .`。
- 改动引擎、宿主或自动发现时，另在 iOS Simulator 上运行示例工程测试：`xcodebuild test -project Examples/LYStackRouterExamples.xcodeproj -scheme LYStackRouterExamples`（宿主内引擎测试与 UI 测试）。
- 改动公开 API 时同步更新 `Examples/` 与 README；修改 `Examples/project.yml` 后用 `xcodegen generate` 重新生成工程并一起提交。
- 提交信息使用简体中文，前缀为 `feat:`、`fix:`、`test:`、`docs:`、`refactor:`、`chore:`。
