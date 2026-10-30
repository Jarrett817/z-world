# 美术资产管线方法论

> 目标：可发行级画面，零编辑器依赖（Blender/Godot 均可通过 MCP 或无头 CLI 驱动），一人可维护。
> 本文沉淀「资产从哪来、怎么造、怎么进游戏、怎么验收」的固定流程，后续每次美术迭代都按此执行并回写经验。

## 1. 资产来源决策顺序

按成本从低到高、确定性从高到低排序：

1. **现成免费模型优先**（Sketchfab/Poly Pizza 等，授权必须可商用：CC0 / CC-BY 可署名 / Sketchfab Store 免费可商用）
   - 硬门槛：glTF/GLB、PBR 材质、拓扑干净；下载后必须过一遍授权记录（见 §6）
   - 已知坑：依赖 `EXT_meshopt_compression` / `KHR_mesh_quantization` / specGloss 的包 Godot 导入会坏，需 gltf-transform 解压转材质（2026-10-20 companions 包内容还货不对板，整包删除）
2. **Blender 手工建模**：硬表面道具（油桶、木箱、修车箱、家具、车辆装甲件）用 bpy 脚本化建模——可复现、可微调、零体积浪费
3. **AI 3D 生成**（tripo/meshy/hyper3d/混元）：仅用于有机/复杂曲面且手工成本高的单件；当前 MCP 生成器全部关闭，需要时先让用户在 Blender 插件里开启并配 Key
4. **程序化图元兜底**：Godot 内 Box/Capsule/Sphere 拼装只允许用于远景剪影与占位；进入「画面专项」后，玩家近景可见的角色/物品必须换成真模型

**角色不走下载路线**：免费人形模型质量与授权双不可控（瓷娃娃/比基尼事故）。角色采用「共享骨架 + 手工/半手工模块化换装」自建（§4）。

## 2. Blender 建模/导出规范

- **单位**：场景 unit scale = 1.0，公制；角色真实身高 1.7–1.8m，导出时按 Godot 侧的实例 scale 校正，不靠缩放物体凑尺寸
- **原点与朝向**：模型原点在脚底（y=0 即地面）；VRM 经 vrm_addon 导出的 glTF **正面朝 +Z**（2026-10-21 AABB+截帧实测，推翻旧「-Y forward」结论），进引擎后朝向在 station 配置上按局部旋转调整，不在 Blender 里转模型
- **命名**：网格 `geo_<物>_<件>`、骨骼 `rig_<物>`、材质 `mat_<物>_<部位>`；Blender 控制器（圆环/自定义形状）导出前必须剔除（丧尸脚本现按尺寸启发式删除，新资产应在 Blender 侧直接清理，不把垃圾带进 glb）
- **修改器**：导出前应用非形变修改器（Solidify/Bevel/Boolean）；Armature 保留为骨骼形变
- **贴图**：baseColor ≤1024（主角/大件可 2048），MR/normal ≤512/1024，JPEG 85（透明才 PNG）；文件名 `<glb名>_<材质>_baseColor.jpg` 与现有包保持一致，Godot 会自动同名识别
- **glTF 导出设置**：GLB 单文件、+Y up 由 glTF 标准保证、应用修改器、包含 UV/法线/切线、材质 PBR metallic-roughness；不压缩、不嵌入多余动画数据
- **导出脚本化**：能写 bpy 脚本就不点菜单（`bpy.ops.export_scene.gltf(export_format='GLB', ...)`），脚本保留在本次任务上下文中便于重导

## 3. Godot 导入与实例规范

