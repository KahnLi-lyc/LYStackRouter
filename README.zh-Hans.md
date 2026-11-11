# LYStackRouter

[English](README.md)

**类型化路由、模块自己注册、每次导航只结算一次的执行引擎。** 面向 Swift 6 的 UIKit 路由库。

- 路由是接入方自己的枚举。URL 只在入口解析成路由，不以字符串在 App 内传递。
- 每个业务模块登记自己的页面、动作和 URL 模板；宿主显式列出模块，或通过可选的 `@LYRouteModule` 宏自动发现。
- `build()` 失败关闭：漏注册、重复注册、URL 冲突、缺依赖在启动时报错，不会在用户点击时悄悄失效。
- 执行引擎处理常见路由库忽略的情况：按身份复用页面，避免重复堆叠；返回可以抢占异步准备；弹窗或转场挡住时外部请求只保留最近一个并在之后执行；只清理确实离开导航栈的页面；确认门不会一直占用导航权。
- 无单例：每个窗口一个路由器，由宿主创建并注入。核心与引擎零第三方依赖，严格并发检查下零警告。

## 安装

```swift
.package(url: "https://github.com/KahnLi-lyc/LYStackRouter.git", from: "0.1.0")
```

| 产品 | 内容 | 要求 |
|---|---|---|
| `LYStackRouter` | 核心（注册表、URL 模板、拦截、重写、观察）与 UIKit 执行引擎 | iOS 16、Swift 6 语言模式、swift-tools 6.1 |
| `LYStackRouterDiscovery` | 可选：`@LYRouteModule` 宏与 Mach-O section 自动发现 | 另需 Swift 6.3 及以上工具链（`@used` / `@section`）；宏会引入 swift-syntax |

`LYStackRouterCore` 同时支持 macOS 13，注册与 URL 逻辑可以直接用 `swift test` 测试。

## 快速上手

```swift
import LYStackRouter

// 1. 路由：每个目的地一个 case。新增 case 时编译器会要求补齐 kind。
enum AppRoute: LYRoutable {
    case club(String)
    case chat(String)
    case wallet

    enum Kind: CaseIterable { case club, chat, wallet }

    var kind: Kind {
        switch self {
        case .club: .club
        case .chat: .chat
        case .wallet: .wallet
        }
    }
}

// 2. 业务模块登记自己负责的路由，不 import 其他业务模块。
struct ClubRouteModule: LYRouteModule {
    static let moduleID = "club"
    let api: ClubAPI

    init(environment: LYRouteEnvironment) throws {
        api = try environment.require(ClubAPI.self)
    }

    func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
        builder.url("club/<id>", parse: { $0["id"].map(AppRoute.club) }, print: { route in
            if case let .club(id) = route { LYURLValues(path: ["id": id]) } else { nil }
        })
        builder.page(.club, policy: .init(allowsExternal: true)) { route, context in
            guard case let .club(id) = route else { return }
            // 栈内已有同一身份的页面就回到最近的实例，否则新建并 push。
            context.show(identity: id) {
                let page = ClubViewController(id: id, api: api)
                page.onOpenChat = { context.open(.chat($0)) } // 跨模块只发路由，不引用对方类型
                return page
            }
        }
    }
}

// 3. 每个窗口一个协调器，同时持有宿主与路由器。
//    路由器只弱引用宿主：直接在 build(host:) 里创建的宿主会立刻释放。
@MainActor
final class AppCoordinator {
    private let host: LYTabBarHost
    let router: LYStackRouter<AppRoute>

    init(tabs: UITabBarController, environment: LYRouteEnvironment) throws {
        let host = LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("messages"): 1])
        host.isReady = false                    // 根视图上屏前不导航
        self.host = host
        router = try LYStackRouter<AppRoute>.build(
            host: host,
            modules: .explicit([ClubRouteModule.self, ChatRouteModule.self, WalletRouteModule.self]),
            environment: environment,
            interceptors: [.session(isActive: { session.isSignedIn })],
            url: LYURLConfiguration(schemes: ["myapp"], universalLinkHosts: ["app.example.com"])
        )
    }

    func rootDidAppear() {
        host.isReady = true
        router.navigationDidStabilize()         // 执行冷启动时等待的深链
    }
}

// SceneDelegate 用属性持有协调器。
var environment = LYRouteEnvironment()
environment.provide(ClubAPI.self, clubAPI)
coordinator = try AppCoordinator(tabs: tabs, environment: environment)

coordinator.router.request(.club("42"))                    // 用户点击，同步返回结果
await coordinator.router.openURL(url, source: .deepLink)    // 外部请求
```

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

## 注册方式：显式或自动发现

显式列表结果完全确定，适用于单元测试、模块 Demo 和不想引入宏的 App：

