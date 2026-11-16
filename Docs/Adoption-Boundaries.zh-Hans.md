# UIKit 模块化应用的采用边界

LYStackRouter 可以承担类型化导航、注册校验、页面身份复用、异步准备取消、确认门、来源绑定和外部最新请求等待。认证、动态权限、业务写入、共享会话以及业务结果同步由应用负责。

## 能力与集成责任

| 场景 | 当前 public API | 应用保留的责任 |
| --- | --- | --- |
| 跨模块纯导航 | LYRouteClient、makeClient(from:) | 依赖注入；保持既有业务 Client 的 actor 与结果契约。 |
| 稳定路由及模块登记 | LYRoutable + Kind、builder.page/action/url | Hashable 稳定业务值、穷尽 Kind、模块依赖与外部开放策略。 |
| push、返回已有页、顶页去重 | context.show(identity:)、LYPageIdentifiable | 页面实时身份和幂等清理。 |
| 先查数据再展示 | context.prepare、await isStillValid()、fail | 数据/权限服务与每个业务等待边界的有效性判断。 |
| 通用确认 | context.confirm | 确认文案、动态业务条件复查、必要副作用的所有权。 |
| 单栈/标准 Tab | LYSingleStackHost、LYTabBarHost | 强持有 host/router、根就绪状态及代理转发。 |
| 双栏/自研容器 | LYRouterHost domains/all/select/reveal/customShow/tearDown | 容器几何、可见列、草稿、详情关闭与生命周期、事件上报。 |
| 共享会话页面跨域恢复 | context.revealExisting(where:) | 会话仍有效、已实际挂载才撤销恢复入口。 |
| 上一页/模态关闭 | client.dismiss、context.back | 自定义详情容器状态；业务结果不由返回动作产生。 |
| 账号/宿主变化 | invalidateContext、detach/attach、tearDown | 明确选择清空还是保留等待意图、重建客户端、资源清理。 |
| 业务页面结果 | 不提供通用结果回传通道 | 显式业务 callback、Reducer 或应用协调器。 |
| 指定 kind/identity 只返回 | 不提供专门的 public popTo API | handler 内有条件组合查找，定义缺失/跨域/模态策略。 |

LYRoutable 要求 Hashable/Sendable 及 CaseIterable Kind。已有应用路由若只符合 Equatable，或带 UIKit/Store/完整快照，不能直接作为路由器可延后的公共值。公开 Route 参数只携带稳定目标信息；请求 metadata 与应用业务权限各自管理。

注册 policy 的 placement 是目标域默认值。LYOpenOptions 提供动画、弱来源和 Sendable 附加值，没有单次 placement 覆盖字段。同一业务目标如果存在“在来源栈打开”和“窗口入口固定去某 Tab”两套语义，应由应用适配明确表达。

## 结果必须保持原意

| 结果 | 能证明什么 |
| --- | --- |
| created | 本次展示了新页面；context.replaceStack 当前固定以此值标记，调用方不能只凭枚举名推断构造次数。 |
| reused | 回到已有页面。 |
| alreadyVisible | 已有目标就在顶部。 |
| performed | 动作已执行；不表示创建了页面，也不表示服务端业务写入已确认。 |
| awaitingConfirmation | 确认框已呈现；后续确认导航是另一次执行。 |
| deferred | 当前请求已结算为等待；重试仍会重新校验。 |
| ignored | 当前用户请求未执行。 |
| failed(reason) | 请求以给定原因失败。 |

只有 created/reused/alreadyVisible/performed 的 isSuccess 为 true。awaitingConfirmation/deferred 均不是最终成功。初始调用不承诺在后续确认/重试后再次返回最终结果。同步 request 可能返回执行提出的结果，需要 await open 才能等待本次执行的实际结算。

action 注册默认以 performed 提出结算结果，处理器可显式失败；它不确认导航器没有等待的外部异步工作。若外部请求执行中以 blocked 失败，最终结果可转为 deferred，应映射调用者实际收到的结算值。

如果应用原有结果枚举缺少 performed，不能把动作映射为 created；缺少 unregistered/notExternal/unmatchedURL/rejected 等失败时，也应明确扩充或记录有损映射，而不是吞掉原因。页面客户端的已移除/被覆盖来源在当前代次下返回 ignored；代次失效则 contextChanged，兼容适配应保留应用实际契约而非全局互换。

## 自定义容器与会话

allNavigationControllers 可列出可被找回的全部栈；当前 navigationDomain 必须与可交互来源一致，或由应用额外预检来源。仅把隐藏列的 top 列入当前域，并不足以阻止旧页面发起导航。自定义宿主仍需上报 didShow、Tab 选择、可见性和阻挡解除。

customShow 接管页面展示并报告结果，应用容器可保留另一栏草稿和会话。context.show 的 make 最多调用一次；这不保证特定宿主复用详情时一定跳过构造，采用方应在构造前明确查找已有详情，并验证实际宿主行为。标准 Tab 宿主不自动理解任意嵌套容器。应用自行替换的详情栈和业务 dismiss，继续由容器维护清理；库移除通知只覆盖库主动移出的页面，系统返回和业务自行 dismiss 仍需要页面自身的幂等生命周期。

会话型页面被物理移出后，恢复可创建新控制器并复用原业务会话；页面仍在某个栈时可 revealExisting。二者都不能被解释成重新启动业务会话。恢复入口只能在真实挂载后关闭，不能用 deferred、awaitingConfirmation 或动作 performed 代替挂载证明。

confirm 会重新核对导航上下文与来源；应用仍须重新核对会话、资源代次、业务 busy 状态和权限。导航准备被取消，不代表应用已经接纳的必要离场/清理工作也可以取消。认证根替换和窗口事务继续由应用协调器执行；临时宿主未就绪后通知 navigationDidStabilize 会抢占准备、保留代次与等待项，账号变化则应显式 invalidateContext。

## 明确限制

没有专门的 public popTo(kind/identity) 或业务页面结果回传通道。show(identity:) 找不到页面会创建；revealExisting(where:) 仅在创建它的导航执行仍为当前有效执行时生效，模态时只查自身导航栈，找到但受阻仍返回 true 并报告 blocked。因此“重新打开路由”不等于“只返回、绝不创建”，也不能替代允许抢占准备的上一页操作。

context.replaceStack 只替换当前执行的目标栈，且将本次导航结果标记为 created；不提供通用跨任意多栈的事务或任意结果 setter。应用原有跨栈清理/结果兼容由自己的宿主策略负责。这些边界不阻止采用通用执行引擎，也不代表需要把认证、权限或业务结果协调迁入库。

这份能力表来自公开源码与现有用例审阅。应用采用后的容器、会话、业务结果和认证回归必须由实际接入证据证明；通用示例通过不能替代实际应用、设备或服务验收。
