# 交接文档 · M2 完成，下一步 M3

> 写给下一个会话：读完这份就能接着干，不需要翻上面的对话。
> 生成时间：2026-11-05 12:50（Asia/Singapore）

## 一句话现状

M1、M2 都已在真机验收并关闭；**下一步是 M3（打磨与验收）**，`#3` 已解锁。

## 里程碑状态

| 里程碑 | 状态 |
| --- | --- |
| M1 端上跑通 | ✅ 已验收关闭（#1） |
| M2 闭环打通 | ✅ 已验收关闭（#2） |
| M3 打磨与验收 | ⬜ 待开始（#3，已解锁） |

## 仓库状态

- 分支 `main`，工作区干净。关键提交：
  - `3c36ff5` feat(m2): 种植/生长/收获/金币闭环 + 离线结算 + 调试加速 + Blender 8 资产接入 (#2)
  - `f265afa` docs: M2 交接文档
  - 之后还有：修「回拨 2 小时」让它真正走离线结算路径、README 补 M2 真机截图
- 规格：`docs/spec.md`（数值表在那里改）
- 截图：`docs/screenshot-m1.png`、`docs/screenshot-device.png`、`docs/screenshot-m2-device.png`

## M2 已交付并验收的内容

**玩法闭环**（`scripts/main.gd`）
- 点空地：扣 20 金币、种下（`growing` + `planted_at`）
- 每秒 tick：满 600 秒自动转 `mature`
- 点成熟：+45 金币回 `empty`；点生长中：显示剩余秒数
- 离线结算：`last_seen_at` 算时长、封顶 8 小时，启动时结算
- 调试按钮（仅 debug 包）：`立刻成熟`、`回拨 2 小时（模拟离线）`——后者会把 `last_seen_at` 和 `planted_at` 一起回拨，走的是**真实离线结算代码路径**
- 存档 schema v2，v1 的 `state:"selected"` 自动迁移成 `empty`

**8 个资产**（`tools/blender/generate_assets.py` → `assets/models/*.glb`）
地块 / 种子 / 发芽 / 成熟 / 金币 / 地面 / 栅栏 / 风车，低模纯色，脚本可重跑。

**真机验收记录**（HONOR AMP-AN00，Android 16）
- 启动：金币 120、HUD 显示「离线 480 分钟」（12 小时离线被 8 小时封顶 ✅）
- 种下：120→100，出现种子土堆
- 点「立刻成熟」：作物 + 金币出现，成熟 1
- 收获：100→145
- 杀进程重开：金币 145 持久化 ✅
- 点「回拨 2 小时」：作物直接变成熟，证明离线结算路径可用 ✅

## M3 要做什么（按 spec）

范围：
1. **音效**：至少种植 / 收获 / 金币三个。可以用代码生成简单音效（Blender 不行，考虑用脚本合成 wav 或找 CC0 素材）
2. **收获反馈**：金币跳字 + 作物消失动效（Tween 缩放/上浮）
3. **横屏 UI 收尾**：金币显示、买种子入口、空地提示更清楚（现在 HUD 是一行文字）
4. **应用图标**：现在导出还报 “No project icon specified”，需要一个 1024×1024 图标 + 各密度
5. **真机连续 5 分钟不崩不卡**

验收（spec 里写了顺序）：
1. 连续玩 5 分钟没有想切出去
2. 关掉 30 分钟回来有「哦可以收了」的期待
3. 收获瞬间有爽感

## 环境（全在 D 盘）

| 东西 | 路径 |
| --- | --- |
| Godot 4.7.2 编辑器 | `D:\Godot\Godot_v4.7.2-stable_win64.exe` |
| Godot 控制台版（导出用） | `D:\Godot\Godot_v4.7.2-stable_win64_console.exe` |
| 自包含数据 | `D:\Godot\editor_data\`（`._sc_` 模式） |
| Android 导出模板 | `D:\Godot\editor_data\export_templates\4.7.2.stable\android_debug.apk` |
| debug keystore | `D:\Godot\android\debug.keystore`（密码 `android`，别名 `androiddebugkey`） |
| Blender | `D:\Blender\blender.exe`（4.5.14 LTS） |
| Android SDK | `C:\Users\rongyao\AppData\Local\Android\Sdk`（build-tools 36.1.0；adb 在 platform-tools） |

**导出 APK**：
```
"D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/dsh project/111" --export-debug "Android" "D:/dsh project/111/build/xiaonongchang.apk"
```

**桌面截图（无需手机）**：
```
cd /d/Godot
./Godot_v4.7.2-stable_win64_console.exe --path "D:/dsh project/111" -- --tap=640,470 --shot="res://build/x.png"
./Godot_v4.7.2-stable_win64_console.exe --path "D:/dsh project/111" -- --mature --shot="res://build/y.png"
```

**真机**：
- 无线调试每次重连端口都会变，向用户要当前「IP 地址和端口」
- `adb connect <ip>:<port>`（注意：手机上无线调试页面要开着、别锁屏）
- `adb install -r build/xiaonongchang.apk`
- 截图：`adb exec-out screencap -p > build/x.png`
- 点屏：`adb shell input tap <x> <y>`（设备分辨率 1224×2700，横屏时 2700×1224）

## 踩过的坑（别重踩）

1. **Android 导出必须开 ETC2/ASTC**：`project.godot` 里 `textures/vram_compression/import_etc2_astc=true`。
2. **导出模板 1.2 GB 全平台包**：只需 `android_debug.apk`（121 MB），用 HTTP Range 直接取 zip 条目。
3. **Blender 颜色要 sRGB→线性**：直接填 sRGB 会整体发白，脚本里有 `srgb_to_linear()`。
4. **Blender 方块尺寸**：`primitive_cube_add(size=1)` 边长 1，`scale` 直接等于目标边长。
5. **Blender 是 Z 轴朝上**，`export_yup=True` 后游戏里 y 是高度。
6. **无线调试连上会因 adb daemon 重启断开**：`adb connect` 重连即可，端口可能变。
7. **手机存档不能直接改**：`run-as` 能读但写 `/data/data/.../files/save.json` 会被 SELinux 拒绝；要造离线场景用游戏里的「回拨 2 小时」按钮。
8. 导出仍有「没有项目图标」警告，M3 补图标。

## 建议的第一步

读 `docs/spec.md` 的 M3 节 → 先做**应用图标 + 收获反馈动效**（视觉上最容易被感知），再加音效，最后真机跑 5 分钟稳定性验收。
