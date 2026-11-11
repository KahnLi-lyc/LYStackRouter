# Changelog

## 0.1.1 (2026-11-11)

### Fixed

- 处理器上下文绑定创建它的那次执行：`show`、`present`、`prepare`、`confirm`、`replaceStack`、`revealExisting`、`continueNavigation`、`markPerformed`、`fail` 在该执行结算后调用会被忽略，旧上下文不再能展示页面或改写后来执行的结果。`open`、`back` 不受影响。
- 确认框结算后，确认回调在每个挂起点之后核对代次与会话；会话重置或切换后不再继续导航。
- 禁用（静态或远程重写）与占位路由走兜底前，先经过外部白名单、参数校验与拦截器；未注册路由的外部请求一律 `.unregistered`。
- 展示阶段以 `.blocked` 结算的外部请求只在新的稳定事件后重试，不再自我重放；执行期间到达的更新请求照常执行。
- `url(for:)` 只返回能被整张路由表解析回原路由的 URL：首选模板被遮蔽时换用别名模板，都不行时返回 nil。
- `LYTabBarHost`、`LYSingleStackHost` 在路由器 `attach` 时为全部导航栈安装代理，先建宿主后放导航栈也能上报 `didShow`。

### Documentation

- README 与接入指南改为由协调器同时持有宿主与路由器；说明 `.blocked` 后需调用 `navigationDidStabilize()`、URL `parse`/`print` 需往返一致。
- 示例 App 改为先放导航栈再创建宿主。

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
