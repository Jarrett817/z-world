# 开发日志

## 2026-10-30 · n98 KayKit shoot/reload 重定向 + 枪手实弹换弹链路验证

- **现成动作包补战斗动作（用户要求禁手捏）**：role1/role2 各加 KayKit Adventures（CC0）的 `2H_Ranged_Shoot`（32 帧/1.07s 单发）与 `2H_Ranged_Reload`（48 帧/1.6s 换弹），沿用 n97 两阶段跨骨架重定向（非 hips 骨只转旋转 + 逐骨 rest 段 qcorr），四肢段世界方向误差 0.0°；两 GLB 各 12 个 action
- CharLively.play_combat 接 shoot/reload/aim：shoot 一次性、animation_finished 自动回 aim；reload 一次性停末帧等逻辑切回；shoot/reload 显式压 LOOP_NONE（不依赖 GLB 导入默认循环识别）；reload 播放中或 shoot 未播完时拒绝重入
- main 自动枪手接线：弹匣 30 发（guns.json npc_gunner.mag_size），cd 到点打空判断——0 发进 reload_until=now+1.7s 播 reload、名牌显「换弹中」、期间停火，到点补满回 aim；有弹才播 shoot 发弹（600m/s 射线弹）+ 枪口焰 + 枪声
- **新增 `--gunnertest` 无头实弹断言**：驻车两侧射界每秒补怪保持每侧 2 只，跟踪每名在岗射手 fired/reloaded/refired，全部「换弹后复火≥3」则 PASS quit(0)，180s 超时 FAIL。修两个验证自身的问题：① 开局 2.5s intro 序章把 story_active 置 true，枪手主循环早退冻结 fire_cd（测试同 --nostory 禁用剧情系统）；② 空槽尾哨（5 人只占前 5 槽）也计入断言导致 all_pass 永假，过滤无 Char/muzzle 的空槽
- 结果：4 名车顶哨 fired≈32/reloaded=1/refired=3，PASS t≈45s；标准无头回归 EXIT=0 零非基线错误

## 2026-10-30 · n97 KayKit 现成动作重定向修枪手坏 aim + 房车扩员到 20 人

- **现成动作包替换手捏占位（用户明确要求）**：role1/role2 的 aim 原是 0.033s 坏占位（截帧里队员 T-pose 伸臂诡异）。改用 KayKit Character Pack Adventures（CC0，76 动画）的 `2H_Ranged_Aiming`（48 帧双手据步枪循环），Blender 5.2 后台两阶段重定向到 VRM J_Bip 骨架，逐帧四肢段世界方向误差 0.025°（验收线 <5°），双手屈指握枪；保留各 GLB 其余 action 与网格材质
- 重定向踩坑与定版写法沉淀到 art-pipeline 第 26 条：非 hips 骨禁止插 location 键（钉死头位导致四肢恒为 T-pose，首轮误差 138°）；逐骨 rest 段对齐修正（Q 版↔写实骨轴向差异，脚段 16°→0°）；两阶段采样（单会话二次 glTF 导入失败）
- **房车扩员到 20 人（用户：「跟大巴车似的，载 20 个没问题」）**：CREW_MAX 10→20，stations 补到 20 槽（10 持枪战斗位 + 10 舱内生活位）；try_recruit 满员拦截
- **4 个射击点 + 闲着都开枪**：副驾瞭望 + 车顶 5 哨 + 4 窗射孔（两前侧窗/右后窗/尾门，深色开孔板+枪灰钢框，metal 0.25 守第 17 条）；命名角色收齐后泛型幸存者 genN（survivors.json _generic 池，role1/role2 奇偶轮换）
- **舱内自行走动**：生活位队员 6–11s 随机起身边走边播 walk，到过道点 idle 停 2.5–5s 再回岗；战斗/驻车/剧情/漫游接管立即杀 tween 回岗
- **遇袭满舱开火**：固定 gun/port 槽永久持枪索敌（弹匣打空停火换弹），生活位遇袭 `_set_life_combat` 全员领枪、14m 全向开火，战后收枪回坐姿/站活
- 右墙补贴墙长凳两坐姿位、储物箱挪右后角避开尾射孔火线；AK GLB 0.066 缩放绕 Y180° 对齐枪手 +Z 瞄准向
- Godot --headless --import 重导入 + 8 人/150 帧无头回归 EXIT=0 零 SCRIPT/动画错误（窗口截帧本会话环境卡死，姿势以 Blender Workbench 三机位目检 + 数值验收为准）

## 2026-10-30 · n96 树木/植被随风摆动（原神化批次 6）

- 树与植被接入「TIME + 世界坐标相位」阵风（沿用 n92 草叶同款双频正弦阵风沿世界 xz 传播机制）：顶点色 r 通道编码逐顶点风摆权重（根/干=0 不动、枝梢/叶球=1 满摆），顶点阶段按权重位移
- 两个共享 spatial shader：贴图版（GLB PSX 枯树包，沿用原树皮 baseColor 贴图）+ 纯色版（程序化植被，tint/amp uniform），均 toon 明暗、cull_disabled
- GLB 枯树：`_apply_glb_tree_wind()` 实例化后逐片网格按各自树高（换算到树根空间）烘焙风摆顶点色并换 ShaderMaterial，只改本实例、不动共享导入资源；程序化阔叶树叶球（full 权重整体摇，amp 0.7）、松树三层松塔（amp 0.5）、灌木球（轻微 amp 0.18）改走 `_wind_weighted()` 烤色 + 纯色风材质；树干/电线杆保持静止
- forest/city 交界窗口截帧目检阔叶/松塔/枯枝树几何无错位、贴图保留，无头回归 EXIT=0 零 SHADER/SCRIPT ERROR

## 2026-10-30 · n95 lake/coast 景物水面避让（修穿帮）

- n94 波光暴露出湖/海段景物泡在水里：新增 `_in_water(wx,z)`，与 terrain.gd `_water` 同一确定性碟形包络公式（coast 仅右侧 center90/half 80·zw、lake 两侧 center95/half 55·zw、段内 sin 包络，岸边留 2m 干地，INF/NaN 早退）
- 树：`_spawn_scenery` 落点叠加 `_in_water` 跳过（coast 原本已强制左岸）
- 网格土路支路：抽 `_branch_end(n)` 求支路末端点，末端落水则整格取消——`junctions_in`（地形条带源头）、`loop_road_distance`（防撞距离）、`junction_gap`（护栏缺口/loop 回接口）、`_spawn_detour`（尽头 POI 与预告牌）共用同一判定，四处一致；cross 沥青十字路口不做避水
- 剧情点 town/gas 支路：抽 `_place_branch_end(pj)`，`junctions_in`/`junction_gap` 避水；`_spawn_place` 对湿支路整条早退（建筑/物资/丧尸/到达牌都不生成）；`_place_scenery` 再拒收水中 BUILDING_SCENE 兜底
- lake 10.5km / coast 15.6km 窗口截帧目检：水中棕楼消失、海面无树杆楼，岸线干净；无头回归 EXIT=0 零 SCRIPT/SHADER ERROR（注意 GDScript 内建是 `is_inf()` 不是 `isinf()`）

## 2026-10-30 · n94 湖面/海面卡通波光（原神化批次 5）

- 水面材质从平涂 StandardMaterial3D 换成片元 shader：双频正弦在世界 xz 面叠加出漂移亮纹，`smoothstep` 陡切出卡通式白色波光；近岸浅青 `(0.26,0.55,0.62)` 与远水深蓝 `(0.09,0.27,0.38)` 按水深混合，保留低粗糙/弱金属反光
- 水深由水面网格顶点色 r 通道编码（碟心 `sag/1.5` 归一、岸边 0），片元经 varying 取世界坐标（dummy 渲染器不支持 `WORLD_POSITION` 内建，vertex 用 MODEL_MATRIX 计算）
- 不扰动水面顶点，碟形岸沿仍与地面齐平不离缝；地形材质数组类型放宽为 `Array[Material]` 以容纳 ShaderMaterial
- 湖面（lake 段）/海面（coast 段）窗口截帧目检波光与深浅渐变达标，无头回归 EXIT=0 零 SHADER/SCRIPT ERROR；已知：海岸浅水里偶有既有的杆/树穿帮，属景物避让的遗留问题，非本次材质引入

## 2026-10-30 · n93 晴天空气漂浮光点（原神化批次 4）

- 复用雨/雪「跟随 RV 的盒形 CPUParticles3D」模式新增 motes：晴天在草尖高度（盒中心 +2.5m、半高 4m）漂浮的暖色微尘，近零重力缓升、180° 散射、billboard 朝向相机，80 颗稀疏点缀空气感
- 光点贴图程序化生成 32×32 径向柔光（中心实、二次方衰减到全透），远看是圆点而非硬方块，零外部贴图
- 仅 clear 天气发射，雨雪雾在 `_apply_weather()` 自动隐藏；明亮晴天窗口截帧目检柔和不抢镜，无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n92 草叶随风摆动（原神化批次 3）

- 草材质从 StandardMaterial3D 换成自定义 spatial shader：顶点阶段按世界坐标 + `INSTANCE_ID` 生成相位，双频正弦阵风沿 xz 传播，叶尖 `h*h` 大摆、根部不动，实例相位打散避免齐摆；fragment 沿用 toon 明暗，`COLOR` 取引擎已相乘的网格顶点色×MultiMesh 实例色
- 与云穹共用「TIME 驱动 + 世界坐标相位」同款风机制；dummy 渲染器不支持 `INSTANCE_CUSTOM`，实例色改走 use_colors 注入的 COLOR（真实渲染器两路径同色）
- 平原窗口截帧目检草色/几何正常，无头回归 EXIT=0 零 SHADER/SCRIPT ERROR

## 2026-10-30 · n91 路边草丛 MultiMesh（原神化批次 2）

- 近景丰茂感：新建全场景共享的单片草网格（三片放射交叉的窄长叶，根部暗/尖部亮顶点色、叶尖留窄宽并各向微倾，双面渲染），沿路每 50m 生成一条 `MultiMeshInstance3D`（`TRANSFORM_3D` + 实例色），离路 9.5~34m 两列条带、随机旋转/宽高/色相乘，单 draw call 覆盖数千米草坡；关闭实例投影省填充
- 数据化生态：密度与草色按景观段区分（forest 最密深绿、plain 黄绿鲜亮、hills 偏深、coast/city 稀疏），海岸段右侧整片海域与支路路廊（`loop_road_distance<10`）自动避让
- 流式确定性：草带前沿对齐 GRASS_LEN 绝对网格，跳转/重建在同一世界坐标长出同样草丛；实例挂 `consumable` 组随现有车后回收机制统一 free，不新增生命周期系统
- 出生区原 70 丛独立 Node3D 双 Quad 草删除（野花保留），改由 MultiMesh 统一覆盖；平原/丘陵窗口截帧目检近景竖立草叶成片、zone 色差清晰，无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n90 天空积云与大气透视地形（原神化批次 1）

- 天空新增跟随相机的云穹（radius 760）：spatial shader 内 3D FBM，以 `normalize(VERTEX)` 方向采样避开球面 UV 拉伸；低频大团定云形 + 高频细节撕棉絮边缘，陡阈值切成实芯团块与蓝天缝隙（coverage 平移阈值），仰角遮罩让地平减淡、高空略收，TIME 风吹漂移；云色/不透明度/覆盖随昼夜与天气联动（深夜暗蓝稀薄、晨昏暖粉、正午亮白，雨雪雾压成厚云），纯代码零运行时贴图
- 远山改大气透视配色：近山蓝绿灰 `Color(0.42,0.58,0.58)`、远山淡青蓝 `Color(0.6,0.72,0.83)`（双面），告别绿色塑料薄片
- 地表顶点色 `_mottle` 按景观段分区染色（plain/forest/hills/mountain/lake/coast/city 各自草色），叠大尺度低频坡面光影（big×0.14）与中频斑块（mid×0.045）打破平涂，并按离路距离做近鲜远淡的地面大气透视（60~240m lerp 0.4）
- 白天平原/丘陵/黄昏三机位窗口截帧经多轮迭代（贴图云球 UV 拉伸白雾带→3D FBM→团块阈值）目检达标，标准无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n89 队友羁绊系统

- main.gd 新增 `bonds: Dictionary`（队友 id → 0..100，每 15 一颗心、3 心满）与 `add_bond()/bond_hearts()`；add_bond 跨心阈值时 toast「与 X 的羁绊加深 · ★★☆」；bonds 入 save.json（旧档无键默认 {}，不改版本号）
- 成长完全数据驱动：events.json 全部个人线/招募事件选项 fx 新增 `bond: {id: 增量}`（招募热情 +10、个人线共情 +8、中立 +4~6、负心 −2~−5，roll 事件 ok/bad 各自结算），story.gd `_apply()` 通用结算，不加第二套系统
- HUD 队伍面板名字行追加 ★/☆ 三星（ACCENT 色）；新增 `--shotcrew` 截帧参数（注入 45/30/15/0/0 演示阶梯值），窗口截帧目检三/二/一/零星渲染正确，无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n88 任务追踪 + 任务日志

- 新增 JSON 驱动的任务系统：`data/quests.json`（主线 2：南下 680km 五段里程、集结四名幸存者；支线 1：首个补给点），目标类型仅 dist/crew，全部复用 dist_km/crew_members，不引入第二状态源
- 新增 `scripts/quest.gd`：每帧自动推进满足的目标，里程碑 toast「新目标」、全部完成 toast「任务完成」；done/goal_i 入存档（save.json 新增 quests 节），读档恢复
- HUD：左上状态面板下方常驻追踪条（主线橙名/支线白名 + 当前目标），J 键或右上新增「任务」触屏按钮打开居中任务日志（全任务描述 + 全部目标 ✓/▸ 清单）；触屏按钮行四个重排，操作提示补 J 任务并避开按钮
- 新增 `--shotquest` 截帧参数；追踪条开局/任务日志两张窗口截帧目检达标，标准无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n87 全屏沉浸对话（左立绘 + 右台词）

- 剧情框从底部通栏弹窗重构为全屏：0.97 暖黑遮罩，有立绘时左 42% 屏宽铺全身像（KEEP_ASPECT_COVERED）+ 暖色竖分隔线，右半屏 30 号说话人/短杠 + 21 号打字机正文 + ScrollContainer 选项区（终章 7 选项可滚动）；无立绘电台事件时对话区 6% 起横向铺满
- story_root 改挂 CanvasLayer 本体并共用主题；show/hide 时整体显隐游戏 HUD 根（剧情期间不显示车速/摇杆/触屏按钮）
- 选项区起点按 events.json 最长正文（135 字 ≈5 行）下移到 336，删除旧底部弹窗 offset_top/高度自适应逻辑
- 新增 `--shotstory=事件ID` 截帧参数（驻车开事件→直接出全文露选项→1s 后截帧）；end_shenman（立绘）/intro（无立绘）两张窗口截帧目检达标，标准无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n86 车内上下铺睡眠隔间

- 隐藏 GLB 原模横贯整车的大通铺（bed/bed_pad/blanket/pillow），改在 `_build_life_props()` 沿左墙代码搭建纵置上下铺：四根通高角柱兼支架，两层各配床板/床垫/枕头（头朝车尾）/毯子，上铺过道侧加防护横杆（床尾留口），床尾双竖杆四横档爬梯
- 床尾 z≈1.04 加左半封死半墙（右侧留过道）+ 上下铺各一道帆布杆垂帘（带褶痕），围出独立睡眠隔间；原床尾罐头挪到餐桌
- 新增 `--shotbunk` 截帧机位（床尾高位越半墙俯拍）；窗口截帧目检两层铺/半墙/爬梯/布帘就位，无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-30 · n85 车顶固定双哨兵 + 代驾中自由选择守卫/车内

- 两个射手岗位从车内射击孔移到车顶固定哨位（x=±0.82、车顶 RV_ROOF_Y、z=0.55），各守一侧 180° 半平面内 22m 最近丧尸自动开火、自由转身无射界锥限，左右合盖全车；车顶新增低矮护栏（两侧立柱+双横杆）与圆形哨兵踏板，纯视觉无碰撞
- 删 guns.json npc_gunner.fire_arc 锥限；哨兵子弹仅排除房车 RID（车顶俯射不被车壳挡）；追尾视角可见双哨兵站岗、舱内视角隐藏防穿顶、m1 车顶战斗同框守车
- 代驾/驻车车内走动闭环：走动中按 T（或移动端新增「车顶」按钮）= 收起车内玩家、队友留主驾继续巡航、主角爬车顶卧射；G/T 回到车内时重建车内走动玩家而不打断代驾；start_combat 守卫去掉 rv_walk 硬拦截
- HUD：combat_root 新增仅 rvwalk 时可见的「车顶」按钮，路由 start_combat(1)；战斗激活时强制隐藏
- 验证：`--gunnertest` 双哨兵各 fired=32/reloaded=1/refired=3 PASS（t=47s）；标准无头回归 EXIT=0 无脚本错误；追尾与车顶卧姿窗口截帧目检双哨兵持枪站岗、护栏就位（调试命令行需 `--` 分隔，否则 user args 被吞）

