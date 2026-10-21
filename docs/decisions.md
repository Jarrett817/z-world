# 决策记录

## 2026-10-21 · 拾取物改自研低模（而非继续找 Sketchfab）

- **背景**：发光方块辨识度低；外部小道具模型授权/风格/轴向不可控，集成成本高于自建
- **决策**：关键小型可拾取物（油桶/食物箱/修理箱）由 Blender bpy 程序化建模，单模型 100–170KB、10–11 个部件、Principled PBR；Godot 侧 pickup.gd 只按 kind preload + AABB 统一缩放到 0.95m，模型自管原点（脚底中心）
- **踩坑沉淀**：①bpy `primitive_cube_add(size=1)` 后 scale 即全尺寸（不是半尺寸）；②必须先 apply scale 再设 rotation，事后对已旋转物体非均匀缩放+apply 会出错；③圆柱默认轴沿 Z，"横躺"须在创建时传 rotation 且 scale/rotation 一次性 apply（先 apply scale 再 apply rotation 会把旋转带进网格导致轴向混乱，实测用 transform_apply(rotation=True, scale=True) 一次完成）；④Blender X/Y/Z → Godot X/Z/Y（Y-up 导出），部件布局按 Blender 轴思考
- **立绘裁切**：UI 框比例必须严格等于图源比例（1728:2304=3:4），STRETCH_KEEP_ASPECT_COVERED 才零裁切；方形框装全身图必裁头

## 2026-10-20 · 天气 / 夜间 / 人物资产决策（Godot 版）

- **天气三态影响玩法**：晴/雨/雾每 50–90 秒切换；雨降低抓地力（加速 ×0.78、刹车 ×0.85），雾大幅降低能见度（fog_density 0.013）——天气不只是滤镜
- **夜间不做纯黑**：夜晚切换为月光色环境光（AMBIENT_SOURCE_COLOR，冷蓝），车头 SpotLight 自动开启，保证剪影可辨、路面可读
- **人物资产结论**：Sketchfab companions 三模型依赖 `EXT_meshopt_compression` + `KHR_mesh_quantization` + specGloss，Godot 原生不支持；gltf-transform 解压/反量化/材质转换后，实际内容为瓷娃娃摆件与比基尼人物，不符合末世设定 → 删除，幸存者先用程序化人形，3D 角色资产留待专项
- **地形重建条件**：地形覆盖 `[terrain_front-SPAN, terrain_front]`，只在可视前沿（rvz-VIEW_AHEAD）逼近覆盖末端时才重建，杜绝每帧重建

## 2026-10-19 · 驾驶手感打磨：加速推背动画 + 舱内画中画（用户需求）

**需求**：①启动/突然加速要有明显前倾动画，模拟"坐车被带一下"的相机没跟上感；②人物模型要精致、符合 TapTap 社区审美（3D 候选待选）；③舱内视角时画面顶部同时显示车辆内部视角。

**实现（Drive3D.ts）**：
- **推背模型 boost**：加速度 `accelNow = Δspeed/dt`，`accelNow>12` 时 boost 以 `dt*4.5` 快升（上限 1.0），`accelNow<-30` 急刹反向降到 -0.9，否则 `exp(-dt*1.1)` 慢落恢复——猛加速瞬间相机后移（z+boost*2.2）+下压（y-boost*0.55）+车体前倾（rotation.x -boost*0.05）+lookAt 下压看近（前方 -boost*12），约 1s 追回；急刹反向"前顶"
- **车内画中画**：`camInterior`(60°, pos(0,2.4,-2.0) lookAt(0,2.3,6))，仅 `camMode==='cockpit'` 时 `setViewport+Scissor` 在左上角（left:14 top:78，min(230,w*0.3)×0.7）渲染第二视角，橙色边框 DOM 同步显隐
- **验证**：浏览器实测——舱内左上角出现车内小窗、切回追尾消失；启动瞬间 boost 触发（车尾丧尸可见、路障卡车模型正常渲染）；tsc 零错误

**待办**：前倾幅度按用户实测微调；3D 人物模型待用户从候选清单拍板（用途=车内/车顶可见角色？）；夜间丧尸/路障辨识度。

## 2026-10-19 · 玩法定调：线性直行生存驾驶（用户确认）

