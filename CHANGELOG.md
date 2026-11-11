# Changelog

## 0.2.0 (Unreleased)

### Added

- `LYOpenOptions` 传递动画、弱来源页面和 `Sendable` 附加值，打开入口与上下文支持选项。
- `canOpen`、`canOpenURL` 与提交共用静态准入检查。
- 来源限定的模态导航栈内流程及执行绑定的目标导航域。
- 可注入且绑定来源／代次的 `LYRouteClient`，支持打开、URL 和关闭操作及测试替身。
- 场景感知的 `LYWindowContext`，提供窗口、顶层控制器、几何和安全区查询。
- 四个独立示例包、两个可运行模块 Demo、注册与 UI 冒烟测试，以及嵌套容器、模态流程和会话最小化恢复场景。

### Fixed

- 页面复用回退使用请求或处理器显式指定的动画选项。
- 禁用路由的兜底执行与等待调度使用一致的导航目标域。
- 导航上下文变化后及时终止失效准备，并在清理前核对页面归属。
- 跨目标域确认后绑定确认页面，继续保留附加值与动画选项。
- 修改 URL scheme、Universal Link host 和首选 scheme 后继续进行大小写归一化。
- 模态关闭通知晚于导航容器释放时，仍能清理存活页面并终止旧准备。
- 失效转场释放页面强快照，迟到清理跳过重新挂载、展示或入栈的页面；原宿主释放后仍通知页面生命周期。
- 保留上下文在路由器释放后创建的客户端，三个操作统一返回 `contextChanged`。

### Documentation

- 中英文 README、接入与设计说明增加新接口、生命周期边界、独立模块结构与运行方式。
- 验证矩阵、缺陷复现与环境边界见 [0.2.0 审查记录](Docs/Review-0.2.0.zh-Hans.md)。

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
