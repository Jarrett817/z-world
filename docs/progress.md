# 开发日志

## 2026-10-19 · 立绘升级 + 丧尸攻击 + 天气系统

### 本次完成

- **人物立绘**：GenerateImage 生成精致二次元立绘——林晚（正常/微笑）、陈默（正常/严肃），替换 survivors.json avatar 路径；RVPanel/EventDialog/TeamPanel 自动生效
- **丧尸攻击**：DriveScene 行驶时右侧随机生成丧尸（速度>5km/h 才刷，车速越快刷越密），丧尸向左移动，碰到房车触发 Game.zombieAttack() 随机扣资源 + 房车震动 tween 反馈
- **天气系统**：GameState 加 weather 字段，driveTick 每 0.5km 15% 概率切换；雨=80 条斜线粒子/雪=60 个飘落圆点/雾=半透明灰覆盖；雨天刹车×0.7、雪天加速×0.6；右上角显示天气标签
- 旧存档兼容：constructor 读取后补 weather 字段默认值

### 素材清单

| 文件 | 用途 | 来源 |
|---|---|---|
| public/assets/linwan_normal.jpg | 林晚·正常 | GenerateImage |
| public/assets/linwan_smile.jpg | 林晚·微笑 | GenerateImage |
| public/assets/chenmo_normal.jpg | 陈默·正常 | GenerateImage |
| public/assets/chenmo_serious.jpg | 陈默·严肃 | GenerateImage |
| public/assets/zombie_walk.jpg | 丧尸 sprite | GenerateImage |
| public/assets/rv3d/rv_01-08.png | 房车 8 帧行驶动画 | Blender 预渲染 |
| public/assets/rv_interior.jpg | 房车内部背景 | GenerateImage |
| public/assets/parallax_*.jpg | 驾驶场景视差背景 | GenerateImage |
| public/assets/*.jpg (start/gas/market/camp/bridge/ending/stall) | 事件场景图 | GenerateImage |

### API Keys

- Sketchfab: `261c712c3091437eb81e760c7ee93f71`（模型搜索/下载）
- Poly Pizza: `06fc0b9edad94e3e9216a6ff11185da5`（低多边形模型）

### 待办

- 大地图自由探索（当前 6 节点线性章节，需重构为开放地图）
- 房车内部 3D 视角（当前静态图+头像叠加）
- 水陆两栖（需要新场景+物理+美术）
- 更多幸存者/事件/章节内容
- TapTap 预约素材（图标/宣传图/截图）
- 软著申请

---

## 2026-10-19 · 车内 NPC 忙碌场景 + 车轮 3D 化转向

### 本次完成

- **车内 NPC 忙碌场景**：RVPanel 以 rv_interior.jpg 为底，已招募幸存者按工位显示立牌（立绘 object-top 裁切 + 名字·活计标签），motion 呼吸浮动动画错开相位；陈默→车门侧「检查车况」、林晚→厨房区「整理药品」（CREW_SPOTS 表驱动）；人物层 pointer-events-none 不挡网格交互，设施标签升 z-20
- **车轮转动实验（效果不达标，方向已改 3D，见 decisions）**：PowerShell 从 rv.png 圆形抠出 3 轮（圆心实测 383,872 / 685,886 / 1376,864，半径≈143，遮罩+羽化）→ wheel1-3.png；DriveScene 独立 sprite 按 pxSpeed/轮半径 累加 rotation
- 新依赖：motion（React 动画库）
- 验证：typecheck 通过；浏览器实测——轮子对位准确无穿帮、车内 NPC 正常显示、控制台零报错

### 待办

- 房车 3D 化方案验证（Meshy 预渲染 vs Three.js 实时层）
- 地图场景化底图接入、角色表情差分、TapTap 预约、软著申请（照旧）

---

## 2026-10-18 · 驾驶化重构：横版卷轴替代点选地图

用户反馈：点选节点=文字游戏，要「车辆驾驶的真实感、行路感」。

- **DriveScene**（删 MapScene）：三层视差——AI 远景城市剪影（0.15x）/中景路边废墟（0.5x）/路面虚线（1x）；房车剪影（橙色暖窗+车灯光柱+车轮转动+悬挂正弦起伏）
- **操控**：屏幕油门/刹车踏板 + 键盘 D/A/方向键；速度物理 0~80km/h，accel 40 / brake 90 / drag 8
- **Game 状态机**：phase（profession/event/route/driving/finished）；edges 改 `{from,to,km}` 数据驱动；燃料按公里烧（fuelPerKm 0.2）；**半路油尽触发 ev_stall 事件**（徒步找油 stamina-3 fuel+2），选完继续赶路（travel 进度保留）
- **RouteChoice**：岔路口路线卡（名称+公里数）替代点地图
- 存档升 v3；fuel 改浮点（HUD floor 显示）；driveTick 对 React 按 0.1km 节流 emit
- 验证：bun 冒烟全流程 PASS（职业→序章→选路→驾驶→抵达→招募→终章；燃料/里程数学核对）；浏览器实测五层视觉渲染正常、零报错
- 素材：parallax_far/parallax_mid（3750x1250 平铺剪影，已裁右下角水印至 3380x1140）、stall.jpg（抛锚事件图）

## 2026-10-18 · 视觉层接入：AI 场景图 + 立绘

- 生成 8 张 AI 绘画素材（橙青末日色调、This War of Mine 风）：6 场景图（start/gas/market/camp/bridge/ending，landscape_16_9）+ 2 立绘（林晚/陈默，portrait_4_3），存 public/assets/*.jpg
- EventDialog 改版：顶部场景大图 + 渐变遮罩 + 右下角悬浮立绘（有 character 时）；章节结算页配图
- TeamPanel 改横排卡片，左侧 avatar 头像
- 数据层：GameEvent 加 image/character 字段，Survivor 加 avatar 字段，EventEffects 加 fuel
- 教训：`trae-api-cn.mchost.guru/api/ide/v1/text_to_image` 是异步占位图语义（返回 176626 字节占位，不可用）；改用 GenerateImage 工具直接出图（自动存 .jpg）
- 验证：typecheck 通过；浏览器实测零红色报错、图片 200、场景大图渲染正常

## 2026-10-18 · 房车化重构：职业 + 燃料 + 车厢布局

### 设计定稿（用户拍板）

- **世界观**：全球灾变，各国蔓延速度不一；主角是普通上班族（职业可选）
- **故事三幕**：求生（活下去）→ 发现（寻找尸变解法）→ 解法（灭活病毒免疫：让病毒认为宿主不健康）
- **核心载体**：先进房车——移动时耗燃料，驻扎时是庇护所，可入水变船；房车形态随剧情升级（代步→庇护所→移动实验室）
- **决策**：职业系统轻量做（初始属性+专属事件）；房车经营走空间布局向（车厢俯视网格放置设施）；现有原型立刻按房车设定重构

### 本次实现

- 职业选择开局：程序员/厨师/销售/健身教练（避开林晚医生、陈默司机防重复），数据驱动 professions.json
- 燃料资源：移动耗燃料 1，加油站事件重做为抽油补给（地点语义=资源产出），上限 12 clamp
- 序章事件 ev_start：楼下找到房车（文案：车窗全家福被雨泡花一角）
- 房车布局系统：rv.json 定义 8×3 网格 + 4 设施（床铺=体力上限+2 / 储物架=食物上限+5 / 医疗角=移动体力+1 / 工作台=改装占位），点选放置、点击拆除、重叠检测
- 存档 key 升 v2；资源上限 = 基础值 + 设施加成动态计算

### 验证

- typecheck 通过；浏览器实测：职业→序章→资源栏数值正确、零红色报错
- bun 冒烟：布局放置/拆除/重叠检测/上限加成/燃料消耗与 clamp 全过

### 下一步

- Blender 预渲染场景图试点（加油站），接入地图背景
- 布局交互升级拖放（后续）；设施效果随章节扩充
- AI 立绘、软著申请照旧

---

## 2026-10-18 · 引擎迁移：Cocos → Phaser，原型重新跑通

### 背景

Cocos 原型卡在「点击无响应」的编辑器层问题，且手写 .scene/.meta 反复踩私有序列化格式的坑。用户明确拒绝编辑器拖拽工作流 → 整体迁移到全代码技术栈。

### 本次完成

- 清理全部 Cocos 工程文件（assets/library/temp/settings 等），保留 docs 和 git
- 新工程：Vite + React 19 + Tailwind v4 + TypeScript + Phaser
- 核心逻辑零改动移植：Game 状态机（subscribe/emit + 不可变 state）、DataLoader（直接 import JSON）、SaveManager（window.localStorage）
- MapScene：graphics 画连线、circle+text 画节点、zone.setInteractive 接 pointerdown（替代 Cocos 触摸层体系，点击天然可靠）
- React UI 三件套：HudBar / EventDialog / TeamPanel（末日暖调：#e8862e 篝火橙 + #2a2320 面板）
- 数据原样迁移：chapter1.json（6 节点 4 事件）+ survivors.json（林晚/陈默）

### 验证结果（浏览器实测）

- ✅ 页面渲染正常，控制台零红色错误
- ✅ 点击节点 → 事件弹窗 → 选项生效（食物 10→16、体力 10→7，移动-1+选项-2 符合设计）
- ✅ 修复：React StrictMode 双挂载导致 Phaser 报错 → 入口去掉 StrictMode + redraw 加守卫

### 架构

```
src/
├── main.tsx / App.tsx        # 入口（无 StrictMode）+ Phaser 容器与 UI 覆盖层
├── index.css                 # Tailwind v4 + 全局深色
├── game/
│   ├── PhaserGame.ts         # Phaser.Game 配置（1280x720 FIT）
│   ├── scenes/MapScene.ts    # 地图渲染 + 点击 → Game.moveTo
│   └── core/                 # 引擎无关，可整体复用
│       ├── Game.ts           # 状态机（useSyncExternalStore 桥）
│       ├── DataLoader.ts     # import JSON
│       └── SaveManager.ts    # localStorage
├── ui/                       # HudBar / EventDialog / TeamPanel（React + Tailwind）
└── data/                     # chapter1.json + survivors.json
```

### 下一步

- AI 立绘风格定稿（MJ/SD 试验图）→ 图标/宣传图 → 开 TapTap 预约
- 软著申请启动（45-60 天周期）
- 远期：Capacitor 打 APK + TradPlus 桥接；微信小游戏适配

---

## 2026-10-18 · 最小可玩原型骨架完成（Cocos 版，已废弃）

### 本次完成

- **TapTap 游戏草稿创建**：「末世：我要当救世主」appId 982388，RPG / APK
- **推进方向**：开预约（素材暂缓，待原型出来后再补图标/宣传图/截图）
- **最小原型代码骨架**（纯代码驱动 UI，零美术资源依赖）：

```
assets/
├── scene/main.scene            # 手写场景（Canvas + Camera + Main 入口）
├── scripts/
│   ├── Main.ts                 # 入口：加载数据 → 初始化状态 → 组装 UI
│   ├── core/
│   │   ├── Game.ts             # 游戏状态机（移动/事件/招募/存档）
│   │   ├── DataLoader.ts       # JSON 数据加载（章节/幸存者）
│   │   └── SaveManager.ts      # localStorage 存档
│   └── ui/
│       ├── UIHelper.ts         # 主题色 + 代码创建 UI 工具函数
│       ├── MapView.ts          # 地图：节点/连线绘制 + 点击移动
│       ├── EventDialog.ts      # 事件弹窗：标题/正文/选项
│       ├── TeamPanel.ts        # 队伍面板：幸存者卡片列表
│       └── HudBar.ts           # 顶部 HUD：章节名/资源/队伍按钮
└── resources/data/
    ├── chapter1.json           # 第一章：6 节点 4 事件（加油站/超市/营地/大桥）
    └── survivors.json          # 2 名幸存者：林晚（医生）、陈默（司机）
```

### 核心玩法闭环（已实现）

地图节点移动（体力消耗）→ 触发事件弹窗 → 选项影响资源/招募幸存者 → 队伍面板查看同伴 → 自动存档 → 抵达终点显示章节完成

### 验证方式

1. 用 Cocos Dashboard 打开 `D:\Projects\z-world`
2. 编辑器首次打开会自动生成缺失的 .meta 文件（属正常）
3. 双击打开 `assets/scene/main.scene`
4. 点编辑器顶部「预览」按钮（浏览器打开）
5. 预期：看到深色地图 + 6 个节点，点击相邻节点移动，事件弹窗正常

### 已知待验证项

- 手写 main.scene 在编辑器中的兼容性（如报错需手工建场景：Canvas 1280x720 + Camera + 空节点挂 Main 脚本）
- Label 字体显示（系统默认字体）

### 下一步

- 原型验证通过 → AI 立绘风格定稿（MJ/SD 试验图）→ 生成图标/宣传图 → 开预约
- 原型验证失败 → 按报错修正
- 并行：软著申请启动