**背景**：用户明确不做复杂大地图——"一路直行杀僵尸，路上偶遇幸存者、收集物资"，并要求"先要自己觉得好玩"。

**玩法结构（三块闭环）**：
1. **驾驶核心**：追尾直视角（宏观选路承担拐弯），手动 D/A 油门刹车 + Q/E 横向躲避；招募到会开车的幸存者后自动巡航，玩家切车顶射击位，可随时接管
2. **遭遇层**：丧尸（撞击/射击）、路障（软=可撞飞、硬=必须绕或硬撞）、幸存者（路边招募上车）、物资（**停车才能收集**）
3. **环境层**：昼夜循环（光照/路灯/丧尸夜间活跃）、天气（雨雪雾已有）、路边景色 3D 模型铺景

**硬约束（用户点名）**：
- 中间穿插突发事件与剧情，不是单调杀丧尸
- **持续撞丧尸扣车辆耐久度**，需要维修（车内经营/营地）
- **房车内部经营是重点玩法**（2.5D 俯视），不能只是开车杀怪
- **丧尸随存活时间变强**（难度曲线）
- **车毁（耐久归零）即死亡重开**（roguelike）

## 2026-10-19 · 步骤1落地：3D 丧尸/路障模型 + 撞击耐久玩法

**模型**（Sketchfab 免费，已筛非商用授权）：丧尸动画包 Polyart Zombies（Free Standard，带 walk 动画）、路障/锥桶套装、军用路障、废弃卡车、废弃轿车（CC-BY，需署名）。

**压缩管线**：Blender 5.2 无头 `-b --python` 导入 glTF → baseColor 降 1024 / metallicRoughness 512 / normal 512 → JPEG85 导出 GLB → `public/assets/props/`（zmb 3.4MB + barriers 3.7MB + barricade 1.9MB + wtruck 0.9MB + wcar 0.6MB，原包 400MB）。

**Drive3D**：
- 丧尸 GLB 实例 + AnimationMixer 走/跑动画，材质微绿自发光（暗夜辨识度）、scale 1.05-1.35；丧尸 x 朝车靠近、横向接近判定碰撞
- 路障软/硬两类程序化生成：软（锥桶/矮栏）撞飞动画+轻扣耐久 2；硬（军用路障/废弃车）强制减速至 20%+重扣耐久 12
- Q/E 横向躲避（±4.5），相机跟随偏移；撞击震屏反馈；耐久越低极速越低（×0.5~1.0）

**Game**：GameState 加 `durability`（0-100，旧档兼容）；`zombieAttack`→`zombieHit()`（扣耐久 3 + 20% 拍窗扣体力 1）；`damageVehicle/repairVehicle` API；Phase 加 `dead`，`DeathScreen` 全屏重开。

**验证**：tsc 零错误；浏览器实测行驶 10s：耐久 100→44（硬路障 12×4 等）、拍窗体力 8→4、速度被硬路障压到 50→重新加速、HUD 显示"80 km/h · 车况44%"。

**待办**：丧尸/路障夜间辨识度（灯光后置）、碰撞血花/碎片粒子、停车收集交互、车内 2.5D 经营、幸存者招募+代驾、昼夜循环、丧尸随时间变强曲线、模型署名 credits 页。

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

### 2026-10-20 手机实测修复（z-world 3D 驾驶版）
- 丧尸躺着根因：zmb.glb 是爬行丧尸（bbox 高 0.5）+ 单动画 Take 001。替换为 Low Poly Zombie（Idle/Walk/Attack/Death 四动画，Sketchfab free-st 可商用），gltf-transform 压缩 737KB。
- 丧尸行为：主动走向车 + 贴近后"挂车边啃咬"（z=-9 固定、每 0.8s 扣 1 耐久、攻击动画 LoopOnce），被玩家碾压撞飞（cannon 物理保留）。
- 生成深度随机化（-260~-120）：丧尸/路障/路边遭遇错落分布，消除"所有东西跟着车"的排队感。
- 移动端：竖屏 OrientationHint（md 以下显示）；HudBar 窄屏压缩（label 隐藏/间距收紧）；html/body/#root 100dvh 跟随地址栏收展。
- 引擎选型结论：维持 Three.js 原生 + cannon-es。Babylon.js 换库=Drive3D 全套重写收益≈0；PixiJS 是 2D 渲染不解决 3D；不引入 Unity WebGL（非 JS 工作流）。
- GitHub CLI 已装（用户目录，PATH 已加），auth 待用户 gh auth login（需 GitHub 授权）；push 已恢复直连成功。