```swift
modules: .explicit([ClubRouteModule.self, ChatRouteModule.self])
```

引入 `LYStackRouterDiscovery` 后，给模块加上宏，宿主即可自动发现：

```swift
import LYStackRouterDiscovery

@LYRouteModule
struct ClubRouteModule: LYRouteModule { ... }

modules: .discovered                                                // 按 moduleID 排序
modules: .discovered(plus: [FakeClubModule.self], excluding: ["club"]) // 用测试替身替换真实模块
```

宏在编译期向 `__DATA,__lystackrouter` 写入一条记录。`build()` 读取所有已加载镜像中的该 section（不依赖 ObjC `+load`，也不扫描类表），只保留路由类型一致的模块，然后走与显式列表完全相同的登记和检查。万一某条记录被链接器丢弃，该模块负责的路由会在启动时以 `missingRegistration` 报出。链接器验证记录和唯一的剩余风险（预编译静态库）见 [Docs/AutoRegistration.zh-Hans.md](Docs/AutoRegistration.zh-Hans.md)。

## 概念

| 类型 | 作用 |
|---|---|
| `LYRoutable` | 接入方的路由枚举：`Hashable & Sendable`，带 `CaseIterable` 的 `Kind`。 |
| `LYRouteModule` | 业务模块的登记单元：`moduleID`、`init(environment:)`、`register(into:)`。 |
| `LYRouteEnvironment` | 每个路由器各自的依赖容器；缺依赖时 `build()` 报出模块名与类型。 |
| `LYRoutePolicy` | 状态（`implemented` / `placeholder` / `disabled`）、目标域、`allowsExternal`（默认 `false`）、`requiresSession`、参数校验。 |
| `LYRouteInterceptor` | 按优先级同步执行，返回类型化决策：`proceed`、`redirect(Route)`、`reject(Failure)`、`deferUntilReady`；在任何副作用之前运行。 |
| `LYRouteRewrite` | 可 Codable 下发的远程配置：禁用某些路由种类，或精确替换 URL 模板。 |
| `LYRouteObserver` | 只读的埋点回调，只拿到种类、来源与结果，不拿 URL 原文。`routeDidDropPending(_:source:reason:)` 报告已 `deferred` 但不会再执行的外部请求。重定向后观察者只看到目标路由。 |
| `LYRouteFallback` | 处理占位与禁用的路由，以及非穷尽构建中本地请求的未注册路由，例如 `.placeholder`。只在外部白名单、参数校验与拦截器都通过后执行。 |
| `LYRouteContext` | 处理器拿到的上下文：`show(identity:)`、`present`、`prepare` + `isStillValid()`、`confirm`、`open`、`back(from:)`、`replaceStack`、`revealExisting(where:)`、`markPerformed`、`fail`。 |
| `LYRouterHost` | 接入方的容器：会话标识、是否就绪、各目标域的导航栈、`select` / `reveal`，以及给分栏容器用的 `customShow` 钩子。内置 `LYSingleStackHost` 与 `LYTabBarHost`。`LYTabBarHost` 会成为 TabBar 的代理，未实现的 Tab 代理方法转给 `forwardingTabDelegate`，导航代理方法转给 `forwardingDelegate`。 |
| `LYOpenResult` | `created`、`reused`、`alreadyVisible`、`performed`、`awaitingConfirmation`、`deferred`、`ignored`、`failed(LYRouteFailure)`。 |

### 引擎保证

- 一次导航只结算一次。另一导航进行中或转场进行中时，用户请求返回 `ignored`，连点不会排队。
- `prepare` 期间合法的返回会抢占本次导航（`failed(.contextChanged)`），迟到的准备结果不能再展示页面。准备结束后必须先 `await context.isStillValid()` 再展示，路由器不会替你检查。
- 宿主未就绪只抢占准备阶段；已在展示的导航由转场或确认框结算。
- 推送、深链、H5 等外部请求暂时不能执行时返回 `deferred`：只保留最近一个并绑定当前会话，在挡住它的弹窗或转场结束后执行，包括被取消的交互返回手势。
- 切换账号或退出登录会丢弃等待请求；从无会话登录则保留并继续。每个被丢弃的 `deferred` 请求都会以 `LYPendingDropReason` 通知 `routeDidDropPending` 一次。
- 路由器回到已有页面时，只有确实离开导航栈的页面收到 `routerDidRemovePage()`。用户手动返回不算路由器清理。
- URL 忽略末尾斜杠：`myapp://club/42/` 与 `club/<id>` 匹配。
- UIKit 拒绝展示确认框时，本次导航以 `failed(.blocked)` 结算，不会一直占用导航权。

## 示例 App

