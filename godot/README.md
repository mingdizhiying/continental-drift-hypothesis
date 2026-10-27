# Godot 运行版

在 Godot **4.7.2** 项目管理器中导入本目录的 `project.godot`，打开后按 **F6** 运行当前主场景，或按 **F5** 运行项目。默认完整离线运行，不需要启动 Node.js、不需要安装插件。字体使用系统中文字体，不依赖在线字体服务。

当前正在分三阶段对齐网页 v0.3.2，进度见 [MIGRATION.md](MIGRATION.md)。已完成第一阶段：八种治理行动、五种守护与三种旧法则、圣光屏障、任期结果和结局汇总。地图仍暂用允许重叠的示意板块与中心距离关系；真实领地、资源争夺与外交休战将在第二阶段加入。迁移允许反复返回旧城。

## 在编辑器里改什么

| 文件 | 编辑入口 |
| --- | --- |
| `scenes/main.tscn` | 主界面容器、按钮、面板和弹窗；节点保存在场景中 |
| `scenes/world_map.tscn` | 地图容器和城市显示层 |
| `scenes/city_view.tscn` | 板块 Polygon2D 的轮廓、城市标记和标签；轮廓线运行时跟随多边形 |
| `scenes/metric.tscn` | 城市指标文字与进度条 |
| `theme/atlas.tres` | 所有面板、按钮、字体与颜色的统一主题 |
| `data/world.tres` | 在检查器展开 Cities、Actions、Events，调整城市初始位置/速度/指标/颜色、行动效果与事件文案/效果/优先顺序 |
| `scripts/world_rules.gd` | 回合执行顺序、漂移、誓约保护、事件条件、迁移和结局规则 |
| `scripts/city_economy.gd` | 完整支付、旧法则的行动成本/收益、失败原因及屏障结果 |
| `scripts/main.gd` | 玩家输入、选城、预览确认、界面刷新、导出与异步请求协调 |
| `scripts/ai_client.gd` | 本地代理地址与请求超时；默认 `http://127.0.0.1:4173/api/world` |

`data/world.tres` 使用四种自定义 Resource：CityDefinition、ActionDefinition、CitizenEventDefinition、WorldConfig。运行时复制资源生成 Dictionary 状态，不会把游玩结果写回初始资源。规则状态与地图节点分离；地图缩放和动画不会改变距离或结算。

地图标签避让，并提供六个固定城名按钮；板块重叠时仍能分别查看。仅当前治理城市允许行动或立誓，行动完成后选中城市跟随迁移。鼠标悬停治理按钮可查看原版的数值代价。

### 修改边界

- 当前以六座城市、八种治理行动为基线。行动资源中的cost/gain驱动支付、按钮说明和历史；新增城市/行动后，需要同时调整界面、代理校验和对照测试。
- 事件的 `predicate` 对应 `WorldRules.event_matches()` 中的已实现条件。修改说明文案不改变判定；新条件需补充脚本。
- 位置誓约恢复时回到**立誓坐标**；数值誓约按轮初条件生效，以轮初指标减主动支付成本为下限，不能返还建设或公开秘密成本。
- 真实 AI 的追加影响在本地迁城判定之后处理，与网页原型一致。
- 漂移地形是示意多边形，尚无独立地形、美术贴图、迷雾、代码热更新或存档恢复。关闭程序或重新创造世界会清空进度；JSON 导出供查看历史，不能作为读档导入。

## 真实 AI（可选）

Godot使用与迁移基准配套的独立代理。按根目录 README 配置 `.env` 后在仓库根目录运行：

```sh
node --env-file=.env tools/godot-proxy.mjs
```

再在游戏右侧勾选“使用真实 AI 接口”。誓约、回合和结局使用相同的三类请求。密钥只在代理环境中；Godot 工程不保存供应商密钥。

无法连接、503、超时或数据格式错误都会显示原因并使用本地规则；AI 明确拒绝誓约时不改为本地接受。客户端再次校验保护类型、条件、城市 ID、重复影响和每指标 ±3 的整数范围，不能突破生效誓约。

**验证状态：**使用本地假代理测试了 HTTP 协议和回退；未使用真实模型供应商凭据联调，不代表真实模型效果已验证。

## 验证

在仓库根目录执行；需要 Node.js 24 和 Godot 4.7.2：

```sh
npm test
npm run check
npm run test:godot -- /absolute/path/to/godot
```

Windows 示例：

```powershell
npm run test:godot -- 'D:\godot\Godot_v4.7.2-stable_win64.exe'
```

脚本会生成被 Git 忽略的参考数据，执行参考网页引擎测试、无界面资源导入、规则对照、完整 UI 流程和本地假代理测试。第一阶段26组参考场景共1883次操作，包含支付失败、八类誓约、动态成本和AI支付后守护边界及任期复核。每轮对比城市、行动成本、事件、关系、历史与结局。UI测试覆盖六轮共誓路线、完整六十轮、资源不足和重复建设禁用。遇到 Godot 错误日志或非零退出码，测试失败。

用图形渲染器运行 UI 测试并生成初始、六轮、重叠、结局和紧凑布局截图（截图不提交）：

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64.exe' --path godot --script res://tests/test_ui.gd -- --screenshots=D:/godot/continental-drift-hypothesis/godot-preview
```

根目录现有 GitHub Actions 继续检查 JavaScript；Godot 测试目前通过上述命令在本地执行。

## 维护原版基线

`tools/web-baseline/` 保存已注明提交来源的网页引擎快照，用于对照和可选代理；根目录网页文件保留原样。`node tools/export-godot-data.mjs` 从此快照重新生成 `data/world.tres`。**它会覆盖手动调整后的资源**，仅在有意更新基线时运行，正常游戏和测试不会覆盖。