- glb 放 `godot/assets/<分类>/`；导入器默认开 LOD/阴影网/tangent，保持默认即可
- **贴图压缩**：Windows/S3TC 首次导入会自动生成 `.s3tc.ctex` 并改写 `.import`（VRAM compress/mode=2），这类自动改写与 glb 一起提交，避免干净环境首次运行卡顿
- **源文件必须入库**：只允许 `.godot/imported` 缓存存在、`.import` 指向的 glb 本体缺失是事故（本次发现 `zmb_stand_g.glb` 就是此状态）。修复方式：补回本体，或删除引用改代码
- **动画名契约**：VRM 人类角色统一 `idle`（LOOP_LINEAR）/ `sit`（静态坐姿循环）；丧尸沿用 `Walk` / `Attack` / `Death`。脚本经 `find_child("AnimationPlayer",true,false)` 按名取轨道，`has_animation` 守卫，换模型不改脚本
- **实例 scale 契约**：丧尸为 Quaternius 真实米数模型（站立约 2m），spawn 处 `scale=randf_range(0.75, 0.9)` 保持体型差异；角色按真实米数建模后 spawn 处显式 scale=1.0。旧 Sketchfab 25m 怪比例（0.058–0.072）已随模型替换废弃
- 碰撞不用 glb 内三角面：RigidBody/StaticBody 外挂 Capsule/Box 碰撞（现有 spawn 代码已是此模式，保留）

## 4. 角色方案：VRM 女性基底 + 程序化 idle/sit 烘焙

5 名队友 + 主角 + 路边幸存者全部为女性（2026-10-21 用户拍板：不要男性角色）。资产为 3 个 VRM 导出的 GLB 基底，`godot/scripts/char_util.gd` 统一入口：

- **基底**（`godot/assets/roles_glb/`，脚底 y=0、真实米数、正面朝 +Z、自带 Body/Face/Hair/Cloth 多材质槽）：
  - `hero.glb`：紫短发黑色战术外套主角，只映射 `hero`
  - `role1.glb` / `role2.glb`：可复用队友基底；`CharUtil._role_key` 按 `CREW_ORDER=[lin_wan,chen_mo,ye_lan,tang_tang,ivory]` 序号奇偶轮换（偶→role1，奇→role2），id 直连（hero/role1/role2）优先
  - PackedScene 用 `static var _scene_cache` 缓存；`instantiate(cid,anim)` 返回 `{"node","anim"}`，实例化即按名播动画
- **车内站位**（main.gd stations：本地坐标/朝向/是否坐姿）：地板顶面 y=-0.4，站姿 station y=-0.4 精确接地；坐姿 Hips 下沉约 0.42m，root y=-0.15 使臀部落坐垫顶 y=0.25；GLB 朝 +Z，朝车头(-Z)的副驾 rotation.y=PI
- 路边幸存者（survivor.gd）与车内队友共用同一基底与 idle 动画；求救光柱/灯光/招募 Area3D 均为外挂节点，模型替换不影响玩法碰撞

### 4.1 VRM → 带动画 GLB 烘焙管线（Blender 后台脚本）

工具：Blender 5.2 LTS + VRM 插件 v4.10（模块名 `vrm_addon`），全程后台无编辑器：

```
blender --background --addons vrm_addon --python run_pipeline.py -- <in.vrm> <out.glb>
```

固定要点（重导新 VRM 时照此重写脚本，脚本本体留任务上下文、不入库）：

