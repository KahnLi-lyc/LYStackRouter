# 设计说明

本文说明 LYStackRouter 的分层、一次请求的处理顺序、执行引擎的语义，以及设计前对开源路由库的源码分析。

## 1. 分层

| 模块 | 依赖 | 职责 |
|---|---|---|
| `LYStackRouterCore` | Foundation | 路由协议、注册表与 Builder、策略、URL 模板与路由表、拦截器、重写、观察者、结果类型、依赖环境。可在 macOS 上测试。 |
| `LYStackRouter` | Core、UIKit | 路由器、执行、复用、抢占、等待、清理、确认门、宿主协议与内置宿主、`LYRouteModule`。重新导出 Core。 |
| `LYStackRouterDiscovery` | 引擎、宏 | `@LYRouteModule` 声明、section 读取、`LYRouteModuleSet.discovered`。 |
| `LYStackRouterMacros` | swift-syntax | 宏实现，只在使用 Discovery 时编译。 |

## 2. 构建

`LYStackRouter.build(...)` 依次：

1. 解析模块集合（显式列表，或自动发现结果按 `moduleID` 排序）；
2. 检查 `moduleID` 重复；
3. 用 `init(environment:)` 创建每个模块，把缺依赖转换为 `missingDependency(module:type:)`；
4. 依次调用 `register(into:)`，Builder 记录每条登记属于哪个模块；
5. 检查重复登记、URL 模板语法与冲突；默认要求每个 `Kind` 都已登记（`allowsUnregistered: true` 时关闭）；
6. 创建路由器并绑定宿主。

任何一步失败都抛出 `LYRouteBuildError`，不会得到一个部分可用的路由器。

## 3. 一次请求的准入顺序

`request` / `open` / `openURL` 都进入同一个准入流程，所有检查都在切换 Tab、创建页面等副作用之前完成：

1. 路由器已停止 → `failed(.stopped)`
2. 没有登记 → 本地请求在允许未登记且有兜底时交给兜底；外部请求一律 `failed(.unregistered)`（未注册路由没有策略，不能推断为允许外部打开）
3. 策略为禁用或被重写禁用，且没有兜底 → `failed(.unavailable)`
4. 外部来源且未放开 `allowsExternal` → `failed(.notExternal)`
5. 参数校验失败 → `failed(.invalidParameter)`
6. 拦截器按优先级执行：`reject` 失败；`redirect` 让新路由重新走完整流程（深度上限 4）；`deferUntilReady` 外部请求等待、用户请求忽略
7. 选择处理器：禁用路由交给兜底（原因 `unavailable`），占位路由在有兜底时交给兜底（原因 `placeholder`），其余交给登记的处理器
8. 宿主与目标域是否空闲（没有进行中的执行、弹窗或转场）→ 不空闲时外部请求等待、用户请求 `ignored`
9. 取得执行权，切换目标域，调用处理器

兜底可以展示页面，也可以打开 H5 或执行自定义动作，所以禁用与占位路由走兜底前同样经过第 4～6 步，降级不会放宽原入口的约束。

URL 入口先按模板解析成路由，解析失败为 `failed(.unmatchedURL)`；之后与类型化请求相同。

## 4. 执行引擎

### 执行与结算

- 每次导航对应一个执行对象，记录会话、代次、阶段（准备 / 展示）、预期结果和后台任务。
- 执行只结算一次。处理器同步完成且没有转场时立即结算；否则等待准备任务和转场结束后再结算。
- 代次在会话变化、宿主解绑、停止时更新；所有异步回调先核对代次，迟到的回调不会生效。

### 返回抢占

- `prepare` 会绑定来源页面与导航栈，执行进入准备阶段。
- 准备期间，用户的合法返回、来源页离开栈顶、宿主状态变化都会让本次导航以 `failed(.contextChanged)` 结束，并取消准备任务。
- 准备完成后必须 `await context.isStillValid()`：它会等待来源上的转场结束，再确认没有被抢占、来源仍在栈顶、没有弹窗。

### 外部请求等待

- 外部请求受阻时只保留最近一个，带序号与会话标识；新的外部请求取代旧的。
- 唤醒来源：弹窗离开窗口（观察 presentation 对应的视图被移除，不替换代理）、导航栈 `didShow`、阻挡转场的完成回调（交互返回被取消时 UIKit 不保证回调 `didShow`）、宿主调用 `navigationDidStabilize()`。
- 从无会话变为有会话时保留等待请求并绑定新会话；切换账号或退出登录时清空。

### 复用与清理

- `show(identity:)` 在当前导航栈中从栈顶向下查找身份相同的页面：在栈顶为 `alreadyVisible`，在栈内则回退到它为 `reused`，找不到再新建。
- 回退或 `replaceStack` 只清理确实离开栈的页面，并且等转场结束后再调用 `routerDidRemovePage()`，避免在动画中途释放资源。
- `revealExisting(where:)` 在宿主全部导航栈中查找会话型页面，找到后切换到所在的域并回到它。

### 确认门

- `confirm` 展示确认框，本次导航以 `awaitingConfirmation` 结算并释放执行权的等待。
- 确认框未能展示（UIKit 拒绝）时以 `failed(.blocked)` 结算。
- 用户确认后，等确认框真正关闭、并确认来源页仍可见，再重新取得执行权调用后续操作；取消什么也不做。

## 5. 开源路由库源码分析

设计前下载并阅读了以下库的源码（RouteComposer 与 swift-parsing 只读了 README）。

