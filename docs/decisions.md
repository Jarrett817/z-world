# 决策记录

## 2026-10-19 · 3D 预渲染管线落地：房车/人物/场景全面 3D 化

**路线确定**：Sketchfab 免费 CC-BY 模型 → Blender 无头渲染（`blender -b --python`）→ PNG 序列帧/立绘 → Phaser 贴图。不走实时 3D。

- **房车**：GMC Motorhome（lionsharp）+ 程序化装甲（防撞杠/车顶架/探照灯/侧裙甲/备胎/排气管），橙黑配色，8 帧车轮转动序列帧接入 DriveScene 替换 2D 贴片
- **人物**：林晚=Anime Nurse 模型，陈默=Stylized anime character 模型，渲染正面半身像做头像
- **场景**：Destroyed Building shell 渲染黄昏废墟做驾驶中景
- **工作流**：Blender MCP socket 易被 factory reset 杀掉，改用 `blender -b --python` 无头模式更稳定；模型下载走 Sketchfab `/v3/models/{uid}/download`（S3 预签名 URL 不带 Authorization 头）

## 2026-10-19 · 驾驶表现层转向 3D：2D 车轮贴片方案否决

**背景**：房车实图（rv.png）接入后，用「从车身抠出 3 个轮子做独立 sprite、按车速旋转」的 2D 方案实现车轮转动。浏览器实测对位准确、零报错，但转动视觉效果用户判定不达标——2D 贴片旋转做不出真实的车轮滚动感。

**结论**：驾驶表现层转向 3D 方向，候选路线：
- Meshy 生成房车 3D 模型 → Blender 预渲染（序列帧 / 多角度），仍走 2D 管线出图
- 或驾驶场景引入实时 3D 层（Three.js），Phaser 仅负责 UI 层

具体方案待验证后定。**本条修订 2026-10-18 总决策中的「不做实时 3D」原则**——驾驶真实感是核心体验，值得为此破例。

## 2026-10-18 · 游戏创建：名字占位完成

- **游戏名**：末世：我要当救世主
- **TapTap appId**：982388
- **厂商**：肥脸嘟嘟工作室（developer_id: 497045），角色：developer
- **类型**：角色扮演 RPG
- **包体方向**：H5 直发 TapTap H5 专区 → Capacitor 套 APK（接 TradPlus）→ 微信小游戏后期适配
- **后台入口**：https://developer.taptap.cn/v3/497045/app/982388/store/update
- 创建后待办：完善资料素材 → 上传绑定包体 → 就绪后提审

## 2026-10-18 · 引擎切换：Cocos Creator → Phaser + React

**触发**：Cocos 编辑器私有序列化格式（.scene/.meta）与全代码 AI 协作工作流冲突——手写 .scene 触发 404，手写 .meta 触发 UUID 冲突，UI 拖拽强依赖编辑器。

**最终技术栈**：
- **Phaser**（游戏场景：地图渲染、节点交互、氛围表现）
- **React 19 + Tailwind v4**（DOM UI：HUD、弹窗、队伍面板——70% 交互时间花在 UI，DOM 开发效率碾压）
- **Vite + TypeScript**，JSON 数据驱动，localStorage 存档
- **桥接**：`useSyncExternalStore` 订阅外部 Game store，单向数据流
- **Capacitor**（后期打 APK、桥接 TradPlus 原生广告 SDK）

**排除过程**：LayaAir（强制 IDE）× Godot（编辑器中心）× PixiJS（仅渲染器无游戏循环）×

**注意**：Phaser 与 React StrictMode 双挂载冲突（重复创建/销毁 Game 实例），入口不用 StrictMode。

## 2026-10-18 · 平台 / 引擎 / 美术 / 变现总决策

| 维度 | 决策 |
|---|---|
| 平台 | TapTap 首发（H5 专区，2025.7 上线无版号可发）→ Capacitor 套 APK → 微信小游戏后续 |
| 引擎 | **Phaser + React + Tailwind + Vite**（全代码，零编辑器依赖；原 Cocos 方案已废弃） |
| 美术 | AI 2D 立绘（MJ/SD + LoRA 统一风格）；Meshy 3D → Blender 预渲染 2D 背景；DragonBones 骨骼动画 |
| 音乐 | Suno 生成 BGM + 音效素材库 |
| 变现 | 纯广告（TradPlus 激励视频），无内购（无版号约束） |
| 合规 | 申请软著（个人可办，45-60 天）；虚构地名规避国界审核；血腥克制（暗/绿血液，无断肢） |
| 玩法结构 | 《归家异途》章节制旅行 + 队伍管理；《明日方舟》美术公式 |
| 数据 | JSON/CSV 表格驱动；本地 JSON 存档；纯离线单机（规避 ICP + 防沉迷） |

### 关键设计原则
1. 不做实时 3D——一人开发扛不住全链路，烂 3D 不如好 2D
2. 角色立绘是核心卖点，必须精致（AI 2D + 表情差分）
3. 章节制发布——一章一国，一章一个版本
4. UI 即游戏——70% 时间在界面交互，UI 手感决定留存
5. 纯单机不联网，规避合规成本
