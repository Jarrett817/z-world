# AGENTS.md

本文件是 AI 编码助手在本项目工作的**强制规范**。所有规则必须遵守，无一例外。

## 项目一句话

末日生存游戏「末世：我要当救世主」——**Godot 4.7 + GDScript**，全代码工作流（零编辑器依赖），JSON 数据驱动。PC 单机 3D：线性公路驾驶 + 下车战斗 + 营地经营 + 剧情。

工程根目录：`godot/`（场景 `godot/main.tscn`，入口 `godot/scripts/main.gd`，数据 `godot/data/*.json`，资产 `godot/assets/`）。

## 铁律：最小可靠改动

1. **只做被要求的事**——不多做、不少做。修 bug 不顺手"优化"周边代码，加功能不附带"顺手重构"
2. **优先编辑现有文件**，禁止随意新建文件；禁止主动创建 README/文档（用户明确要求除外）
3. **禁止冗余验证逻辑**：不写防御不可能发生的场景的代码；信任内部代码与引擎保证，只在系统边界（用户输入、外部文件）做校验
4. **禁止过度抽象**：不为一次性操作造 helper/util/抽象层；三行相似代码好过 premature abstraction；不为假想的未来需求设计
5. **禁止冗余文件与中间产物**：不留草稿、测试脚本、调试输出在项目里（临时脚本/导出产物放 `%TEMP%`，用后即删）
6. **无 backwards-compatibility 包袱**：确认没用的代码直接删，不留 `_unused` 变量、re-export、"// removed" 注释

## 铁律：成熟资产优先

**写任何功能前，先查网上免费开源的现成资产/库。禁止手写引擎或插件已能做的东西。**

- 3D 模型/动画优先用 `godot/assets/` 现有 GLB 与 `godot/assets/props/scene_models/`，不足再走资产管线
- 角色/丧尸模型统一 GLB（VRM 需经 Blender 管线转换，见 `docs/art-pipeline.md`）
- 例外：游戏核心状态机、无限公路流式生成这类强领域逻辑可以自研，但保持极简

## 视觉规范

- 美术基调：**明媚末日**——蓝天白云、阳光明亮、草木葱郁、水面清澈、远处高楼废墟，风景本身是好的，威胁来自丧尸而非天气
- 场景全部代码生成（`ArrayMesh`/`BoxMesh`/`StandardMaterial3D` 等），不依赖在编辑器里摆场景
- 材质颜色直接写在生成代码或数据 JSON 中；程序化材质允许做旧/随机变化
- 禁止在画面上暴露引擎、插件或技术栈信息

## 代码规范

- GDScript 4.x：静态类型标注（`var x: int`、函数参数返回值），tab 缩进
- 可复用逻辑抽成独立脚本（如 `char_util.gd`），单一职责，文件不过长
- 游戏状态以 `main.gd` 为唯一中心；HUD/子节点通过持有 main 引用读写，不引入第二套状态源
- 数值/文案只改 `godot/data/*.json`，不硬编码进逻辑
- preload 资源用常量集中在文件头部

## 工作流

1. 改代码 → 2. Godot 无头回归通过（零新增错误）→ 3. 立即 `git commit`
4. commit 后立即 push；**push 失败（GitHub SNI 阻断 / Connection reset）不硬重试**，告知用户开 VPN 后再试
5. commit message：英文、conventional commits 风格（feat/fix/chore/docs）
6. 重要决策与进度沉淀到 `docs/decisions.md` 与 `docs/progress.md`——轻量记录，不堆砌

### Godot 无头回归（唯一验证手段）

```powershell
& "C:\Users\Jarrett\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --headless --path d:\Projects\z-world\godot --quit-after 120
```

- **EXIT=0 即通过**。dummy 渲染器噪声 `ERROR: Parameter "material" is null.` 是已知唯一允许的基线噪声
- 新增脚本/资源后首次运行会自动导入，属正常输出
- 视觉改动需要截帧验收时，另行用窗口模式跑场景确认

## 资产管线（详见 docs/art-pipeline.md）

- VRM→GLB：Blender 后台脚本烘焙（idle/sit 等动画、glTF 正面朝 +Z、脚底 y=0）
- 立绘/2D：Seedream skill，先存 `%TEMP%` 目检合格再覆盖正式目录
- 二进制大文件（GLB/VRM/图片/音频）走 git LFS
- PowerShell 下 commit message 含多行时用多个 `-m` 参数（heredoc 会报 ParserError）

## 项目特定禁忌

- **禁止复活已废弃的 Web（Phaser/React/Vite）时代任何文件与工作流**（该工程已整体删除）
- 存档/配置 key 变更必须考虑旧数据清理
- 丧尸是"好风景里的威胁"：不要靠永久阴雨/灰雾营造末日感，恶劣天气只是偶发天气

## 沟通

- 全程中文
- 回复简短直接：先说结论/动作，不复述需求，不写客套话
- 报错时给根因 + 修复，不给流水账
