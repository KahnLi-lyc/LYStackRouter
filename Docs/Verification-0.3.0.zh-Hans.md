# 0.3.0 验证记录

基线：`27afa9c26a19f00ae02670039d82949f5f393c92`（0.2.0）。0.3.0 尚未发布；本记录区分修复交付与生产接入，不能用旧版本通过记录代替新版本验收。

## 范围与环境

实施与验证日期：2026-11-16 至 2026-11-17。

- 实现通用上下文失效、取消传递、宿主替换与示例业务登录迁移；未修改具体业务 App。
- Xcode 27.2（27B52），Swift 6.4.2，iPhone 17／iOS 27.2 Simulator（`E453F84C-39A3-4A08-99D2-CAB389F6B52B`）。
- 验证使用主 checkout 内独立批次 `lysr-030-20261116`，与旧失败审查任务分开。
- 证据根：`/Users/kahnli/Desktop/SwiftLibraries/LYStackRouter/.build/codex-030/tasks/`。

## 原版本缺陷复现

在未修改 0.2 生产源码时运行 6 个可编译的回归，出现 14 条预期失败断言；不是接口移除造成的编译错误。

| 回归 | 旧版表现 | 新版要求 |
|---|---|---|
| 保留上下文 `open` | 重置后仍可发起新导航 | `.contextChanged`，不改栈 |
| 保留上下文 `back` | 重置后仍可返回 | 不改栈、不清理页面 |
| 保留上下文 `makeClient` | 获得当前有效代次 | 继承旧代次，操作均失效 |
| 调用方取消准备 | 等底层工作结束后仍展示 | 及时结算，迟到工作不展示 |
| 准入前已取消 | 仍可创建页面 | 不构造页面／不改等待项 |
| 弱宿主释放后替换 | 展示执行未结束，后继被阻塞 | 及时结算，后继可准入 |

原版证据：`lysr-030-context/evidence/lifecycle-red.log`、`lifecycle-red.xcresult`。另对失效期间观察者重入添加失败用例；初始实现出现 3 条断言失败，加入代次先更新与失效期间准入保护后复验。证据：`lifecycle-reentrancy-red.xcresult`。

页面构造、宿主展示／选择／恢复、谓词、UIKit 包含关系回调与移出页面清理也检查同步重入。通过 Git archive 导出原始 `27afa9c`，逐个核对生产 `Sources` 的 Git blob，测试只适配为旧 `resetSession`／`sessionReset` 与宿主协议：最终 `original-final-red.xcresult` 中 10 项实际运行并全部失败（准备任务启动 1 项、操作回调 9 项）。原始测试适配源码与完整性核对位于 `original-final-tests/`；此前含不完整测试替身的中间 red 不作为该结论证据。

新原子失效机制实施过程中另补停止重入回归，确认失效中停止仍拆除模态事件桥，更换宿主中停止不会重新绑定宿主；分别先观察到失败再修复，见 `reentrant-stop-red.xcresult` 与 `host-attach-red.xcresult`。最终审查还确认公开 `navigateBack` 在失效观察者中重入会改栈并留下未结算执行；`back-admission-red.xcresult` 的 1 项测试出现 4 条预期失败断言，随后增加失效期间的返回准入保护。

## 验证矩阵

以下为实际执行结果。最终包测试包含最后一处返回准入保护；完整示例／Demo 与三次动画复跑在该保护前运行，该新增保护只在同步失效期间拒绝返回，正常路径不变。集成后继续复验完整包与宿主测试。

| 检查 | 证据与状态 |
|---|---|
| 原版宿主完整基线 | `lysr-030-verification/evidence/baseline-hosted.xcresult`：31 项通过 |
| 生命周期与操作回调矩阵 | 22 项生命周期、9 项操作回归，最终结果随完整包复验记录 |
| 严格并发 Swift build／macOS Core 与宏测试 | `lysr-030-verification/evidence/swift-build.log`／`swift-test.log`：构建通过，Core 39 + 宏 4 项通过，无编译警告 |
| iOS Package 测试（跳过宏测试） | `lysr-030-cancellation/evidence/package-quality-green.xcresult`：199 项通过（引擎 153、Core 39、Discovery 7） |
| 主示例完整宿主与 UI 测试 | `lysr-030-verification/evidence/examples-final.xcresult`：49 项通过（宿主 34、UI 15） |
| 两个模块 Demo 注册与 UI 冒烟 | `DemoCommunityFeature.xcresult`、`DemoMessagingFeature.xcresult`：各 3 项通过 |
| 动画回退三次定向复跑 | `animated-reuse-1/2/3.xcresult`：各 1 项通过，历史风险见下文 |
| SwiftFormat 0.59.1／差异检查 | `swiftformat.log`：105 个文件，0 个需格式化；`git diff --check` 通过 |
| 本地 `main` 集成后复验 | `integrated-package.xcresult`：199 项；`integrated-hosted.xcresult`：34 项；严格并发 build、macOS Core 39 + 宏 4 项、全仓格式与差异检查均通过 |

