import LYStackRouterMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class LYRouteModuleMacroTests: XCTestCase {
    private let macros: [String: any Macro.Type] = ["LYRouteModule": LYRouteModuleMacro.self]

    func testStructGetsSectionRecord() {
        assertMacroExpansion(
            """
            @LYRouteModule
            struct ClubModule: LYRouteModule {
                static let moduleID = "club"
            }
            """,
            expandedSource: """
            struct ClubModule: LYRouteModule {
                static let moduleID = "club"

                @used
                @section("__DATA,__lystackrouter")
                nonisolated static let _lyRouteDiscoveryRecord: LYStackRouterDiscovery.LYRouteDiscoveryRecord = (
                    0x4C59_5352_0000_0001,
                    {
                        LYStackRouterDiscovery.LYRouteDiscovery.collect($0, ClubModule.self)
                    }
                )
            }
            """,
            macros: macros
        )
    }

    func testClassAndEnumAreSupported() {
        assertMacroExpansion(
            """
            @LYRouteModule
            final class ChatModule {
            }
            """,
            expandedSource: """
            final class ChatModule {

                @used
                @section("__DATA,__lystackrouter")
                nonisolated static let _lyRouteDiscoveryRecord: LYStackRouterDiscovery.LYRouteDiscoveryRecord = (
                    0x4C59_5352_0000_0001,
                    {
                        LYStackRouterDiscovery.LYRouteDiscovery.collect($0, ChatModule.self)
                    }
                )
            }
            """,
            macros: macros
        )
        assertMacroExpansion(
            """
            @LYRouteModule
            enum MeModule {
            }
            """,
            expandedSource: """
            enum MeModule {

                @used
                @section("__DATA,__lystackrouter")
                nonisolated static let _lyRouteDiscoveryRecord: LYStackRouterDiscovery.LYRouteDiscoveryRecord = (
                    0x4C59_5352_0000_0001,
                    {
                        LYStackRouterDiscovery.LYRouteDiscovery.collect($0, MeModule.self)
                    }
                )
            }
            """,
            macros: macros
        )
    }

    func testGenericTypeIsRejected() {
        assertMacroExpansion(
            """
            @LYRouteModule
            struct GenericModule<Route> {
            }
            """,
            expandedSource: """
            struct GenericModule<Route> {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@LYRouteModule 不支持泛型类型：泛型类型不能声明静态存储属性，请改用显式模块列表",
                    line: 2,
                    column: 21
                )
            ],
            macros: macros
        )
    }

    func testProtocolAndExtensionAreRejected() {
        let message = "@LYRouteModule 只能用于 struct、class 或 enum 声明"
        assertMacroExpansion(
            """
            @LYRouteModule
            extension ClubModule {
            }
            """,
            expandedSource: """
            extension ClubModule {
            }
            """,
            diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)],
            macros: macros
        )
        assertMacroExpansion(
            """
            @LYRouteModule
            protocol Module {
            }
            """,
            expandedSource: """
            protocol Module {
            }
            """,
            diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)],
            macros: macros
        )
    }
}