1. **后台启插件**：`--addons` 只注册 operator 不写 preferences，脚本里必须再 `addon_utils.enable("vrm_addon",default_set=True,persistent=True)` 并从 preferences 取 addon；场景用工厂启动（`use_empty` 会清掉插件 preferences）
2. 导入 `bpy.ops.import_scene.vrm(filepath=...)`，取名为 `Armature` 的对象；删除 VRM 弹簧物理的全部 EMPTY 辅助节点
3. **Blender 4.4+ slotted Action**：新建动作走 `anim_data.action_blok`/layer/strip 新 API，旧的 `action = bpy.data.actions.new()` 直接赋值会报错
4. **J_Bip 局部轴向（实测）**：上臂下放 左绕局部 -Z / 右绕 +Z（`q("z",-s*86)`，s=+1 左/-1 右）；上臂前摆、前臂屈肘、大腿前抬均绕局部 -X；姿态用四元数累乘拼在 pose_bone.rotation_quaternion
5. **动画契约**：30fps；idle 32 帧 LOOP（呼吸：Hips/脊柱小角度正弦，手臂随动，Hips z 位移 0.006）；sit 是**两帧同姿态**静态循环——单帧会被 Godot 压成 0.001s，必须第 0、1 帧插相同关键帧给非零时长；sit 姿态见第 9 条（2026-10-22 世界空间重烘焙，推翻旧「Hips location z=-0.50」写法——那是骨骼局部空间，局部 -Z 实为世界后退，烘出高脚凳畸变）
6. **NLA strip 帧范围必须错开**：多动作 `export_animation_mode="ACTIONS"` 导出时，strip 重叠会互相污染烘焙姿态；idle 占 0–32，sit 推到 40–41
7. 导出：`bpy.ops.export_scene.gltf(export_format="GLB",export_apply=True,export_yup=True,export_animations=True,export_animation_mode="ACTIONS",export_image_quality=90)`
8. Godot 侧 `.import` 确认 `embedded_image_handling=2`（材质内嵌）、`fps=30`；AnimationPlayer 动画库名 `""`，动画名即 idle/sit
9. **摆姿一律用世界空间矩阵（2026-10-22 根因教训）**：骨骼局部轴朝向每根骨都不同，`pose_bone.location/rotation_*` 直接写必踩坑。正确做法：`m = arm.matrix_world @ pb.matrix` 取世界矩阵 → 世界空间改位置/旋转（`Matrix.LocRotScale` 重建）→ `pb.matrix = arm.matrix_world.inverted() @ m` 写回，每步 `bpy.context.view_layer.update()`。坐姿参数实测：髋 z=0.46（大腿 0.409 + 小腿 0.365，髋 rest 0.895）、大腿绕世界 X -90° 水平前伸、小腿 +90° 回竖直、上臂局部 Z 轴 86° 下放后绕世界 X 前 20°、前臂 55° 手搁大腿
10. **导出前必须清场（2026-10-22 根因教训）**：Blender 默认场景的 Cube 会被一起烘进 GLB（三个角色 GLB 曾全部内嵌 2×2×2 可见立方体）；glTF 导入器还会合成 Icosphere 等副产物。烘焙/渲染脚本里统一删非蒙皮网格：`if o.type=='MESH' and not any(m.type=='ARMATURE' for m in o.modifiers): remove`——蒙皮白名单比按名字删安全（role2 狐尾、hero Other 等蒙皮件须保留）
11. **关键帧插入前禁止 frame_set（2026-10-22 教训）**：摆姿→`keyframe_insert(frame=f)` 的循环里若调 `scn.frame_set(f)`，会先用已有关键帧重估姿态、把刚摆好的姿势冲掉，从第二个关键帧起全部变成 f0 静态姿势。`keyframe_insert(frame=f)` 本身就按 f 落键，无需 frame_set
12. **渲染/诊断脚本 fps 必须在导入前设为 30（2026-10-22 教训）**：glTF 导入器按**导入那一刻**的场景 fps 把动画秒数映射成帧；工厂默认 24 而烘焙按 30，导入后再改 fps 不会重映射——`frame_set(45)` 实际采到 t=1.875s 而非 t=1.5s，验收图全是错误时刻的姿势。顺序：`read_factory_settings` → `scene.render.fps = 30` → `import_scene.gltf`。Godot 侧不受影响（按秒读）
13. **新动作从 idle.copy() 起步**：Blender 4.4+ slotted Action 新建 API 不稳；稳妥路线 = `idle.copy()` 改名 → 清空全部 fcurves（`layers→strips→channelbags→fcurves.remove`）保留 slot 结构 → `ad.action = act; ad.action_slot = act.slots[0]` → 摆姿 keyframe_insert
14. **表情基零资产方案**：VRM 烘焙 GLB 的 Face 网格自带 72 个 morph target（Fcl_ALL/BRW/EYE/MTH/HA 全套 + VRC 口型），Godot 直接 `mi.find_blend_shape_by_name("Fcl_EYE_Close")` + `set_blend_shape_value` 驱动，无需任何资产改动（见 char_lively.gd）
15. **NLA 污染根治（2026-10-22 教训，取代 stash 法）**：`stash()` 建的未静音 NLA 轨会在关键帧间隙 HOLD 外推、污染后续动作（aim 烘完 walk 全带端枪手）。对策 = 导入 GLB 后**立即删全部 NLA 轨**（`for tr in list(ad.nla_tracks): ad.nla_tracks.remove(tr)` + `ad.action=None`），新 action 一律**不 stash**——`ACTIONS` 导出模式不需要 NLA 轨。配合第 13 条 idle.copy 起步即可
16. **替换 GLB 后必须重导入（2026-10-22 教训）**：覆盖 `godot/assets/` 下 GLB 后，Godot 运行时**不会自动重导入**，仍读 `.godot/imported` 旧缓存（症状：`Animation not found: "aim"` 连环空引用）。必须先跑一次 `Godot --headless --path godot --import` 再启动游戏
17. **Godot 天空环境下金属材质偏蓝（2026-10-22 教训）**：metallic ≥0.7 的材质会镜面反射环境天空，在舱内第一视角反出突兀亮蓝（转向柱曾是视觉正中央一根亮蓝柱子）。**内饰金属件 metal ≤0.25、rough ≥0.5**（钢台面/罐头定版 0.25/0.55、0.2/0.5），靠浅灰基色而非金属度表达"金属感"；Blender Workbench 预览看不出来，必须 Godot 窗口截帧验收
18. **Quaternius 官网下载被墙时的镜像直链法（2026-10-22 教训）**：quaternius.com 的 Download 按钮实际指向 Google Drive 文件夹（本机 ERR_CONNECTION_TIMED_OUT）。fallback = poly.pizza 官方镜像：PowerShell `Invoke-WebRequest -UseBasicParsing` 抓模型页面 HTML，正则提取 `https://static.poly.pizza/<uuid>.glb` 直链直接下载（本机直连可达，无需浏览器）。同一作者多包混杂，按上传日期甄别包归属（Zombie Apocalypse Kit = 2024-03-17 上传，CC0；2021 年的 Animated Zombie 是 CC-BY 老物）
19. **poly.pizza GLB 的 NLA 前缀动画导出法（2026-10-22 教训，两次翻车定版）**：poly.pizza 下的 GLB 导入 Blender 后动画 stash 在 NLA（16 轨），active action 带 `CharacterArmature|` 前缀。直接删前缀 action 会把 active 一并删掉、`ACTIONS` 模式导出丢全部动画（Godot 里无 AnimationPlayer）；只改裸名也匹配不上带前缀的轨名。定版做法：`short_name(n)=n.split("|")[-1]` **同步**重命名全部 action 与 NLA 轨名（`Idle_Attack`→`Attack` 契约一并完成）→ `arm.animation_data.action = None` → `export_animation_mode='NLA_TRACKS'` 导出
20. **重导入只认 `--import`，游戏模式与 `--editor --quit` 都不可靠（2026-10-22 教训，补第 16 条）**：根因——游戏模式（`-s script`）**只读 `.godot/imported` 缓存，完全不重扫源资产**；`--headless --editor --quit` 看似能触发导入，但 quit 可能早于 import 完成（GLB 大时尤为明显），属不可靠。**唯一稳妥：覆盖 GLB 后先跑 `Godot --headless --import --path godot`（该命令等导入完成才退出），再截帧/回归**。曾因此误判「贴图丢失」三道排查（疑 emission 白洗、疑 UV 塌陷、dumpmat 查材质），最后实锤是 Godot 在读旧缓存——**「GLB 文件正确 + Godot 端表现错」时，先怀疑 import 缓存过期**
21. **以现有动作为底做姿势修正时，应用底姿势后必须立即 `ad.action = None`（2026-10-24 教训）**：`frame_set()` 会用 action fcurves 重算全部 pose，把 `pb.matrix`/`rotation_quaternion` 的手动修改冲掉（`keyframe_insert(frame=f)` 不切帧、不例外）——drive 烘焙时脊柱扳直被静默吞掉两轮才发现（v1/v2 打印的头位置逐字节相同）。正确顺序：`ad.action = sit` → `frame_set(0)` 应用底姿势 → `ad.action = None` 冻结 → 手动改姿势/IK/手型 → bake。IK 约束不受影响（约束随 target 重求解，与 action 无关）
22. **IK target 必须先验可达性（2026-10-24 教训）**：烘焙前量有效臂长（UpperArm head→Hand head ≈ 0.43m，J_Bip 骨骼 tail 不代表关节点，LowerArm tail→Hand head 有 ~11cm gap 是腕关节区）；target 距肩超臂长时 IK 会把手臂拉直仍够不到（drive 前两轮手悬空 15cm 的根因是 sit 髋后移 0.28m、肩距方向盘 0.53m 超臂长）。解法是把髋部在动画里前移（`pb_hips.matrix` 世界空间平移 y-=0.13），不是去够更远的目标。**drive 定版参数**：sit 底 + 髋前移 0.13 + Spine/Chest 各绕世界 X -7° 扳直 + Neck/Head 各 +8° 回正 + 双臂 IK 手腕目标 Blender 世界 (±0.16, -0.22, 1.02)、pole (±0.75, 0.35, 0.40) + 四指绕局部 Z 42/52/38° 半握、拇指 18/22/12° + 呼吸 64 帧（IK target z ±2mm）；车辆侧配合：fig.position=(-0.55,-0.42,-2.85)、rotation.y=PI、播 drive 即可（运行时 TwoBoneIK 方案已废弃删除——IK 修不了 sit 本身的佝偻躯干，且手型跟随 sit 张开）
23. **Blender 里的 Icosphere 不是 GLB 内容，别去"清理"（2026-10-24 教训）**：VRM addon 导入 glTF 时会把 20 个 `physBoneCollider_*` 弹簧碰撞体节点可视化成 Icosphere（42 顶点、±1m），纯 Blender 端产物——GLB 文件内不存在该节点/网格，Godot 端更没有。症状：Blender 里删除后 `ACTIONS` 模式导出，重导入 Icosphere 又出现（导出器重建），误以为"删不掉"。验证法：用纯 glTF 解析（读 JSON chunk 的 nodes/meshes 清单）而非 Blender 重导入来判断 GLB 实际内容。附带教训：备份脚本每次运行覆盖同一备份路径，**重复运行会把原始备份污染成已修改版**——备份前先 `if exists: skip`，GLB 原始版以 git LFS 为准（`git checkout -- path` 恢复）
24. **跨骨架动作重定向：世界空间 delta 旋转法（2026-10-25 验证，KayKit→VRM J_Bip）**：两套骨架都是 T-pose 时逐骨 `delta = src_pose_world_rot @ src_rest_world_rot⁻¹`、`tgt_world_rot = delta @ tgt_rest_world_rot`，用第 9 条 `pb.matrix = arm.matrix_world.inverted() @ m` 写法按**父先子后**写回，每骨写后 `view_layer.update()`；髋骨另写位置 `tgt_rest + (src髋世界位移)×(tgt髋高/src髋高)`。源骨架必须 `frame_set` 采样（第 11/21 条禁令只针对被手改姿势的目标骨架）。**验收用数值不用截图**：逐帧对比两骨架对应肢体段的世界方向向量（upperarm/forearm/thigh/shin 的 head→head 归一化），逐骨 <5° 即对；关节世界**位置**受骨长/比例影响不可直接比（chibi↔写实比例差数倍，位置必然不同）。坑：KayKit 手腕关节名是 wrist（hand 是手掌附件点）、无肩无颈；VRoid 脚掌骨是 ToeBase 不是 Toes；KayKit 宽步幅动作会让 VRM 长外套蒙皮帐篷化（外观取舍，非姿势错误，启用前先带外套渲染验收）。动作源：KayKit Adventurers（CC0，GitHub 免登录克隆，75 个动作内嵌每个角色 GLB）。动作是否齐全以 GLB 实际动画清单为准，不能按角色骨架相同推断

