# 111

一个还没定用途的仓库。

**状态：占位。** 项目定位、技术栈、目标用户都还没定，等想清楚再回填下面「这是什么」一节。在那之前，这里只放骨架和协作约定，不写假装知道用途的内容。

## 这是什么

- 一个等待被填内容的骨架：`src/` 目前是空的
- 一批工程协作约定的落脚点：issue tracker、标签词汇、域文档布局（见 [约定](#约定)）

## 这不是什么

- 还不是任何具体产品的代码
- 没有构建工具、没有依赖、没有 CI

## 目录结构

```
/
├── AGENTS.md            ← agent 读的仓库配置入口（issue tracker / 标签 / 域文档路径）
├── README.md
├── .gitignore           ← 覆盖 macOS/Windows、编辑器、Node/Python/通用产物
├── docs/
│   └── agents/          ← 配置正文：issue-tracker.md、triage-labels.md、domain.md
└── src/                 ← 源码，等技术栈定了再填
```

## 约定

### Issue

工作项都开在 GitHub Issues，用 `gh` 管理，不另建 TODO 文件。建票、读票、父子票、阻塞边的写法见 [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)。

### 标签

分流只用五个角色标签：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`，字符串与角色同名。探索地图及其子票只带 `wayfinder:*` 标签（`map` / `research` / `prototype` / `grilling` / `task`），不混入分流标签。映射见 [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md)。

### 域文档

本仓库按 **multi-context** 布局记录领域词汇：根目录 `GLOSSARY-MAP.md` 指向各上下文自己的 `GLOSSARY.md`，系统级架构决策放 `docs/adr/`。这两个文件现在都还不存在，留给第一次真正写下词条时由 `/domain-modeling` 创建。消费规则见 [`docs/agents/domain.md`](docs/agents/domain.md)。

## 下一步

1. 定下这个仓库到底做什么，替换「这是什么」一节
2. 按选定技术栈补骨架（`package.json` / `pyproject.toml` 等）和 `.gitignore` 对应条目
3. 开第一张 issue，或用 wayfinder 开第一张探索地图

## 本地开发

暂无构建与运行方式。技术栈定了以后在这里补：怎么装、怎么跑、怎么测。