`Examples/LYStackRouterExamples.xcodeproj` 是由 `Examples/project.yml` 生成的三 Tab UIKit App。`Examples/Packages` 下的 `DemoRouteContract`、`DemoUIKit`、`DemoCommunityFeature` 和 `DemoMessagingFeature` 四个独立包分别负责路由契约、共享 UI、社群功能和消息功能，功能包之间通过契约通信。两个功能包各有注册测试、独立 Demo 工程和 UI 冒烟测试。

主示例使用 `-assembly explicit` 或 `-assembly discovered` 比较两种组装方式，演示页面复用、URL 入口、登录重定向、外部请求等待、嵌套导航容器、跨 Tab 会话复用、房间最小化与恢复、模态流程内导航、请求选项、静态检查和窗口上下文。

```sh
xcodegen generate --spec Examples/project.yml
xcodegen generate --spec Examples/Packages/DemoCommunityFeature/Demo/project.yml
xcodegen generate --spec Examples/Packages/DemoMessagingFeature/Demo/project.yml
xcodebuild test -project Examples/Packages/DemoCommunityFeature/Demo/DemoCommunityFeatureDemo.xcodeproj -scheme DemoCommunityFeatureDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test -project Examples/Packages/DemoMessagingFeature/Demo/DemoMessagingFeatureDemo.xcodeproj -scheme DemoMessagingFeatureDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

运行时选择本机已安装的模拟器。

## 与 URLNavigator、TheRouter、ReerRouter 的差异

| | LYStackRouter | URLNavigator | TheRouter | ReerRouter |
|---|---|---|---|---|
| 路由模型 | 类型化枚举，URL 只在入口解析 | URL 模式 | URL 模式，KVC 传参 | URL key |
| 注册 | 模块自己注册；显式列表或宏 + section | 集中 `register` | 运行时扫描类并缓存 | 宏 + section |
| 漏注册 | `build()` 失败 | 无法发现 | DEBUG 一致性检查 | 无法发现 |
| URL 歧义 | 字面段最多者优先，同等具体报冲突 | 字面段最多者优先，并列时不确定 | 第一个命中 | — |
| 重复页面 | 栈内按身份复用 | — | 按类回退到页面 | — |
| 忙碌或转场中 | 忽略用户点击，外部请求保留最近一个 | — | `asyncAfter` 延时 | — |
| 异步准备 | `prepare`，返回可抢占 | — | — | — |
| 单例 | 无 | 无 | 有 | 有 |

## 设计参考与致谢

设计前阅读了以下开源库的源码。没有复制代码；每一行写明借鉴了什么、刻意没有采用什么。

| 项目 | 许可证 | 借鉴 | 未采用 |
|---|---|---|---|
| [URLNavigator](https://github.com/devxoul/URLNavigator) | MIT | 逐段匹配与类型化占位、按具体程度消歧、页面与动作处理器分离 | `[String: Any]` 上下文、查找最顶层控制器 |
| [TheRouter](https://github.com/HuolalaTech/hll-wp-therouter-ios) | Apache-2.0 | 优先级拦截器、重定向操作分类、调试期一致性检查 | 运行时扫描类、KVC 注入、延时跳转、前缀重定向 |
| [ReerRouter](https://github.com/reers/ReerRouter) | MIT | 编译期把注册记录写入 Mach-O section、运行时读取 | ObjC `+load`、记录丢失时无感知 |
| [swift-url-routing](https://github.com/pointfreeco/swift-url-routing) | MIT | 同一定义同时解析与生成、往返测试、完整路径匹配、按模块组合路由表 | parser-printer 依赖栈 |
| [FFRouter](https://github.com/imlifengfeng/FFRouter) | MIT | 把重写作为远程配置 | 正则重写、单例 |
| [CTMediator](https://github.com/casatwy/CTMediator) | 阅读的源码中没有许可证文件，只借鉴思路 | 区分本地可调用与外部可调用、统一的找不到目标兜底 | 字符串反射 |
| [swift-router](https://github.com/eriicafes/swift-router) | MIT | 由路由声明双向 URL 转换 | 只面向 SwiftUI |
| [RouteComposer](https://github.com/ekazaev/route-composer) | 只读了 README，未审阅源码 | 以导航后任务作为观察者的参考 | — |

执行引擎为模块化 UIKit 应用提供显式容器归属、准备取消和会话隔离。

## 后续方向

计划提供页面业务结果回传、`popTo(kind:)` 与按身份回退到指定页面、SwiftUI 宿主、路由表导出和独立测试产品。

## 当前限制

SwiftUI 宿主、状态恢复，以及在泛型模块类型上使用 `@LYRouteModule`（请改用显式列表）。从预编译静态库或 XCFramework 中自动发现尚未验证；这类场景可以在 `.discovered(plus:)` 中引用模块，或直接使用显式列表。

## 许可证

MIT