25. **非 T-pose 源动作与动作转移（2026-10-29）**：role1/role2 原本不含 `drive`，本轮从 hero 重定向补齐，逐帧四肢方向误差分别为 0.0343°、0.0°。hero 的 `prone` 来自 TurboSquid 免费 **Soldier prone idle**（作者 imocap，产品 ID 1070018，Royalty Free License，2026-10-29 下载）；该文件只有单个卧姿待机，不是射击/换弹战斗动作包。源骨架 rest 不是 T-pose，不能套第 24 条的 rest delta，改用源/目标 rest 的解剖方向正交基校准，最大四肢方向误差 0.0°；保留原角色网格、材质与绑定
26. **跨骨架重定向三条踩坑定版（2026-10-30，KayKit `2H_Ranged_Aiming`→VRM，四肢段误差 138°→0.025°）**：
    - **非 hips 骨禁止 keyframe location**：首轮给每根骨都插 location 且把骨 head 钉在 rest 世界坐标，父骨旋转后子骨不跟随，四肢恒为 T-pose（max err 138°）。定版：每帧先全部 `matrix_basis=Identity` + `update`，父先子后只写旋转；hips 写 location+rotation，其余骨只 `keyframe_insert("rotation_quaternion")`，head 用传播后真实值 `tarm.matrix_world @ tpb.head`
    - **逐骨 rest 段对齐 qcorr（补第 24/25 条）**：Q 版（KayKit）与写实（VRM）骨架即使同 T-pose，「骨 head→子骨 head」rest 段轴向也不一致，单纯 delta 旋转后脚段仍偏 16.4°。对每根有映射子骨的骨预算 `qcorr = tgt_rest段方向.rotation_difference(src_rest段方向)`，烘焙写 `want_world_rot = delta @ qcorr @ tgt_rest_world_rot`，修后全部段 0.00–0.02°
    - **两阶段采样（单 Blender 会话不能二次 import glTF）**：第二次 `bpy.ops.import_scene.gltf` 报 "Please select a file"。必须 PHASE1 导源骨架、采样全部帧世界矩阵**以及源 rest 段方向**到 dict，`bpy.ops.wm.read_factory_settings(use_empty=True)` 重开场后 PHASE2 导目标烘焙——重开场后源 Object 的 StructRNA 已释放，PHASE2 再引用源 armature 必崩 ReferenceError
    - VRoid 双手手指局部卷曲轴同向（均局部 +Z），镜像骨不需要反号；实握据枪屈角定版：指节 0.85/1.15/0.95、拇指 0.35、Thumb1 额外绕 Y 0.45 对握