## 2026-10-30 · n84 倒车 + 左侧单摇杆驾驶

- 删除右下油门/刹车与左下左右四个旧触摸按钮，屏幕左下改为单一驾驶摇杆：前推前进、后拉在前进中先刹车停稳再进倒档真正倒退、左右转向、松手回中滑行；键盘 W/S(↑/↓) 与 A/D(←/→) 同语义
- 速度模型改为 `speed_kmh` 恒非负 + 独立 `reversing` 倒档（drive_dir=±1），避免带符号速度牵动油耗/碰撞/音效/相机/碾压；倒车限速 45km/h，位移/车轮/转向角速度/撞击冲量全部反向，旅程里程只记前进不回滚
- 驻车/队友代驾/剧情冻结分支统一在停稳后清倒档；流式地形在倒车接近高度图后沿时也重建，杜绝超长倒车撞隐形后沿
- 战斗 HUD 补移动端「手雷」按钮（键盘仍为 X）
- 验证：无头自动驾驶状态机六项全 PASS（前进加速/反向输入先刹车/倒车位移/里程不回滚/松手滑行停稳/倒车中驻车）；标准无头回归 EXIT=0 无新增错误；驾驶与战斗界面窗口截帧目检单摇杆与手雷按钮就位（验证用临时代码用后即删）

## 2026-10-29 · n83 七项体验修复与首条探索支线

- 车顶第三人称恢复完整服装；Q 与触屏按钮明确为点按车内/接管，车内行走仍由队友代驾
- 房车加速俯仰与转向侧倾移至视觉模型，物理车身四点贴地并保留合理车底余量；丧尸上限提至 48、每批 3~6 只并统一按地形贴地
- 车内宽度扩大 18%、长度扩大 12%，同步岗位、相机、射击孔和行走边界；做饭/收拾加入手臂、前臂与手腕骨骼动作
- 首条探索支线支持驶离主路、经过路侧 POI 后贝塞尔回接；入口与回接口护栏开口，路廊视觉/碰撞同源，岩石、楼、树和残骸按支路占地避让
- 验证：正式景物无清场自动驾驶完成整圈（18.52s，终点速度 28.89km/h）；直出段与回接段窗口截帧目检通过；标准无头回归 EXIT=0，无新增脚本错误

## 2026-10-29 · n82 环境二次元 3D 第一阶段样板

- 道路、草地、远山与程序化景物统一使用引擎内置 toon 明暗；地形改用地绿/蓝灰柏油/清晰标线的低对比色板，保留轻量轮迹和修补变化
- 房车、树楼、废车与障碍等环境 GLB 保留原贴图，仅收敛金属高光并统一卡通明暗；角色、碰撞、里程、流式预算与玩法未改
- 晴天降低灰雾和泛光，以暖日光、冷色环境光和清晰蓝天配合环境色板；昼夜与雨雪雾状态沿用原逻辑
- 验证：出生区/森林同机位改造前后截帧目检，城市正午与出生区黄昏补验通过；Godot 无头回归 EXIT=0

## 2026-10-29 · n81 队友代驾 + 极端天气 + 正式卧姿 + 分区景物

- 幸存者代驾补齐完整闭环：车内行走由首位队友接管主驾，静止自动起步并巡航 60 km/h、自动跟弯；支持驻车、剧情刹停/恢复与 Q 接管。修复车内玩家碰撞层导致房车推挤；role1/role2 补入 hero 重定向的现成 `drive`
- 天气新增大雨、大雪：复用雨粒子并新增雪粒子，联动天空、雾、光照、车灯、HUD、抓地与制动；晴 64%，雨/雪/雾各 12%，大雨/大雪各 6%。新增 `--weather=` 固定天气截帧参数
- 车顶卧姿弃用整体翻转假姿势，接入 TurboSquid 免费 Soldier prone idle 重定向动画，按右手 grip 实测布置 M4，并修正第三人称/FPS 自我遮挡与眼位
- 沿线环境按分区组合现有资产：森林绿树为主，山地增加松树与坡地大岩块，城市补足近景窗格楼、废墟与废弃车，其他分区增加路肩灌木；全部沿用 `consumable` 流式回收，不新增地图系统。大岩块按占地最低点贴地
- 验证：基础与暴雨驾驶无头回归 EXIT=0（仅已知 dummy material 基线噪声）；代驾巡航/驻车/剧情/恢复断言全过；大雨、大雪及森林/山地/城市窗口截帧均 EXIT=0 并目检；动作重定向误差低于 5° 门槛

## 2026-10-28 · n80 全流程巡检：驾驶 + 剧情 + 存档 + 发行包

- NPC 实弹闭环：`--gunnertest` 强制满员并持续补怪，双侧射手均完成打空 30 发弹匣→2.4s 换弹→复火，记录各 fired=32 / reloaded=1 / refired=3，PASS
- 三区长时驾驶：`--drive` 持续油门并每分钟输出里程/速度/天气/耐久；海岸车毁确认进入 deathbed 剧情。修复顶墙后仍按油门目标速度表显/耗油/转轮：仅在 `is_on_wall()` 时用 `get_real_velocity()` 限制 `speed_kmh`
- 无头退出音频泄漏：音乐、2D/3D 音效和引擎音在 headless 下不启动播放，退出时停止并清空播放器 stream；连续基础回归与海岸 soak 均无泄漏
- 剧情链修复：`goto`、`next`、概率分支 `roll.goto` 跳转前把上游节点写入 `fired`，避免续档重播；旧存档只记录 `intro_2` 时也不重播序章
- 验证：106 个剧情事件、1612 项结构/关键链检查全过；真实窗口存档写读与旧档兼容 32 项全过，测试后恢复原存档；最终无头回归 EXIT=0；Windows release 单 exe 导出及无头/窗口试跑均 EXIT=0，无脚本或资源错误

## 2026-10-28 · n79 车顶卧姿射击 + 射击孔防穿模 + NPC 射手弹匣换弹

- 天窗射击改卧姿：`model_root.rotation.x=PRONE_ANGLE(1.25rad≈72°)` 绕脚部前倒趴向车顶（Godot 欧拉 YXZ 序，先 yaw 后前倒），`PRONE_LIFT 0.22` 抬躯干防穿顶；枪挂点随身体前倒，`gun.rotation.x` 减 θ 补偿回水平；俯角下限收紧 -1.35→-0.55 防枪口穿车顶；FPS 眼位移到前伸头部（eye_h 0.78 / back -1.45，头骨缩零不挡视线），三人称跟拍降到 2.2m 高/3.6m 后
- 车内射击孔穿模三维根因：射手站位 x±0.92 太贴墙 + aim 姿势枪口前伸 0.95m（枪口 x≈1.87 远超墙 1.31）+ 全向跟枪转身扫墙。组合修复：站位后撤 ±0.66；射界钳制 ±fire_arc(0.45rad)（锥外目标直接跳过不打）；射击孔改横向长条（孔 z 宽 1.0/y 0.85 对齐枪管高度），枪管摆动恒在黑孔范围内，孔本身充当穿插遮罩
- NPC 射手不再无限弹药：guns.json 新增 `npc_gunner` 节（mag_size 30 / reload_time 2.4s / fire_arc 0.45）；crew_figure meta 挂 `npc_ammo`/`reload_until`/`gun_node`，打空停火换弹（枪口下垂动画+reload 音效+名牌切「×·换弹中」），到点满弹恢复；`_sync_crew` 换人 remove_meta = 新队员满弹上岗
- 截帧档新增 `--shotsunroof`（驻车进车顶卧姿，稳定 1.5s 截帧，可叠 `--fps`）
- 验证：无头回归 EXIT=0；截帧目检三人称趴姿 ✓、FPS 卧姿视野无自身遮挡 ✓（首版眼位在躯干内穿模，移到头部解决）、车内整舱射手不穿墙 ✓

## 2026-10-28 · n78 车内岗位灵动化 + 代驾可视化 + 爬坡修复 + 路面质感 + 丧尸闷响

- 车内「死站着」根因：`_sync_crew` 只给 sit/gun 播动画，cook/tidy 落默认 idle。新增 `duty_motion.gd` 程序化微动组件（作用于 Char 根节点不与骨骼动画冲突）：做饭=看锅前倾+搅拌微颤，收拾=转身+平方曲线蹲起（低处停留更久像码货），随机相位错开多人节奏
- 代驾可视化：Q 键车内行走时首位队友挪主驾位且名牌切「×·代驾」，G 回座还原；顺手修归位 bug（旧代码挪回 z=-2.85 主驾位，应为副驾岗位 z=-3.18）
- 爬坡难根因：rv.gd `velocity=-basis.z*speed` 带 y 分量，上坡被 move_and_slide 当碰撞损耗。修复=velocity 水平化（y 由贴地逻辑接管）+ 坡度动力补偿 `climb=1+slope*2.2`；`_elev_at` 纵坡过渡放缓（90→110m、×6→×7.5）
- 路面质感：`_mottle` 加车轮磨损双暗带（|dx|∈[1.1,3.2]，wear 0.22）+ 低频修补斑块；路面 band 横向细分 3→8 且 **mottle 开关必须开**（原 false 导致前两轮改动不生效，顶点色靠插值、细分不足也呈现不出条带）
- 丧尸闷响：ffmpeg 合成 `zombie_thud.wav`（82Hz 正弦指数衰减+brown 噪声低通 380Hz，0.27s），碾压时叠加在 run_over 之下，音高/延迟随机
- 手雷「没做」系误报（X 键早已实现，toast 一闪而过）→ hud 准星下补常驻操作提示「左键 开火 · R 换弹 · X 手雷 · 1-4 换枪 · C 下蹲 · V 视角 · G 上车」，车内行走时隐藏
- 车内空间感：RV_WALK 相机 fov 68→80（狭长空间显大），行走范围放宽 x±1.06/z[-2.72,2.68]；新增 `_build_life_props()` 生活内饰：单人铺四件套、吊柜×3、地毯、水壶、罐头、盆栽、吊灯罩（emission 暖黄）、照片板、储物箱、帆布袋，挂 interior 下随内饰显隐
- 踩坑：headless 全局类缓存不刷新，新 class_name 解析失败，沿用项目惯例文件头 `preload` 常量；新 wav 需先 `--import` 生成导入产物再回归
- 角色模型无损确认：VRM vs GLB 贴图最大分辨率均 2048×2048，体积减小系 glTF 打包效率+去 VRM 扩展
- 验证：无头回归 EXIT=0 且 stderr 完全干净；窗口截帧目检车内内饰/岗位名牌 ✓、公路轮迹暗带+补丁 ✓

## 2026-10-28 · n77 发行包三区域截帧验收 + 海岸段海面贴岸 + survivor 编译修复

- exe 实机截帧验收发现 `--jump=KM` 语义是里程（`KMH_FACTOR=250`，1km=250 世界米），此前按世界米选点导致截帧全落在错误区域；正确映射：mountain≈6.6km、city≈13.7km、coast≈15.6km（zones 循环 4560m=18.24km）
- 截帧被「车载电台」弹窗挡住：story.gd 早有现成 `--nostory` 调试参数，截帧命令补上即可，非 bug
- coast 段海面原 center=150m/half=120m，车载视角下被透视压成细线融进远山，开全程看不到海；收窄至 center=90/half=80（10~170m 贴岸铺开），截帧可见大片蓝色水面
- coast 段右侧树（23~65m 随机带）会泡水，改为该段树只生左岸；lake 段维持现状
- 修复 bcc9178 引入的 headless 编译错误：survivor.gd `var door := _main.rv.global_position`——`_main: Node3D` 无 `rv` 静态属性，`:=` 对 Variant 推断失败，需显式 `var door: Vector3`。教训：**EXIT=0 不代表编译通过**，回归必须查 stderr 的 SCRIPT ERROR
- 验证：无头回归 EXIT=0 且 stderr 零错误；三区域窗口截帧目检 coast 海面/山地集市/城市废墟均达标

## 2026-10-28 · n76 军用路障署名考据 + Windows 导出管线打通

- credits.json `pending` 组清零：从 barricade.glb 的 GLB JSON chunk 提取 Sketchfab UID `91e4783d...`（已 404 下架），按 8 材质名/面数/部件命名反查到作者重传版本——「Military Barricades / Walls」by A_W（CC-BY 4.0），补署进 cc_by 组
- 导出模板从官方对象存储镜像（`godot-releases.nbg1.your-objectstorage.com`，GitHub 被 SNI 阻断的替代源）断点续传下载 1.28GB，安装到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`（注意目录是点号不是连字符）
- 新增 `godot/export_presets.cfg`（Windows Desktop 预设，pck 嵌入单 exe）；`--export-release` 出 321.5MB exe，`--headless --quit-after 120` 试跑 EXIT=0 仅基线噪声
- 验证：无头回归 EXIT=0

## 2026-10-27 · n75 山段岩石去白模

- `_spawn_rock()` 原为单一灰 BoxMesh（n70 白模盘点遗留项），改为低面数 SphereMesh（9 段 6 环）压成不规则椭球 + 侧面叠一块 0.4~0.75 倍小石破蛋形轮廓；随机三轴翻转、比例控制在 0.72~1.35 之间避免压成飞碟
- 新增程序化石纹 `_rock_texture()`：8×8 低频石斑双线性放大 + 28% 高频颗粒（64² 单张缓存复用），`uv1_scale=(2,1.5,1)` 重复；每块随机明暗 0.82~1.12，中心埋深 30~50%
- 碰撞盒随缩放走（相对 1.4×1.45×1.4），仍入 `obstacle_hard`
- 验证：无头回归 EXIT=0 零 SCRIPT ERROR；`--jump=6.5` 截帧目检岩石为有棱面/阴影的巨石，不再是灰方块

## 2026-10-27 · n74 设置菜单（音量/显示/分辨率）+ 总线架构

- 音频从单 Master 拆三条总线：`_init_settings()` 运行时 `AudioServer.add_bus()` 建 `Music`/`SFX` 并 send 到 Master；`music_a/b` 挂 Music，sfx.gd 全部播放器（2D/3D/引擎）挂 SFX
- 设置面板（hud.gd）：暂停菜单「设置」进入，总音量/音乐/音效三条 HSlider（0-100 即时生效）+ 全屏/窗口切换 + 四档分辨率（1280×720 / 1600×900 / 1920×1080 / 2560×1440）；Esc 层级 settings > pause > 打开暂停
- 持久化 `user://settings.cfg`（`[audio] master/music/sfx`，`[video] fullscreen/res_w/res_h`）：启动 `_init_settings` 读取并应用，面板关闭与 `_exit_tree` 写盘；headless 下跳过显示操作与写盘
- `apply_setting(key, value)` 作为 HUD 唯写入口，main 仍是唯一状态源
- 顺手清理 credits.json 失效项（`ui_click.wav` 已移除，Kenney 界面点击音署名无对应资产）
- 踩坑：窗口截帧 `--shot` 需 `--quit-after 1500`（4.5s 游戏时间 ≈ 560 帧），`120`/`600` 帧会早退导致无截图
- 验证：无头回归 EXIT=0 零报错；设置面板截图目检 ✓；伪造 cfg（music=0.3 / 1600×900）重启后面板显示 30% / 1600×900 且窗口实际 1600×900 ✓；测试 settings.cfg/save.json 与临时截图均已清理

## 2026-10-27 · n73 存档系统 + Esc 暂停菜单

- 新增 `user://save.json`（version 1）：只存生存/车辆/队伍/设施/剧情进度（durability/fuel/food/morale/parts/crew/crew_ids/dist_km/day/hour/facility_levels/story_fired），战斗/丧尸/天气/驻车等瞬时状态不入档
- 自动存档 40s 一次 + 驻车状态变化即存；`_exit_tree` 兜底写档；通关清档；死亡回到最近检查点
- 续档复用 `--jump` 游标对齐：读档只把 dist_km 塞进 `_jump_km`，rv/terrain/obs/pick/surv/lamp/scenery/pole/place/hamlet 游标全部走既有 jump 分支，数值初始化末尾 `_apply_save` 恢复
- Esc 暂停菜单（hud.gd，`PROCESS_MODE_ALWAYS`）：继续 / 保存并退出 / 从头开始；死亡结算加「从头开始」，通关结算改「再来一局」
- 竞态与污染防护：`new_game()` 先置 `_no_save` 再 reload，避免旧实例 `_exit_tree` 回写覆盖已删存档；任意调试命令行（`--shot/--jump/--dump`）与无头回归（`DisplayServer.get_name()=="headless"`）既不读也不写档
- story.gd 序章定时器加 `fired.has("intro")` 守卫，续档不再重播 intro
- 验证：无头回归 EXIT=0 零报错；窗口实跑写档 ✓；伪造存档（12.5km/双队员/设施 2 级/剧情标记）续档后全部保留且里程不回退 ✓；测试存档已清理

