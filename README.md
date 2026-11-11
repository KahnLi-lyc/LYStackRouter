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

// 3. One coordinator per window owns both the host and the router.
//    The router holds its host weakly: a host created inline in `build(host:)` is released at once.
@MainActor
final class AppCoordinator {
    private let host: LYTabBarHost
    let router: LYStackRouter<AppRoute>

    init(tabs: UITabBarController, environment: LYRouteEnvironment) throws {
        let host = LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("messages"): 1])
        host.isReady = false                                       // until the root is on screen
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
        router.navigationDidStabilize()                            // runs a waiting cold-start deep link
    }
}

// SceneDelegate keeps the coordinator in a property.
var environment = LYRouteEnvironment()
environment.provide(ClubAPI.self, clubAPI)
coordinator = try AppCoordinator(tabs: tabs, environment: environment)

coordinator.router.request(.club("42"))                           // user tap, synchronous result
await coordinator.router.openURL(url, source: .deepLink)           // external request
```

## Open options and static capability checks

```swift
let options = LYOpenOptions(
    animated: false,
    from: sourceViewController,
    extras: ["entry": "inbox", "campaign": 42]
)
let result = await router.open(.club("42"), options: options)
let urlResult = await router.openURL(url, source: .deepLink, options: options)
```

`from` is weak. It must remain the top page of a visible host navigation stack or of the topmost presented navigation stack in the same window. A child controller embedded in that page (a pager or segment) counts as the page itself. An explicit source never falls back to the current top page:

| Source state | User request | External request |
|---|---|---|
| Released, no longer on top, or not owned by the host | `ignored` | `failed(.contextChanged)` |
| Owned but covered by a presentation, a transition or a host that is not ready | `ignored` | `deferred` |

Route-associated values carry destination data, and `extras` carries supplementary `Sendable` metadata available through `context.options`. Observers receive kind, source and result without extras or raw URL parameters. Explicit `show(animated:)`, `present(animated:)` and `replaceStack(animated:)` arguments override the request animation setting. A custom host can receive options through `customShow(_:identity:in:options:)`.

```swift
if router.canOpenURL(url, source: .deepLink) {
    // Offer an entry point. Opening still returns its own result.
    let result = await router.openURL(url)
}
```

`canOpen(_:source:)` and `canOpenURL(_:source:)` share static admission checks with opening. They account for registration, fallback, disabled routes, external policy and parameter validation. They do not execute interceptors or handlers, create pages, check login, or guarantee current host readiness. Validation and URL parsing must be free of side effects. A permitted fallback counts as a capability.

## Injecting navigation into features

`context.open` is the simplest way for a page created by a handler to start a new navigation. Use `LYRouteClient` when a page or a feature service should receive navigation as a dependency: it can be replaced by a test double, carries the source page, and also exposes `openURL` and `dismiss`.

```swift
// Bind a page client after creating the page.
let navigation = context.makeClient(from: page)
page.onOpenChat = { id in
    Task { _ = await navigation.open(.chat(id)) }
}

