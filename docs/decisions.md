# 决策记录

## 2026-10-19 · 3D 驾驶层落地：Three.js 原生接管，移除 Phaser

**背景**：驾驶是核心体验，2D 贴片/视差滚动不达标（用户："纯贴图没意思，先要自己觉得好玩"）。架构方向已和用户确认。

**决策**：
- **渲染引擎**：Three.js 原生（非 react-three-fiber——高频游戏循环+三相机切换+性能敏感，声明式桥接反而别扭），移除 Phaser（其唯一职责 DriveScene 已被替代，双引擎=双渲染循环打架）
- **不用 Unity**：目标 H5→Capacitor APK，Unity WebGL 包体 20MB+ 加载慢、与 React+Vite+TS+JSON 数据驱动+localStorage 工程割裂，一人维护双体系成本不可接受
- **3D 化分级**：操控=3D（驾驶/车顶战斗/丧尸遭遇）、叙事=AI 插画（已定调）、经营=2.5D（车内俯视，8×3 网格玩法零重构平移）、人物保持 2.5D 立绘
- **房车模型**：Sketchfab GMC Motorhome（CC-BY）→ Blender 改装甲（防撞杠/侧裙/橙条/车顶架）+ 恢复原厂 PBR 涂装贴图 → 导出 GLB（10MB，JPEG 85 压缩内嵌纹理）→ `/assets/rv/gs_001.glb`
- **三视角相机**：1 追尾 / 2 舱内 / 3 车顶（车顶=射击位预留），车顶+舱内预留战斗扩展
- **桥接不变**：`Game.driveTick(deltaKm)` 里程/燃料/天气推进、`Game.zombieAttack()` 丧尸撞车扣资源，`useSyncExternalStore` 单向流照旧

**关键教训**：GMC 模型自带 4096 橙黄×黑美式涂装贴图（含 GMC 标/TEXACO 贴纸/做旧细节），此前"断开贴图刷纯色"是"全棕"根因。**换色优先改贴图或 PBR 参数，不要断贴图。**

**待办**：①速度 HUD 与顶部资源栏重叠需移位置；②丧尸撞击扣资源过频繁（体力被打到 0）需平衡（减速/击退优先，资源惩罚降低）；③丧尸 3D 低模换 Sketchfab 模型；④车内 2.5D 交互空间；⑤10MB GLB 后续可缩贴图到 2048 优化首载。

## 2026-10-19 · 美术风格基准定调（用户逐张确认）

**背景**：多套风格（写实 AI 场景 / Blender 白底 3D / 干净二次元）混搭导致贴图"丑"，用户要求先统一画风、再谈玩法。

**场景基准（已确认）**：手绘质感末世插画——低饱和灰青/深褐/土灰，暖橙仅用于光源（车灯/篝火），冷青阴影，纸面颗粒噪点+轻微笔触边缘，This War of Mine 写实 × 明日方舟冷峻。房车=温暖庇护所（暖光），丧尸=威胁（冷灰剪影），零水印、零白底。
- 样张：`cws_59028321059063042/deliverables` 场景定调样张

**人物基准（已确认）**：废土美拉德暖棕大地色系 + 二次元手游女性化精致（对标头部二游女角色精致度：柔和脸型、灵动神情、设计感穿搭细节）。全身立绘 3:4，身份锚点不丢（林晚：黑长发/听诊器/医生气质）。
- 样张：林晚全身立绘·二游版（画布同目录）

**落地原则**：全项目素材朝这两张样张收拢；**砍 Blender 白底 3D 预渲染线**（房车/中景产出最丑且背离"先好玩"）；事件场景图、丧尸、房车、立绘全部按基准重做并去水印/去白底。

## 2026-10-19 · 人物立绘升级：AI 精致二次元替代 3D 基础模型

**背景**：3D 预渲染的人物立绘（Anime Nurse / Stylized anime character）效果太素，不符合「二次元手游级精致」要求。

**结论**：改用 GenerateImage AI 直接生成精致二次元立绘，支持表情差分（正常/微笑/严肃），存 public/assets/*.jpg。3D 预渲染管线保留给房车/场景，人物立绘走 AI 2D 生成。

## 2026-10-19 · 丧尸攻击 + 天气系统落地

- **丧尸**：DriveScene 右侧随机生成 zombie_walk.jpg sprite，车速越快生成越密；碰到房车触发 Game.zombieAttack()（随机扣体力/食物/士气）+ 房车震动 tween 反馈
- **天气**：GameState 加 weather 字段（clear/rain/fog/snow），driveTick 每 0.5km 15% 概率随机切换；雨=斜线粒子，雪=飘落圆点，雾=半透明覆盖层；雨天刹车×0.7，雪天加速×0.6

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