## 2026-10-25 · n72 引擎换重型柴油机 loop + 碾压改触发区无顿帧

- 引擎仍嫌噪音：domasx2 0.67s 赛车 loop 整体替换为 Nayckron「engine_heavy_loop_0」（CC-BY 3.0，重型柴油机 4 秒 loop），ffmpeg 转 44.1kHz 单声道 + 0.2s 头尾交叉淡化，署名入 credits.json cc_by 组
- 碾压卡顿根因：丧尸在碰撞层 1 ∈ 房车 mask，move_and_slide 把 70kg RigidBody 当无限质量墙整堵一帧。修复：丧尸挪层 3（独占）、房车挂 Area3D（mask=4）碾压触发区，进区即撞飞，物理层完全不挡车；保留质量比动量衰减与 hit_cd/速度门槛
- 验证：无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-25 · n71 引擎接缝咔哒修复 + 碾压/拾取音再换柔

- 「开车滴滴滴」根因：engine.wav 循环首尾电平跳变 -14207（峰值一半），0.67s 周期咔哒被 pitch 拉成滴滴声。Python 一次性脚本做 0.2s 头尾交叉淡化，缝差降至 137（不可闻），循环缩至 0.47s
- 碾压/拾取音仍嫌刺耳：换同 CC0 包（Spring Spring「Various Sound Effects」）更柔的 `crush.wav`（0.74s）与 `pop.wav`（1.01s），署名不变
- 验证：无头回归 EXIT=0

## 2026-10-25 · n70 音效换真实素材 + 废墟楼立面改造

- 用户嫌撞丧尸/捡物资音效难听并**禁止程序化合成音效**：从 OpenGameArt 下载 CC0 包「Various Sound Effects」（Spring Spring）——碾压用 `snd_splathit.wav`（湿击溅射 0.46s）、拾取用 `get_important_item.wav`（道具获取音 1.19s），ffmpeg 转 44.1kHz 单声道覆盖。其余 7 个音效本就走 credits.json 的外部 CC0/CC-BY 素材，不重复替换；sfx.gd 头注释改为「外部素材」；credits.json 合并「枪声/碾压音/拾取音」为 Spring Spring 一条（去掉 WobbleBoxx）
- 用户嫌大楼不真实：`_make_scenery` 废墟楼原是纯 BoxMesh 灰盒/蓝盒。改造（ca7d95f）：新增 `_facade_tex` 程序化窗格立面纹理（base 底 + cols×rows 窗格，6% 亮窗/44% 半旧窗，按参数缓存），近楼随机混凝土/砖红/米色三色、远楼保留蓝灰玻璃幕墙（metallic 0.3）；楼顶加女儿墙 + 70% 概率电梯机房，轮廓不再一刀切
- 白模盘点（备查）：农舍/售票亭/观景台/加油站/营地帐篷篝火/残骸车/广告牌/电线杆均为 BoxMesh 组合但带细节件，风格化可接受；山段石头（`_spawn_rock`）是纯灰盒，优先级最低
- 验证：无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-25 · n69 四连修：废墟挡路根治 + HUD 面板加宽/成员滚动/立绘回框

- 用户报「遇到一个废墟开不过去」「车子开不上山坡」。根因：`_place_scenery` 楼模型宽高比约 2.3:1，随机旋转后半对角线可达 ~21m，突破 hamlet 22-27m / city 23-32m / _town 25m 全部放置安全距离压到主路；且楼/集装箱/树干/石头的 StaticBody3D **不在 obstacle_hard 组**——静默墙，撞上零伤害零提示，全速顶着走不动（rv.gd 坡度只影响视觉俯仰，物理上坡度不可能挡车，排除坡度阻力假设）
- 修复（main.gd）：① `_place_scenery` 加底面半对角线封顶（楼 9.5m / 集装箱 3.0m，超限缩 scale，从构造上保证走廊可通行）② `_solid_box` 加 `report := false` 参数，景物三调用点传 true 进 obstacle_hard（撞上有伤害+toast+横推反馈），营地设施等其余 11 处保持静默 ③ `_town` junk perp 5.5-8.0 → 7.0-10.0 保支路 ≥4m 通道
- HUD（hud.gd）：左上状态面板 276→348、BAR_W 168→240；成员列表 crew_rows 包 ScrollContainer、面板高度封顶（minf(n×82, 540)）；剧情立绘从全屏方案（story_bg/story_dim 已删）改回对话框内左侧 150×200 缩略图，有立绘时正文/选项右移让位（190/724）
- 验证：无头回归 EXIT=0 零 SCRIPT ERROR；commit 6da0c72，push 遇 SNI 阻断待 VPN

## 2026-10-25 · n68 动作库调研：契约已齐全，KayKit 重定向管线验证备用

- 起因：计划引入外部动作包补跑/走/受击/死亡。盘点发现**三角色动作契约已齐全**：hero 12 个（idle×3/sit×2/aim/walk/run/crouch/drive/jump/T-Pose），role1/2 各 9 个；player/mate/survivor/main 引用的全部动作名零缺口；手烘 walk/run Workbench 目检质量合格（run 抬膝摆臂到位、walk 外套不帐篷）
- 动作源调研结论：VRM 官方仓库只有模型无动作包；BOOTH 需登录无法自动化；万代南梦宫动捕数据集 CC BY-NC 4.0 非商用排除；**KayKit Adventurers（CC0、GitHub 免登录、75 动作 GLB 内嵌）可用**
- 重定向管线验证可行：KayKit chibi 骨架→VRM J_Bip 世界空间 delta 旋转法烘 walk，肢体方向向量逐骨 <5° 数值验收通过（方法见 art-pipeline.md 第 24 条）。因现有动作已齐全且合格，**不批量替换、不引入未引用动作**（避免死代码与外套帐篷化回归），管线存档备用

## 2026-10-25 · n67 昼夜循环修复：360° 连续太阳 + 晨昏平滑带 + 流速放慢挪 world.json

- 用户报「黑夜白天切换太快了」。双层根因：流速硬编码过快（行驶 8 分钟/驻车 1 分钟一昼夜）+ 太阳只扫 160° 致 hour 回绕时午夜跳白天 + 昼夜 if/else 硬切无黄昏
- 修复（12f2919）：太阳 24h 连续 360°（`deg=90-hour*15`，回绕数学连续）；`smoothstep(-0.12,0.12,elev)` 晨昏带约 55 游戏分钟平滑过渡；`noon=clampf(elev,0,1)` 插值日色（晨昏暖橙↔正午蓝白）；流速挪 `world.json time`（drive 0.03=13.3 分钟、park 0.15=2.7 分钟一昼夜）
- 教训：DirectionalLight3D 太阳高度 elev=**-sin(rotation.x)**（-90 正午直射），初版误用 cos 返工一轮；截帧脚本 `root.get_texture().get_image()` 在 `_process` 抓**上一帧**渲染，HUD/画面滞后一 step 属脚本特性非游戏 bug
- 验证：四时刻截帧（日出 6.5 橙暖/正午 12 蓝白明亮/入夜 18.2 黑沉车灯）+ 无头回归 EXIT=0 零脚本错误

## 2026-10-25 · n66 发行冲刺：岗位/手雷/路障通道/立绘UI + credits 指纹补署 + 队友真枪 + 冒烟巡检

- **f1 车内岗位系统**（bbc33c1）：5 岗位点位——副驾瞭望（坐姿）/灶台前做饭/货架收拾/左右射击孔射手；射手播 aim 持枪、`_update_port_gunners` 自动开火；灶台蒸汽粒子 + 两侧射击孔墙洞道具；名牌「名字·岗位」。同提交含 t1 子弹反向修复（见 n65）
- **f2 手雷武器**（f5dc31d）：guns.json grenade（damage 6 / radius 6 / fuse 2.2 / count 3），战斗 X 键抛物线投掷、范围伤害
- **f3 路障留车宽通道**（2966b79）：`_spawn_obstacle` 旋转后按 hx_eff 留位，不再堵死公路
- **f4 剧情全屏立绘 UI**（86f98b9）：幸存者立绘全屏（`STRETCH_KEEP_ASPECT_CENTERED` 修复左上对齐→居中），对话框移屏幕中下；两帧截屏验收通过
- **r1 credits 署名补署**（06e2578）：本地线索（git 历史/Downloads/GLB copyright）耗尽后，用 **GLB 节点名/材质名当指纹 + Sketchfab API 下载原包对比**——废轿车/废卡车确认 rashad-brahimli（阿塞拜疆语部件名 QAPI/ARXA/BAQAJ/KAPOT 锁定）、施工路障包确认 sabriayes（材质名含原作者笔误 warning_sing 都一致）；barricade 三个候选（MRowa/TampaJoey/_SeF_）下载验证全排除，留 pending 收窄披露
- **r3 队友枪换真 AKM**（06e2578）：`CharUtil.build_gun()` 程序化方块枪→AKM GLB，变换从 guns.json ak 同源推算（0.066 缩放、绕 Y 180° 对齐 +Z 瞄准向、grip 对位原程序化枪握把），枪手枪口节点移到 0.62（枪管末端）
- **r2 冒烟巡检**：SceneTree 帧计数状态机四状态截帧——驾驶（HUD/路障/明媚基调）/车内（做饭/收拾/射手各就各位、AK 朝窗外）/天窗战斗（M4+手雷×3+准星）/设施面板（灶台/工作台/储物架/种植箱/拆解台），目检全通过；无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-24 · n65 子弹轨迹"反向"修复：曳光改为枪口→弹头生长线

- 现象：用户报"落点对、轨迹反"。排查：曳光几何（look_at -Z 朝飞行方向、杆 +Z 拖尾）、4 枪 muzzle 挂点、队友程序化枪 muzzle、击退方向全部数值/截帧验证正确
- 真根因：弹速 600 m/s（每帧 10 米）玩家看不清飞行过程，只能看清命中瞬间——曳光杆锚在弹头向后拖 1.5 米，视觉上成了"从落点朝枪口画的亮条"，方向感相反
- 修复（main.gd spawn_bullet/_update_bullets）：曳光杆改为从枪口生长到弹头的完整轨迹线，杆长=|pos−muzzle|（clamp 40m），命中瞬间恰好连接枪口与落点；记录 muzzle/trail 进子弹字典
- 验证：无头回归 EXIT=0；窗口模式慢速弹截帧确认亮条后端锚枪口、前端跟弹头
- 事故教训：Grep 不支持 `type:"gd"`（报 unrecognized file type），过滤 GDScript 用 `glob:"*.gd"`；本 bug 排查因此死循环 200+ 次

## 2026-10-24 · n64 四连问修复：枪朝向/手离枪/视角键提示

- FPS 枪拿反：四把枪 rot_deg 全修——m4/glock 原生枪口 +Z 转 [0,180,0]、ak 原生已朝 -Z 转回 [0,0,0]；deagle 是 Sketchfab 蒙皮模型，渲染姿势由骨骼决定、静态节点坐标不可信，Python 解 GLB 蒙皮（joints 全局矩阵×IBM×顶点加权）算绑定姿势：枪口朝本地 +X → rot [0,90,0]，muzzle/grip 按顶点质心重标 [134.4,50,0]/[-75,-45,0]
- 手离枪：第一人称（fps / RV_WALK 车内行走）锁 aim 端枪动画，不再播 walk/run 摆臂；第三人称照旧
- 视角键：C/HUD「视角」按钮切档时 toast 档位名（车外/驾驶位第一人称/车厢右键环顾），提示条「C 换视角」「Q 车内走动」；RV_WALK 恒第一人称、V 仅下车战斗有效
- 验证：排枪渲染脚本（运行时同款装备逻辑）确认 4 枪枪口全朝 -Z 且黄球在枪口端；游戏内 FPS 截帧枪口朝前手不离枪；无头回归 EXIT=0
- 顺带确认：队友枪是 CharUtil.build_gun() 程序化方块枪，非 guns.json GLB

## 2026-10-24 · n63 皮肤灰蓝根因修复：材质 metallic=1 + 无损贴图真正落地

- 现象：用户截帧车内角色皮肤灰蓝、色块，质疑模型压缩
- 排查链：GLB 源贴图原始分辨率完整（Body/Face 2048² 等，Python 解 GLB JSON chunk 读 PNG IHDR）；但 `.import` 改 `embedded_image_handling=3` 后 `.godot/imported` 的 ctex/scn 缓存仍是 10/21 旧文件——**游戏运行模式不会因 .import 参数变化自动重导**，需删缓存 + `--import` 重建；重建后贴图不再产 ctex，直接内嵌进 .scn，运行时探针（`--script` SceneTree 脚本 load GLB 打印 `img.is_compressed()`）全部 false、原分辨率
- 真根因：三个角色 GLB 全部材质 `metallic=1.0 roughness=1.0`（Blender 导 glTF 没写 metallicFactor，glTF 规范默认 1.0）→ 皮肤成全金属反射蓝天环境光 → 灰蓝。role1 截图"正常"只是反射角度碰巧
- 修复：char_util.gd `_get_scene` 加载后实例化探针节点 `_fix_materials` 钳共享材质 metallic=0（修正一次对缓存 PackedScene 所有后续实例生效）；动漫哑光风格 roughness=1 保持不动
- 顺带：`events.json` 双重 BOM（`EF BB BF`×2）导致 `Parse JSON failed` 剧情事件静默失效，剥 BOM 修复；全目录扫描其余 json 无 BOM
- 验证：独立渲染脚本近拍 ye_lan（role2）——皮肤暖肤色、发丝瞳孔锐利；无头回归 EXIT=0 且 Parse JSON 错误消失
- 教训：`--script` 继承 SceneTree 可跑独立验证脚本（root.add_child 后 look_at 仍会报 Node not inside tree，用 look_at_from_position 或先 add 再调）

## 2026-10-24 · n62 小聚落系统：3-5km 一处镇/村/景区可搜刮（p4）

- 需求：用户要真实城镇/乡村/景区，目的「3-5 公里能搜刮物资」
- 实现：`_hamlet_km` 确定性游标（`_next_hamlet_km` 步进 3-5km，`_wseed(z,11)`），避开剧情地点 ±2.5km（`_hamlet_near_place`）与 city 带；按 zone 分派——lake/coast/mountain 55% 景区，plain 50% 村，forest/hills 混合；world.json `hamlets` 表配 km_range/名字池/店铺名
- 三类生成：town（两侧各 4-5 栋 7-12m 临街楼依次排开，一栋带金黄 Label3D 店招+门口搜刮箱，丧尸 2-4）；village（2-3 栋白墙红瓦农舍+两块绿垄农田，首栋门口箱，丧尸 1-2）；scenic（沥青停车场+车位线+废弃车、售票亭带挑檐亭后箱、木观景台栏杆朝景侧，丧尸 0-2）；预告牌镇/村蓝底、景区棕底
- jump 游标同步跳过条件 `_hamlet_km - 0.72 <= _jump_km`（含等号）→ 截帧验收窗口 `(X-1.04, X-0.72)`，跳过头就连聚落一起跳过
- 坑：PowerShell `[int]` 是四舍五入，复算 GDScript `int()` 截断序列必须用 `[Math]::Floor`（序列 3.62/8.15/12.50 避让/15.57/20.50/24.72/29.25 避让/33.55...）；`--shot` 等自定义参数必须在 `--` 之后（`get_cmdline_user_args`）；`--quit-after` 按帧数非秒，高 fps 下 240 帧 < 3s 截帧时机会提前退出
- 验收：headless print 实测 km/zone/kind/name 序列（渡口游园 scenic、王家营 village、双河镇等 town 群）；截帧确认王家营蓝牌+红瓦农舍、观景台棕牌、石桥镇夹道楼群；无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-24 · n61 副驾坐姿修复 + 驻车/贴图问题闭环（101b835/2d048b1/ec55738）

- p1 驻车闪退（101b835）：驻车行走分支 `end_rv_walk()` 后缺 return 落到出发分支
- p2 角色贴图压缩（2d048b1）：`.import` `embedded_image_handling=2→3`；确认三个 GLB 就是用户 VRM 原模型烘焙产物
- p3 副驾坐姿奇怪（ec55738）：双根因——①sit 动画髋在 root 后方 0.324m，副驾 root z=-2.85 时髋落在坐垫(z -3.04..-2.50)最后沿半悬空（"压座椅前沿"观感），root 前移 z=-3.18 髋坐进坐垫后 1/3；②坐姿头顶 rv 本地仅 0.79，名牌 y=1.72 悬空 0.53m 透视飘到挡风玻璃外公路上方，按 seated 分支坐姿降 1.30/站姿保持 1.72
- 弯路警示：怀疑 GLB 混入 Icosphere 异物做了一轮"清理"，实测 GLB 本身干净（Blender 里的 Icosphere 是 VRM addon 导入 collider 的可视化，见 art-pipeline 第 23 条）；且清理脚本重复运行把 role1 的 %TEMP% 备份污染成已修改版，靠 `git checkout`（LFS）恢复原始
- 调试基建：`--crew=N` 直接上 N 名队友、`--shotseat` 副驾近拍截帧（随 ec55738 提交）
- 验收：--crew=2 --shotseat 见屁股大腿贴坐垫、小腿自然垂下；--shotrvwalk 见名牌在座椅正上方不再飘出车外；无头回归 EXIT=0 零 SCRIPT ERROR；两个 commit 已 push

