public extension LYRouteRegistry {
    /// 模块用来登记页面、动作与 URL 模板的构建器。
    ///
    /// 登记过程不会立即报错；所有问题在 `build` 时一并报告，方便一次看清全部冲突。
    @MainActor
    struct Builder {
        // MARK: - Properties

        /// 当前正在登记的模块标识，用于诊断。由引擎在调用模块 `register` 前设置。
        package var moduleID = "unknown"

        private var entries: [Route.Kind: Entry] = [:]
        private var duplicates: [String] = []
        private var urlEntries: [LYURLTable<Route>.Entry] = []
        private var templateErrors: [LYRouteBuildError] = []

        // MARK: - Initialization

        /// 创建空构建器。
        public init() {}

        // MARK: - Public

        /// 登记一个页面路由：处理器会打开或复用页面。
        public mutating func page(
            _ kind: Route.Kind,
            policy: LYRoutePolicy<Route> = .init(),
            file: StaticString = #fileID,
            line: UInt = #line,
            handler: @escaping @MainActor (Route, Context) -> Void
        ) {
            add(kind, .page, policy, "\(file):\(line)", handler)
        }

        /// 登记一个动作路由：处理器执行动作，不改变导航栈，例如弹出面板。
        public mutating func action(
            _ kind: Route.Kind,
            policy: LYRoutePolicy<Route> = .init(),
            file: StaticString = #fileID,
            line: UInt = #line,
            handler: @escaping @MainActor (Route, Context) -> Void
        ) {
            add(kind, .action, policy, "\(file):\(line)", handler)
        }

        /// 登记一个 URL 路径模板，同时给出解析与生成。
        ///
        /// - Parameters:
        ///   - template: 只写路径，例如 `club/<clubID>`、`user/<int:id>`、`web/<path:rest>`。
        ///   - parse: 由取值构造路由；取值缺失或不合法时返回 nil，视为不匹配。
        ///   - print: 由路由生成取值；不是本模板负责的路由时返回 nil。
        public mutating func url(
            _ template: String,
            parse: @escaping @Sendable (LYURLValues) -> Route?,
            print: @escaping @Sendable (Route) -> LYURLValues?
        ) {
            do {
                let parsed = try LYURLTemplate(template)
                urlEntries.append(.init(template: parsed, moduleID: moduleID, parse: parse, print: print))
            } catch let error as LYRouteBuildError {
                templateErrors.append(error)
            } catch {
                templateErrors.append(.invalidURLPattern(template))
            }
        }

        // MARK: - Internal

        /// 汇总并校验登记结果。
        ///
        /// - Parameter requireExhaustive: 为 true 时，任何未登记的路由种类都会让构建失败（正式宿主使用）；
        ///   为 false 时允许缺失，由引擎的兜底处理（模块 Demo 使用）。
        package func build(requireExhaustive: Bool) throws -> LYRouteRegistry {
            if let first = templateErrors.first { throw first }
            guard duplicates.isEmpty else { throw LYRouteBuildError.duplicateRegistration(duplicates.sorted()) }
            if requireExhaustive {
                let missing = Route.Kind.allCases.filter { entries[$0] == nil }
                guard missing.isEmpty else {
                    throw LYRouteBuildError.missingRegistration(missing.map { String(describing: $0) }.sorted())
                }
            }
            return try LYRouteRegistry(entries: entries, urlTable: LYURLTable(entries: urlEntries))
        }

        // MARK: - Private

        private mutating func add(
            _ kind: Route.Kind,
            _ handlerKind: LYRouteHandlerKind,
            _ policy: LYRoutePolicy<Route>,
            _ location: String,
            _ handler: @escaping @MainActor (Route, Context) -> Void
        ) {
            if let first = entries[kind] {
                duplicates.append(
                    "\(kind)：首次 \(first.moduleID) \(first.location)，重复 \(moduleID) \(location)"
                )
                return
            }
            entries[kind] = Entry(
                policy: policy,
                handlerKind: handlerKind,
                moduleID: moduleID,
                location: location,
                handle: handler
            )
        }
    }
}
