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

// 3. 宿主为每个窗口组装一个路由器。
var environment = LYRouteEnvironment()
environment.provide(ClubAPI.self, clubAPI)
let router = try LYStackRouter<AppRoute>.build(
    host: LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("messages"): 1]),
    modules: .explicit([ClubRouteModule.self, ChatRouteModule.self, WalletRouteModule.self]),
    environment: environment,
    interceptors: [.session(isActive: { session.isSignedIn })],
    url: LYURLConfiguration(schemes: ["myapp"], universalLinkHosts: ["app.example.com"])
)

router.request(.club("42"))                    // 用户点击，同步返回结果
await router.openURL(url, source: .deepLink)    // 外部请求
```

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
| `LYRouteObserver` | 只读的埋点回调，只拿到种类、来源与结果，不拿 URL 原文。 |
| `LYRouteFallback` | 处理占位与禁用的路由，以及非穷尽构建中本地请求的未注册路由，例如 `.placeholder`。只在外部白名单、参数校验与拦截器都通过后执行。 |
| `LYRouteContext` | 处理器拿到的上下文：`show(identity:)`、`present`、`prepare` + `isStillValid()`、`confirm`、`open`、`back(from:)`、`replaceStack`、`revealExisting(where:)`、`markPerformed`、`fail`。 |
| `LYRouterHost` | 接入方的容器：会话标识、是否就绪、各目标域的导航栈、`select` / `reveal`，以及给分栏容器用的 `customShow` 钩子。内置 `LYSingleStackHost` 与 `LYTabBarHost`。 |
| `LYOpenResult` | `created`、`reused`、`alreadyVisible`、`performed`、`awaitingConfirmation`、`deferred`、`ignored`、`failed(LYRouteFailure)`。 |

### 引擎保证

- 一次导航只结算一次。另一导航进行中或转场进行中时，用户请求返回 `ignored`，连点不会排队。
- `prepare` 期间合法的返回会抢占本次导航（`failed(.contextChanged)`），迟到的准备结果不能再展示页面。
- 推送、深链、H5 等外部请求暂时不能执行时返回 `deferred`：只保留最近一个并绑定当前会话，在挡住它的弹窗或转场结束后执行，包括被取消的交互返回手势。
- 切换账号或退出登录会丢弃等待请求；从无会话登录则保留并继续。
- 路由器回到已有页面时，只有确实离开导航栈的页面收到 `routerDidRemovePage()`。用户手动返回不算路由器清理。
- UIKit 拒绝展示确认框时，本次导航以 `failed(.blocked)` 结算，不会一直占用导航权。

## 示例 App

`Examples/LYStackRouterExamples.xcodeproj` 是一个三 Tab 的 UIKit App，由 XcodeGen 根据 `Examples/project.yml` 生成。业务模块放在本地包 `Examples/DemoFeatures` 中，互相之间不 import。示例覆盖：循环复用、自定义 scheme 与 Universal Link、登录重定向、深链等待弹窗关闭或交互返回取消、跨模块只发路由、分栏容器的 `customShow` 钩子、带确认与跨 Tab 恢复的会话型房间页、准备阶段抢占、降级兜底。启动参数 `-assembly explicit` 或 `-assembly discovered` 可以对比两种组装方式。示例工程上运行 11 个 UI 测试和 6 个宿主内引擎测试。

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

执行引擎泛化自一个线上 UIKit App 的导航层，其作者同意以开源形式发布。

## 暂不支持

SwiftUI 宿主、状态恢复，以及在泛型模块类型上使用 `@LYRouteModule`（请改用显式列表）。从预编译静态库或 XCFramework 中自动发现尚未验证；这类场景可以在 `.discovered(plus:)` 中引用模块，或直接使用显式列表。

## 许可证

MIT