## 2026-10-24 · n60 可探索支路：POI + 锈牌预告（b4 公路单一）

- 根因：随机岔路（junctions_in）纯装饰——支路尽头空无一物，玩家没有开进去的理由，公路观感单一
- 方案：`_jh(n+5000)<0.35` 从既有岔路筛可探索支路（约 1/3），支路末端按 `world.json` detours 表刷三类 POI（wrecks 废车场/camp 旧营地/truck 翻倒货车），复用 consumable 回收；`DETOUR_SIGN_LEAD=180` 在支路口前 180m 立锈棕牌（矮单柱+BoxMesh 牌面+Label3D「名称 →/←」）预告
- 实心残骸抽成 `_wreck_solid`（StaticBody+BoxShape3D+模型，撞不动）；truck 侧翻绕长轴 roll 90°，碰撞盒高宽互换
- 坑：①侧翻模型绕原点 roll 后半埋（原 y∈[0,h] 翻成水平向，x 半宽变垂直半高）——`if roll!=0: model.position.y=center.y` 按新半高抬回地面；②match 分支内 `_wreck_solid` 调用 SearchReplace 丢一级 tab 致 Parse Error（「Expected indented block after match pattern block」），且截帧静默失败不产 PNG——先跑 headless 查 stderr 才发现
- 验收：headless print 实测 13 个 detour 的 id/end/sign_z/side 全合理（end 距路心 45-90m）；截帧确认锈牌文字可读、箭头方向与支路同侧、支路条带+护栏缺口清晰；无头回归 EXIT=0 零 SCRIPT ERROR

## 2026-10-24 · n59 驾驶座穿模修复：烘焙 drive 动画替代 sit+运行时 IK

- 根因：sit 动画本身是佝偻休息坐姿（手放腿上、躯干前倾 25°+），运行时 TwoBoneIK 只能修手臂修不了躯干，且手型跟随 sit 张开；三轮 IK 调参（grip 位置/pole/fig.rotation.x）到极限仍「举手投降/瘫坐玩手机」
- 方案：Blender 烘焙专用 drive 动画进 hero.glb（沿用 aim 管线）：sit 底保下半身 → `ad.action=None` 冻结 → 髋前移 0.13m（臂长 0.43m vs 肩距方向盘 0.53m 物理不可达的根因）→ Spine/Chest 各 -7° 扳直 + Neck/Head +8° → 双臂 IK 到 (±0.16,-0.22,1.02) 屈肘握轮 7/5 点 → 四指半握 42/52/38° → 呼吸 64 帧
- main.gd：`_build_driver` 删全部运行时 IK（TwoBoneIK3D+grip/pole 节点、fig.rotation.x 补偿），`CharUtil.instantiate("hero","drive")` 一行替代；新增 `--shotcab` 截帧参数（切车内视角+主驾正侧面近拍相机）供驾驶座验收
- 验收：Blender Workbench 双机位 + Godot --shotcab 截帧——坐直、双手扣轮缘、无穿模 ✓；无头回归 EXIT=0 零 SCRIPT ERROR
- 教训（已入 art-pipeline.md §4.1 第 21/22 条）：frame_set 会冲掉手动 pose 修改（底姿势应用后必须 `ad.action=None`）；IK target 先验臂长可达性；GDScript SearchReplace 易丢 tab 缩进致 Parse Error 且无头回归 EXIT=0 漏报（需查 stderr SCRIPT ERROR）；StopCommand 不停 Godot 子进程需 `Get-Process *Godot* | Stop-Process` 清场

## 2026-10-23 · n58 驻车修复闭环：剧情弹窗吞驻车（3a8654f）

- 根因：剧情弹窗期间按 F/HUD 驻车按钮，_toggle_park 置 parked=true 但 start_rv_walk 被 story_active 静默拦截——状态隐形翻转，再按又隐形取消，用户体感"要长按/按很多次"；退出驻车同理（剧情中出发视觉被冻结）
- 修复：_toggle_park 开头加 story_active 早退（2 行），剧情期间驻车状态不可能隐形变化；剧情关掉后按一次即生效
- 实测：窗口实例 PostMessage 注入 F，车速 0 单次按键秒驻车起身（"驻车中"+车内行走视角）✓；无头 EXIT=0 零 SCRIPT ERROR
- 工具教训：keybd_event/SendInput 注入的键游戏里没反应（Godot 物理键轮询吃不到），PostMessage WM_KEYDOWN/UP 直投窗口句柄才可靠；截图为窗口矩形（GetWindowRect）区域，先 AttachThreadInput+Alt 解锁 SetForegroundWindow

## 2026-10-23 · n57 一键驻车：自动重刹替代长按体感（addba52）

- 根因：超速按 F 只弹 toast 拒绝（不显眼），DRAG=10 滑行约 12 秒才停——玩家以为要长按，且松手后车还在自己滑
- 修复：超速按 F 置 _park_brake 标志，rv.gd 刹车行生效（BRAKE=120，约 1 秒停稳），main.gd 检测 ≤0.5 km/h 后复用 _toggle_park 完成驻车；刹车中再按 F 取消；start_rv_walk 防空档起身竞态
- 坑：rv.gd 的 main_node 无脚本静态类型，`var brake := ... or main_node._park_brake` 推断失败报 Parse Error——显式标注 `var brake: bool`；教训：无头回归 EXIT=0 不代表零错误，必须查 stderr 的 SCRIPT ERROR

## 2026-10-23 · n56 战斗手感 + 营地经营深化（2c64199 + 72acaf0）

- 战斗：丧尸 HP（2 起，150km 后 3、300km 后 4）+ 枪械伤害差异（M4/格洛克 1 伤，AKM/沙鹰 2 伤）——此前所有枪一枪毙命，武器差异只剩射速；命中点过肩算爆头 ×2（M4 爆头一枪倒）；非致命命中 0.32s 硬直 + 沿弹道击退；击杀准星红闪放大（爆头更醒目），pivot_offset 修正绕中心缩放；队友/幸存者支援火力默认 1 伤
- 营地：设施 3 → 5，新增种植箱（3h 收获食物 4/7/10）与拆解台（2h 拆零件 2/3）——零件此前只能靠捡/事件，经济循环闭合；facility_action 通用化处理 fx_food/fx_parts 新分支；设施面板 284 → 344px 容纳 5 行
- 验收：guns/facilities JSON parse OK（4 枪伤害 1/2/1/2、5 设施 id 正确），无头 EXIT=0 零 SCRIPT ERROR

## 2026-10-23 · n55 剧情事件池扩充：93 → 106（ab6658c）

- 量化缺口：mile 空窗 165→250（85km）/ 280→340（60km）/ 530→600（70km）；random 池 33 个×均 95s 长旅程后段耗尽
- 填 3 个 mile 空窗：mile_200 鹰嘴岩山道校车（粉笔太阳）、mile_310 铁轨道口货运列车（「进镇请走支路」锈牌联动岔路）、mile_555 方舟整点广播信号变清晰
- random 池 +10：旧地图红圈岔路超市 / 「有 房」霓虹旅馆 / 路肩新土坟 / 萤火虫河谷 / 橘猫（唐棠「教练」）/ 修桥团伙买路粮（叶澜谈判）/ 侧翻货车矿泉水 / 末世主持人问答 / 岔路尽头水塔侦察 / 后视镜尾随车队——town_detour 与 water_tower 直接联动新岔路玩法
- 文风对齐现有：「N 公里+场景特写+诗意细节」、roll 60/40、fx 仅 dur/fuel/food/morale ±1~14
- 验收：JSON parse OK（106 事件），无头 EXIT=0 零 SCRIPT ERROR / Parse Error

## 2026-10-23 · n54 岔路进城 + 镇内探索（6821e55 + d6f8aa9）

- 岔路系统：_place_junction 按地点 km 哈希确定性出参，junctions_in/junction_gap 查询时合并聚落岔路——terrain 渲染支路、护栏断口零改动生效（解决 terrain 提前 840m 生成 vs _spawn_place 260m 才触发的时序矛盾）；--jump 后补 terrain.rebuild 修车悬空
- 小镇/加油站围绕支路布局：_town 楼群沿支路后半段两侧（压主路 25m 内翻对侧/舍弃），_gas_station 迁支路末端正对来车；到达牌立支路对侧避让；地点前 1.5km 高速预告绿牌
- 镇内探索：搜刮箱 2~3 个（pickup.gd 新增 walkable——mask 含玩家层 1 步行可拾取，boost 倍率 ×2.5 比路面丰厚）+ 预置丧尸 3~6 只楼间巡逻
- 验收：无头 EXIT=0 零 SCRIPT ERROR；--jump=29.9/29.97 截帧支路岔口/楼群/到达牌对侧/楼间箱光正常

## 2026-10-23 · n53 确定性大地图：世界种子 + 沿途聚落 + 旅程条，修高楼贴脸巨墙

- 大地图：world.json 定义 world_seed + 11 个沿途地点（镇/加油站/营地/地标），_wseed 按坐标派生种子，六游标（障碍/物资/幸存者/路灯/景物/电线杆）全部确定性；聚落生成器 + 高速地名名牌 + HUD 顶部旅程条（前方 3 地点与距离）
- 调试钩子：--jump=KM 直达里程、--nostory 跳过剧情、--dump 打印场景节点 AABB（headless 定位异常物）
- 修复 1：远山脊线最高 71m 顶出屏幕上缘被雾洗成"巨墙"，压低到 26.5m（远层 15.9m）读得出山形
- 修复 2（核心）：60m 玻璃高楼回收一次后贴到路边 10-33m 成贴脸巨墙——_recycle_world 重放道具时无视原放置距离带；现在 _make_scenery 把横向距离带写进 x_band meta（默认 22-44 / 矮楼 45-90 / 高楼 105-190 / 广告牌 22-28），回收按带重放，高楼永远 105m 外
- 验收：--jump=55.0 dump 六座 52-75m 高楼全部退到 |x|≥121m；55.0/54.85 双机位截帧视野通透，断桥营地帐篷/残骸/电线杆/远处天际线正常

## 2026-10-23 · n52 路边景物穿车：带碰撞景物全部推到路肩外

- 现象：出生点旁一棵松树紧贴车尾（碰撞盒挡车、视觉穿模），车一开就撞；路边集装箱/混凝土块贴护栏
- 根因：_make_scenery 默认放置 ROAD_HALF+3~+29（10-36m）、广告牌 11-16m、GLTF 树 10-65m、city 楼 16-30m / JUNK 9.5-13m、rock 12-45m——路肩可行驶区到 21m，这些带碰撞/实心景物全在路肩内
- 修复：默认 22-44m、广告牌 22-28m、GLTF 树 23-65m、city 楼 23-32m / JUNK 22.5-28m、rock 23-45m（无碰撞的灌木/油桶随默认一并推远）
- 验收：zw_drive2.png 同随机序列下贴脸松树消失，车尾干净，远景层次不变

## 2026-10-23 · n51 体验反馈批修：旧资产还原 / 驻车起身 / 座椅贴方向盘 / 弯道加强

- 还原旧写实废车/路障：git checkout 1552e21^ 恢复 wcar/wtruck/barriers/barricade 四件套与 PBR 贴图（作者信息遗失的旧素材，credits pending 保留待核），恢复 wtruck 0.28 / barricade 0.55 缩放；删 Quaternius 替代版孤立贴图与 ui_click.wav
- 去掉按钮滴滴声：hud.gd 6 处 ui_click 播放全删，sfx KEYS 同步清理
- 驻车即起身：_toggle_park 驻车成功后直接 start_rv_walk（驾驶位空出，主角车内自由走动）；行走中按驻车键 = 回座出发（PC F 键原被行走提前 return 吞掉，F/E 键处理移到 return 之前）；Q/车内键在驻车行走中仅提示出发方式
- 座椅贴方向盘：内饰 GLB 建模座椅距方向盘 1.7m，双排座椅+头枕整体前移 1.27m（坐垫中心 -1.5 → -2.77），主驾/副驾/代驾去/代驾回 root 同步 -2.85（髋部坐垫后部贴靠背），IK 肘部 pole 随肩前移
- 弯道加强：road_x 振幅 3.5/1.6/7 → 7.5/4/11（横向 ±20m 级），bend_weight 低谷 0→0.25（直道保留微弯）；rv 松手自动跟弯已有，无需改
- 截帧验收：车内特写座椅贴仪表台、主角坐方向盘后；z=-400 弯道明显盘弯、护栏跟弯、旧废车回路上
- 无头回归 EXIT=0 且无 SCRIPT ERROR（GLB 还原后需先 --import 重建缓存）

---

## 2026-10-23 · n50 FPS 枪镜像 + 坐姿穿模修复

- 枪"拿反了"根因：`fps_rig.rotation.y = aim_yaw + PI` 转 180°，挂点本地 +X 翻到画面左；`FPS_GUN_POS.x` +0.24 → −0.24 即归位画面右侧（枪口朝向原本就正确）
- 坐姿穿模根因：sit 动画髋部相对 root 向车尾（+Z）滑 0.28m，未补偿时髋部 z=−1.17 插进靠背 seat_b0（z −1.23~−1.09）。root 前移 0.13（z −1.45→−1.58），髋部落坐垫上（seat_c0 顶 y=0.0），背贴靠背不插入
- 四处座位 z 同步：主驾/副驾（_build_crew 首项）/start_rv_walk 代驾去/end_rv_walk 代驾回
- 诊断手段：临时 --probe 骨骼探针（Skeleton3D.get_bone_global_pose 取 posed 髋/膝/脚 rv 本地坐标）+ 座椅三件 AABB 探针；skinned mesh 的 get_aabb() 返回绑定姿势，不能用于坐姿判定
- 验收：zw_fps2.png 枪持于画面右侧；zw_seat3.png 车内特写 hero 正常坐于主驾位
- 无头回归 EXIT=0 且无 SCRIPT ERROR

---

## 2026-10-23 · n49 手机端驻车体验修复

- 闪回根因：`end_rv_walk` 回座强制 `view_mode = 0`（车外追尾），驻车状态相机瞬切。改为 `2 if parked else 0`
- 状态错乱：车内行走中可按「驻车」直接出发。`_toggle_park` 入口加 `rv_walk_active` 守卫（先回驾驶座）
- 手机环顾：驻车座位自由视角原来只认右键拖动，补 `InputEventScreenDrag` 分支（灵敏度 0.005，对齐 player.gd 触屏手感）；行走环顾 player.gd 已有 ScreenDrag，无需补
- 面板收不起来：标题写死「E 收起」手机无入口。标题行改 HBox + 显式「收起」按钮（复用 `_facility_button` 样式），标题去掉 PC 键位提示
- 驻车/车内行走 toast 按 `DisplayServer.is_touchscreen_available()` 分平台文案
- 无头回归 EXIT=0 且无 SCRIPT ERROR

---

## 2026-10-23 · n48 路边程序化：里程路牌 + 电线杆

- 里程路牌：每 50km 路右高立柱绿底白字高速指示牌（钢柱 + 白背板 + 绿面板 + Label3D「方舟 N km」），剩余里程按方舟实际位置实时换算，呼应 680km 主线
- 郊野电线杆：平原/森林/丘陵段路左每 48m 一根（木杆 + 横担），跨间 6 段悬链近似垂弧电线，出区自动断线重接
- 护栏未做：截帧时发现 terrain.gd `_rail` 已有全路波形护栏（含损毁缺口/岔路断口），重复造轮子违反铁律，已写代码当场删除
- 验收：临时 --shotwarp 里程跳转截帧钩子（验后已删）拍三张——起始区电线杆+垂弧、6km 山区既有护栏、199.85km 里程牌近景，全部合格
- 无头回归 EXIT=0 且无 SCRIPT ERROR

---

## 2026-10-23 · n47 画质提升：渲染器切 Forward+

- project.godot `gl_compatibility` → `forward_plus`：PC 单机目标下解锁 SSAO/SSIL/高质量阴影
- `_build_sky` 环境增强：tonemap FILMIC→AGX（蓝天更通透、高光不过曝）、SSAO 接触阴影 + SSIL 间接光反弹、adjustment 饱和 1.06/对比 1.04
- 太阳光阴影显式 4 级 PSSM + 级间混合，远距阴影过渡更柔
- 截帧验收：玻璃幕墙高楼反射天光层次分明、房车高光质感、树木草地鲜活、路面橙白路障（n46 新模型实机确认）、明媚末日基调保持