### 4.2 截帧验收法

- Godot headless（dummy 渲染器）**不能截图**，必须窗口模式跑 SceneTree runner：`godot --path godot -s res://tmp_shot.gd`
- **窗口模式 `--script` 失灵（2026-10-22 未解，已绕开）**：窗口模式 `-s res://x.gd` 只打印 banner 立即 exit 0、`--verbose` 重定向日志全空。动画/姿态验收改用 **Blender Workbench 渲染**：STUDIO + OBJECT 着色、角色灰 0.7 + 绿地板 + 红参照坐垫盒（顶 z=0.40），540×720 侧视/前 3/4 视双机位，镜头对准 `cam.rotation_euler = (Vector(target)-Vector(pos)).to_track_quat('-Z','Y').to_euler()`；玩法验收仍走无头回归
- 截图要在 `_process` 里延迟到第 50 帧以后（等 GLB 实例化/动画首帧/seek 生效），`root.get_texture().get_image().save_png(globalize_path(...))`
- runner 里调 main.gd 自定义方法返回 Variant，`:=` 推断会报 Cannot infer type，须显式 `var x: float = main.road_x(z)`
- 接地/尺寸用 AABB 实测：实例化后合并全部 MeshInstance3D 的 `global_transform * get_aabb()`，确认 min.y≈0、身高米数；正交顶视会被车顶（顶棚盒 y=2.2）遮挡，穿模检查用坐标严格核对而非顶视图
- 尸群维持 Q 版方案：现有四档材质染色 + 2–3 套服装变体 + 随机身高，不换 VRM 写实基底

