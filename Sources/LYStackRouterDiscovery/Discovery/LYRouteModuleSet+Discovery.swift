#if canImport(UIKit)
    public extension LYRouteModuleSet {
        /// 自动发现所有标注了 `@LYRouteModule`、且路由类型与本路由器一致的模块，按 `moduleID` 排序。
        static var discovered: LYRouteModuleSet {
            discovered()
        }

        /// 自动发现并与显式列表混用。
        ///
        /// - Parameters:
        ///   - additional: 额外加入的模块，例如测试替身；与已发现的同一类型只登记一次，按给定顺序排在发现结果之后。
        ///   - excludedIDs: 从发现结果中排除的模块标识；不影响 `additional`，因此可以用同一标识的替身替换真实模块。
        static func discovered(
            plus additional: [any LYRouteModule<Route>.Type] = [],
            excluding excludedIDs: Set<String> = []
        ) -> LYRouteModuleSet {
            LYRouteModuleSet {
                let found = LYRouteDiscovery.moduleTypes()
                    .compactMap { $0 as? any LYRouteModule<Route>.Type }
                    .filter { !excludedIDs.contains($0.moduleID) }
                    .sorted { $0.moduleID < $1.moduleID }
                var seen = Set<ObjectIdentifier>()
                var modules: [any LYRouteModule<Route>.Type] = []
                for type in found + additional where seen.insert(ObjectIdentifier(type)).inserted {
                    modules.append(type)
                }
                return modules
            }
        }
    }
#endif