---

## 2026-10-23 · n46 路面四件套替换 Quaternius CC0

- credits.json `pending` 段清零：原 Sketchfab 佚名四件套（wcar/wtruck/barriers/barricade）整体替换为 poly.pizza 的 Quaternius CC0 模型，署名风险彻底消除
- 选型目检定案：Broken Car→wcar（锈棕废轿车）、Truck→wtruck（厢式货车，Blender 程序化做旧：基色混锈棕 0.4 + 压暗 0.75，车窗保留）、Traffic Barrier→barriers（橙白条纹施工路障）、Barrier Large×2 + Sack Trench×2 组合→barricade（黄黑警示围栏 + 两端沙袋，军用检查哨）
- Blender 无头管线：逐件非均匀缩放精确匹配碰撞盒 half×2（wcar 5.6×8.1×3.5 / wtruck 6.6×10×4 / barriers 6×3.6×2.4 / barricade 11.4×0.75×1.9），脚底 y=0、x/z 居中，apply 全变换导出自包含 GLB
- main.gd 配套精简：障碍物 scale_f 归一（删 wtruck 0.28 / barricade 0.55 特例与变量本身），碰撞 half/center 不变
- 旧外挂贴图 146 张（.jpg/.png + .import）全删，新 GLB 贴图内嵌
- 验收：Workbench TEXTURE 渲染确认调色板贴图采样正确（EEVEE 灰白为显示怪癖排除）；`--import` + 无头回归 EXIT=0；驾驶截帧路面障碍正常

---

## 2026-10-23 · n45 role1/role2 队友动捕重定向

- 沿用 n40 hero 管线（世界旋转差法 + 51 骨 UE→J_Bip 映射 + slotted action），UAL1_Standard.glb 动捕替换 5 动画：idle/walk/run/sit/sit_talk（aim/idle_look/idle_stretch/T-Pose 保留原程序化）
- hips 身高比：role1 = 0.9767（0.895/0.917），role2 = 0.8873（0.813/0.917）；帧数 idle 76 / walk 41 / run 21 / sit 51 / sit_talk 89
- role2 裙摆/狐尾 J_Sec/J_Opt 物理骨未映射，保持 rest 随父动，验收无畸变
- Blender Workbench 渲染目检 10 图全过：idle 自然站立、walk 真实迈步、run 屈肘高抬、sit 大腿水平臀部落坐垫、role2 裙摆随体/狐尾后垂，无 T-pose 残留
- 覆盖 `godot/assets/roles_glb/role1.glb`（14.7MB）/ `role2.glb`（18.4MB）→ `--import` 重导入 → 无头回归 EXIT=0 → 截帧场景正常

---

## 2026-10-23 · n44 丧尸 spawn 分布收紧

- 刷怪距离车前 20~170m → 12~90m（无雾视野内，远处太散看不见也构不成威胁）
- 路面/野地权重 45%/55% → 65%/35%（行驶主威胁在路面）；野地偏移 60m → 35m
- 回归 EXIT=0，截帧确认场景正常

---

## 2026-10-23 · n43 游戏内署名页（CC-BY 署名 + CC0 致谢）

### 本次完成

- **数据**：`godot/data/credits.json` 新建——7 项 CC-BY + 1 项来源待补 + 7 项 CC0，文案走数据文件不硬编码
- **界面**：HUD 右上新增「署名」按钮（hint 提示行右移避让），署名面板 640×580 居中 + ScrollContainer，仿设施面板样式；数据驱动渲染三段
- **署名清单实锤**（GLB 元数据 extras + Sketchfab API + docs 三方交叉）：Lionsharp Studios（房车）、pxltiger（丧尸，**勘误：CC-BY 4.0 非 docs 旧载 3.0**）、jeandiz（M4）、dan741vlasov（AKM）、5Nikitos5（Glock）、TastyTony（沙鹰）、Colodical（丧尸音效 CC-BY 3.0）
- **来源待补披露**：废弃轿车/废弃卡车/路障套装/军用路障四件 Sketchfab CC-BY，作者在工程迁移中遗失（GLB 经 Blender 重导出元数据被抹、git LFS 初版即压缩版、Sketchfab API 检索未命中），面板内如实披露「核实后补署」
- **踩坑**：`OS.get_cmdline_user_args()` 只取 `--` 分隔符之后参数，截帧命令漏 `--` 导致引擎 banner 后静默退出（EXIT=0 假成功）
- 截帧目检通过：面板渲染/换行/滚动/按钮避让全正常

### 待办

- 四件套作者继续考据，或直接替换为 CC0 资产以清 pending 段
- role1/2 重定向、VRoid 换装、画质提升

---

## 2026-10-23 · n42 玩法链路自动化连贯性测试

### 本次完成（用户要求「玩法链路连贯性要测啊」）

- **方法论**：main.gd 临时 `--playtest=目录` 钩子（验后已还原不入库）——14 步状态机，`Input.parse_input_event` 注入物理键（项目按键全为 `is_physical_key_pressed` 轮询，注入即真实走按键→轮询→状态转换全链路），每步条件断言+超时保护，关键节点截帧
- **链路 14 步全绿**：序章弹出→关闭→W 加速 15.6→车头前 25m 放食物箱→行驶撞上自动拾取（food 10→18）→S 刹停→F 驻车（设施面板+车内视角）→G 下车战斗→W 走位 2s 位移 4.5m→开火弹药 30→29→G 返回（面板按驻车恢复）→Q 车内行走→Q 回驾驶座→F 出发（面板关）→W 再加速 10.1
- **截帧目检 3 张**：驻车设施面板 / 下车战斗 / 车内第一人称持枪行走，HUD 提示与触屏按钮随状态正确切换
- **踩坑**：①物资放 road_x 路心 12s 撞不上——起步点偏离路心，改车头正前 25m 并保持油门后秒撞；②match 无条件分支下一帧即执行，「按 W 走位 2s」实际只走 1 帧（位移 0.56m 假 FAIL），加 `_pt_t > 2.0` 门控
- **顺带确认**：拾取/位移/弹药数值断言全过，非仅「画面看起来对」；mates=0 因初始队伍 0 人属正常

### 待办

- 玩法链路已验通；剩余听感类（音量平衡/引擎循环顺滑度）只能人肉试听
- 同 n41：署名欠账、role1/2 重定向、VRoid 换装、画质提升

---

## 2026-10-23 · n41 音效全换真实录音（ce41340 + c96be22）

### 本次完成（用户反馈「一开车就有滴滴滴的噪音」）

- **盘点实锤**：assets/sfx/ 全部 10 个 wav 均为早期程序化合成音；engine.wav 是正弦波 0.86s 短循环——滴滴滴噪音源
- **engine.wav**：换 OpenGameArt domasx2 赛车引擎循环（CC0），61Hz 低沉基频，归一化 0.92 + 首尾 8ms 交叉淡化消循环咔哒（ce41340）
- **其余 9 个一并替换**（c96be22）：gunshot←Various Sound Effects snd_gunshot1（CC0 Spring，96kHz 转 44.1k）；reload←BMacZero clipload1（CC0）；ui_click←Kenney click1（CC0）；pickup←WobbleBoxx Coin01.aif（CC0，包络 -35dB 截断 2.55s→0.82s）；story_open←Luckius Paper Sound 1（CC0）；run_over←Various Sound Effects snd_splathit（CC0）；zombie_bite/die/growl←ZombiePackSFX 3（**CC-BY 3.0，署名 Colodical**）
- **统一规格**：44.1kHz 单声道 s16，峰值归一化 0.92（ffmpeg 预压 0.45 防立体声混音削波，Python 再归一）；sfx.gd 零改动（文件名不变）
- **验收**：无头回归 EXIT=0（Start-Process -Wait 取 ExitCode；`$LASTEXITCODE` 在该调用方式下偶发为空，注意）

### 待办

- 署名页欠账新增：Colodical（ZombiePackSFX 3 已实际使用）；其余同 n40
- role1/role2.glb 队友同管线重定向；VRoid 换装；画质提升——P3
- （可选）CharLively 插播池扩充：UAL 还有 Idle_Talking_Loop/Interact 可重定向为新闲置变体

---

## 2026-10-23 · n40 动捕重定向：动画去僵硬（8b7ed76）

### 本次完成（用户反馈「代码写的动画太僵硬」）

- **根因实锤**：Blender 采样 hero.glb 证实旧程序化动画数据退化——crouch 单帧且髋部恒 0.93 不下沉、jump 无身体起伏；动画链路（状态机/融合/优先级）本身全对
- **动捕来源**：Quaternius Universal Animation Library（CC0，npm metaverse-avatar 包 jsDelivr 直下 UAL1_Standard.glb，65 骨 UE 命名、45 动画、自带 A_TPose 参考）
- **重定向管线**（Blender 5 无头脚本，临时 %TEMP% 用后已删）：世界旋转差法——源参考 A_TPose f0 / 目标参考 rest，`delta=cur@ref.inv`、`want=delta@dst_rest`，链式求 matrix_basis；hips 位移按身高比 1.015 缩放；四元数相邻帧点积防翻转；51 骨映射含五指
- **替换 7 动画**：idle←Idle_Loop、walk←Walk_Loop、run←Sprint_Loop、crouch←Crouch_Idle_Loop、jump←Jump_Loop、sit←Sitting_Idle_Loop、sit_talk←Sitting_Talking_Loop；保留 aim（UAL 只有单手枪姿不合步枪）/idle_look/idle_stretch/T-Pose
- **验收**：crouch 髋部 0.886→0.478 真蹲下；walk 大腿四元数 ±0.7 摆动；jump 收腿滞空；Godot 连拍 5 张（aim/walk/run/crouch/jump）目检全过；无头回归 EXIT=0
- **经验**：Blender 5 采样动画必须 `ad.action_slot = act.slots[0]`（slotted action），只 mute NLA track 无效；`Action.fcurves` 已移除，走 `layers[].strips[].channelbags[].fcurves`

### 待办

- VRoid 换装与超清模型（用户自捏 VRM 导出后走 VRM→Blender→GLB 管线）——P3
- 画质提升（大公司手游质感）：玻璃幕墙反射、光影、后处理——P3
- role1/role2.glb 队友模型同管线重定向（hero 管线已跑通，脚本模式可复制）
- 署名页欠账：pxltiger、Colodical、TastyTony、5Nikitos5、SpatialNeglect、Vlasov Daniil（CC-BY）；Quaternius UAL 为 CC0 可致谢

---

## 2026-10-23 · n39 房车内部行走（937fc6f，push 待 VPN）

### 本次完成（用户 12 项反馈中的第 10 项）

- **Q 键 / HUD「车内」按钮**：驻车起身车内第一人称行走；有队友时行驶中也可起身（首位队友挪到主驾代驾，rv.gd 定速巡航 + 公路自动跟弯，回正逻辑复用）
- **实现**：player.gd 新增 `Mode.RV_WALK`，玩家挂 rv 子节点在本地空间直接挪动（地板 y=-0.4，x±1.0 / z -2.7~4.3，无物理）；aim_yaw 保持 rv 本地、相机直接用本地变换——车转弯不甩视角；强制 FPS（toggle_fps 加 force 参数）
- **限制**：车内无法开枪（toast 引导回驾驶座）、跳跃/下蹲自动禁用（既有 ON_FOOT 守卫）；剧情事件在行走中不触发（鼠标捕获态点不了选项）
- **HUD**：复用 combat_root 但隐藏开火/跳跃/换弹/换枪/下蹲/视角按钮与弹药行，只留摇杆 + 「上车」撤离（新增 set_rv_walk_active；combat_fire_buttons 引用数组）
- **验收**：`--shotrvwalk` 截帧钩子（先驻车再 start_rv_walk 稳定 1.5s 截图），zw_walk1.png 目检通过；无头回归 EXIT=0

### 待办

- VRoid 换装与超清模型（丝袜/裙子/御姐；VRM→Blender→GLB 管线或游戏内服装 mesh 切换）——P3
- 画质提升（大公司手游质感）：玻璃幕墙反射、光影、后处理——P3
- 署名页欠账：pxltiger、Colodical、TastyTony、5Nikitos5、SpatialNeglect、Vlasov Daniil（CC-BY）

---

## 2026-10-23 · n38 地形碰撞架构重构 + P0 反馈六连修（92884ed）

### 本次完成（用户 12 项反馈中的 9 项，余：房车内部行走/VRoid 换装/画质）

- **拾取/招募失效**：pickup.gd、survivor.gd 的 Area3D 补 `collision_mask=2`（房车独占层），开车压过即触发
- **剧情弹窗鼠标锁死**：story.gd `_open` 强制 `MOUSE_MODE_VISIBLE`，结束按战斗态恢复锁定
- **子弹反向/不出枪口**：瞄准射线与地面交点落到枪口后方时强制改用相机朝向（`dir.dot(aim_dir)<0.5` 守卫）；曳光杆长 9m→2.2m（不再视觉穿背）
- **第一人称射击**：V 键 + HUD「视角」按钮切换，相机贴眼位（站 1.62/蹲 1.05）、视模型枪位、俯仰放宽 ±1.35；下车/上车自动还原
- **车轮转动**：按 AABB 启发识别三根车轴轮，随车速绕本地 X 滚动
- **车外层穿模圈**：RV GLB 的 armor_skirt_l/r 裙边比车壳宽且颜色不搭，直接隐藏（截帧对比确认）
- **丧尸半身埋地根因**：terrain.gd 恒定 `WorldBoundaryShape3D`（y=-1.56 平面）与起伏地形不符——改每条带重建 `HeightMapShape3D`（x±400m 步长 2.5、z 前 40 后 900，行缓存采样防卡顿），丧尸刚体自然落在真实地表
- **地形唯一贴地函数**：新增 `ground_height(x,z)`（路面平/路肩 -0.05/野地含 side_elev，21~25m smoothstep 缓坡过渡），实体贴地调用点 20 处全部从 ground_y 切换；RV 自动回正只在近路 10m 内生效——开出公路可自由探索，山海地形全程生效
- **建筑穿墙**：`_solid_box` 给废墟楼/枯树/阔叶/松树/电线杆/广告牌腿/岩石加碰撞；GLB 楼/集装箱整体实心、树只挡树干（layer 1，房车/玩家/丧尸全撞得上）
- **附带修复**：远处废墟楼 x 位移后未重算 y 导致悬浮（截帧实锤）；HUD 顶部提示与「队伍/设施」按钮重叠，补 V 键说明
- **验收工具**：`-- --shot=路径` 命令行钩子，启动 3s 截帧存 PNG 并退出（窗口模式目检自动化）

### 待办

- 房车内部行走（驻车起身车内转 / 队友驾驶时行驶中走动）——P2
- VRoid 换装与超清模型（mcp-vroid 为 Linux/Hyprland 专用，Windows 不可用；走 VRM→Blender→GLB 管线或游戏内服装 mesh 切换）——P3
- 画质提升（大公司手游质感）：玻璃幕墙反射、光影、后处理——P3
- 署名页欠账：pxltiger、Colodical、TastyTony、5Nikitos5、SpatialNeglect、Vlasov Daniil（CC-BY）

---

## 2026-10-22 · n37 战斗/驾驶手感 + 手游化 + 公路/内饰扩充（用户 9 项反馈全落地）

### 本次完成

- **驻车面板战斗时收起**（6726b61）：下车战斗开始自动隐藏设施面板，不再挡操作
- **天窗贴实车顶**（6726b61）：行驶中探出车顶的玩家吸附真实 RV 车顶面，消除悬浮
- **主角坐主驾驶位**（d894cb5）：开局 hero 即坐驾驶座，TwoBoneIK3D 双手够方向盘做开车动作（复用已有角色模型）
- **武器系统数据驱动**（cf6f96e）：`data/guns.json` 定义 M4 卡宾枪 / AKM / 格洛克17 / 沙漠之鹰（自动/单发、射速/弹匣/换弹/初速/后坐/枪口/握点全字段），四款现成 GLB 模型
- **弹道真实化**（730eaf7）：曳光飞行 + 重力下坠 + 扫掠射线命中（swept-ray 防高速穿靶），弹速按枪种实测（步枪 715~880 / 手枪 375~470）
- **手游触屏全套**（44fc0f7）：虚拟摇杆移动、拖拽瞄准、战斗/驾驶分态按钮，替代全部键盘快捷键
- **跳跃/下蹲**（8ba50e8）：贴地物理（重力/起跳/落地）+ 触屏按钮；VRoid 三基底共享骨架复用同一套动作烘焙
- **公路不再单线**（7e90a22）：岔路 / 十字路口 / 直弯变化，告别单一正弦路
- **内饰精致化**（11c226e）：12 张程序贴图（木纹/墙板/布料/地毯/仪表盘/导航/挂画）嵌入 GLB + 14 件新家具（地毯/凳子/顶灯/导航屏/仪表盘/灭火器/挂画/书/垃圾桶/挂杆）；cab_light 3.0→1.5 治过曝
- 验收：三视角截帧（驾驶舱/车尾挂画/仪表盘贴图）通过；无头回归 EXIT=0