| 库 | 源码中的实际机制 | 借鉴 | 读源码确认的问题 |
|---|---|---|---|
| URLNavigator | 逐段匹配，`<type:key>` 占位经 converter 转换，失败即不匹配；多个候选取字面段最多者；`register`（返回页面）与 `handle`（执行动作）分开 | 类型化占位、按具体程度消歧、页面与动作分离 | 模式存在字典中，具体程度相同时结果不确定；https 的 host 被当作路径；退回最顶层控制器找宿主；`[String: Any]` 参数 |
| TheRouter | 扫描类后注册并按版本缓存成 JSON；同 scheme、同段数时第一个命中即返回；`alloc init` 后用 KVC 注入参数；切 Tab 用 `asyncAfter(0.05)`；同步 Bool 拦截器加模式白名单；重定向分 replace/add/delete/reset；DEBUG 下做一致性差集检查 | 优先级拦截器、重定向操作分类、调试期一致性检查、统一失败回调 | 运行时扫描；KVC 无类型；延时规避转场；按类回退页面；重定向用前缀匹配，多条 replace 只有最后一条生效 |
| ReerRouter | 宏生成 `@used @section` 记录（key 哈希 + 类），启动时在 `+load` 或手动读取；页面用 `static make(with:)` 构造；打开前可改写 URL；失败回退 URL | 编译期写记录、运行时读取；类型自带工厂；打开前改写；失败回退 | 依赖 ObjC `+load`；重复只靠 assert；没有穷尽检查，记录丢失不会被察觉；key 中没有占位 |
| swift-url-routing | 路由枚举 + parser-printer，`OneOf` 组合，`PathEnd` 要求完整匹配，子路由可嵌套 | 同一定义双向使用与往返测试；子路由组合对应“模块拥有 URL 表”；完整匹配 | 依赖 Parsing 与 CasePaths，泛型很重，只取思路 |
| FFRouter | 字典树逐段下钻，`:id` 只能在末段，`*` 通配；正则 Rewrite | 路由很多时可用字典树；重写作为配置 | 单例；正则难维护 |
| CTMediator | `Target_X` / `Action_y:` 反射调用；`native` 前缀的 action 禁止从 URL 远程调用；找不到目标时走统一兜底 | 区分本地与外部可调用；统一兜底 | 字符串反射，没有编译期检查 |
| swift-router | SwiftUI 类型化路由 + `FromURL` / `IntoURL` 双向转换 | 由路由自己声明双向 URL | 只面向 SwiftUI |

结论：这些库都把“URL → 页面”的注册与匹配做得比较完整，执行层普遍很薄，依赖最顶层控制器和延时，没有转场锁、返回抢占、异步准备后的复验、多页清理和会话隔离。LYStackRouter 组合了开源库擅长的注册与匹配层，以及显式处理导航执行权、转场与生命周期的引擎。

### 为什么不基于 swift-navigation 的 `NavigationStackController(path:)`

本库面向页面自行持有状态、业务模块独立组装的 UIKit 应用，通过宿主描述分栏、嵌套导航与会话型页面的实际容器。导航栈的真实页面和身份作为复用与清理依据。

## 6. URL 模板

- 模板只写路径，如 `club/<id>`、`<int:x>`、`<path:rest>`；scheme 与 Universal Link host 由 `LYURLConfiguration` 统一配置。
- 自定义 scheme 的 host 当作第一段；https 先校验 host 在白名单中，再去掉 host。
- 消歧：字面段最多者优先，其次按登记顺序；形状相同的两个模板在构建时报冲突。
- query 键重复或无值时拒绝匹配，避免歧义输入被静默接受。
- 每条模板同时提供解析与生成。`router.url(for:)` 逐个尝试能表达该路由的模板，只返回能被整张路由表解析回同一路由的 URL：首选模板被更具体的模板截获（例如 `club/new`）时换用别名模板，都不行时返回 nil。往返校验不应用远程重写。


## 7. 打开选项、静态能力与业务客户端

`LYOpenOptions` 位于 UIKit 引擎层，携带动画、弱来源页面与 `Sendable` 附加值。业务路由仍通过关联值声明输入。等待请求保存完整选项，重定向与确认后的执行继续使用这些选项。来源存在性单独记录，弱引用失效后不会被解释成一次无来源请求。

静态检查与提交共享停止、登记、禁用、外部策略和参数校验规则。`canOpen` 和 `canOpenURL` 不执行拦截器与处理器，静态结果允许 UI 判断是否提供入口，运行时结算仍由打开流程负责。禁用路由走兜底时，执行和等待都使用 `.current`。

`LYRouteClient` 封装主执行器上的异步操作，可作为 `Sendable` 依赖注入业务模块。路由器工厂绑定当前代次、会话和可选弱来源。客户端调用前检查这些凭据，旧账号、旧宿主、隐藏或销毁页面不会继续导航。公开初始化方法允许模块测试注入记录型替身。

## 8. 执行导航域与模态流程

执行对象记录本次目标导航栈，处理器上下文、异步校验、确认及转场等待使用该绑定。宿主可以把嵌套详情栈声明为当前导航域的一部分，来源必须位于可见域的栈顶。

最上层模态导航栈通过显式来源进入 `.current` 流程，模态域内复用查找只在该域中进行。内部事件桥转发业务导航代理能力，并在停止接管时按归属恢复原代理。返回完成或模态移出后终止失效准备，交互取消保留来源。页面清理与业务会话分离，库只处理页面退出责任，房间等会话资源由模块管理。

## 9. 窗口上下文与示例边界

`LYWindowContext` 为辅助展示提供场景感知查询，引擎使用宿主和执行绑定解析导航。自动活跃场景必须唯一，主窗口候选必须可见、normal 且有根控制器。顶层控制器优先展开 presented，再展开系统容器与实际可见的搜索结果。几何解析是可独立测试的纯函数。

示例使用独立契约、UI 和功能包，模块 Demo 只组装自身功能。主示例验证两种组装方式、嵌套宿主、跨域会话复用和模态生命周期，功能之间仅发送公共路由。
