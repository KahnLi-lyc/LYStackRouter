# 自动注册：`@LYRouteModule` 与 Mach-O section

本文说明自动发现的机制、已验证的链接场景和剩余风险。只写有构建或测试记录支撑的结论。

## 机制

1. 在模块类型上标注 `@LYRouteModule`。宏为类型生成一个静态成员：

   ```swift
   @used
   @section("__DATA,__lystackrouter")
   nonisolated static let _lyRouteDiscoveryRecord: LYStackRouterDiscovery.LYRouteDiscoveryRecord = (
       0x4C59_5352_0000_0001,
       { LYStackRouterDiscovery.LYRouteDiscovery.collect($0, ClubRouteModule.self) }
   )
   ```

   - 第一个字段是格式标识（"LYSR" + 版本 1），读取方跳过不认识的记录。
   - 第二个字段是不捕获任何值的 C 函数指针。`collect` 的泛型约束让编译器检查被标注的类型确实遵循 `LYRouteModule`。
   - `@used` 阻止编译器和链接器把未被引用的记录当作死代码删除；`@section` 把记录放进固定的 section。

2. `LYRouteModuleSet.discovered` 在 `build()` 时：
   - 遍历 `_dyld_image_count()` 个已加载镜像，用 `getsectiondata` 读取 `__DATA,__lystackrouter`；
   - section 大小不是记录大小整数倍的镜像整体跳过，格式标识不符的记录逐条跳过；
   - 调用每条记录的函数，收集模块元类型；
   - 只保留路由类型与当前路由器一致的模块（同一 App 中可以有多套路由），按 `moduleID` 排序以保证结果确定。

3. 之后与显式列表完全相同：创建模块、登记、穷尽检查、重复检查、URL 冲突检查。

不依赖 ObjC `+load`，也不扫描类表；读取只发生在构建路由器时，不在启动时自动执行。

## 限制

- 需要 Swift 6.3 及以上工具链（`@used`、`@section`）。本仓只在 Swift 6.4.2 / Xcode 27.2 上验证过。
- 只支持非泛型的 struct、class、enum：泛型类型不能声明静态存储属性，宏会给出编译期错误。协议、扩展同样报错。
- 函数体内的局部类型不能使用成员宏，请使用显式列表。
- 不使用 Discovery 的接入方不会编译宏和 swift-syntax，但 SwiftPM 仍会解析 swift-syntax 依赖。

## 已验证的链接场景

| 场景 | 配置 | 结果 | 记录 |
|---|---|---|---|
| macOS 可执行文件，模块在未被引用的 SwiftPM target 中 | Debug 与 Release | 发现成功 | 第 2 步 spike |
| iOS App，模块在未被引用的 SwiftPM target 中 | Debug 与 Release（`-O`、`-dead_strip`、strip） | 发现成功 | 第 2 步 spike |
| 包内 iOS 测试 | Debug | 7 个 Discovery 测试通过：按路由类型过滤、排序、与显式等价、替身替换、重复与缺失报错 | `Tests/LYStackRouterDiscoveryTests` |
| 示例 App：账号模块在 App target，社群与消息模块在本地包的两个 target | Debug | UI 测试 `testLoopReusesExistingPagesWithDiscoveredModules` 通过 | `Examples/` |
| 同上 | Release（`-Os`/`-O`、`-dead_strip`、去除符号） | 符号表中已无记录符号，但二进制的 `__lystackrouter` section 仍为 48 字节（3 条 × 16 字节）；启动输出 `组装：discovered · 模块：account,community,messages` | `xcrun size -m`、`simctl launch --console-pty` |

Xcode 以整个 `.o` 链接 SwiftPM target，加上 `@used`，未被引用的模块记录也会保留。

## 剩余风险与兜底

- **预编译静态库或 XCFramework（未验证）**：链接器只会从 `.a` 中拉取被引用的目标文件。如果模块所在的目标文件没有被任何代码引用，它的记录不会进入最终二进制。
- **兜底方式**，按推荐顺序：
  1. 在 `.discovered(plus: [ClubRouteModule.self])` 中引用该模块。引用本身会让链接器拉入目标文件，同一类型只登记一次。
  2. 对该静态库使用 `-force_load`。
  3. 对这类模块改用显式列表。
- **失败可见**：无论哪种原因丢失记录，该模块负责的路由种类都会在 `build()` 时以 `LYRouteBuildError.missingRegistration` 报出，不会在运行时悄悄失效。只有使用 `allowsUnregistered: true` 的非穷尽构建（例如模块 Demo）才会把它们交给兜底处理。

## 已知编译器问题

Swift 6.4.2 对存在类型元类型的 key path（例如 `[any LYRouteModule<Route>.Type].map(\.moduleID)`）会在 SILGen 阶段崩溃。库内和测试都改用闭包，并用 `// swiftformat:disable:next preferKeyPath` 标注原因。
