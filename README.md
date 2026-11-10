# LYStackRouter

[简体中文](README.zh-Hans.md)

**Typed routes, module-owned registration, and a navigation engine that settles every request exactly once.** A UIKit router for Swift 6.

- Routes are your own enum. URLs are parsed into routes at the edge and never travel through the app as strings.
- Each feature module registers its own pages, actions and URL templates. The host lists the modules explicitly, or discovers them with the optional `@LYRouteModule` macro.
- `build()` fails closed: missing registrations, duplicates, URL conflicts and missing dependencies are reported at launch instead of failing silently on tap.
- The engine handles the cases thin routers skip: identity-based reuse instead of piling up duplicate pages, back preempting an async preparation, only the latest external request waiting while a sheet or transition blocks it, cleanup only for pages that really left the stack, and a confirmation gate that never holds the navigation lock forever.
- No singleton. One router per window, injected by the host. Zero third-party dependencies in the core and engine, and zero warnings under strict concurrency.

## Installation

```swift
.package(url: "https://github.com/KahnLi-lyc/LYStackRouter.git", from: "0.1.0")
```

| Product | Contents | Requirements |
|---|---|---|
| `LYStackRouter` | Core (registry, URL templates, interceptors, rewrite, observers) and the UIKit engine | iOS 16, Swift 6 language mode, swift-tools 6.1 |
| `LYStackRouterDiscovery` | Optional `@LYRouteModule` macro and Mach-O section discovery | Additionally a Swift 6.3+ toolchain (`@used` / `@section`); brings in swift-syntax for the macro |

`LYStackRouterCore` also builds on macOS 13, so registry and URL logic can be tested with `swift test`.

## Quick start

```swift
import LYStackRouter

// 1. Routes: one case per destination. Adding a case forces `kind` to be updated.
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

// 2. A feature module registers what it owns. It never imports other features.
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
            // Reuses the nearest page with this identity in the stack, otherwise pushes a new one.
            context.show(identity: id) {
                let page = ClubViewController(id: id, api: api)
                page.onOpenChat = { context.open(.chat($0)) } // cross-module: send a route, not a type
                return page
            }
        }
    }
}

// 3. The host assembles one router per window.
var environment = LYRouteEnvironment()
environment.provide(ClubAPI.self, clubAPI)
let router = try LYStackRouter<AppRoute>.build(
    host: LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("messages"): 1]),
    modules: .explicit([ClubRouteModule.self, ChatRouteModule.self, WalletRouteModule.self]),
    environment: environment,
    interceptors: [.session(isActive: { session.isSignedIn })],
    url: LYURLConfiguration(schemes: ["myapp"], universalLinkHosts: ["app.example.com"])
)

router.request(.club("42"))                                       // user tap, synchronous result
await router.openURL(url, source: .deepLink)                       // external request
```

## Registration: explicit or discovered

Explicit lists are deterministic and work everywhere: unit tests, module demos and apps that don't want macros.

```swift
modules: .explicit([ClubRouteModule.self, ChatRouteModule.self])
```

With `LYStackRouterDiscovery`, annotate a module and let the host discover it:

```swift
import LYStackRouterDiscovery

@LYRouteModule
struct ClubRouteModule: LYRouteModule { ... }

modules: .discovered                                               // sorted by moduleID
modules: .discovered(plus: [FakeClubModule.self], excluding: ["club"]) // swap in a test double
```

The macro writes a record into `__DATA,__lystackrouter` at compile time. `build()` reads the section of every loaded image (no ObjC `+load`, no class scanning), keeps modules whose route type matches, and then runs the same registration and checks as the explicit path. If the linker ever drops a record, the routes that module owns show up as `missingRegistration` at launch. See [Docs/AutoRegistration.zh-Hans.md](Docs/AutoRegistration.zh-Hans.md) for the linker evidence and the one remaining risk (prebuilt static libraries).

## Concepts

| Type | Role |
|---|---|
| `LYRoutable` | Your route enum: `Hashable & Sendable` with a `CaseIterable` `Kind`. |
| `LYRouteModule` | A feature's registration unit: `moduleID`, `init(environment:)`, `register(into:)`. |
| `LYRouteEnvironment` | Per-router dependency container. Missing dependencies fail `build()` with the module and type name. |
| `LYRoutePolicy` | Status (`implemented` / `placeholder` / `disabled`), placement, `allowsExternal` (default `false`), `requiresSession`, validation. |
| `LYRouteInterceptor` | Priority-ordered, synchronous, typed decision: `proceed`, `redirect(Route)`, `reject(Failure)`, `deferUntilReady`. Runs before any side effect. |
| `LYRouteRewrite` | Codable remote config: disable kinds or replace exact URL templates. |
| `LYRouteObserver` | Read-only analytics hooks. Receives kind, source and result, never the raw URL. |
| `LYRouteFallback` | Handles unregistered (non-exhaustive builds only), placeholder and disabled routes, e.g. `.placeholder`. |
| `LYRouteContext` | What a handler gets: `show(identity:)`, `present`, `prepare` + `isStillValid()`, `confirm`, `open`, `back(from:)`, `replaceStack`, `revealExisting(where:)`, `markPerformed`, `fail`. |
| `LYRouterHost` | Your container: session ID, readiness, navigation stacks per placement, `select` / `reveal`, and a `customShow` hook for split containers. `LYSingleStackHost` and `LYTabBarHost` are built in. |
| `LYOpenResult` | `created`, `reused`, `alreadyVisible`, `performed`, `awaitingConfirmation`, `deferred`, `ignored`, `failed(LYRouteFailure)`. |

