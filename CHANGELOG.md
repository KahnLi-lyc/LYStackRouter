# Changelog

## 0.1.0 (2026-11-11)

### Added

- `LYStackRouterCore`：`LYRoutable`、`LYRouteRegistry` 与 Builder（`page`、`action`、`url`）、`LYRoutePolicy`、`LYRouteEnvironment`、`LYRouteBuildError`；构建时检查漏注册、重复注册、重复模块、缺依赖与 URL 冲突。
- URL 模板：`<key>`、`<int:key>`、`<path:key>` 占位，自定义 scheme 与 Universal Link host 白名单，按字面段数消歧，解析与生成双向使用。
- 管线：`LYRouteInterceptor`（优先级、类型化决策、`.session` 会话拦截）、`LYRouteRewrite`（可 Codable 下发的禁用与模板替换）、`LYRouteObserver`、`LYRouteFallback`。
- `LYStackRouter` 执行引擎：一次导航只结算一次、按身份复用页面、返回抢占异步准备、外部请求只保留最近一个并绑定会话、只清理确实移出的页面、确认门与未呈现兜底、跨导航栈恢复会话型页面。
- 宿主：`LYRouterHost` 协议、`LYSingleStackHost`、`LYTabBarHost`、`LYNavigationEventSource`、`customShow` 钩子；`LYRouteModule` 与 `LYRouteModuleSet.explicit`；`router.moduleIDs`。
- `LYStackRouterDiscovery`：`@LYRouteModule` 宏与 Mach-O section 自动发现，`LYRouteModuleSet.discovered` 与 `discovered(plus:excluding:)`。
- `Examples/`：三 Tab UIKit 示例 App（XcodeGen）、本地业务模块包、11 个 UI 测试与 6 个宿主内引擎测试。
- 文档：设计说明、接入指南、自动注册说明。