### 待办

- **署名页（CC-BY 合规，欠账累积）**：pxltiger（丧尸模型）+ Colodical（丧尸音效）CC-BY 3.0；TastyTony（Deagle）+ 5Nikitos5（Glock-17）+ jeandiz/SpatialNeglect（AR-15→M4）+ dan741vlasov/Vlasov Daniil（AKM）四款枪模——待入游戏关于页
- 相机面冲房车时穿壳（无遮挡处理），后续加相机拉近/避障

---

## 2026-10-22 · n36 剧情事件池扩充（+22 事件）

- **新增 8 个里程碑**（补里程空档）：mile_65 加油站 / mile_135 跨江大桥 / mile_165 未办完婚礼 / mile_265 大学 / mile_355 天文台 / mile_485 葡萄酒庄 / mile_530 热气球 / mile_620 最后书店
- **新增 14 个随机事件**（weight 3~7）：冰淇淋车/太阳雨/风筝/导航/菜园/广告牌/烟花/钓鱼老人/滑板丧尸/太阳能板/相机/果园/里诺字条(后续)/电台点歌；8 个事件带 crew 专属选项（requires 林晚/沈蔓/唐棠/叶澜/苏薇）
- **修复 events.json 文件头 6 个重复 BOM**（编辑器累积事故，Godot 只剥第一个，剩余 U+FEFF 导致 JSON 解析失败）→ 精简为单 BOM
- 基调遵循「明媚末日」：温情/幽默/善意传递为主，威胁来自丧尸；数值走 fx clamp 范围
- 验收：无头回归 EXIT=0（零 ERROR）

---

## 2026-10-22 · n35 多地形世界 + MOBA 下车战斗 + 车内自由视角 + 物理残骸

### 本次完成（用户 8 项反馈全部落地）

- **多地形世界 terrain v1**（abdbba4）：`data/terrain_zones.json` 数据驱动 10 段循环（平原/森林/丘陵/山地/湖泊/城市/海岸），`ground_y` 叠加分段海拔（段首 smoothstep 过渡，坡度随高差放缓），RV 按前后轮高差自动抬头/压头上坡下坡；走廊外地势 `side_elev`（山段隆起、湖海段下沉成床）；大地带改非均匀断点网格（±20/±34 关键点有顶点，防粗网格线性插值把山坡盖到路面）；水面 zone 化（海岸段右侧大海、湖段两侧湖、其余周期小河）；按 zone 生成景物（城市楼群/森林密树/山岩），scene_models 三套 gltf AABB 归一化落地
- **MOBA 下车战斗**（80bcdd3）：高位俯视背后视角（类王者荣耀），玩家自由操控开枪；新 `mate.gd` 队友 AI——下车自动跟随扇形站位、16m 索敌据枪、贴身反杀，未被操控的队友自由战斗
- **车内自由视角**（25781a0）：车内/驾驶舱视角下鼠标右键拖动环顾舱内
- **幸存者逃命招募**（b699af2）：幸存者自带武器跑向房车逃命（不再呆站），接入 5 段招募触发对话
- **物理真实化**（fc2867a）：软障碍撞飞后解冻成刚体留残骸（不再消失），`_wrecks` 列表监测落地（`y<=ground_y+0.35`）即冻结，高海拔段残骸不沉穿地面
- 验收：数值断言 16/16 PASS（zone 定位/海拔连续性 max_d=0.252/地势符号/段权重/景物生成）；无头回归 EXIT=0

### 待办

- 视觉验收待窗口环境（当前环境无法创建 OS 窗口，改数值断言兜底）

---

## 2026-10-22 · n35 第 3 种精致丧尸 + 碾压真实物理 + 现成音效替换

### 本次完成

- **新增精致写实丧尸 zmb_ripper.glb**（Sketchfab pxltiger "Zombie"，CC-BY 3.0 需署名）：2684 顶点带 PBR 全套贴图，10 动画契约齐（Walk/Attack 直有，FallingBack 改名 Death）；gltf-transform 纹理 1k+webp 压到 2.7MB；spawn 池三混编 ripper 30% / 蓝胖 28% / 绿瘦 42%，旧两款保留
- **碾压物理真实化**：RV 独占碰撞层 2，丧尸被撞飞/击毙即清 mask 第 2 位不再挡车（消除顿帧）；车速按动量衰减 `speed_kmh *= 4000/4070`（房车 4 吨 vs 丧尸 70kg，单撞无感、尸群累积拖慢）；震屏 0.25→0.08、耐久扣 2.0→0.5（唐棠 1.2→0.3）
- **音效换现成资产**（弃程序合成）：引擎 opengameart domasx2 引擎循环（CC0）；丧尸 growl/bite/die 换 opengameart Colodical ZombiePackSFX 2（CC-BY 3.0 需署名）
- .gitattributes 补 `*.webp` LFS
- 无头回归 EXIT=0

### 待办

- 署名页：pxltiger（模型）+ Colodical（音效）CC-BY 3.0 两处署名待入游戏关于页
- push 9a70279 起多个 commit 待 VPN 推送

---

## 2026-10-22 · n34 丧尸换 Quaternius CC0 双模型修长手 + 立绘回收

### 本次完成

- **丧尸模型整体替换**：旧 Sketchfab Low Poly Zombie 确诊蒙皮/绑定事故（Walk 单手拖地细长），不修直接换 Quaternius Zombie Apocalypse Kit（CC0，2024-03）：绿瘦 zmb_stand.glb + 蓝胖 zmb_stand_g.glb 双变体，各 16 动画（Walk/Attack/Death 契约齐，Idle_Attack 重命名 Attack）
- **下载链路**：官网 Google Drive 被墙 → poly.pizza 官方镜像 Invoke-WebRequest 抓 HTML 提取 static.poly.pizza 直链（沉淀 art-pipeline §4.1 教训 18）；Blender NLA 前缀动画导出两次翻车后定版 split("|") 同步改名 + NLA_TRACKS 模式（教训 19）
- **zombie.gd 净删约 72 行**：`_remove_rig_controls`（旧模型 rig 圆环 workaround，会误删新 2m 模型）+ `_trim_animations` 系（旧模型动画冻结前缀事故运行时修复）全部删除，无 backwards-compatibility 包袱
- **main.gd scale 改真实米数**：0.058–0.072 怪比例废弃，改 randf_range(0.75, 0.9)（站立约 2m，40% 概率出蓝胖变体）
- **立绘回收**：c_black.jpg 从 git LFS 历史回滚用户原图（黑丝御姐），b_white 白丝金发图补沈蔓空缺 shen_man.jpg
- 验收：Blender 渲染双模型无长手 → `--headless --import` 重导入 → Godot 动画列表 16 短名契约齐 → 窗口截帧三只全 Walk 贴地有影无 T-pose；无头回归 EXIT=0

### 待办

- 幸存者逃命跑向房车 + 自带武器 + 接入触发对话
- 下车战斗 MOBA 式背后视角 / 车内自由视角 / 物理碰撞不消失 / 多地形路面

---

## 2026-10-22 · n33 房车内饰精模 GLB 化

### 本次完成

- **程序化盒子内饰（144 行）整体替换为 Blender 精模 GLB**（assets/rv_interior.glb，约 60 物件）：壳体/驾驶舱/厨房/货架/餐桌/后铺/窗帘/方向盘组 1:1 还原原布局，新增头枕、盖钮、瓶颈等细节；`_build_interior` 只剩实例化 + cab_light 暖色小灯（夜间/雾天舱内可视），`_interior_box`/`_interior_cyl` helper 删除
- **Godot↔Blender 坐标映射定式**：`G(x,y,z)=(x,-z,y)`、尺寸 `(sx,sy,sz)→scale(sx,sz,sy)`、rotation.x 直通；方向盘辐条局部系照抄原构造（spoke 共享中心、各转 120°）
- **金属度返工一次**：转向柱 metallic=0.75 在天空环境反射下反出亮蓝，steel/canm 降到 0.25/0.2、rough 提到 0.55/0.5 修复（沉淀 art-pipeline §4.1 教训 17）
- 兼容性零改动：节点名 "Interior"、rv 本地系（地板顶 y=-0.4）不变，队友五站位/view_mode 显隐/combat 隐藏全部直接兼容
- 验收链：Blender Workbench 双机位目检 → Godot 窗口 harness C 键切 view_mode 1/2 截帧（驾驶舱：方向盘+发光仪表条+A柱+侧窗绿野；生活舱：钢台面+煎锅+吊柜+窗帘+货架）；harness 与建模脚本已删；无头回归 EXIT=0

### 待办

- 相机面冲房车时穿壳（无遮挡处理），后续加相机拉近/避障
- 沈蔓立绘 shenman_normal.jpg + avatars/shen_man.jpg（需 ARK_API_KEY）
- push 积压：e869390/35dc84e/61519d1/aa04889/51d6bf7（GitHub SNI 阻断，待 VPN）

---

## 2026-10-22 · n32 下车玩家 GLB 精模化 + 战斗相机根因修复

### 本次完成

- **hero.glb 新增 aim/walk/run 三动作**（Blender 烘焙 v2，9 actions 全）：aim 端枪戒备（双手同深度紧凑持枪，世界空间迭代器 4 轮定版 O 组参数）、walk 24f/run 16f 循环（步态+髋起伏+躯干扭转，长裙随腿 flare）；EVAL 数值 + Workbench 渲染双验收
- **player.gd 精模化**：程序化小人换 `CharUtil.instantiate("hero","aim",{},false)`（lively=false 防闲置插播覆盖战斗动画）；静止 aim、走动 walk、Shift run，0.15s 融合切换；程序化步枪按 Blender 实测双手坐标对位（gun local (-0.12,1.30,0.33)）
- **战斗相机根因修复**：`_aim_and_camera` 的 `back` 误取 `-cam_basis.z`（瞄准前方），相机架在玩家面前 3.2m 还朝前看——玩家永远不在画面里；改 `+Z` 即玩家身后，肩后视角恢复
- **NLA 污染根治**（art-pipeline §4.1 教训 15，取代 stash 法）+ **替换 GLB 必须 `--headless --import`**（教训 16，运行时读旧缓存导致 Animation not found）
- 窗口 e2e harness 截帧验收：aim 端枪背影、walk/run 步态均入镜正常；harness 与临时脚本已删；无头回归 EXIT=0

### 待办

- 相机面冲房车时穿壳（无遮挡处理），后续加相机拉近/避障
- 沈蔓立绘 shenman_normal.jpg + avatars/shen_man.jpg（需 ARK_API_KEY）
- 内饰精模替换程序化盒子（进行中）
- push 积压：e869390/35dc84e/61519d1/aa04889（GitHub SNI 阻断，待 VPN）

---

## 2026-10-22 · n31 角色「活感」：表情系统 + 闲置动作变体

### 本次完成

- **表情系统零资产改动**：实锤三个角色 GLB 的 Face 网格各带 72 个 morph target（Fcl_ALL/BRW/EYE/MTH/HA + VRC 口型全套）——VRM 烘焙时表情基随 GLB 导出，Godot 侧纯代码驱动
- **char_lively.gd（新组件）**：CharUtil.instantiate 自动挂载。周期眨眼（EYE_Close 正弦 0.12s，间隔 2.2~4.8s 随机）+ 常态微表情（survivors.json 五人各配 expression，林晚暖笑/沈蔓冷脸/糖糖俏皮等差异化）+ banter 说话嘴动（MTH_A 13Hz 张合 4.5s，随气泡）+ 闲置动作变体插播（6~12s 首播、之后 8~16s 随机、fade 0.3s 切变体、播完回基准）
- **三个新动作烘焙进全部 GLB**（zw_idle_variants.py，世界空间摆姿法）：idle_look（72 帧张望：右转 30°→左转 25°→回正）、idle_stretch（84 帧伸懒腰：双臂上举过头→放下）、sit_talk（96 帧坐姿谈话：前臂手势 + 头倾/点头）；anims=[idle, idle_look, idle_stretch, sit, sit_talk, T-Pose]，坐姿髋高 0.46 与 72 morphs 均完好
- **两个烘焙/验收坑实锤并沉淀**（art-pipeline §4.1 第 11/12 条）：①`keyframe_insert` 循环里调 `frame_set` 会冲掉刚摆好的姿势（三个动作一度全被烘成 f0 静态帧）；②渲染/诊断脚本 fps 必须在导入 GLB **之前**设 30（工厂默认 24，导入器按导入时的 fps 映射动画时间，事后改不重映射）——曾导致 f45 验收图实际采到 t=1.875s
- Blender Workbench 渲染验收 4 关键帧通过（转头/双臂过头/坐姿手势/侧视姿态）；`--headless --import` 重导入 + 无头回归 EXIT=0

### 待办

- 沈蔓立绘 shenman_normal.jpg + avatars/shen_man.jpg（需 ARK_API_KEY）
- 窗口全链路实测（G/T 战斗、音乐切换、队友互动、活感表现）
- .gitignore `data/` 规则误伤 godot/data 改 `/data/`

---

## 2026-10-22 · n30 坐姿根因修复：世界空间重烘焙 + GLB 内嵌 Cube 清除

### 本次完成

- **坐姿根因**：旧烘焙脚本把 `pb(Hips).location = (0,0,-0.50)` 当世界竖直方向写，实际是骨骼局部空间——髋骨局部 -Z 对应世界「后退」，sit 被烘成「髋后移 0.49 + 上移」的高脚凳畸变（用户看到「头和身体反向」）
- **世界空间摆姿法**：`arm.matrix_world @ pb.matrix` 取世界矩阵，`Matrix.LocRotScale` 重建后乘 `arm.matrix_world.inverted()` 写回 `pb.matrix`，每步 `view_layer.update()`；与骨骼局部轴向完全解耦。坐姿参数：髋 z=0.46、大腿绕世界 X -90° 水平、小腿 +90° 回竖直、上臂下放 86° 后微前 20°、前臂屈 55°（手搁大腿）
- **GLB 内嵌垃圾节点**：三个角色 GLB 全部内嵌 2×2×2 默认 Cube（原 VRM 管线导出时未清 Blender 默认场景），Godot 节点树 dump 实锤 `vis=true` 真实可见；另有 Blender glTF 导入器合成 Icosphere 副产物。清理法：删非蒙皮网格（`o.type=='MESH' and not any(m.type=='ARMATURE' for m in o.modifiers)`），role2 狐尾/hero Other 等蒙皮件安全保留
- role1/role2/hero 三 GLB 全部重烘焙：sit 髋高 0.46、无 Cube、anims=[idle, sit, T-Pose]；`--headless --import` 重导入；headless dump 节点树确认干净
- **验收方式变更**：窗口模式 `--script` 失灵（banner 后立即 exit 0、--verbose 日志全空，未解），改用 Blender Workbench（OBJECT 着色）渲染验收——BEFORE/AFTER 对照确认躯干直立、大腿水平、小腿垂直、双手搁膝、臀部落座
- 无头回归 EXIT=0 零新增错误；临时脚本已删

### 待办

- **角色动作/表情丰富化**（用户：「人物要有动作表情，不能僵尸一样」）：idle 仅 32 帧呼吸循环太静
- 沈蔓立绘 shenman_normal.jpg + avatars/shen_man.jpg（需 ARK_API_KEY）
- 窗口全链路实测（G/T 战斗、音乐切换、队友互动）
- .gitignore `data/` 规则误伤 godot/data 改 `/data/`

---

## 2026-10-21 · n29 战斗系统收尾 + 六首场景音乐 + 队友互动

### 本次完成

- **战斗系统**（commit f89a81d）：`player.gd` 第三人称持枪角色（程序化步枪 + 枪口闪光 + 曳光弹射线）；G 驻车下车、T 行驶中天窗探出射击；丧尸中弹死亡、枪声 85m 惊动全向狂暴；被咬掉血、血尽结算；HUD 战斗层（准星/弹药/生命条/命中闪标）
- **曳光弹朝向修复**：`Transform3D().looking_at` 三参不存在（被解析成 Node3D 两参签名），改为 add_child → 实例 `look_at(target, Vector3.UP)` → `rotate_y(PI)` 对齐 BoxMesh 长轴
- **六首 Suno 场景音乐**（commit 0f08e38）：Daylight Drive（行驶）/ Gunfire at Dawn（战斗）/ Embers Tonight（驻车营地）/ The Long Quiet（剧情）/ They Are Coming（丧尸逼近）/ Last Light Fades（失败挽歌），纯器乐，落盘 `godot/assets/music/`
- **音乐系统**（main.gd）：双 AudioStreamPlayer 交叉淡入淡出，按 结局 > 剧情 > 战斗 > 丧尸逼近 > 驻车 > 行驶 优先级选曲；`zombie.is_hunting()` 提供 55m 内冲锋判定
- **队友互动**（commit 7a47d28）：车内视角下每 14~24s 随机一名队友说一句（`survivors.json` 新增 banter 数组，五人各 3 句），Label3D 气泡 4.5s，听者转身看向说话者后转回
- Suno 下载流程沉淀：More options → Download → 先点 MP3（否则 Unlock 按钮 disabled）→ Unlock & Download；切片过短（0:10/0:16）需改 prompt 重生成