// A deterministic test double can record calls and report a result.
let navigation = LYRouteClient<AppRoute>(open: { route, options in
    .performed
})
```

`LYRouteClient` is a `Sendable` value whose operations run on the main actor. It weakly references the router and the optional source page. A client survives signing in from no session. Switching accounts, signing out, `resetSession()`, attaching a different host or `tearDown()` invalidate it, and it then returns `failed(.contextChanged)`. A page client whose page is released, no longer on top or covered follows the source table above and returns `ignored`. Its `openURL` uses a user source. `dismiss(animated:)` pops the source stack, closes a presented flow at its root, or returns `ignored` at a primary root.

A source inside the topmost presented `UINavigationController` can open `.current` routes within that flow. The execution uses its weakly bound target stack through preparation, confirmation and transition settlement. Back completion and flow dismissal invalidate the old preparation. Cancelled gestures keep valid origins. Cross-placement requests from the flow are `ignored` for users and `deferred` for external sources; when the flow closes, the waiting request is dropped. The example's modal workflow exercises this behavior.

The router adopts a presented navigation stack the first time it navigates from it, and when a handler presents one with `context.present`. Adoption installs an internal delegate that forwards every delegate method to the existing delegate and restores it afterwards. `UIImagePickerController`, `UIVideoEditorController`, `MFMailComposeViewController` and `MFMessageComposeViewController` are never adopted. Only a dismissal performed by the router (`LYRouteClient.dismiss`) sends `routerDidRemovePage()` to the flow's pages. A user swipe-down or a dismissal by feature code does not, matching the rule for system back on the primary stack.

## Window context

```swift
if let scene = sourceViewController.view.window?.windowScene,
   let top = LYWindowContext.topViewController(in: scene) {
    // Present an alert or other auxiliary UI from this explicit window context.
}
```

`LYWindowContext` provides scene, key window, normal window, visible controller, bounds and safe-area queries. Prefer a view, window or scene supplied by the caller. `activeWindowScene()` returns a value only when exactly one foreground-active scene exists. `mainWindow(in:)` selects a visible normal window with a root controller, preferring the normal key window and returning nil for ambiguous candidates. `keyWindow(in:)` reports the real key window, including overlays. Geometry follows valid window, scene and associated-screen bounds. Container geometry starts with the view's bounds. Routing uses the explicit host and execution domain.

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
| `LYRouteObserver` | Read-only analytics hooks. Receives kind, source and result, never the raw URL. `routeDidDropPending(_:source:reason:)` reports a `deferred` external request that will no longer run. After a redirect, observers see the target route only. |
| `LYRouteFallback` | Handles placeholder and disabled routes, and unregistered routes for local requests in non-exhaustive builds, e.g. `.placeholder`. It runs only after the external allowlist, validation and interceptors pass. |
| `LYRouteContext` | What a handler gets: `show(identity:)`, `present`, `prepare` + `isStillValid()`, `confirm`, `open`, `back(from:)`, `replaceStack`, `revealExisting(where:)`, `markPerformed`, `fail`. |
| `LYRouterHost` | Your container: session ID, readiness, navigation stacks per placement, `select` / `reveal`, and a `customShow` hook for split containers. `LYSingleStackHost` and `LYTabBarHost` are built in. `LYTabBarHost` becomes the tab bar delegate and forwards unimplemented methods to `forwardingTabDelegate`; navigation delegate methods go to `forwardingDelegate`. |
| `LYOpenResult` | `created`, `reused`, `alreadyVisible`, `performed`, `awaitingConfirmation`, `deferred`, `ignored`, `failed(LYRouteFailure)`. |

### Engine guarantees

- A navigation settles once. A user request while another navigation runs, or while a transition is in flight, is `ignored`. Taps never queue up.
- During `prepare`, a legitimate back preempts the navigation (`failed(.contextChanged)`). The late preparation cannot show anything. Always `await context.isStillValid()` before showing after preparation: the router does not check for you.
- A host that is not ready preempts preparation only. A navigation already presenting settles through its transition or confirmation alert.
- External requests (push, deep link, web) that cannot run yet are `deferred`. Only the latest one is kept, bound to the current session, and it runs after the blocking sheet or transition ends. That includes an interactive back swipe that is cancelled.
- Switching or signing out of an account drops the waiting request. Signing in from no session keeps it. Every dropped `deferred` request reaches `routeDidDropPending` exactly once with a `LYPendingDropReason`.
- When the router pops back to an existing page, only the pages that actually left the stack receive `routerDidRemovePage()`. Pages the user pops are not treated as router cleanup.
- URLs ignore trailing slashes: `myapp://club/42/` matches `club/<id>`.
- If UIKit refuses to present a confirmation alert, the navigation settles as `failed(.blocked)` instead of holding the lock.

## Example app

`Examples/LYStackRouterExamples.xcodeproj` is a three-tab UIKit app generated from `Examples/project.yml`. Four independent packages in `Examples/Packages` separate the route contract, shared UI, community and messaging features. Feature packages do not depend on each other. Each feature has its own registration tests and runnable Demo project with UI smoke tests.

The main example supports `-assembly explicit` and `-assembly discovered`. Scenarios cover identity reuse, URL entry, login redirection, external requests waiting through transitions, nested navigation containers, cross-tab session reuse, minimizing and restoring a room session, modal flow navigation, request options, capability checks and window context.

```sh
xcodegen generate --spec Examples/project.yml
xcodegen generate --spec Examples/Packages/DemoCommunityFeature/Demo/project.yml
xcodegen generate --spec Examples/Packages/DemoMessagingFeature/Demo/project.yml
xcodebuild test -project Examples/Packages/DemoCommunityFeature/Demo/DemoCommunityFeatureDemo.xcodeproj -scheme DemoCommunityFeatureDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test -project Examples/Packages/DemoMessagingFeature/Demo/DemoMessagingFeatureDemo.xcodeproj -scheme DemoMessagingFeatureDemo -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Choose a simulator installed on your machine.

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

The execution engine supports explicit container ownership, preparation cancellation and session isolation for modular UIKit applications.

## Planned additions

Page result delivery, `popTo(kind:)` and popping back to a page identity, SwiftUI hosts, route-table export and a dedicated testing product are planned.

## Current limitations

SwiftUI hosts, state restoration, and generic module types with `@LYRouteModule` (use an explicit list). Discovery from prebuilt static libraries or XCFrameworks is not verified; reference the module in `.discovered(plus:)` or use an explicit list there.

## License

MIT
