# 111

一个安卓 APK 小游戏项目。

**状态：起步。** 定位已定（安卓小游戏），玩法、引擎/技术栈、目标用户还没定，本文档随进展回填。

## 这是什么

最终产物是一个能装到 Android 手机上的 `.apk`：玩家拿到的是安装包，不是网页或桌面程序。

- **玩法与题材**：待定，还没想清楚玩家在玩的是什么
- **引擎 / 技术栈**：待定（Android 原生 Kotlin、Godot、Unity、Cocos 等都可能，选型理由以后记进 `docs/`）
- **规模**：小游戏，一个人能完整维护的量级
- **现状**：刚起步，`src/` 还是空的
- 同时也是本仓库协作约定的落脚点（issue tracker、标签词汇、域文档布局，见 [约定](#约定)）

## 这不是什么

- 还不是任何具体产品的代码
- 没有构建工具、没有依赖、没有 CI

## 目录结构

```
/
├── AGENTS.md            ← agent 读的仓库配置入口（issue tracker / 标签 / 域文档路径）
├── README.md
├── .gitignore           ← 通用条目 + Godot（.godot/、build/、*.apk）
├── project.godot        ← Godot 工程入口
├── export_presets.cfg   ← Android 导出配置（debug 签名）
├── scenes/main.tscn     ← 主场景；世界在 `scripts/main.gd` 里用代码搭
├── scripts/
│   ├── main.gd          ← 相机 / 6 地块 / 单指点选 / HUD
│   ├── balance.gd       ← 全部数值（成熟时间、价格、初始金币…）
│   └── save_manager.gd  ← 原子写存档（tmp → rename，保留 .bak）
├── assets/models/       ← M2 的 8 个 .glb（Blender 脚本生成）
├── build/               ← APK 与截图，已 gitignore
└── docs/                ← spec.md、screenshot、agents/ 配置
```

## 约定

### Issue

工作项都开在 GitHub Issues，用 `gh` 管理，不另建 TODO 文件。建票、读票、父子票、阻塞边的写法见 [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)。

### 标签

分流只用五个角色标签：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`，字符串与角色同名。探索地图及其子票只带 `wayfinder:*` 标签（`map` / `research` / `prototype` / `grilling` / `task`），不混入分流标签。映射见 [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md)。

### 域文档

本仓库按 **multi-context** 布局记录领域词汇：根目录 `GLOSSARY-MAP.md` 指向各上下文自己的 `GLOSSARY.md`，系统级架构决策放 `docs/adr/`。这两个文件现在都还不存在，留给第一次真正写下词条时由 `/domain-modeling` 创建。消费规则见 [`docs/agents/domain.md`](docs/agents/domain.md)。

## 下一步

玩法、引擎、数值、资产、存档、里程碑已经定死在 [`docs/spec.md`](docs/spec.md)（一次完整 grill 的结论）。按三个里程碑顺序推进，**不绑日期**——里程碑是门槛，不是期限：

1. [#1 M1 端上跑通](https://github.com/000saber000/111/issues/1)：Godot 工程 + 6 地块 + 点选 + 导出 APK 装机
2. [#2 M2 闭环打通](https://github.com/000saber000/111/issues/2)：种植/生长/收获/金币 + 离线结算 + 8 个资产
3. [#3 M3 打磨与验收](https://github.com/000saber000/111/issues/3)：音效/反馈/横屏 UI/真机稳定

## 本地开发

**环境**（都在这台机器的 D 盘，C 盘只用到你原有的 Android SDK）：

- Godot 4.7.2：`D:\Godot\Godot_v4.7.2-stable_win64.exe`（自包含模式，配置与导出模板在 `D:\Godot\editor_data`，不写 C 盘 AppData）
- Android SDK：`C:\Users\rongyao\AppData\Local\Android\Sdk`（导出用 build-tools 36.1.0）
- debug keystore：`D:\Godot\android\debug.keystore`（`storepass` / `keypass` 均为 `android`）

**打开工程**：用上面的 Godot 直接打开本目录。

**桌面跑**：

```bash
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path .
```

调试参数（无人值守验收用）：`-- --tap=640,470 --shot=res://build/shot.png` 会模拟一次点击并截图。

**导出 APK**：

```bash
"D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-debug "Android" build/xiaonongchang.apk
```

**装到手机**（手机先开 USB 调试并连上）：

```bash
"C:\Users\rongyao\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r build/xiaonongchang.apk
```

**存档位置**：手机上是应用私有目录；桌面调试时在 `%APPDATA%\Godot\app_userdata\小农场\save.json`。

![M1 桌面截图](docs/screenshot-m1.png)
