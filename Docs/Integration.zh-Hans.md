# 接入指南

## 1. 定义路由

在所有业务模块都能依赖的位置（例如 `AppRoutes` 包）定义路由枚举。只放路由、页面身份和目标域常量，不放页面实现。

```swift
public enum AppRoute: LYRoutable {
    case club(String)
    case chat(String)
    case wallet

    public enum Kind: CaseIterable, Sendable { case club, chat, wallet }

    public var kind: Kind { ... }
}

public extension LYRoutePlacement {
    static let messages = LYRoutePlacement("messages")
}
```

`Kind` 的名称（`String(describing:)`）会出现在构建错误、远程降级配置和观察者回调中，确定后不要随意改名。

## 2. 每个业务模块写一个路由模块

- `moduleID` 稳定且唯一，用于诊断、排序和去重。
- 依赖只从 `LYRouteEnvironment` 取：`try environment.require(ClubAPI.self)`。缺依赖时构建报出模块名和类型。
- 页面用 `builder.page`，不改变导航栈的操作（弹面板、打开系统设置）用 `builder.action`，后者结果为 `.performed`。
- 需要从推送、深链、H5 打开的路由，显式设置 `allowsExternal: true`。
- 参数校验放进 `validate`，校验失败不会产生任何导航副作用。
- 跨模块跳转只调用 `context.open(.chat(id))`，不 import 对方模块。

### 处理器里的常用操作

| 需求 | 写法 |
|---|---|
| 已有就回到它，否则新建 | `context.show(identity: id) { makePage() }` |
| 每次都新建 | `context.show { makePage() }` |
| 先拉数据再决定 | `context.prepare { ctx in try await load(); guard await ctx.isStillValid() else { return }; ctx.show { ... } }` |
| 需要用户确认 | `context.confirm(title:message:confirmTitle:cancelTitle:) { ctx in ctx.show { ... } }` |
| 会话型页面（例如语音房）在任意 Tab 中已存在 | `if context.revealExisting(where: { ($0 as? RoomPage)?.id == id }) { return }` |
| 处理器内同步改为另一路由 | `context.continueNavigation(to: .login)` |
| 页面按钮发起新导航 | 页面持有 `{ context.open($0) }` |

### 页面协议

- `LYPageIdentifiable.routeIdentity`：页面当前的业务身份，每次查找时实时读取，所以“草稿页保存后变成详情页”这类身份变化可以直接反映。
- `LYRoutePageLifecycle.routerDidRemovePage()`：只在路由器把页面移出导航栈后调用一次，用于停止播放、断开连接等。用户手动返回不会触发它，页面自己的生命周期仍需处理。

## 3. 宿主组装

```swift
var environment = LYRouteEnvironment()
environment.provide(ClubAPI.self, clubAPI)

let router = try LYStackRouter<AppRoute>.build(
    host: host,
    modules: .discovered,                    // 或 .explicit([...])
    environment: environment,
    interceptors: [sessionInterceptor],
    observers: [analytics],
    url: LYURLConfiguration(schemes: ["myapp"], universalLinkHosts: ["app.example.com"]),
    rewrite: remoteConfig.routeRewrite,
    fallback: .placeholder
)
```

- 每个窗口创建自己的宿主和路由器，由 SceneDelegate 或窗口协调器持有。路由器弱引用宿主。
- 根视图上屏前把宿主的 `isRouterReady` 设为 false；上屏后改为 true 并调用 `router.navigationDidStabilize()`，冷启动携带的深链会在这之后执行。
- 会话变化后更新宿主的 `routerSessionID` 并调用 `router.sessionDidChange()`。
- 场景断开时调用 `router.tearDown()`，之后的请求以 `.stopped` 失败。

### 选择宿主

| 场景 | 宿主 |
|---|---|
| 模块 Demo、单元测试、单栈 App | `LYSingleStackHost(navigationController:)` |
| 标准 `UITabBarController`，每个 Tab 一个导航栈 | `LYTabBarHost(tabBarController:placements:)` |
| 自研 TabBar、分栏容器、浮窗 | 自定义类型遵循 `LYRouterHost`；可以组合 `LYTabBarHost`，只覆盖需要的方法 |

自定义宿主需要在导航栈 `didShow` 时调用 `router.navigationDidShow(in:)`，或者遵循 `LYNavigationEventSource` 让路由器在 `attach` 时自动接上回调。示例工程的 `DemoHost` 展示了组合写法与 `customShow` 钩子。

如果业务也需要导航代理，设置内置宿主的 `forwardingDelegate`，不要替换导航栈的 `delegate`。

## 4. 拦截、降级与观察

- 拦截器同步返回决策，在切换 Tab、创建页面之前执行。常见的会话拦截：未登录时用户点击重定向到登录页，外部请求等待登录后继续。

  ```swift
  LYRouteInterceptor<AppRoute>(name: "session", priority: 1000) { request in
      guard request.requiresSession, !session.isSignedIn else { return .proceed }
      return request.source.isExternal ? .deferUntilReady : .redirect(.login)
  }
  ```

- 重定向后的路由重新经过完整准入，重定向深度上限为 4。
- `router.rewrite` 可以随时整体替换。`disabledKinds` 中的路由以 `.unavailable` 失败；配置了 `fallback` 时交给兜底展示。兜底前仍会检查外部白名单、参数校验与拦截器，降级不会放宽原入口的约束。
- 观察者只能读取，不能改变执行结果。回调中没有 URL 原文，日志里不要再自行拼接参数。

## 5. 模块 Demo

业务模块的 Demo App 只需要自己的模块：

```swift
let router = try LYStackRouter<AppRoute>.build(
    host: LYSingleStackHost(navigationController: navigation),
    modules: .explicit([ClubRouteModule.self]),
    environment: demoEnvironment,
    fallback: .placeholder,
    allowsUnregistered: true
)
```

`allowsUnregistered: true` 关闭穷尽检查，其他模块的路由会打开占位页。正式 App 不要开启它。

## 6. 测试建议

- 模块的登记逻辑可以用 `LYSingleStackHost` 加假依赖做单元测试，`request` 同步返回结果。
- 涉及转场、弹窗、确认框的行为需要在有窗口的宿主测试或 UI 测试中验证，包内无窗口测试覆盖不到。
- 为 URL 模板写往返测试：`router.route(for: router.url(for: route)!) == route`。