## 2026-10-20 · 引擎迁移：Three.js → Godot 4.7（实时 3D 定稿）

**触发**：Three.js 驾驶版画面被用户判定「贴图游戏，太 low」——要求实时 3D 的大地图驾驶体验（光照、阴影、昼夜、动态模型），Web 手搓渲染管线性价比过低。

**最终技术栈**：
- **Godot 4.7.2**（GL Compatibility 渲染器，保证老机器/后期移动端可跑）
- **全代码构建场景**：main.tscn 只挂一个根节点 + main.gd，其余全部 GDScript 运行时创建——延续「零编辑器依赖」铁律
- 无头验证：`Godot.exe --headless --path godot --quit-after N` 抓脚本错误，不开编辑器即可回归
- Godot MCP（`@coding-solo/godot-mcp`，bunx 运行）已配置进 Trae mcp.json，重启 Trae 生效
- 原 src/（Phaser+React+Three.js）整体封存，不再维护

**Godot 版核心架构**（godot/ 目录）：
- main.gd：编排器——状态机（耐久/燃料/食物/队伍/里程/昼夜）、追尾相机（指数平滑+trauma 震屏+速度 FOV）、frontier 前沿生成（障碍/物资/幸存者按间隔刷在车前方 260m）、丧尸生成上限 22、无限地形重建触发
- terrain.gd：`rebuild(start_z)` 程序化 ArrayMesh 条带（柏油+路肩+边线+中央虚线 6 surface），车开过 340m 即向前重建，实现无限公路
- rv.gd：CharacterBody3D，WASD/方向键+HUD 触摸按钮双输入，`touch_*` 字段桥接移动端；slide 碰撞分发（丧尸→物理冲量+碾压判定，障碍→软/硬伤害回调）
- zombie.gd：RigidBody3D，追车 AI（RV 相对坐标）、贴身啃咬（每 0.8s 扣耐久，随里程增强）、高速碾压播放 Death 动画、撞飞后物理接管 1.3s
- hud.gd：SystemFont 挂微软雅黑解决 Godot 默认字体无 CJK 问题

**模型规格备忘**（inspect.gd 实测后已删除）：gs_001.glb 房车朝 -Z、轮底 y≈-1.557（RV_MODEL_FOOT=1.557）；zmb_stand.glb 缩放 0.065、动画 [Attack, Death, Idle, Walk]；wtruck 缩放 0.28；barricade 缩放 0.55。

**玩法定调**（已确认）：线性直行生存驾驶、追尾视角、撞丧尸/障碍扣车况、房车内部经营、丧尸随时间变强、车毁即死重开（roguelike）、昼夜循环。

## 2026-10-21 · 人类角色方案定稿：VRM 女性基底，否决共享骨架换装

**决策**：用户提供 3 个 VRM 并拍板「角色3 当主角，不要男性角色，以女性为主角」。废弃原 art-pipeline §4 的「一套人形骨架 + 模块化换装件」方案，改为直接采用成品 VRM 外观。

**理由**：
- 免费人形模型质量/授权双不可控；手工绑骨架做换装件的成本远高于给成品 VRM 程序化烘焙两套简单动画
- VRM 生态自带标准 Humanoid 骨名（J_Bip_*）与材质槽，vrm_addon 导入即可用；3 个基底轮换已能支撑 5 名队友的辨识度需求
- 主角 hero 独占一套（紫短发战术外套），队友 role1/role2 按 CREW_ORDER 奇偶机械轮换——刻意保持极简，不做运行时换装

**动画范围控制**：当前只烘焙 idle（32 帧呼吸循环）与 sit（两帧同姿态静态坐姿）。废弃原计划的 Walk/Wave/Drive——路边幸存者用 idle + 橙色光柱表意即可，车内全员坐姿/站位静止；不为用不到的动作投入烘焙成本。

**待决**：陈默（chen_mo，唯一男性、driver:true、油耗-25%）需改为女性角色，driver 被动须有人承接；role2 猫耳兽尾奇幻洋装与写实末世基调违和，3 基底对 5 人的分配待数据去男性化时一并调整。