### Engine guarantees

- A navigation settles once. A user request while another navigation runs, or while a transition is in flight, is `ignored`. Taps never queue up.
- During `prepare`, a legitimate back preempts the navigation (`failed(.contextChanged)`). The late preparation cannot show anything.
- External requests (push, deep link, web) that cannot run yet are `deferred`. Only the latest one is kept, bound to the current session, and it runs after the blocking sheet or transition ends. That includes an interactive back swipe that is cancelled.
- Switching or signing out of an account drops the waiting request. Signing in from no session keeps it.
- When the router pops back to an existing page, only the pages that actually left the stack receive `routerDidRemovePage()`. Pages the user pops are not treated as router cleanup.
- If UIKit refuses to present a confirmation alert, the navigation settles as `failed(.blocked)` instead of holding the lock.

## Example app

`Examples/LYStackRouterExamples.xcodeproj` is a three-tab UIKit app generated by XcodeGen from `Examples/project.yml`. Its feature modules live in a local package (`Examples/DemoFeatures`) and never import each other. It demonstrates loop reuse, custom scheme and universal links, login redirect, deep links waiting for a sheet or a cancelled back swipe, cross-module routes, a split-container `customShow` hook, a session-style room page with confirmation and cross-tab reveal, preemption and a degraded fallback. Launch it with `-assembly explicit` or `-assembly discovered` to compare both assemblies. 11 UI tests and 6 hosted engine tests run against it.

## Compared with URLNavigator, TheRouter and ReerRouter

| | LYStackRouter | URLNavigator | TheRouter | ReerRouter |
|---|---|---|---|---|
| Route model | Typed enum; URLs parsed at the edge | URL patterns | URL patterns, KVC params | URL keys |
| Registration | Module-owned, explicit or macro + section | Central `register` | Runtime class scan, cached | Macro + section |
| Missing route | `build()` fails | Not detected | DEBUG consistency check | Not detected |
| Ambiguous URL | Most literal segments, then conflict error | Most literal segments; ties undefined | First match | — |
| Duplicate pages | Identity reuse in stack | — | Pop to page by class | — |
| Busy / transition | Ignore user taps, latest external waits | — | `asyncAfter` delays | — |
| Async preparation | `prepare`, back preempts | — | — | — |
| Singleton | No | No | Yes | Yes |

## Design references and acknowledgements

LYStackRouter was designed after reading the source of these libraries. No code was copied; each row lists what was borrowed and what was deliberately left out.

| Project | License | Borrowed | Not adopted |
|---|---|---|---|
| [URLNavigator](https://github.com/devxoul/URLNavigator) | MIT | Segment matching with typed placeholders, specificity-based disambiguation, separate page and action handlers | `[String: Any]` context, top-most controller lookup |
| [TheRouter](https://github.com/HuolalaTech/hll-wp-therouter-ios) | Apache-2.0 | Priority interceptors, categorized redirect operations, a debug consistency check | Runtime class scanning, KVC injection, delay-based navigation, prefix redirects |
| [ReerRouter](https://github.com/reers/ReerRouter) | MIT | Compile-time registration records in a Mach-O section, read at runtime | ObjC `+load`, silent loss of records |
| [swift-url-routing](https://github.com/pointfreeco/swift-url-routing) | MIT | One definition for parse and print, round-trip tests, full-path matching, composable per-module tables | The parser-printer dependency stack |
| [FFRouter](https://github.com/imlifengfeng/FFRouter) | MIT | Rewrite as remote configuration | Regex rewrites, singleton |
| [CTMediator](https://github.com/casatwy/CTMediator) | No license file in the source we read; ideas only | Separating locally callable from externally callable targets, a unified no-target fallback | String reflection |
| [swift-router](https://github.com/eriicafes/swift-router) | MIT | Routes declaring both URL directions | SwiftUI-only design |
| [RouteComposer](https://github.com/ekazaev/route-composer) | README only, source not reviewed | Post-navigation tasks as the model for observers | — |

The execution engine is generalized from the navigation layer of a production UIKit app whose authors agreed to open-source it.

## Not supported yet

SwiftUI hosts, state restoration, and generic module types with `@LYRouteModule` (use an explicit list). Discovery from prebuilt static libraries or XCFrameworks is not verified; reference the module in `.discovered(plus:)` or use an explicit list there.

## License

MIT
