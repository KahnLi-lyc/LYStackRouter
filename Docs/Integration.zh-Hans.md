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
- URL 的 `parse` 与 `print` 必须往返一致且没有副作用：`router.url(for:)` 会用整张路由表解析生成的 URL，解析结果不等于原路由时返回 nil，因此 `parse` 做了规范化（例如把未知参数改成默认值）的路由无法生成 URL。
- 参数校验放进 `validate`，校验失败不会产生任何导航副作用。
- 跨模块通过路由契约通信：页面按钮用 `context.open(route)` 发路由；需要依赖注入或测试替身时，注入 `context.makeClient(from: page)` 创建的客户端。

### 处理器里的常用操作

| 需求 | 写法 |
|---|---|
| 已有就回到它，否则新建 | `context.show(identity: id) { makePage() }` |
| 每次都新建 | `context.show { makePage() }` |
| 先拉数据再决定 | `context.prepare { ctx in try await load(); guard await ctx.isStillValid() else { return }; ctx.show { ... } }`（`isStillValid` 必须写，路由器不会自动检查） |
| 需要用户确认 | `context.confirm(title:message:confirmTitle:cancelTitle:) { ctx in ctx.show { ... } }` |
| 会话型页面（例如语音房）在任意 Tab 中已存在 | `if context.revealExisting(where: { ($0 as? RoomPage)?.id == id }) { return }` |
| 处理器内同步改为另一路由 | `context.continueNavigation(to: .login)` |
| 页面按钮发起新导航 | `page.onTap = { context.open(route) }` |
| 页面或业务服务注入导航能力 | `let client = context.makeClient(from: page)`，调用 `await client.open(route)` |

### 页面协议

- `LYPageIdentifiable.routeIdentity`：页面当前的业务身份，每次查找时实时读取，所以“草稿页保存后变成详情页”这类身份变化可以直接反映。
- `LYRoutePageLifecycle.routerDidRemovePage()`：只在路由器把页面移出导航栈后调用一次，用于停止播放、断开连接等。路由器移出包括复用回退、`replaceStack`、`back` 与 `LYRouteClient.dismiss` 关闭模态流程；用户手动返回、下滑关闭模态、业务自行 `dismiss` 都不会触发它，页面自己的生命周期仍需处理。

清理会重新检查页面是否仍在导航栈、被其他容器接管、被模态展示或挂在窗口中。转场期间重置宿主会释放强页面快照，迟到回调只检查仍存活的页面。清理使用操作开始时的宿主；原宿主释放后直接通知页面生命周期。自定义宿主若需要执行额外的 `tearDown` 工作，应保持存活至对应转场结束。

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

- 每个窗口创建自己的宿主和路由器，由 SceneDelegate 或窗口协调器**同时持有两者**（写法见 README 的 `AppCoordinator`）。路由器只弱引用宿主，宿主也只弱引用路由器的回调，两者之间没有循环持有；只保存路由器、不保存宿主时，宿主会立刻释放，用户请求被忽略、外部请求一直等待。
- 根视图上屏前把宿主的 `isRouterReady` 设为 false；上屏后改为 true 并调用 `router.navigationDidStabilize()`，冷启动携带的深链会在这之后执行。
- 会话变化后更新宿主的 `routerSessionID` 并调用 `router.sessionDidChange()`。
- 场景断开时调用 `router.tearDown()`，之后的请求以 `.stopped` 失败。

### 选择宿主

| 场景 | 宿主 |
|---|---|
| 模块 Demo、单元测试、单栈 App | `LYSingleStackHost(navigationController:)` |
| 标准 `UITabBarController`，每个 Tab 一个导航栈 | `LYTabBarHost(tabBarController:placements:)` |
| 自研 TabBar、分栏容器、浮窗 | 自定义类型遵循 `LYRouterHost`；可以组合 `LYTabBarHost`，只覆盖需要的方法 |

自定义容器（或 `customShow`、处理器）以 `.blocked` 挡住外部请求时，请求会进入等待，只在新的稳定事件后重试；阻挡解除后宿主必须调用 `router.navigationDidStabilize()`，否则请求会一直等待。

