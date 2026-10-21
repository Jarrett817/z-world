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
- **原点与朝向**：模型原点在双脚中心（地面 y=0）；角色/僵尸面朝 **-Y**（Godot 公路行进方向为 -Z，进引擎后在实例上统一旋转，Blender 内保持 glTF 习惯 -Y forward）
- **命名**：网格 `geo_<物>_<件>`、骨骼 `rig_<物>`、材质 `mat_<物>_<部位>`；Blender 控制器（圆环/自定义形状）导出前必须剔除（丧尸脚本现按尺寸启发式删除，新资产应在 Blender 侧直接清理，不把垃圾带进 glb）
- **修改器**：导出前应用非形变修改器（Solidify/Bevel/Boolean）；Armature 保留为骨骼形变
- **贴图**：baseColor ≤1024（主角/大件可 2048），MR/normal ≤512/1024，JPEG 85（透明才 PNG）；文件名 `<glb名>_<材质>_baseColor.jpg` 与现有包保持一致，Godot 会自动同名识别
- **glTF 导出设置**：GLB 单文件、+Y up 由 glTF 标准保证、应用修改器、包含 UV/法线/切线、材质 PBR metallic-roughness；不压缩、不嵌入多余动画数据
- **导出脚本化**：能写 bpy 脚本就不点菜单（`bpy.ops.export_scene.gltf(export_format='GLB', ...)`），脚本保留在本次任务上下文中便于重导

## 3. Godot 导入与实例规范

- glb 放 `godot/assets/<分类>/`；导入器默认开 LOD/阴影网/tangent，保持默认即可
- **贴图压缩**：Windows/S3TC 首次导入会自动生成 `.s3tc.ctex` 并改写 `.import`（VRAM compress/mode=2），这类自动改写与 glb 一起提交，避免干净环境首次运行卡顿
- **源文件必须入库**：只允许 `.godot/imported` 缓存存在、`.import` 指向的 glb 本体缺失是事故（本次发现 `zmb_stand_g.glb` 就是此状态）。修复方式：补回本体，或删除引用改代码
- **动画名契约**：角色/丧尸动画统一 `Walk`（LOOP_LINEAR）/ `Attack` / `Death`，脚本按名字取 AnimationPlayer 轨道；换模型不改脚本
- **实例 scale 契约**：丧尸当前实例 scale 0.058–0.072（源模型约 25m 高的历史遗留），新做的角色按真实米数建模后，在 spawn 处显式 scale=1.0，不再沿用怪比例
- 碰撞不用 glb 内三角面：RigidBody/StaticBody 外挂 Capsule/Box 碰撞（现有 spawn 代码已是此模式，保留）

## 4. 角色方案：共享骨架 + 模块化换装

5 名队友 + 路边幸存者 + 车内队友是同一批人的不同出现位置，**一套骨架一套动画，外观靠服装/发型/配件区分**：

- 骨骼只做一套人形（Humanoid 骨名：hips/spine/neck/head/shoulder/elbow/hand/hip/knee/foot），T-pose 绑定
- 外观差异件：上衣/外套/裤子/鞋/发型/随身物（林晚医药箱、陈默腰包、叶澜相机、唐棠红绷带+马尾、苏薇手提包），各自独立网格挂同一骨架
- 动画：Idle / Walk / Wave（路边求救）/ Sit（车内）/ Drive（驾驶位），丧尸专用 Walk / Attack / Death 不与人类混用
- 路边幸存者（survivor.gd）与车内队友（main.gd `_make_crew_figure`）加载同一角色 prefab 的不同姿态动画，删除全部方块拼装代码
- 尸群复用同一丧尸骨架，差异靠现有四档材质染色 + 2–3 套服装网格变体 + 随机身高，维持海量同屏廉价感

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
