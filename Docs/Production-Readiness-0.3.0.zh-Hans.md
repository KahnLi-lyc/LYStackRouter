# 0.3.0 生产接入审查（2026-11-17）

状态：库修复与当前环境完整验收通过；最低工具链、最低系统及有效签名／真机验收尚未完成，**不放行完整生产接入**。版本继续为 **0.3.0 — Unreleased**，无标签或 Release。

## 范围与版本

起点为 `28c384f4af4383cd0c813f6ea2a8f22547c3bcb4`。原交付两个提交已推送 main，远端 SHA 已核对；[对应 CI](https://github.com/KahnLi-lyc/LYStackRouter/actions/runs/43916702145) 的 macOS、iOS 包/示例/模块 Demo、SwiftFormat 全部通过。本轮在 `codex/lystackrouter-production-readiness` 完成独立审查；测试证据另记录每份实际源码哈希，不能把旧 CI 当成本轮修复验证。

只修复可复现的库缺陷，新增能力另行设计。业务认证、权限、账号依赖、房间会话与页面业务结果均由采用方负责。本轮未实施任何业务 App 迁移。公开能力边界见 [接入边界](Adoption-Boundaries.zh-Hans.md)，最小环境复验入口见 [CompatibilityHost](../Examples/CompatibilityHost/README.md)。

## 缺陷与历史动画风险

### 内置宿主可选导航代理

单栈宿主原来只转发 willShow/didShow，遮蔽业务动画和交互代理，手动代理查询 RED 有六项断言失败。真实 UIKit 又确认：Tab 宿主与单栈宿主均在初次安装代理时缓存可选能力，后来注入业务代理仍无法提供自定义动画/交互。新增真实交互用例验证 UIKit 确实查询业务驱动，不能以手动调用方法代替。

修复按业务代理实际响应的 selector 宣告动画/交互能力；显式设置、替换或清空时，仅为仍归宿主所有的导航栈刷新 UIKit 缓存。方法自身保留安全的 nil 回退。业务负责持有弱代理；弱代理释放后，内部生命周期订阅在下一次 MainActor 执行恢复默认能力。通知按订阅身份隔离，支持多个宿主共享业务代理，deinit 不访问 UIKit，没有新增公开配置或业务接口。

本轮验证曾阻止一个错误候选：永久宣告可选动画方法，即便返回 nil，也会破坏系统侧滑。相同诊断下，原 `28c384f` 两项侧滑 2/2 通过、错误候选 0/2；修正后的候选真实自定义交互、默认侧滑完成/取消、代理释放后直接侧滑及订阅测试 9/9。失败 bundle、截图、源码快照与命令均保留，未将错误候选提交。源码规格与质量复核没有阻断意见，冻结源码的完整复验结果见下表；隔离侧滑复现夹具已作为文本补丁和 Python 脚本保存在 [WeakDelegateEdge](../Examples/CompatibilityHost/Probes/WeakDelegateEdge/README.md)。

### 历史动画复用失败的因果证据

对原版 `27afa9c26a19f00ae02670039d82949f5f393c92` 与当前起点应用相同诊断，记录 App active、窗口 visible/key、根页 appearance/window、真实栈、转场协调器及执行结算。

| 同样的旧测试前置条件 | 通过 | 失败 |
| --- | --- | --- |
| 当前版本定向 20 次 | 19 | 1 |
| 原版首次独立进程 20 次 | 20 | 0 |
| 原版追加独立进程 100 次 | 92 | 8 |

所有九次失败均在根页面尚未收到 appearance 且自身 window=nil 时开始；容器已挂载、窗口 key、App active 并不能证明页面完成首次展示。失败均复现历史五项签名：reused 同步返回、无 coordinator、wait=nil、栈仍为四页、两页清理为零。已上屏的通过记录产生真实 coordinator，最终回退两页并各清理一次。原版全部 48 份生产 Sources 与原 Git blob 相同。

因此根因是测试错误的首次上屏前置条件，以及该窗口内 UIKit 延迟栈操作。修正为等待真实根页 didAppear、其 window/key、App active 和无转场；保留原动画、栈与清理断言，不增加固定延迟或失败重试。原版修正后 20/20；当前最终源码 20/20；三个独立 xcodebuild 进程各 1/1，App PID 分别为 75599、76004、76331；聚焦回归 6/6。

采用方必须遵守既有宿主就绪约定：启动未上屏时 `isReady=false`，根页真实就绪后设 true 并调用 `navigationDidStabilize()`；内置宿主默认 true 不会推断业务或 UIKit 启动完成。本次不改变默认值。[最小消费工程](../Examples/CompatibilityHost/Sources/CompatibilityApp.swift) 演示这一约定。

### 其他审计边界

- 交互返回完成会抢占准备，取消保留有效准备；不响应取消的底层工作迟到后不能 push。
- 缺失/迟到回调由执行身份、代次、显式生命周期结束隔离；UIKit 永不完成且宿主不失效时，展示等待没有自动截止时间，宿主需显式结束生命周期。
- 只清理库确实移出的页面，系统返回和业务自行关闭仍需页面/容器的幂等清理。
- 两个真实窗口与两个 router 的来源不串栈；宿主仍须正确声明实际导航域与可见性。
- 通用确认只验证导航来源/代次，业务仍须重查资源与权限；业务未失效且宿主未改变时，库无法察觉业务环境变化。

## 分阶段兼容性

本机 macOS 27.0.1，Xcode 27.2（27B52）、Swift 6.4.2；已装 iOS 27.1/27.2 模拟器。部署目标为 iOS 16 的当前 SDK 构建不等于已在 iOS 16 运行。

| 目标 | 状态与证据要求 |
| --- | --- |
| 当前严格并发与完整测试 | 严格构建通过，macOS XCTest 39/39（含宏4），iOS 包 199/199；完整示例 51/53，两侧滑 UI 失败调查中，尚未放行 |
| 两个 Release 公开 API 消费宿主 | 当前 iOS 27.2 均通过 11 项真实公开 API 检查；Discovery 以实际发现装配，无显式 fallback |
| Release Archive | 两产品 arm64 无签名 Archive 成功；完整示例 Release 构建通过；签名尝试明确因未配置 development team 失败，不能视为签名验收 |
| Swift 6.1 配套工具链/SDK | 未验证：官方配套 Xcode 16.3 下载转向账号授权页面，本机未安装 |
| Swift 6.3 配套工具链/SDK | 未验证：官方配套 Xcode 26.4 下载转向账号授权页面，本机未安装 |
| iOS 16 最小 UIKit 宿主 | 未验证：官方运行时元数据 maxHostVersion/maxXcodeVersion=26.99.0，与本机 27 不兼容；未下载不可用的 6 GB 镜像 |
| iOS 17 完整示例 | 未验证：本机未安装，官方直接下载需要账号；官方平台下载器请求 17.0 返回 exit 70（本机未支持该下载项），未安装运行时 |
| iPhone/iPad 冒烟、签名 Archive | 未验证：末次盘点 iPhone 12 Pro Max（iOS 27.0.1）已通过 USB 连接且开发者模式开启；iPad 仅确认配对。签名仍缺少明确授权 Team／匹配 profile，未安装或启动验证 App |

未修改全局 Xcode 选择；下载仅查询官方来源，没有用非官方 SDK、提高系统下限、屏蔽 warning 或删除目标代替验收。旧环境若无法在本机安装，应在官方支持的另一台 Mac 上按固定源码 SHA 执行 CompatibilityHost 命令。

## 分场景结论与放行门槛

| 场景 | 结论 |
| --- | --- |
| 普通页面 | 通用执行原语具备，可先规划 App 适配；身份、来源、结果、稳定路由值及实际接入回归需验证 |
| 消息双栏 | 需自定义宿主，验收真实来源栈/可见性、详情关闭、窄宽布局与跨栈恢复；标准 Tab 宿主不能直接替代 |
| 房间流程 | 保留业务会话、换房校验、浮窗与挂载证明；逐项验收收起/恢复、取消、确认与必要离场工作 |
| 认证根切换 | 保留业务根协调器；失效旧能力后更新依赖并注入新客户端，账号旧等待不得重放 |

库没有专门的“指定目标只返回”或页面业务结果通道，也没有公开任意多栈事务；不把 reopen/create、performed 或 deferred 当成这些能力。采用方保留结果协调器，能力扩展另行规划。

修复交付与完整生产放行分开记录。完整生产放行仍要求最低工具链、最低系统、真机与有效签名、实际 App 分场景接入测试通过。当前新系统模拟器通过只覆盖当前环境。

## 验证与证据

批次 `lysr-production-readiness-20261117`，预登记能力审查、风险修复、兼容性、最终复验四项。持久根在主 checkout `.build/codex-production-readiness-20261117`，各子任务 evidence/deliveries 分离，共享本批 cache；不复用已回收目录。App 具体映射仅在内部交付材料中，公开文档保持通用。

冻结源码通过两次独立审查；完整复验日志位于 `lysr-readiness-verification/evidence/final`。两个 Release 消费宿主各 11 项检查通过，启动 stderr 无重复类提示。设备架构 Archive 为 arm64、minos 16.0、SDK 27.2，明确未签名。持久侧滑复现脚本另通过 3/3；实际源文件哈希与完整复验一致。

工具链提示分别核实，未使用统一屏蔽：

- 自有源码与测试在最终严格并发构建下没有 Swift 编译警告；两处测试弱局部变量改用弱引用容器，避免依赖较新 weak-let 语法。
- sysroot 提示来自宿主 macOS SDK 进入 iOS 链接环境。最小相同源文件对照表明：只移除变量仍可能被未指定平台的 xcrun 注回 macOS SDK；`xcrun --sdk iphonesimulator` 或明确子进程 iOS SDKROOT 后提示消失。最终 xcodebuild 清除继承的 SDKROOT、由目标选择 SDK，没有该提示，没有修改全局 Xcode 选择。
- AppIntents metadata processor 的“无 AppIntents.framework、跳过提取”来自构建工具，验证宿主未使用 App Intents；原始日志保留。
- Debug hosted 测试存在测试框架与 App debug dylib 重复携带路由类型的既有链接拓扑，原版也存在；独立 Release 消费工程单独运行并采集 stdout/stderr，不能以 Debug 测试替代生产链接证据。

本地集成的源码 SHA、远端 CI 及实际缓存处理结果写入本批交付记录。未解决签名或环境阻塞保持未验证，不以当前环境的通过代替。
