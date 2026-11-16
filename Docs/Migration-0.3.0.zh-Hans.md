# 0.3.0 迁移说明

0.3.0 尚未发布，包含源码不兼容调整。组件只管理导航、取消、来源与上下文生命周期；登录状态、权限、登录页跳转与登录后是否继续原请求由业务负责。本轮不迁移任何具体业务 App。

## 接口替换

| 0.2 接口 | 0.3 迁移方式 |
|---|---|
| `LYRoutePolicy.requiresSession`、`LYInterceptRequest.requiresSession` | 删除参数；在业务处理器读取业务状态 |
| `LYRouteInterceptor.session` | 删除；业务判断登录／权限，通用拦截器仍可用于其他准入条件 |
| `LYRouterHost.routerSessionID`、内置宿主 `sessionID` | 删除实现／赋值；宿主只描述容器与就绪状态 |
| `sessionDidChange()`、`resetSession()` | 业务边界失效前显式调用 `invalidateContext()`；普通登录自行决定是否失效 |
| `.sessionChanged`、`.sessionReset` | 观察者改为处理 `.contextInvalidated` |

## 业务边界与新客户端

```swift
@MainActor
func replaceBusinessEnvironment() {
    router.invalidateContext()          // 必须先撤销旧能力
    account.replaceEnvironment()        // 接入方自己的业务操作
    feature.navigation = router.makeClient(from: visiblePage)
}
```

`LYRouteEnvironment` 是构建时依赖，不支持原地替换已构造模块的依赖。上例需由业务持有的依赖容器更新状态；需要重建模块时，先失效并停止旧路由器，再通过 `build` 构建新实例并注入其客户端。

旧 `LYRouteContext.open` 返回 `.failed(.contextChanged)`；旧 `back` 不操作栈；旧上下文 `makeClient` 继承旧代次，其 `open`、`openURL`、`dismiss` 都返回 `.contextChanged`。正常导航结算不撤销页面后续回调。路由器停止或释放后，`context.open` 返回 `.stopped`，客户端仍返回 `.contextChanged`。

`invalidateContext()` 保留宿主和导航栈，不关闭任何页面、不切根、不执行登录。当前执行以 `.contextChanged` 结算，准备任务被取消，执行权立即释放；旧确认回调失效；每个等待请求通知一次 `.contextInvalidated`，重复失效不重复通知。已提交给 UIKit 的转场可以结束，其迟到回调不能改写新执行。

业务决定是否保留页面、重建根页面与释放业务资源。需要继续导航的页面应重新注入客户端，不能通过旧上下文重新获取能力。**业务未调用失效接口且宿主未变化时，组件无法识别业务环境已经更换。**

## 登录判断放在业务处理器

```swift
builder.action(.wallet, policy: .init(allowsExternal: true)) { _, context in
    guard account.isSignedIn else {
        if context.source.isExternal {
            context.fail(.blocked)       // 外部请求进入通用等待机制
        } else {
            context.continueNavigation(to: .login)
        }
        return
    }
    wallet.open(using: context)
}
```

普通登录可以保留代次，登录页仍可用原 `context.back(from:)` 返回。示例不自动继续用户原来的钱包请求，登录后由用户再次点击；外部钱包请求则在业务确认条件满足、调用 `navigationDidStabilize()` 后重试。业务也可以选择失效并丢弃等待项。这些都是业务策略。

主示例的 `DemoAccount` 保存登录状态，`AccountRouteModule` 判断准入；退出时 `SceneDelegate` 先显式失效，再更新状态并给根页面注入新客户端。功能模块 Demo 不实现账号协议。

## 宿主更换

更换宿主无论旧宿主是否仍存活，都撤销旧执行与导航能力，清理事件观察，隔离缺失／迟到的完成回调。同一宿主重复 `attach` 仅重新连接事件，不撤销当前代次。

单纯更换宿主保留可重试的外部等待项；来源不再属于当前宿主时仍按来源规则丢弃。账号、业务依赖或根页面环境更换应先调用 `invalidateContext()`，不要依靠宿主替换推断业务边界。

## 调用方取消

- `open`／`openURL` 准入前已取消：返回 `.contextChanged`，不构造页面、不改栈、不替换等待项。
- 创建导航的调用方在准备中取消：只终止自己的当前执行；立即结算，不等待底层工作响应取消。底层工作可能仍运行，继续操作前必须检查 `await context.isStillValid()`。
- 已进入展示阶段：按实际结果结算，不回滚展示或业务副作用。迟到取消不影响后继执行。
- `waitForNavigation()` 只是观察；取消等待者不撤销别人的导航。已返回 `.deferred` 的外部请求成为独立等待项，之后取消原调用方不撤销它。

## 接入门槛

本轮交付与生产放行分别记录。当前新系统模拟器通过不代表最低系统、最低工具链、真机与 Release 签名验收通过。验证范围和未完成项见 [验证记录](Verification-0.3.0.zh-Hans.md)。先通过 App 层适配已有导航契约，普通页面、消息自定义容器、房间流程与认证根切换分别验收，具体业务 App 的迁移另行实施。
