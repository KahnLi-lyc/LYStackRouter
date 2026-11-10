/// 构建注册表时发现的错误。任何一项都会让构建失败，避免运行时悄悄失效。
public enum LYRouteBuildError: Error, Hashable, Sendable {
    /// 正式宿主要求穷尽注册，这些路由种类没有模块处理。
    case missingRegistration([String])
    /// 同一路由种类被重复注册，附首次与重复的位置。
    case duplicateRegistration([String])
    /// 模块标识重复。
    case duplicateModule([String])
    /// 模块初始化时缺少依赖。
    case missingDependency(module: String, type: String)
    /// 模块初始化抛出了其他错误。
    case moduleInitializationFailed(module: String, reason: String)
    /// URL 模板写法无效。
    case invalidURLPattern(String)
    /// 两个 URL 模板形状相同，无法确定匹配哪一个。
    case urlConflict([String])
}
