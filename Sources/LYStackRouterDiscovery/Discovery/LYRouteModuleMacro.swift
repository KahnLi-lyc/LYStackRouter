#if canImport(UIKit)
    /// 标注后，模块会被 `LYRouteModuleSet.discovered` 自动发现，宿主无需显式列出。
    ///
    /// 宏在类型内生成一条 `@used @section("__DATA,__lystackrouter")` 静态记录，需要 Swift 6.3 及以上工具链。
    /// 只支持非泛型的 struct、class 与 enum。记录被链接器丢弃时，对应路由会在 `build()` 的穷尽检查中报出。
    ///
    /// ```swift
    /// @LYRouteModule
    /// struct ClubRouteModule: LYRouteModule { ... }
    /// ```
    @attached(member, names: named(_lyRouteDiscoveryRecord))
    public macro LYRouteModule() = #externalMacro(module: "LYStackRouterMacros", type: "LYRouteModuleMacro")
#endif