自定义宿主需要在导航栈 `didShow` 时调用 `router.navigationDidShow(in:)`，或者遵循 `LYNavigationEventSource` 让路由器在 `attach` 时自动接上回调。示例工程的 `DemoHost` 展示了组合写法与 `customShow` 钩子。

如果业务也需要导航代理，设置内置宿主的 `forwardingDelegate`，不要替换导航栈的 `delegate`。

内置宿主在路由器 `attach` 时会成为当前全部导航栈的代理，所以“先建宿主、后放导航栈”也能收到系统返回与侧滑的 `didShow`。之后若再更换 `tabBarController.viewControllers`，请重新调用 `router.attach(host)`。

## 4. 拦截、降级与观察

- 拦截器同步返回决策，在切换 Tab、创建页面之前执行。常见的会话拦截：未登录时用户点击重定向到登录页，外部请求等待登录后继续。

  ```swift
  LYRouteInterceptor<AppRoute>(name: "session", priority: 1000) { request in
      guard request.requiresSession, !session.isSignedIn else { return .proceed }
      return request.source.isExternal ? .deferUntilReady : .redirect(.login)
  }
  ```

- 重定向后的路由重新经过完整准入，重定向深度上限为 4。观察者只收到目标路由的 `routeWillOpen` 与 `routeDidSettle`，需要统计重定向时在拦截器中自行记录。
- `router.rewrite` 可以随时整体替换。`disabledKinds` 中的路由以 `.unavailable` 失败；配置了 `fallback` 时交给兜底展示。兜底前仍会检查外部白名单、参数校验与拦截器，降级不会放宽原入口的约束。
- 观察者只能读取，不能改变执行结果。回调中没有 URL 原文，日志里不要再自行拼接参数。
- 外部请求进入等待时结算为 `.deferred`；之后被更新请求取代、会话变化、重置、来源失效或路由器停止而不再执行时，观察者收到一次 `routeDidDropPending(_:source:reason:)`，原因见 `LYPendingDropReason`。

## 5. 模块 Demo

业务模块的 Demo App 只需要自己的模块：

```swift
// Demo 的 SceneDelegate 用属性同时持有宿主与路由器；路由器只弱引用宿主。
demoHost = LYSingleStackHost(navigationController: navigation)
demoRouter = try LYStackRouter<AppRoute>.build(
    host: demoHost,
    modules: .explicit([ClubRouteModule.self]),
    environment: demoEnvironment,
    fallback: .placeholder,
    allowsUnregistered: true
)
```

`allowsUnregistered: true` 关闭穷尽检查，其他模块的本地路由请求会交给兜底。需要完整登记检查的宿主使用默认值 false。

完整工程位于 `Examples/Packages/DemoCommunityFeature/Demo` 和 `Examples/Packages/DemoMessagingFeature/Demo`，分别使用 `DemoCommunityFeatureDemo` 与 `DemoMessagingFeatureDemo` scheme。各自的 `project.yml` 生成可运行 App、宿主测试和 UI 冒烟测试。功能包只依赖公共契约、公共 UI 和路由库。单栈 Demo 可以自定义宿主，把模块声明的命名 placement 映射到唯一导航栈。

嵌套容器宿主应把详情导航栈纳入 `navigationDomain(for:)` 和 `allNavigationControllers`，转发该栈的 `didShow`，并在 `reveal` 中映射回所属 Tab。主示例的消息容器与 `DemoHost` 提供实现。

## 打开选项与静态可达性

```swift
let options = LYOpenOptions(
    animated: false,
    from: sourceViewController,
    extras: ["entry": "inbox", "campaign": 42]
)
let result = await router.open(.club("42"), options: options)
let urlResult = await router.openURL(url, source: .deepLink, options: options)
```

`from` 是弱引用，必须仍是宿主可见导航域或同窗口最上层模态导航栈的栈顶页面。栈顶页面内嵌的子控制器（分页、分段）视为所在页面。显式来源不会退回到当前栈顶：

| 来源状态 | 用户请求 | 外部请求 |
|---|---|---|
| 已释放、不在栈顶或不属于宿主 | `ignored` | `failed(.contextChanged)` |
| 属于宿主，但被弹窗、转场覆盖或宿主未就绪 | `ignored` | `deferred` |

