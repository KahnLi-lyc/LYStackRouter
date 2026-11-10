import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// 宏插件入口。
@main
struct LYStackRouterMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [LYRouteModuleMacro.self]
}