### 待办

- 窗口实测：下车/天窗开火全链路、被咬掉血、死亡结算、六种音乐切换听感
- 沈蔓立绘/头像缺失（`godot/assets/portraits/` 仍留 chen_mo/chenmo_normal 旧文件）
- 内饰精模替换程序化盒子、水陆两栖、大地图探索
- 图标/宣传图 → TapTap 预约 → 软著

---

## 2026-10-21 · n28 VRM 女性角色 GLB 全面替换方块人偶

### 本次完成

- 用户提供 3 个 VRM（`godot/assets/roles/`），拍板角色3 为女性主角、全角色去男性化；Blender 5.2 + vrm_addon v4.10 后台管线烘焙 idle(32f LOOP)+sit(2f 静态) 后导出 `godot/assets/roles_glb/{hero,role1,role2}.glb`，脚底 y=0、真实米数（hero 1.635m / role1 1.61m / role2 1.465m）、正面朝 +Z、Body/Face/Hair/Cloth 多材质槽
- **char_util.gd**：3 基底统一入口，PackedScene static 缓存；hero 直连，队友按 CREW_ORDER 序号奇偶轮换 role1/role2；实例化即按名播 idle/sit
- **main.gd**：`_build_crew` 方块人偶删除，5 站位换 GLB；AABB 实测+坐标核对调通接地（站 y=-0.4 落地板顶面，坐 y=-0.15 落坐垫顶 0.25；坐姿 Hips 下沉约 0.42）；副驾坐姿朝车头（rotation.y=PI）；车内相机居中 x=0、后移 z=2.6、降高 y=1.66、fov 72，后舱两人不再贴镜头被裁，5 人全员入镜
- **survivor.gd**：路边幸存者方块拼装删除，换 CharUtil GLB + idle；求救光柱/OmniLight/招募 Area3D 为外挂节点不受模型替换影响；截帧确认正面朝来车、接地、光柱正常
- 管线方法论沉淀进 art-pipeline.md §4（含 slotted Action、NLA strip 错开、sit 两帧化、J_Bip 轴向表、窗口截帧延迟、headless 不能截图、车顶遮挡顶视图等坑），§2 朝向修正为实测 +Z
- 窗口截帧验收：车舱全员视图 + 副驾近景 + 路边幸存者，全部合格

### 待办

- 数据去男性化：chen_mo 陈默（双份 survivors.json）改女性角色承接 driver:true/油耗-25%；同步立绘、chapter1.json、Web 侧引用；重新考虑 3 基底对 5 人的分配（role2 猫耳兽尾与写实末世基调违和）
- 内饰精模替换 _build_interior 程序化盒子
- 水陆两栖、大地图探索、图标宣传图 → TapTap 预约 → 软著

---

## 2026-10-21 · n27 苏薇立绘更换 a_office

- 苏薇立绘从 b_white（米白开衫）换成 a_office（白高领+黑包臀裙+黑丝+黑高跟+腕表），更贴「前外贸跟单/黑高跟踩废墟」人设；1773×2364 严格 3:4 零裁切
- 同步两份 survivors.json（web src + godot data）、events.json 4 处苏薇出场 portrait；旧 b_white 双端删除
- 无头 300 帧回归仅基线噪声，EXIT=0

---

## 2026-10-21 · n26 拾取物三精模 + 全身立绘竖框 + 丧尸资产补齐

### 本次完成

- **拾取物三件套（Blender 自研 GLB，替换发光方块）**：
  - `pickup_fuel.glb`：20L 军用油桶——桶身 0.36×0.17×0.47、侧面 X 型压筋（凸起 9mm）、油口颈+黑盖、顶部提手环、双底脚；军红金属 PBR
  - `pickup_food.glb`：木制补给板条箱——三层横板条、四角金属包边、顶部压扁麻袋（袋口内收）+麻绳结
  - `pickup_repair.glb`：军绿灰修车工具箱——闭合箱体+盖缝、双前卡扣、中央提手、盖顶金色扳手/红色螺丝刀（全部贴顶无悬浮）
- **pickup.gd 重写**：按 kind preload 三模型，AABB 自动缩放到统一高 0.95m 贴地；保留上下浮动+缓慢旋转+微光+Area3D 自动拾取
- **全身立绘竖框**：剧情立绘框 150×150 改 150×200（严格匹配 1728:2304=3:4，零裁切），队伍头像 64×64 改 56×72；4 张全身立绘覆盖（林晚/陈默/唐棠/苏薇）
- **zmb_stand_g.glb 补齐**：从 zmb_stand.glb 复制缺失本体，import 闭合
- **方法论沉淀**：docs/art-pipeline.md（资产来源决策/Blender 单位原点规范/先 apply scale 再旋转/Godot glb 导入/截帧验收清单）
- 无头 300 帧零新增错误（仅基线 dummy 渲染器 material null 噪声）；窗口截帧三件套目检合格；临时脚本/截图已删

### 待办

- 3D 人物资产专项：Blender 共享人形骨架 + 5 角色模块化换装 glb，替换 survivor.gd 方块拼装
- 内饰精模替换 _build_interior 程序化盒子
- 剧情立绘框窗口实机复勘
- 水陆两栖、大地图探索、图标宣传图 → TapTap 预约 → 软著

---

## 2026-10-21 · n25 房车设施升级/生产系统

### 本次完成

- **新资源「零件」**：初始 3，修理箱拾取 +2（叶澜被动 ×1.5）；状态栏新增零件显示，燃料条/文案改用动态上限
- **3 个驻车设施（data/facilities.json 数据驱动）**：
  - 灶台（2 级）：生火做饭，食物 -2 / 2 小时 → 士气 +12~18，升级「砌砖扩灶」4 零件
  - 修车工作台（2 级）：深度检修，零件 -1 / 3 小时 → 车况 +18~28，升级「加装吊架」6 零件
  - 储物架（3 级）：被动提高燃料上限 100/120/140，升级 5 / 8 零件
- **交互**：驻车时 E 开关底部设施面板（剧情对话时自动收起、结束恢复）；卡片双行布局（名称+等级点/描述/动作钮/升级钮 + 明细行），资源不足按钮置灰
- **触屏适配**：驻车自动隐藏油门/刹车/左/右四个驾驶按钮（驻车时本就无效），彻底消除与面板的重叠；出发恢复
- **平衡**：驻车被动士气回复 0.6 → 0.3/s，热饭成为快速恢复士气主途径；燃料拾取受储物架等级封顶
- 无头 300 帧零新增错误，窗口截帧验收面板布局/置灰/内饰视角正常；临时脚本与截图已删除

### 待办

- 水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · n24 队友个人支线第二幕 ×5

### 本次完成

- **唐棠（180km）**：七八个半大孩子用钉刺封路，为首少年用的是她拳馆的入门架势——曾经的学员阿哲沦为路匪；师徒对决点醒（战力 5 roll）/ 给干粮留话 / 硬闯三个走向，为 320km 小宇线先铺一层"为师者"的重量
- **林晚（230km）**：咬伤三天的男人护着镇痛药等怀孕的妻子，旁边是已变异的护士；带药追上孕妇并在车里接生 / 现场截肢赌一把 / 只拿药走人，呼应白大褂与仁医结局
- **陈默（300km）**：安全屋门口扎两根辫子的小女孩让他刹车踩到底——不是他女儿；捎带姑侄、情报交易或指路，蜡笔画在手里收了又收，接 205km 老家线、垫车轮不息结局
- **叶澜（455km）**：截获冒方舟之名的诱杀广播，全功率警告会暴露自身位置；公开喊话（roll，成则三车结伴）/ 只发方舟官方频段 / 明哲保身，延续 440km 硬盘线
- **苏薇（580km）**：三十人武装商队敲竹杠，她用灾变前三百万订单的谈判套路硬拆；主谈（roll，成则对方倒贴柴油）/ 交罐头记账 / 掉头绕行，呼应账本结局
- 事件总数 61 → 66；全部 JSON 数据驱动，复用既有 requires/roll/requires_atk/fx 机制零代码改动；bun 引用闭合与里程去重检查通过，无头 300 帧零新增错误

### 待办

- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · n23 剧情扩充：7 分支结局 + 垂死选择 + 14 个新事件

### 本次完成

- **终章 7 分支结局**：finale 改为 7 选项，按队伍构成/士气分流——救世主（4 人 + 士气 70，掉头接回 21 人，"方舟二号"）、林晚仁医、陈默巡逻运输队、叶澜真相广播、唐棠营地学校（小宇彩蛋）、苏薇物资大管家、独行热饭兜底；条件不满足自动置灰并标注原因
- **垂死选择剧情链（6 节点）**：车况归零不再立刻结算，先进入 `deathbed`——抢修续命（医疗 ≥5，roll 成功 dur 回 32 继续旅程）/ 死守待援（roll 成功拖到方舟=特殊胜利结局"最后十分钟"）/ 弃车徒步（苦中带甜的失败结局"徒步者"）；`dying` 标志防重入，车况回升自动复位
- **6 个新里程碑**填补里程空档：115 死玉米地、280 城市废墟（绕城烧油/穿城摸军营仓库）、340 疫检收费站、420 南坳儿童福利院、470 南集集市（陈默在队可摆摊修车间接补 morale）、640 最后 40km 灯柱引导
- **8 个新随机事件**：夜雾、废弃农场、抛锚救护车、武装 convoy、爆胎、野菜园（唐棠立绘）、深夜电台托孤、黄狗"轮胎"
- **剧情系统扩展（story.gd 三处最小改动）**：roll 分支结算后支持 `goto`（抢修续命跳转）、选项支持 `lose` 终局、新增 `requires_morale/requires_crew/requires_med/requires_atk` 四类门控（全队 med/atk 求和）
- **HUD 面板自适应**：终章 7 选项超出固定 334px 面板，`_show_options()` 按选项数动态加高（每行 49px，最高约 551px）
- 事件总数 34 → 61；bun JSON 引用闭合检查（goto/next/roll 分支全覆盖）+ 无头 300 帧零新增错误 + 窗口截帧确认 7 选项布局/置灰态；临时脚本与截图已删除

### 待办

- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 方舟终点营地：生活细节（篝火/炊烟/旗帜/残骸/巡逻哨兵）

### 本次完成

- **篝火跳动**：营地中央篝火点光源 `OmniLight3D` 用循环 tween 在 energy 2.0↔3.4 间不规则明暗（0.16s/0.22s），模拟火焰呼吸感
- **篝火炊烟**：`CPUParticles3D` 64 颗 billboard 贴片，径向渐隐 `GradientTexture2D`（64px、FILL_RADIAL 到对角 0.854 保证四角透明）+ `color_ramp` 生命周期淡入淡出，近匀速上飘（弱重力）并随风横漂，多片低 alpha（峰值 0.13）重叠成柔和烟柱；材质 `vertex_color_use_as_albedo` + UNSHADED
- **门柱双红旗**：大门横梁两端各一根横杆 + 暗红布面片，tween 缩放 x 0.86↔1.0（SINE 0.9s）模拟风摆
- **废弃车辆残骸 ×5**：新增可复用 `_make_wreck()`——锈蚀车身 + 驾驶舱 + 暗色挡风玻璃 + 四轮（CylinderMesh 转置），三色做旧、随机朝向/错位，半数微倾下陷，沿营地通道两侧布置
- **巡逻哨兵 ×2**：军绿胶囊躯干 + 头 + 暗钢头盔，沿围墙 x=±13 用 LINEAR tween 往返巡逻（18s 单程、到位 0.6s 转身），叠加 0.07m SINE 起伏模拟步伐
- 窗口模式四张白天近景截图（大门旗帜/炊烟/残骸/哨兵）逐项确认；无头 300 帧零新增错误（仅既存 dummy material null 提示）；临时脚本与截图已删除

### 待办

- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 场景细腻化：植被层次（常青松树 + 枯灌木混投）

### 本次完成

- **常青松树**：main.gd 新增 `_make_pine()`，短圆柱树干 + 三层 `CylinderMesh(top_radius=0)` 锥形树冠（底半径 1.9/1.45/0.95、自下而上收窄并轻微叠压），灰绿做旧色（0.16–0.24 绿色区间随机 lerp），整体 0.8–1.25 倍随机缩放
- **枯灌木**：2–3 团低矮 5 棱锥枝丛（`CylinderMesh` radial_segments=5、顶径 0、底径 0.45–0.8、高 0.7–1.3）随机错位摆放，暗褐绿 lerp 做旧
- **景物 roll 分档重排**：枯树 0.26 / 松树 0.26–0.42 / 电线杆 0.56 / 废墟楼 0.70 / 广告牌 0.82 / 枯灌木 0.90 / 混凝土块 0.96 / 油桶；初始景物池 80→100，密度提升；随既有 `_recycle_world` 回移机制零新增节点管理即可全程无限出现
- 窗口追尾/侧视双截图确认松树三层锥形、灌木低矮尖刺团簇与枯树/电杆/广告牌/废墟楼混投层次；无头 300 帧零新增错误（`Parameter "material" is null` 经 stash 基线比对确认是 dummy 渲染器在 300 帧后的既存提示，与本次无关）；临时脚本与截图已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 场景细腻化：公路波形护栏 + 双层远景山脊

### 本次完成

- **公路波形护栏**：terrain.gd 新增 surface 7/8，路肩外缘 x=±8.9 沿弯路逐段挤出横梁（0.48 宽 × 0.3 高、y≈0.72）+ 每段一根立柱（0.24 宽 × 0.85 高）；每 15 段单侧留一处损毁缺口、左右错开，金属灰材质（metallic 0.35）
- **挤出盒法线修正**：`_extrude_box` 改为 6 面各自独立顶点，按面赋正确 ±X/±Y/±Z 法线（初版 8 顶点共用 ±Z 法线会导致金属侧面光照错误）
- **双层远景山脊**：surface 9/10 近层 ±150m（峰高 8–71m、深蓝灰），surface 11/12 远层 ±380m（宽 280、h_scale 0.6、淡蓝灰），竖起伏带内端埋入地平线、双面材质，配 fog 0.0036 形成大气透视与夹山公路纵深（单层 ±300m 实测被雾吞掉无层次）
- 窗口模式追尾/侧视双截图确认护栏结构、缺口、山脊双层轮廓；无头 300 帧 exit 0（material null 为既存 dummy 提示）；临时脚本与截图已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 丧尸升级：修素材瑕疵 + 尸群变体差异

### 本次完成

- **修复头顶悬浮粉色双环**：GLB 误导出 Blender 骨骼控制器 custom shape（Skeleton3D 下两个近立方体白色小 mesh），`zombie.gd` 实例化后按 AABB 特征递归删除
- **尸群不再千人一面**：40% 概率使用 zmb_stand_g.glb 变体模型；每只随机体型（0.058–0.072）；四档腐烂色调（泛青新鲜/腐绿/泛黄溃烂/干瘪发黑）+ 亮度抖动，材质 duplicate 后按表面覆写不污染共享资源
- Walk 动画随机起步相位（seek），尸群蹒跚不再齐步走
- 窗口模式 4 只尸群截图确认：粉环消失、色调/体型/步态差异可见；无头 300 帧 exit 0（headless dummy 材质提示既存非新增）；临时脚本已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 路边幸存者升级为五名队友专属精细人形

### 本次完成

- **方块人 → 按招募顺序对应人设的程序化精细人形**：`survivor.gd` 重写，main.gd 生成时注入下一名未招募队友 id（`_next_crew_member`），所见即所得
- 五套人设外观：林晚（白大褂+红十字医药箱+齐肩发）、陈默（深蓝工装+腰包+背包、偏高）、叶澜（卡其风衣+胸前相机+盘发髻+背包）、唐棠（黑红运动装+红绷带拳手+高马尾+背包）、苏薇（米白西装+长发+右手提包、左手挥手）
- 细化件：鞋、腰带、脖子、内搭、眼睛、胶囊手臂+球形手掌；待机动画改为挥臂求救（高举手臂周期摆动）+ 呼吸缩放 + 重心摆动 + 头部张望四条循环 Tween
- 窗口模式 SubViewport 离屏双帧截图确认外观/挥手；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 剧情厚度扩充（5 条队友个人线 + 7 个随机事件，22→34）

### 本次完成

