# 交接 · 小农场 M3 实现完成，待真机验收与关票

> 给一个没有本次会话记忆的 agent。读完这份 + 下面三份引用文档，就能接着干，不需要回翻对话。
> 生成：2026-11-05 13:10（Asia/Singapore）

## 你要接着干什么

**把 M3 收尾**：M3 的四项实现（应用图标 / 收获反馈 / 音效 / 横屏 UI）已经做完、桌面验收通过、APK 已导出；只剩

1. **真机连续 5 分钟稳定性验收**（下面的清单）；
2. **把 APK 发给 1–2 个朋友，收到至少一条反馈**（spec 的 M3 交付项，需要人做）；
3. 回来后把验收结果贴进 [#3](https://github.com/000saber000/111/issues/3) 并关票。

## 必读（按这个顺序，别跳）

1. [docs/spec.md](../../docs/spec.md) —— 21 条已定结论、数值表、M3 验收标准。**唯一的规格真相**，实现可以变，取舍不要悄悄改。
2. [docs/handoff-M2.md](../../docs/handoff-M2.md) —— 环境路径、导出/装机/截图命令、8 条踩坑清单、M2 验收记录。**本文不重复**，只给增量。
3. [docs/agents/issue-tracker.md](../../docs/agents/issue-tracker.md) —— `gh` 建票/挂依赖/评论/关票写法。
4. [AGENTS.md](../../AGENTS.md) —— 仓库约定入口。

## 一句话现状

- 分支 `main`，M1、M2 已真机验收并关闭；`#3` 已被认领（assignee 000saber000），实现 + 桌面验收 + **真机 5 分钟稳定性都通过**，**没关票**——只差朋友试玩反馈（spec 的 M3 交付项，要人做）。
- APK：`build/xiaonongchang.apk`（约 28.6 MB，`com.saber.farm`，arm64-v8a，debug 签名，已带自适应图标与三套音效），已装在那台 HONOR AMP-AN00 上。
- 桌面截图：`docs/screenshot-m3-empty.png`、`-growing`、`-mature`、`-harvest`、`-offline`；真机截图：`-device`、`-device-offline`、`-device-soak`、`-device-empty`。

## 本次 M3 交付（代码）

| 文件 | 做了什么 |
| --- | --- |
| `scripts/farm_logic.gd`（新） | **纯规则模块**：`apply_offline` / `tick_growth` / `plant` / `harvest` / `counts` / `state_of`。不碰节点、不碰时钟，`main.gd` 把地块数据与当前时间喂进来 |
| `tests/run_tests.gd`（新） | farm_logic 的**无头测试**，36 条断言（离线封顶 8 小时、600 秒成熟、种子 20/卖 45、状态计数、时钟回拨） |
| `scripts/main.gd`（改） | 改调 FarmLogic；收获动效（作物弹跳缩小、+45 跳字、2D 金币小圆点飞向 HUD、金币数弹一下、轻微镜头震动）；音效池（种植/收获/金币各 2 个声部，避免连点截断）；HUD 重做（金币大数字、常驻价格牌「种子 -20 · 收 +45」、地块状态、情境提示条）；每块生长中的地一条 3D 进度条；空地显示「+」；离线回来提示；切后台/退出时保存 |
| `scripts/balance.gd` | 未改（数值仍以 spec 为准） |

## 本次 M3 交付（资产与工具）

| 文件 | 说明 |
| --- | --- |
| `tools/icon/generate_icon.py` | Pillow 画图标，4× 超采样 + LANCZOS，可重跑 |
| `assets/icon/icon.png` | 1024×1024 工程主图标（`application/config/icon`） |
| `assets/icon/icon_192.png` | 192×192 传统启动图标（`launcher_icons/main_192x192`） |
| `assets/icon/adaptive_foreground_432.png` | 自适应前景（RGBA，主体在安全区内） |
| `assets/icon/adaptive_background_432.png` | 自适应背景（天空 + 草地，无太阳） |
| `tools/audio/generate_sfx.py` | 纯标准库合成 3 个 wav，自带校验与 ASCII 包络打印 |
| `assets/audio/plant.wav` / `harvest.wav` / `coin.wav` | 22050 Hz / 16-bit / 单声道，峰值 −3 dBFS，140/280/200 ms |

`project.godot` 加了 `config/icon`；`export_presets.cfg` 三行 `launcher_icons/*` 指向上面四个图标。导出日志里已经没有 `No project icon specified`。

## 验证命令（桌面，无需手机）

```bash
# 无头规则测试（36 条，全过才退出 0）
"D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/dsh project/111" \
  --script res://tests/run_tests.gd

# 无人值守截图（windowed，截完自己退出；不会写存档）
"D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --path "D:/dsh project/111" -- \
  --fresh --mute --shot="res://build/m3-empty.png"
# 摆好场景再截：demo = plant | growing | mature | harvest
"D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --path "D:/dsh project/111" -- \
  --fresh --mute --demo=harvest --shot="res://build/m3-harvest.png" --shot-frame=12

# 导出 APK（注意：Godot 要 spawn keytool/apksigner，见坑 1）
"D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/dsh project/111" \
  --export-debug "Android" "D:/dsh project/111/build/xiaonongchang.apk"
```

调试参数全表：`--shot=path`、`--shot-frame=N`、`--fresh`、`--demo=plant|growing|mature|harvest`、`--tap=x,y`、`--mature`、`--mute`。`--shot` 与 `--fresh` 会自动关闭存档写入（截图不污染玩家档）。

## 真机验收（已通过，2026-11-05）

> 手机：HONOR AMP-AN00（Android 16，1224×2700 竖屏；横屏坐标 2700×1224）。无线调试端口每次重连都会变，**向用户要当前的「IP:端口」**（本次是 `172.30.102.249:42689`，下次会变）。

```bash
ADB="C:/Users/rongyao/AppData/Local/Android/Sdk/platform-tools/adb.exe"
"$ADB" connect <ip>:<port>
"$ADB" install -r "D:/dsh project/111/build/xiaonongchang.apk"
"$ADB" shell monkey -p com.saber.farm -c android.intent.category.LAUNCHER 1
"$ADB" exec-out screencap -p > "D:/dsh project/111/build/x.png"
```

**横屏点击坐标（2700×1224，本次实测可用）**：

| 目标 | 坐标 |
| --- | --- |
| 6 块地（上排 3 / 下排 3） | `1061 476` / `1343 476` / `1625 476`；`1061 782` / `1343 782` / `1625 782` |
| `DEBUG: 立刻成熟` | `258 915` |
| `DEBUG: 回拨 2 小时` | `258 1003` |
| `DEBUG: +100 金币` | `258 1091` |

逐条结果：

- [x] 冷启动不崩，正常横屏；APK 里确认有各密度启动图标 + 自适应图标（`aapt2 dump badging`：`application-icon-160…640` 都指向 `res/mipmap-anydpi-v26/icon.xml`）
- [x] 点空地：金币 −20、出现种子与生长进度条、提示「种下 #N（−20）」；点生长中的地：跳字显示剩余时间
- [x] `DEBUG: 立刻成熟`：6 块全熟、状态行「成熟 6」
- [x] 点成熟地块：金币 +45、`+45` 跳字、金币圆点飞向 HUD、金币数弹一下、提示「收获 #N（+45）」（截图 `docs/screenshot-m3-device.png`）
- [x] 真机启动时离线结算生效：真实存档离线 38 分钟回来 → 6 块全熟 + 「离线 38 分钟 · 回来啦，6 块熟了」（截图 `docs/screenshot-m3-device-offline.png`）
- [x] 切后台（HOME）再回前台：状态保持
- [x] **连续 5 分钟 35 轮 种→立刻成熟→收 循环**（期间 2 次切后台/回前台）：无崩溃、无 ANR、logcat 无应用报错；PSS 基线 389.8 MB → 全程 394–397 MB（末次 395.3 MB），无泄漏趋势；截图 `docs/screenshot-m3-device-soak.png`
- [x] 杀进程/重开：金币与地块状态正确（存档持久化；`pid` 变化但数据一致）

真机截图：`docs/screenshot-m3-device.png`、`-device-offline.png`、`-device-soak.png`、`-device-empty.png`。

> 注：`adb` daemon 在长会话里偶尔会掉（`cannot connect to daemon`），`adb start-server` 后 `adb connect <ip>:<port>` 重连即可；期间失败的 `input tap` 不会生效，重连后补点就行。


## 环境（全在 D 盘，沿用 M2）

| 东西 | 路径 |
| --- | --- |
| Godot 4.7.2 编辑器 | `D:\Godot\Godot_v4.7.2-stable_win64.exe` |
| Godot 控制台版（导出用） | `D:\Godot\Godot_v4.7.2-stable_win64_console.exe` |
| 自包含数据 | `D:\Godot\editor_data\` |
| Android 导出模板 | `D:\Godot\editor_data\export_templates\4.7.2.stable\android_debug.apk` |
| debug keystore | `D:\Godot\android\debug.keystore`（密码 `android`，别名 `androiddebugkey`） |
| Android SDK | `C:\Users\rongyao\AppData\Local\Android\Sdk`（build-tools 36.1.0；adb 在 platform-tools） |
| Blender | `D:\Blender\blender.exe`（4.5.14 LTS） |

## 新踩的坑（M2 的 8 条之外）

1. **沙箱里导出 APK 会失败**：`CreatePipe ... ERR_CANT_FORK` + `校验密钥库用户名密码时出现问题`。原因是 Godot 导出要 spawn `keytool` / `apksigner`，受限沙箱不允许建可继承管道。用普通终端，或给这一条命令放宽权限（本次用 full access 跑通）。
2. **windowed 进程不加 `--shot` 不会自己退出**：跑真机前想跑桌面循环一定要带 `--shot` 或自己 `timeout`/杀进程，否则会一直挂着一个窗口，把后续命令排住。
3. **新增 `class_name` 后必须先 `--import` 一次**：否则 `.godot/global_script_class_cache.cfg` 没登记，`--headless --script` 测试会报 `Identifier "FarmLogic" not declared`。同理新增 wav/png 后不 import，`ResourceLoader.exists` 为 false、导出也拿不到资源。
4. **`docs/` 目录的 Windows 权限不吃沙箱**：受限 shell 里 `cp` 进 `docs/` 会被拒（`sandbox: file access denied under workspace-write mode`），但 DSH 的写文件工具可以；二进制截图用一次放宽权限的命令复制即可（本次已复制）。
5. **素材重跑**：`python tools/icon/generate_icon.py`、`python tools/audio/generate_sfx.py` 都是确定性的，改完跑一遍再 `--import` + 重新导出。
6. 音效是脚本合成的，音色是「数值验证过、没经过耳朵」的：种植音偏低频，手机小喇叭靠谐波和土层噪声出来。如果真机听着闷/听不见，改 `tools/audio/generate_sfx.py` 的配方（加中频层或提高 200–800 Hz 能量）再重跑，不要直接改 wav。

## 没做 / 留给下一个会话

- [x] 真机 5 分钟稳定性（已通过，记录见上一节）
- [ ] 朋友试玩反馈（spec 的 M3 交付项，需要人）
- [ ] 收到反馈后把结果贴进 #3、关票
- 规格里没要求的（不枯萎、不做人物、不联网、不上架）继续不做，别扩scope。

## 代码评审（/code-review）结论与处理

两轴各跑了一个独立 sub-agent（对照 `HEAD=86c8e38`）：

**Standards（无硬性违规，只有 judgement call）**，已顺手处理：
- `--mute` 死代码 + 二次扫参数 → 改成 `_mute` 成员变量、删掉 `_mute_audio()`。
- `var _frames` 声明在文件中间 → 移到成员变量区。
- 重复的颜色字面量 → `const BAR_GROW`；音效音量字面量 → `SFX_VOL_*` 常量。
- 重复的 `String(plot.get("state", ...))`（5 处）→ FarmLogic 暴露 `state_of()`，main.gd 统一调用。
- `_build_plot_bar(plot, x, z)` 没用到的参数与没人读的 `bar_bg` → 删掉。
- `if _persist: SaveManager.save_data(...)` 重复 → 统一走 `_save()`。
- 注释缩进、`_show_crop` 与 mature 分支风格不一致 → 统一。
- 未改（judgement）：`tests/` 里故意用 "empty"/"growing"/"mature" 字面量而不是 `FarmLogic.STATE_*`——这是存档 schema 的独立事实来源，引用实现常量会让断言变成同义反复（测试文件里已写注释）；Python 生成器注释是英文（新工具、仓库没有 Python 风格约定）；`_run_demo` 硬编码下标（只给截图/演示用的脚手架）。

**Spec（2 个真问题，已修）**：
1. 金币小圆的落点按「旧金币数」宽度算，数字变宽后会偏一格 → 收获分支先 `_update_hud()` 再起飞。
2. 票面「买种子入口」只有情境提示、没有常驻价格 → 金币面板下加常驻「种子 -20 · 收 +45」价格牌。

**Spec 里的解释性说明（不改代码，记录在案）**：
- `OFFLINE_CAP_HOURS`（8 小时）实际只封顶「离线时长显示」，不约束成熟：作物成熟只取决于 `planted_at`，离线超过 600 秒就全熟，所以 8 小时这个数在当前玩法里不会真正生效（M2 就这样）。如果以后想要它真正生效，需要重新定义「离线收益」（比如按时长给金币），那是改 spec 的取舍，不要在 M3 里悄悄改。
- 应用图标不在 spec 的 M3 四条里，但 M2 交接与导出警告都把它列为 M3 的收尾项，本次按交接做了；`export_presets.cfg` 的 `launcher_icons/*` 已接上。
- 镜头震动（0.07 世界单位、0.18 秒）是反馈，不是玩家控制；spec 的「固定俯视相机（无平移/缩放/旋转）」指操作方式，保持不动。
- 调试面板比 spec 多了一个「DEBUG: +100 金币」，仅 debug 包可见，为了让 5 分钟验收不必等金币；release 包不会出现（`OS.is_debug_build()` 门控）。

