# LYStackRouter 编码规范

本规范是 LY 系列组件库的统一编码规范，只保留与通用组件相关的条目，便于跨项目统一评审。

## 文件与格式

- 文件使用 UTF-8、LF 和末尾换行；缩进由 `.editorconfig` 与 SwiftFormat 统一。
- 日常只用 `swiftformat --lint .` 检查，不改写源码。确需自动格式化时，限定到本次改动的文件，逐项审查 diff 后再提交；不为通过检查批量改写无关代码。
- SwiftFormat 版本或规则的调整单独评估，并验证受影响范围。

## 命名

| 层级 | 规则 | 示例 |
| --- | --- | --- |
| Package、product、target、module | 保留 `LYStackRouter` 完整身份 | `LYStackRouterCore`、`import LYStackRouter` |
| 公开类型与协议 | `LY` 前缀加明确职责 | `LYStackRouter`、`LYRouteRegistry`、`LYRouterHost` |
| 模块内部、private、测试类型 | 只用职责名，不强制前缀 | `ExecutionTicket`、`FakeHost`、`URLMatcherTests` |
| 嵌套类型与系统约定名 | 保持语义名称 | `Builder`、`Kind`、`Entry` |

- 名称短而明确，表达职责；避免 `Manager`、`Helper`、`Utils` 和大型 Provider，优先用 Registry、Host、Context、Adapter 等。
- 不建立 `LY` 命名空间 enum 把类型嵌套进去。
- 主文件名与主要类型一致；扩展文件使用 `Type+Responsibility.swift`。

## 文件组织

- 每个文件只承担一个清晰职责；不把多个独立类型堆在同一文件。
- `Sources/<模块>/` 根目录不散放源码，按职责建目录，例如 `Registry`、`URL`、`Pipeline`、`Results`、`Engine`、`Hosting`、`Discovery`。只建实际需要的目录。
- 测试放在包级 `Tests`，不放进生产 `Sources`。

## 注释

- 公开类型、属性、初始化方法和方法必须使用简体中文 `///` DocC，保留英文类型与 API 名称。
- 内部核心属性、异步方法和复杂逻辑使用中文注释，按需说明用途、调用时机、线程要求、持有关系、取消与清理语义；不逐行翻译代码。
- 使用 `// MARK:` 分组，不为凑顺序创建空分组。类型内默认顺序：

```text
Properties
Initialization
Public
Internal
Teardown
Private
```

UIKit 视图与控制器（示例工程、内置宿主）沿用以下顺序，按实际职责省略空分组：

```text
Properties → UI Components → Initialization → View Lifecycle → Layout → Binding → Actions → Teardown → Private
```

## 可见性

- 默认最小可见性；只有接入方需要的类型和成员才声明 `public`。
- 测试通过 `@testable import` 访问内部实现，不为测试额外加 `public`。

## Swift 6 与生命周期

- 遵守 `-strict-concurrency=complete`，零警告；禁止 `@unchecked Sendable` 与 `nonisolated(unsafe)`。
- UIKit 相关类型与路由执行标注 `@MainActor`。
- 启动、停止、解绑与清理使用显式、幂等的方法；重复调用安全；`deinit` 不访问 UIKit 或 lazy 视图。
- 异步工作用代次或身份令牌拦截迟到回调；新请求覆盖旧请求时取消旧任务。
- 取消不是普通失败，不能触发成功、重试或持久化副作用。

## 错误与日志

- 失败原因使用类型化的 `LYRouteFailure` 与 `LYRouteBuildError` 区分：取消、被拦截、参数无效、不可用、上下文已变化、注册错误等。不吞掉错误，不用含义不明的 `Bool` 代替原因。
- 观察者与诊断只记录路由 Kind、来源和结果，不记录 URL 参数原文，避免泄露 Token 等敏感值。

## 测试

- 任何行为变更都要补测试；修复缺陷先写能复现的失败用例。
- 覆盖成功、失败、取消、迟到回调、重复调用、会话切换与幂等。
- 引擎语义测试使用假宿主与假页面，断言实际的栈与清理结果，而不只是检查方法被调用。

## 文档与生成物

- 文档只陈述源码和测试能证明的现状；未来能力明确标记为计划。
- 示例工程由 XcodeGen 的 `Examples/project.yml` 生成，不手改 `.xcodeproj`。
- 提交信息使用简体中文，前缀为 `feat:`、`fix:`、`test:`、`docs:`、`refactor:`、`chore:`。