- **五名队友专属个人线**（均按里程点触发 + requires 队友门控，错过里程后招人仍可补触发）：
  - 90km 林晚：路肩翻覆的县医院救护车，白大褂与抗生素，「最后一车病人没开出去」——救赎
  - 205km 陈默：烧焦服务区是老家出口，七岁女儿的蜡笔画「等爸爸来接我，不哭」——寻亲
  - 320km 唐棠：废弃加油站拳馆记号，徒弟小宇敲赛前暗号（首选项需战力 4，含受伤 roll）——师徒
  - 440km 叶澜：短波电台收到自己两年前的循环录音与加密坐标，灾变 72 小时真相——真相
  - 555km 苏薇：断桥难民营重逢曾逼她背锅的前老板——宽恕
- **随机事件池 +7**：生日会、野化狼群、鬣狗帮三车追逐、跪地发烧母女、雨后滑坡、车顶银河、白发老人公路小屋（情感/野兽/匪帮/弱者/天灾/美景/善意各一类），weight 加权冷却投放
- mile_150（叶澜主讲）补 requires 门控；专项脚本 172 项断言全过（字段/门控/加权池/完整 choose 链路）；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多分支结局（失败前的垂死选择、不同队伍组合的通关差异）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 终点营地动态化（欢呼人群 + 探照灯扫视）

### 本次完成

- **迎接人群从静态胶囊升级为欢呼小人**：22 个 Node3D 人形（躯干胶囊+肤色头部+双肩双臂），六色外套随机；每人 3 条绑定 camp 生命周期的循环 Tween——左右臂错节奏高举挥动、身体上下起伏蹦跳，周期 0.5~0.9s 随机错相；人群朝向统一转向来车方向
- **哨塔探照灯活起来**：两座 SpotLight3D 在 ±26° 间以正弦缓动往复扫视（10.4s 周期），左右塔起摆方向相反形成错相
- 双帧截图对比确认挥手姿态差异；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 营地更多生活细节（走动巡逻、旗帜/炊烟、车辆残骸布置）
- 更多剧情与分支结局（队友个人线、失败前的垂死选择）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 方舟集结点终点营地（程序化场景兑现终章）

### 本次完成

- **终章场景从"空公路"变为真实营地**：车到 672km 一次性生成 `_spawn_ark_camp()`，大门锚定 680km 世界坐标（680km 弹终章时大门恰在车前 40m）
- 营地元素：钢制敞开双开门 + 门柱顶灯、横梁「方舟集结点」Label3D 招牌、两座高架哨塔（探照灯扫向公路）、集装箱围墙、12 顶人字顶帐篷（两列纵深）、46 点暖光灯海、22 个迎接人群剪影、门内篝火、硬化空地
- **方舟防区**：最后 1.5km 停止刷丧尸，最后约 1km 不刷障碍/物资/幸存者，保证抵达路段干净有仪式感
- 新增 `_emis_mat()` 自发光材质工厂；窗口双截图（远观灯海/近景大门招牌）自查通过；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 人群动画（挥手/走动）替换静态剪影、营地更多生活细节
- 更多剧情与分支结局（队友个人线、失败前的垂死选择）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 士气玩法闭环 + 680km 方舟通关结局

### 本次完成

- **士气从展示条变为真实玩法数值**：`morale_factor()`（50 为轴，0.8~1.2）影响油耗（高士气最低 0.8×、低士气最高 1.2×）、修车速度、丧尸咬伤伤害；驻车有食物时士气 +0.6/s 并检修，断粮 -0.8/s 且检修停摆，行驶缓降 -0.05/s；士气 <25 toast 警告，≥40 复位
- **后半程剧情弧（22 事件）**：新增 150km 三据点交界/250km 断桥尸群（需战力 4）/380km 加油站/500km 曲轴大修（需陈默）/600km 方舟回应 + 680km 终章「抵达方舟」，选项带 win 标记
- **通关链路**：story.gd choose() 识别 win → main._do_win()（冻结世界、刹停、won 状态）→ hud.gd 暖金色结算遮罩（用时天数/里程/队伍人数/最终士气，R 重开），与失败屏区分
- 里程换算常量 KMH_FACTOR 1440→250，一局实际驾驶约 15~28 分钟走完 680km
- **验证**：专项脚本 13 项全 PASS（士气系数边界/终章里程/win 链路/结算屏显隐）；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 更多剧情与分支结局（队友个人线、失败前的垂死选择）
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 车载电台剧情事件系统（数据驱动）

### 本次完成

- **剧情系统全链路上线**：填补玩法中完全空白的叙事层，JSON 数据驱动
  - `data/events.json`：16 个事件——序章事件链（intro→intro_2 点出 680km 方舟集结点目标）、6 个里程里程碑（5/15/30/50/75/100km，部分按队友门控）、8 个加权随机事件（搜刮/电台老歌/队内争吵/风暴/商人交易/故障/善人/尸潮预警）
  - `scripts/story.gd`：里程碑触发（错过可补）+ 70~120s 冷却加权随机 + 事件链（next/goto）+ 60% 概率 roll（ok/bad 双分支）+ 资源结算（车况/燃料/食物/士气）+ 队友 med/atk 条件门控
- **对话框 UI**（hud.gd）：底部通栏橙边深棕面板、角色立绘、说话人、打字机正文（点击/空格/回车快进）、选项按钮（条件不足灰色禁用）；新增**士气**资源与状态条（低红高橙）
- **世界冻结**：剧情打开时 main 主循环暂停、rv.gd 强制刹停贴地（时间/太阳继续走），关闭即恢复
- **验证**：专项脚本 8 项全 PASS（事件链/士气结算/关闭/fired 记录/条件置灰/负向效果/roll 30 次 clamp/里程碑补触发）；窗口双截图自查序章与陈默立绘事件排版；无头 300 帧 exit 0；临时脚本已删除

### 待办

- 士气的实际玩法效果（低士气惩罚/高士气增益）、更多剧情与分支结局
- 房车设施升级/生产（灶台做饭、工作台、储物容量）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 内饰穿模修复 + 场景/人物/车内打磨

### 本次完成

- **关键修复：追尾视角车内框架外露穿模**：程序化内饰统一收入 `interior` 容器，按 view_mode 分层显隐——追尾只见 GLB 车壳，驾驶舱/车内才显示内饰与队友
- **车内视角构图**：相机移至后铺上方斜俯拍生活舱（餐桌前景、灶台/货架队友中景、驾驶位远景），解决副驾头部贴镜头导致的透视畸变；FOV 68
- **人偶去积木感**：新增眼睛、脖子、球形手、鞋、骨盆/领口分节；坐姿改为水平大腿+下垂小腿+朝前脚三段；发帽改暖棕并加深包裹，消除"黑头盔+光蛋"观感；名牌缩小并开启深度遮挡
- **房车内饰**：方向盘三辐+轮毂+转向柱（替换裸圆环）；灶台汤锅/煎锅/水龙头、墙面吊柜、货架木箱/罐头/粮袋、餐桌餐盘杯瓶、后铺枕头毯子衣物卷、窗帘
- **场景地面**：条带网格支持横向细分与顶点色，确定性多频噪声做大地/路肩/柏油斑驳（去纯色塑料感）；路肩新增 70 丛交叉双面枯草
- **验证**：窗口模式三视角渲染截图逐张自查（车壳完整无穿模、车内无贴脸、地面枯草正常）；无头 400 帧 exit 0；临时脚本与截图已删除

### 待办

- 房车设施升级/生产（灶台做饭、工作台、储物容量）
- 突发事件/剧情（车载电台）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-21 · 行驶掉头修复 + 丧尸跑动 + 环境增强 + 副驾队友

### 本次完成

- **关键修复：车辆自动向后拐**：rv.gd 松手回正的目标 yaw 符号错误（`atan2(bx, -2d)` 在直行时 ≈π，整车掉头往 +Z 开），改为 `atan2(bx, 2d)`；该 bug 同时导致玩家看到的丧尸/幸存者都刷在"身后"、车头朝向看似反了
- **丧尸跑动化**：移速 1.8~3.2 → 4.2~6.6（随里程最高 +50%），追车时 Walk 动画 speed_scale 1.3~2.6，啃咬时恢复 1.0；刷新区间 50~160m 改 30~100m，更快接敌
- **环境增强**：路边路灯（每 55m 交替两侧，共享自发光材质，夜间/阴天统一亮灯，无真实光源开销）；远景天际线高楼剪影；路边锈蚀广告牌（双腿支架 + 面板）；混凝土残块概率调整
- **副驾队友**：5 个工位首位改为副驾坐姿位（省略大腿、改画下垂小腿），车内视角可见首位队友坐副驾
- **HUD 触摸按钮**：新增「视角」「驻车」按钮，触屏可切换三种视角与驻车休整
- **验证**：无头 400 帧零报错零警告（顺带修复 env 变量遮蔽类成员的警告）；行驶脚本实证 600 帧直行 143m 不跑偏；渲染截图确认车内副驾、夜晚路灯、丧尸群跑动；临时脚本与截图已删除

### 待办

- 房车设施升级/生产（灶台做饭、工作台、储物容量）
- 突发事件/剧情（车载电台）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · 驻车休整 + 车内视角视觉修正

### 本次完成

- **驻车休整（F 键）**：车速 ≤6 km/h 时驻车，自动切车内视角、锁车；驻车期间全员 2.5 倍速度检修、每 10 秒消耗 1 食物、时间 8 倍快进、不耗油；食物耗尽则检修停摆（toast 提示）；再按 F 出发回追尾视角
- **驻车风险**：丧尸仍会向车聚拢啃咬，驻车不是无风险回血
- **HUD**：提示补「F 驻车休整」，里程行显示「驻车中」
- **车内视觉修正**：侧壁加窗框柱 + 上沿压条 + 低饱和灰蓝玻璃，开放式侧壁改读为一排车窗；车内相机抬高至 1.72m 减少座椅/桌腿前景遮挡；队友头发帽收窄露出面部，名牌上移到头顶上方
- **验证**：驻车专项脚本 8 项全 PASS（高速拒绝/驻车状态/检修/分食/不耗油/时间快进/断粮停摆/出发）；车内与驾驶舱渲染截图确认构图正常；无头 400 帧零报错；临时脚本与截图已删除

### 待办

- 房车设施升级/生产（灶台做饭、工作台、储物容量）
- 突发事件/剧情（车载电台）、水陆两栖、大地图探索
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · 队友专长被动生效

### 本次完成

- **专长被动接入玩法**（数据源 `godot/data/survivors.json` 的 `passive` 字段）：
  - 林晚·急救：行进修车额外 +0.35/s（原仅 crew×0.12）
  - 陈默·驾驶：油耗 -25%
  - 叶澜·情报：物资箱收益 +50%（燃料 37 / 食物 12 / 车况 22）
  - 唐棠·格斗：丧尸啃咬伤害 -40%，碾压伤害 2.0→1.2
  - 苏薇·谈判：招募食物消耗 3→2（入队后生效）
- **队伍面板**：专长行改为「专长 · 被动效果」，招募 toast 显示实际分食消耗
- **验证**：专项脚本 7 项全 PASS（招募价、专长识别、油耗、物资、咬伤、修车、谈判折扣）；无头 400 帧零报错；临时脚本已删除

### 待办

- 房车内部经营（设施升级/消耗品生产）、更多事件内容、水陆两栖
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · 车内全员忙碌视角 + 队伍立绘

### 本次完成

- **视角三态**：C 键循环「追尾 → 驾驶舱 → 车内」；驾驶舱/车内均隐藏 GLB 外壳，避免车体从内部遮挡
- **生活舱**：地板/顶棚/后墙/侧窗台 + 灶台锅具、货架层板、餐桌桌腿、后铺床垫、舱内暖灯，全部程序化搭建
- **车内全员忙碌**：4 个工位（灶台/货架/餐桌/后铺）对应已招募队友，人形带手臂摆动与身体起伏动画，头顶 Label3D 显示「名字 · 专长」；招募后即时上车入位
- **队伍面板**：Tab 开关，读取 `godot/data/survivors.json` 与 5 张立绘（林晚/陈默/叶澜/唐棠/苏薇），显示头像 + 名字 + 专长 + 工作中；招募 toast 播报姓名与专长
- **验证**：无头 400 帧零报错；招募链路脚本验证 PASS（林晚、陈默依次入队，人形同步可见）；三视角渲染截图确认正常

### 待办

- 房车内部经营（设施升级/消耗品生产）、更多事件内容、水陆两栖
- 3D 人物资产专项（可动角色替换程序化人形）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · 舱内驾驶视角（C 键切换）

### 本次完成

- **舱内视角**：C 键在追尾/驾驶舱之间切换；舱内模式隐藏整车 GLB 外壳，由程序化内饰（地板/仪表台/台面/侧窗台/A 柱/顶棚/挡风上沿/后视镜/双座椅/方向盘/仪表光条）组成，方向盘竖直朝向驾驶者，暖色仪表光条与舱内小灯保证夜间可读
- **视野修复**：初版顶棚过低且外壳遮挡导致画面全黑；先改为舱内隐藏车体模型，再抬高顶棚至 2.2m、挡风上沿至 2.03m，并把侧窗台限制在腰线以下，保证挡风与侧窗都能看到路面
- 无头 400 帧零报错；有头渲染截图确认舱内/追尾两视角均正常
- HUD 提示补充「C 切换视角」

### 待办

- 房车内部经营界面、更多事件内容、水陆两栖
- 3D 人物资产专项（幸存者/队友需要可动角色）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · 视觉/天气迭代：路面质感、物资、幸存者、雨雾、夜行车灯

### 本次完成

- **地形重建 bug**：原判断条件恒真，几乎每帧重建 ArrayMesh；改为按覆盖区间 `[terrain_front-SPAN, terrain_front]` 判断，30 秒仅重建 3 次
- **数值平衡**：燃料 0.0045→0.0022、啃咬全局冷却 0.7→1.2s、软/硬障碍伤害下调；无头仿真 11 项全 PASS（不躲障碍的自动驾驶 30 秒车况最低 72）
- **物资箱**：修掉悬空（根节点与箱体位移叠加），改为贴地物资箱 + 微光（燃料锈红 / 食物木箱 / 维修钢灰）
- **幸存者**：程序化人形（双腿/双臂/背包/头/头发）+ 微弱求救光柱 + 原地张望，替换原来的胶囊人
- **天气系统**：晴/雨/雾每 50–90 秒随机切换；雨=CPUParticles 雨丝 + 阴沉天色 + 抓地力 ×0.78，雾=能见度骤降，HUD 天气标签 + 切换 toast
- **夜间**：月光色环境光（避免纯黑）+ 车头 SpotLight 自动开启（雾天也开）
- **人物模型排查**：Sketchfab companions 三个 GLB 采用 extrude meshopt + KHR_mesh_quantization，Godot 不支持；gltf-transform 解压后分别为瓷娃娃摆件与比基尼人物，不适用，已从仓库删除

### 待办

- 房车内部视角/经营界面、更多事件内容、水陆两栖
- 3D 人物资产专项（幸存者/队友需要可动角色）
- 图标/宣传图 → TapTap 预约 → 软著申请

---

## 2026-10-20 · Godot 迁移完成：实时 3D 驾驶生存版

### 本次完成

- **引擎迁移收尾**：Godot 4.7.2 全代码构建（main.tscn 仅根节点），重写 rv / zombie / terrain / hud 四脚本，新建 pickup / survivor，与 main.gd 新接口对齐
- **无限公路**：terrain.rebuild(start_z) 程序化条带（柏油/路肩/边线/中央黄虚线 6 surface），车每前进 ~340m 向前重建；弯道 road_x 双正弦、起伏 ground_y 三正弦
- **驾驶手感**：WASD/方向键 + 触摸按钮双输入；加速前倾、转向侧倾、贴地跟随地形；追尾相机指数平滑 + trauma 震屏 + 速度 FOV
- **战斗循环**：丧尸（上限 22，随里程加密增强）追车→贴身啃咬（0.8s/次）；高速碾压→撞飞/Death 动画；软障碍（废车/护栏）轻伤减速、硬障碍（卡车/拒马）重伤急减速
- **生存经济**：燃料消耗+补给箱、食物招募幸存者（-3 食物/+1 队友，队友行进中修车）、耐久归零→结算遮罩→R 重开（roguelike）
- **HUD**：SystemFont 微软雅黑（解决默认字体无中文）、车况/燃料条、toast、结算界面
- **无头验证通过**：`--headless --quit-after 300` 零脚本错误；Godot MCP 已写入 Trae mcp.json（重启 Trae 生效）
- 清理调试残留 tools/inspect.gd、tools/convert_glb.py

### 待办

- 游玩实测调手感（车型碰撞盒、丧尸密度曲线、昼夜时长）
- 房车内部视角/经营界面、更多事件内容、水陆两栖
- 图标/宣传图 → TapTap 预约 → 软著申请

---

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
