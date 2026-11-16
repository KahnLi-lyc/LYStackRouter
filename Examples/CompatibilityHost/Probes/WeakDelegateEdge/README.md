# 弱代理释放后的系统侧滑复现

这是独立诊断夹具，不改变主示例的用户流程。脚本用固定 `28c384f` 提交提供示例和 UI 测试结构，叠加所指定工作区的**当前 Sources**，再应用可审查的 `probe.patch`，在登记的缓存中运行三项真实 UI 用例。

保留原侧滑完成、侧滑取消／等待深链的断言。新增场景先完成两次真实自定义动画和交互查询，释放业务代理并确认弱引用为空，随后直接侧滑；中间没有 push。预期回到 club.A、depth 2、库清理计数 0。脚本要求实际运行 3/3，不允许缺失或跳过用例。

在已启动的当前 iOS Simulator 上，通过生命周期 `run` 执行（Python 3.9+、Git、patch、Xcode）：

```bash
python3 Examples/CompatibilityHost/Probes/WeakDelegateEdge/reproduce.py \
  --repo /absolute/review/LYStackRouter \
  --destination 'platform=iOS Simulator,id=SIMULATOR_UUID'
```

必须由 `run` 提供 `CODEX_CACHE_DIR`、`CODEX_EVIDENCE_DIR` 和 `CODEX_DEPENDENCIES_DIR`。脚本不修改输入工作区；保存固定夹具版本、当前库哈希、补丁哈希、命令、日志和 xcresult。具体执行环境与结果见 [生产准备记录](../../../../Docs/Production-Readiness-0.3.0.zh-Hans.md)。最低系统与真机验收仍需独立执行。