目标业务数据通过路由关联值表达，`extras` 提供可从 `context.options` 读取的 `Sendable` 附加信息。观察者只接收种类、来源和结果。`show(animated:)`、`present(animated:)`、`replaceStack(animated:)` 的显式参数覆盖请求动画选项，自定义宿主通过 `customShow(_:identity:in:options:)` 获得选项。

```swift
if router.canOpenURL(url, source: .deepLink) {
    let result = await router.openURL(url)
}
```

`canOpen(_:source:)` 和 `canOpenURL(_:source:)` 与打开共用静态准入检查，覆盖注册、兜底、禁用、外部策略和参数校验。合法兜底也视为具备处理能力。检查不运行拦截器、处理器或页面创建，登录与当前宿主状态仍由实际打开流程判断。参数校验和 URL 解析须保持无副作用，实际执行读取 `open` 的返回结果。

## 向业务模块注入导航

处理器创建的页面发起新导航时，`context.open` 最简单。页面或业务服务需要以依赖注入方式获得导航能力时使用 `LYRouteClient`：它可以替换为测试替身，携带来源页面，并提供 `openURL` 与 `dismiss`。

```swift
// 页面创建后绑定来源，回调仅持有轻量客户端。
let navigation = context.makeClient(from: page)
page.onOpenChat = { id in
    Task { _ = await navigation.open(.chat(id)) }
}

// 测试替身可以记录请求并返回确定结果。
let navigation = LYRouteClient<AppRoute>(open: { route, options in
    .performed
})
```

`LYRouteClient` 是 `Sendable` 值，操作在主执行器执行，弱引用路由器和可选来源页面。从无会话登录后客户端继续可用；切换账号（即使尚未调用 `sessionDidChange()`）、退出登录、`resetSession()`、更换宿主或 `tearDown()` 后失效，返回 `failed(.contextChanged)`。来源页面已释放、不在栈顶或被覆盖时，按上面的来源结果表返回 `ignored`。其 `openURL` 使用用户来源。`dismiss(animated:)` 在来源栈内返回，在模态根关闭流程，在主宿主根返回 `ignored`。

最上层模态 `UINavigationController` 内的来源可以打开 `.current` 路由。执行期间使用绑定的目标栈完成准备、确认和转场等待。返回完成或流程关闭后，旧准备立即失效，交互取消则保留有效来源。流程内发往其他 placement 的请求，用户请求返回 `ignored`，外部请求返回 `deferred`，流程关闭后该等待请求被丢弃。主示例提供模态流程演示。

路由器第一次以弹出栈中的页面为来源导航，或处理器通过 `context.present` 弹出导航栈时，会接管该栈：安装内部代理，把全部代理方法转发给原代理，结束接管时恢复。`UIImagePickerController`、`UIVideoEditorController`、`MFMailComposeViewController`、`MFMessageComposeViewController` 不会被接管。只有路由器发起的关闭（`LYRouteClient.dismiss`）才对流程内页面发送 `routerDidRemovePage()`；用户下滑关闭或业务自行 `dismiss` 不发送，与主栈“系统返回不算路由清理”一致。

## 窗口上下文

```swift
if let scene = sourceViewController.view.window?.windowScene,
   let top = LYWindowContext.topViewController(in: scene) {
    // 在明确的窗口上下文展示 Alert 等辅助界面。
}
```

`LYWindowContext` 提供场景、key window、normal 主窗口、可见控制器、bounds 与安全区查询。优先传入调用方的视图、窗口或场景。`activeWindowScene()` 只在唯一前台活跃场景时返回结果。`mainWindow(in:)` 选择可见、有根控制器的 normal 窗口，优先 normal key window，候选有歧义时返回 nil。`keyWindow(in:)` 返回真实 key window，包含浮层窗口。几何查询依次使用有效窗口、场景和场景关联屏幕的 bounds，容器查询先使用视图本身的 bounds。导航执行通过显式宿主与绑定的导航域完成。

## 6. 测试建议

- 模块的登记逻辑可以用 `LYSingleStackHost` 加假依赖做单元测试，`request` 同步返回结果。
- 涉及转场、弹窗、确认框的行为需要在有窗口的宿主测试或 UI 测试中验证，包内无窗口测试覆盖不到。
- 为 URL 模板写往返测试：`router.route(for: router.url(for: route)!) == route`。
