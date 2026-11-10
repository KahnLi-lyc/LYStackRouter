import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@LYRouteModule` 的实现：为模块类型生成一条写入 Mach-O section 的发现记录。
///
/// 记录在编译期写入 `__DATA,__lystackrouter`，运行时由 `LYRouteDiscovery` 读取。
/// 记录中的函数把模块类型交给收集器；收集器的泛型约束保证被标注的类型确实遵循 `LYRouteModule`。
public struct LYRouteModuleMacro: MemberMacro {
    // MARK: - Properties

    /// 记录格式标识（"LYSR" + 版本 1）；读取方据此跳过不认识的记录。
    static let recordMagic = "0x4C59_5352_0000_0001"

    // MARK: - Public

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let name: TokenSyntax
        let genericClause: GenericParameterClauseSyntax?
        if let decl = declaration.as(StructDeclSyntax.self) {
            name = decl.name
            genericClause = decl.genericParameterClause
        } else if let decl = declaration.as(ClassDeclSyntax.self) {
            name = decl.name
            genericClause = decl.genericParameterClause
        } else if let decl = declaration.as(EnumDeclSyntax.self) {
            name = decl.name
            genericClause = decl.genericParameterClause
        } else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: node, message: LYRouteModuleDiagnostic.unsupportedDeclaration)])
        }
        if let genericClause {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: genericClause, message: LYRouteModuleDiagnostic.genericType)])
        }
        let typeName = name.trimmed.text
        return [
            """
            @used
            @section("__DATA,__lystackrouter")
            nonisolated static let _lyRouteDiscoveryRecord: LYStackRouterDiscovery.LYRouteDiscoveryRecord = (
                \(raw: recordMagic),
                { LYStackRouterDiscovery.LYRouteDiscovery.collect($0, \(raw: typeName).self) }
            )
            """
        ]
    }
}

/// `@LYRouteModule` 的编译期诊断。
enum LYRouteModuleDiagnostic: String, DiagnosticMessage {
    case unsupportedDeclaration
    case genericType

    var message: String {
        switch self {
        case .unsupportedDeclaration:
            "@LYRouteModule 只能用于 struct、class 或 enum 声明"
        case .genericType:
            "@LYRouteModule 不支持泛型类型：泛型类型不能声明静态存储属性，请改用显式模块列表"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "LYStackRouterMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
