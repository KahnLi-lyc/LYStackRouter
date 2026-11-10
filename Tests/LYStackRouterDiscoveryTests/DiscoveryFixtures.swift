#if canImport(UIKit)
    import LYStackRouterDiscovery
    import UIKit

    enum DiscoveryRoute: LYRoutable {
        case alpha
        case beta(String)

        enum Kind: CaseIterable {
            case alpha, beta
        }

        var kind: Kind {
            switch self {
            case .alpha: .alpha
            case .beta: .beta
            }
        }
    }

    /// 另一套路由类型，用来确认发现结果按路由类型过滤。
    enum OtherRoute: LYRoutable {
        case only

        enum Kind: CaseIterable {
            case only
        }

        var kind: Kind {
            .only
        }
    }

    final class MarkedPage: UIViewController {
        let mark: String

        init(_ mark: String) {
            self.mark = mark
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }

    @LYRouteModule
    struct BetaModule: LYRouteModule {
        static let moduleID = "beta"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<DiscoveryRoute>.Builder) {
            builder.page(.beta) { route, context in
                guard case let .beta(id) = route else { return }
                context.show(identity: id) { MarkedPage("beta \(id)") }
            }
            builder.url("beta/<id>", parse: { $0["id"].map(DiscoveryRoute.beta) }, print: { route in
                if case let .beta(id) = route { LYURLValues(path: ["id": id]) } else { nil }
            })
        }
    }

    @LYRouteModule
    final class AlphaModule: LYRouteModule {
        static let moduleID = "alpha"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<DiscoveryRoute>.Builder) {
            builder.page(.alpha) { _, context in
                context.show { MarkedPage("alpha") }
            }
        }
    }

    @LYRouteModule
    struct OtherRouteModule: LYRouteModule {
        static let moduleID = "other"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<OtherRoute>.Builder) {
            builder.page(.only) { _, context in
                context.show { UIViewController() }
            }
        }
    }

    /// 未标注的测试替身，与真实模块使用同一标识。
    struct FakeAlphaModule: LYRouteModule {
        static let moduleID = "alpha"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<DiscoveryRoute>.Builder) {
            builder.page(.alpha) { _, context in
                context.show { MarkedPage("fake alpha") }
            }
        }
    }
#endif
