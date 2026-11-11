# 0.2.0 审查与验证记录

## 已复现的缺陷

在 d9f411d 快照新增两个回归用例后，iOS 测试返回 65。

- `testExplicitNonanimatedShowAlsoDisablesReuseAnimation` 观察到复用路径仍传入 `animated: true`，与显式关闭动画不一致。
- `testDisabledFallbackUsesCurrentPlacementWhenSchedulingPending` 观察到禁用路由的等待 placement 为 `me`，而兜底执行域为 `current`。

原始日志位于本批次 `ly020-review/evidence/red-ios.log`。基线 macOS 的 34 项 Core 测试和 4 项宏展开测试通过。

实施后的首轮包测试另复现了跨目标域确认使用旧来源、URL 配置修改后未归一化的问题。首轮宿主测试复现了模态关闭通知晚于导航控制器释放时漏清理的问题。分别保留在 `ly020-options/evidence/package-ios.log` 与 `ly020-demo/evidence/main-20261111-154932.log`，对应修复均有回归用例。

## 实施审查

打开选项与静态准入共用规则，模态执行绑定目标栈。失效等待请求保留现有 deferred 结算契约。客户端弱持有来源和路由器，并验证创建代次。模态关闭持有执行权直至 UIKit 完成。页面上下文弱持有目标栈，以便结算后查询。

真实窗口用例覆盖模态返回、交互取消、全屏覆盖、确认、代理转发和恢复。独立模块示例覆盖嵌套导航与部分组装。

二轮包测试复现了已被其他窗口或展示关系接管的页面仍被清理、原宿主释放后漏通知、转场回调缺失时强快照滞留，以及保留上下文创建的客户端三个操作返回不同失效结果。日志为 `ly020-options/evidence/package-ios-green.log`；该文件虽以 green 命名，实际是新增回归的失败运行，不能作为通过证据。

清理改为独立操作状态，弱引用原宿主，清理前标记页面身份，失效时释放强快照。迟到回调只处理仍存活且未被其他展示树接管的页面。独立复核检查了同步重入、重复回调、宿主替换、模态关闭与执行结算，未发现新的具体缺陷；运行验收仍以最终测试为准。

## 验证状态

| 验证 | 结果 | 证据（批次任务目录下） |
| --- | --- | --- |
| macOS 严格并发构建 | 无 Swift 警告 | `ly020-demo/evidence/final-strict-build.log` |
| macOS Core／宏测试 | 38 + 4 项通过 | `ly020-demo/evidence/final-macos-tests.log` |
| iOS 包测试（跳过宏） | 98 引擎 + 38 Core + 7 Discovery，共 143 项通过 | `ly020-modal/evidence/package-final.log` 与同名 xcresult |
| 主示例 | 24 宿主 + 14 UI 通过 | `ly020-demo/evidence/main-20261111-162903.log` 与同名 xcresult |
| 两个独立 Demo | 各 1 项模块注册 + 2 UI 通过 | `community-20261111-162731`、`messaging-20261111-162823` |
| iPad／Duo | 各 2 宿主 + 2 UI 通过 | `ipad-20261111-165423`、`duo-20261111-165638` |
| 手机标签断言复验 | 3 项受影响 UI 用例通过 | `ly020-demo/evidence/phone-tabs-20261111-165807.log` |
| 格式与差异检查 | SwiftFormat 0.59.1、`git diff --check` 通过 | `ly020-demo/evidence/final-lint.log`、`final-diff-check.log` |

表内缩写的 Demo 日志及 xcresult 均位于 `ly020-demo/evidence`。最终源码摘要为 `final-source-sha256.json`。Xcode 27.2 另输出生成目标的 sysroot 和 AppIntents 元数据诊断，未出现 Swift 源码或并发诊断。

iPad 首次 UI 启动曾卡在系统辅助功能处理阶段，保留中断结果和进程采样后重启对应设备恢复。重试还暴露了测试把标签控件固定查询为手机 TabBar 的问题；已改为兼容原生顶部标签控件，并保留选中状态及目标页面可见性断言。相关失败记录与界面层级附件一并保留，没有通过放宽路由断言掩盖问题。

## 本地集成与缓存收尾

五个实施提交已快进集成至本地 `main`（功能提交 `85f2fbec6ff499c5e581d252bf31458ed0990b8c`）。主分支再次通过 143 项 iOS 包测试、24 项宿主测试、38 项 Core 与 4 项宏测试、严格并发构建、SwiftFormat 0.59.1 及差异检查。Swift 源码、包清单和生成工程的 SHA-256 与已验收工作区完全一致。复验日志和源码对照位于 `ly020-client/evidence/main-*`。

六个阶段任务已执行 `finish`，批次已执行 `batch-finish`。已回收逻辑数据 1.37 GiB，回收前目录占用 1.44 GiB；清理前后磁盘可用空间为 288.41 → 289.86 GiB。目录占用与可用空间变化是不同指标。共享下载依赖、解析元数据及未知目录保留，本批缓存没有跳过项。

证据保留至 2026-11-18 17:06（UTC+8）；批次交付摘要位于 `.build/codex-020/tasks/ly020-integration/deliveries/SUMMARY.json`。版本记录保持 `0.2.0 (Unreleased)`。

## 验证边界

当前使用 Xcode 27.2、Swift 6.4.2 和 iOS 27.2 模拟器。窗口几何的新成员同时受编译器和系统版本保护；较早的 Swift 6.1／SDK 18、iOS 16 真机以及预编译静态库的自动发现未在本轮验证。GitHub Actions 配置已更新并检查 YAML 语法，远程 CI 未运行。