## 5. 立绘生成方法论（Seedream）

- 工具：`.agents/skills/byted-ark-seedream-skill`，Key 在用户环境变量 `ARK_API_KEY`；在 skill 根目录跑 `node scripts/generate.js`
- 尺寸：全身立绘统一 `1728x2304`（3:4，与现有立绘一致），`--output_format jpeg --watermark false`
- 审核产物先存临时目录（`%TEMP%\zw_portraits`），人工/目检合格后再覆盖 `godot/assets/portraits/`，不先生成进正式目录
- 提示词模板（写实电影感游戏立绘，全身必须入镜）：
  `末日生存游戏角色全身立绘，写实电影感画风。<年龄人种性别身份>，<发型发色/五官/神情>；<内搭/外套/下装/鞋/随身物，做旧磨损>；<站姿与手部>，全身构图，从头到脚完整入镜，双脚必须在画面内。背景是<废弃公路/废墟>，<光线>，浅景深。写实人体比例，细腻皮肤与布料磨损质感，游戏宣传立绘品质`
- 关键约束词不可省：「全身构图」「从头到脚完整入镜」「双脚必须在画面内」，否则 3:4 易切脚
- 风格锚定现有最合格的一张（叶澜 d_ye_lan.jpg：废墟背景 + 暖光 + 写实比例）；服装必须符合末世生存设定，拒绝时装礼服风（旧 c_black/b_white 的问题；苏薇立绘已从 b_white 换成 a_office 干练 OL 套装，仍保「黑高跟踩废墟」人设）
- 角色外观要与游戏内 3D 模型、`data/survivors.json` 人设三方一致

