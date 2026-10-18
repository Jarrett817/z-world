# AGENTS.md

本文件是 AI 编码助手在本项目工作的**强制规范**。所有规则必须遵守，无一例外。

## 项目一句话

末日生存游戏「末世：我要当救世主」——Phaser（地图场景）+ React 19（UI）+ Vite + TypeScript，JSON 数据驱动，全代码工作流，零编辑器依赖。

## 包管理：必须用 Bun

- 安装依赖：`bun install` / `bun add <pkg>` / `bun add -d <pkg>`
- 跑脚本：`bun dev` / `bun run build`
- 跑二进制：`bunx <cmd>`（替代 npx）
- **禁止**使用 npm / pnpm / yarn 的任何命令

## 铁律：最小可靠改动

1. **只做被要求的事**——不多做、不少做。修 bug 不顺手"优化"周边代码，加功能不附带"顺手重构"
2. **优先编辑现有文件**，禁止随意新建文件；禁止主动创建 README/文档（用户明确要求除外）
3. **禁止冗余验证逻辑**：不写防御不可能发生的场景的代码；信任内部代码与框架保证，只在系统边界（用户输入、外部 API）做校验
4. **禁止过度抽象**：不为一次性操作造 helper/util/抽象层；三行相似代码好过 premature abstraction；不为假想的未来需求设计
5. **禁止冗余文件与中间产物**：不留草稿、测试脚本、调试输出在项目里
6. **无 backwards-compatibility 包袱**：确认没用的代码直接删，不留 `_unused` 变量、re-export、"// removed" 注释

## 铁律：成熟库优先

**写任何功能前，先查现成库。禁止手写已有成熟实现的东西。**

- 状态管理、日期处理、动画、表单、校验……一律先想"哪个库干这个"
- 本项目 UI 组件用 **shadcn**，动画用 **react motion**，样式用 **Tailwind CSS**
- 引入新库前确认：维护活跃、体积合理、与现有栈兼容
- 例外：游戏核心状态机这类强领域逻辑可以自研，但保持极简

## 样式规范

- **只用 Tailwind CSS**，禁止手写 CSS 文件（`src/index.css` 仅存 Tailwind 入口与全局重置）
- 颜色用项目色板：`#e8862e`（篝火橙 accent）、`#2a2320`（面板）、`#161210`（背景）、`#e8ded2`（主文字）、`#8a7d6d`（次文字）
- 禁止在页面上暴露技术栈信息

## 组件规范

- 合理拆分与复用：可复用的组件、hooks、utils 必须抽出来，放对应目录
- 组件单一职责，文件不过长
- 游戏状态桥接统一走 `useSyncExternalStore(Game.subscribe, Game.getState)`，不引入第二套状态流

## 工作流

1. 改代码 → 2. `bunx tsc --noEmit` 通过（零新增错误）→ 3. 立即 `git commit`
4. commit 后立即 push；**push 失败（GitHub SNI 阻断 / Connection reset）不硬重试**，告知用户开 VPN 后再试
5. commit message：英文、conventional commits 风格（feat/fix/chore/docs）
6. 重要决策与进度沉淀到 `docs/decisions.md` 与 `docs/progress.md`——轻量记录，不堆砌

## 项目特定禁忌

- **禁止 React StrictMode**：双挂载会重复创建/销毁 Phaser.Game 实例导致崩溃
- 排查交互异常前，先 `localStorage.clear()` 排除旧存档干扰
- 游戏数值/文案只改 `src/data/*.json`，不硬编码进逻辑
- 存档 key 变更必须同步 `SaveManager` 并考虑旧档清理
- **禁止**复活 Cocos 时代的任何文件与工作流（该项目已整体废弃）

## 沟通

- 全程中文
- 回复简短直接：先说结论/动作，不复述需求，不写客套话
- 报错时给根因 + 修复，不给流水账
