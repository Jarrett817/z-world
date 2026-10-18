# 开发日志

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