最终生产源码提交为 `9066d0e84e5caece63fe3c4653203fa3d73ad950`，已本地快进集成到 `main` 并实际复验。完整 UI 与模块 Demo 验证后唯一生产源码变化为 `navigateBack` 的失效入口保护，新增回归与集成后的完整包／宿主测试覆盖该最终版本；未重复整套 UI 和模块测试。文件哈希证据为 `full-suite-source-manifest.json`、`final-suite-source-delta.json` 与 `integrated-source-manifest.json`。

## 动画回退既有不稳定问题

旧生产审查的 `hosted-audit.xcresult` 曾在 `HostedTransitionTests.testAnimatedReuseCleansRemovedPagesOnlyAfterTransition` 失败：转场协调器缺失、等待结果 nil、移出页面未清理且栈仍为 4。原工程单项复跑曾通过，本轮未修改基线的完整宿主 31 项也通过。不能据复跑通过判定根因已经解决。

调用链为 `request → submit → admit → execute → context.show → reuse → popTo → replaceStack → setViewControllers`，完成与清理由转场协调器触发。本用例没有失效、取消、宿主替换或业务登录操作；本轮未修改 `setViewControllers` 的调用与转场移出快照清理规则；新增的回调后身份检查在此用例中均应为 true，代次保持不变。这支持将历史现象与本轮明确修复分开评估，但尚未证明 UIKit／窗口时序异常的具体根因。必须保留该风险，不以通过复跑宣布生产放行。

旧失败证据继续保留在 `.build/production-audit-20261116/tasks/lysr-production-audit-20261116/evidence/hosted-audit.xcresult`。

## 工具链与生产边界

macOS 严格并发构建／测试无编译警告。iOS 日志中有两类工具链输出，未全局抑制：

- `LYStackRouterdynamic-product: clang: warning: using sysroot for macOS ... but targeting ... ios ... simulator`：来自 Xcode 为 SwiftPM 产品生成的链接命令，原版基线也存在。检查生成 framework 的 `LC_BUILD_VERSION` 为 `IOSSIMULATOR`、最低版本 16.0、SDK 27.2；当前模拟器测试可运行。这不能代替最低工具链或真机链接验收。
- AppIntents 元数据提取被跳过：相关 Demo／测试目标没有依赖 AppIntents.framework，与路由功能无关。

自有 Swift 源码未出现并发或编译警告；不能将上述结果概括为整个 Xcode 构建零警告。

以下均未在本轮完成：iOS 16／17 最低支持系统、最低 Swift 6.1 核心引擎与 Swift 6.3 Discovery 工具链、真机、签名 Archive／TestFlight、预编译静态库自动发现。生产接入仍需单独验收。

具体业务 App 应通过 App 层适配已有导航契约，先迁移普通 push；消息双栏使用自定义宿主，语音房／换房确认／认证根切换分别验证。本轮没有实施这些迁移。

## 交付记录

本轮在 `codex/lystackrouter-030` 独立工作区实施；旧 Claude 修复 worktree 与 `claude/lystackrouter-production-review-251a94` 分支按用户要求删除。删除前将未提交的 11 个文件完整备份至 `/Users/kahnli/.codex/recovery/lystackrouter-20261116-claude/`，包含归档、补丁、状态和恢复元数据；该恢复备份没有自动到期设置。另一个 GPT 审查 worktree 保留。

规格与质量复核后形成中文提交，本地集成及实际复验另记。当前历史动画失败的具体根因仍未知；最低系统、最低工具链和真机验收未完成，因此本轮不作生产放行判断。

## 修复交付状态

规格与代码质量复核均通过，发现的缺陷均有先失败后通过的回归证据。新增回归、公开接口迁移及上述相关验收无未解决失败；代码可作为 0.3.0 未发布版本交付审查。历史动画偶发问题与最低系统／工具链／真机边界仍保留，**尚不放行完整生产接入**。本地集成后复验已通过；缓存收尾记录存放在同一证据批次。未推送、未打 tag、未发布。