## 6. 授权与署名

- 每个外部下载资产记录：来源 URL、作者、授权类型、下载日期，写入提交信息或 decisions.md
- CC-BY 资产统一在游戏 credits 页署名（待建）；不确定授权的一律不用

## 7. 验收清单（每次美术改动必过）

1. `bunx tsc --noEmit`（若触及 Web 侧）；Godot 侧无头回归：
   `& <godot.exe> --path godot --headless --quit-after 300 2>&1 | Select-String "SCRIPT ERROR|Parse Error|ERROR"`
   基线噪声只有 dummy 渲染器的 `Parameter "material" is null.`，EXIT=0 且无新增即通过
2. **窗口截帧**（SceneTree runner，1280×720）：新资产至少截「追尾远景 / 近景相遇 / 车内视角」三张，目检比例、朝向、材质、动画姿态
   - runner 写法见 progress.md n25：真实 delta 累加（窗口无 vsync）、`get_viewport().get_texture().get_image().save_png`
3. 玩法实跑确认：刷怪/拾取/招募触发盒未因模型替换失效（碰撞是外挂的，理论不受影响，但必须眼见）
4. 临时 runner 脚本/截图用后即删；`localStorage.clear()`（Web 侧）排除旧存档干扰
5. git 提交：英文 conventional commits；glb + 贴图 + 自动改写的 .import 一并提交
