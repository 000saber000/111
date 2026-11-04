# 交接文档 · M2 进行中

> 写给下一个会话：读完这份就能接着干，不需要翻上面的对话。
> 生成时间：2026-11-05 00:35（Asia/Singapore）

## 一句话现状

M1 已验收关闭；**M2 的代码与资产已写完并提交，桌面验证通过，只差真机验收**（卡在手机无线调试端口失效）。

## 里程碑状态

| 里程碑 | 状态 |
| --- | --- |
| M1 端上跑通 | ✅ 已真机验收并关闭（#1） |
| M2 闭环打通 | 🟡 代码+资产已完成、桌面验证通过；**真机验收未做**（#2 仍 open） |
| M3 打磨与验收 | ⬜ 未开始（#3，依赖 #2） |

## 仓库状态

- 分支 `main`，工作区干净；最新提交：
  - `3c36ff5` feat(m2): 种植/生长/收获/金币闭环 + 离线结算 + 调试加速 + Blender 8 资产接入 (#2)
  - `cfa2f26` chore: 清理误提交的临时脚本与 Godot 导入文件，docs/ 加 .gdignore
  - `174e6f3` fix(m1): 横屏改成 expand 拉伸消除黑边；补真机验收截图 (#1)
- 规格：`docs/spec.md`（21 条结论，数值表在那里改）
- issue：#1 已关、#2 进行中、#3 阻塞在 #2

## M2 已完成的东西

**逻辑**（`scripts/main.gd`）
- 点空地 → 扣 20 金币、种下（状态 `growing`，记 `planted_at`）
- 每秒 tick：满 600 秒（`Balance.MATURE_SECONDS`）自动转 `mature`
- 点生长中 → 显示还要几秒；点成熟 → +45 金币、状态回 `empty`
- 离线结算：用 `last_seen_at` 算离线时长（封顶 8 小时），启动时把到期作物转成熟
- 调试按钮（仅 debug 包显示）：`DEBUG: 立刻成熟`、`DEBUG: 回拨 2 小时`
- 存档 schema 升到 v2，v1 的 `state:"selected"` 会迁移成 `empty`

**资产**（`tools/blender/generate_assets.py` → `assets/models/*.glb`，共 8 个）
- `plot_block` / `crop_seed` / `crop_sprout` / `crop_mature` / `coin` / `ground` / `fence` / `windmill`
- 生成方式：`"D:\Blender\blender.exe" --background --factory-startup --python tools/blender/generate_assets.py`
- 风格：低模、纯色材质、无贴图、无骨骼动画

**桌面验证结果**（可复现）
- 空农场 → 点地块种下（120 → 100 金币）→ `--mature` → 成熟（作物+金币出现）→ 点收获（100 → 145）

## 下一步（按顺序）

1. **拿手机重新连接**（无线调试端口每次都会变）：
   - 手机：开发者选项 → 无线调试 → 保持页面打开，把「IP 地址和端口」发给用户拿到的当前值
   - `adb connect <ip>:<port>`
2. **真机验收 M2**：
   - `adb install -r "D:\dsh project\111\build\xiaonongchang.apk"`
   - 启动 → 点空地种下（金币 120→100、地块上出现土堆）
   - 点一次 `DEBUG: 立刻成熟` → 作物+金币出现
   - 点地块收获（100→145）
   - 杀进程重开 → 金币和地块状态应还在
3. 通过就关 #2（附真机截图），然后开 M3（音效/反馈动画/横屏 UI 收尾/真机 5 分钟稳定）
4. 桌面截图复现命令（无需手机）：
   ```
   cd /d/Godot
   ./Godot_v4.7.2-stable_win64_console.exe --path "D:/dsh project/111" -- --tap=640,470 --shot="res://build/x.png"
   ./Godot_v4.7.2-stable_win64_console.exe --path "D:/dsh project/111" -- --mature --shot="res://build/y.png"
   ```

## 环境（全在 D 盘）

| 东西 | 路径 |
| --- | --- |
| Godot 4.7.2 编辑器 | `D:\Godot\Godot_v4.7.2-stable_win64.exe` |
| Godot 控制台版（导出用） | `D:\Godot\Godot_v4.7.2-stable_win64_console.exe` |
| 自包含数据（配置+模板） | `D:\Godot\editor_data\`（`._sc_` 自包含模式） |
| Android 导出模板 | `D:\Godot\editor_data\export_templates\4.7.2.stable\android_debug.apk` |
| debug keystore | `D:\Godot\android\debug.keystore`（密码 `android`，别名 `androiddebugkey`） |
| Blender | `D:\Blender\blender.exe`（4.5.14 LTS） |
| Android SDK | `C:\Users\rongyao\AppData\Local\Android\Sdk`（build-tools 36.1.0，adb 在 platform-tools） |
| 桌面存档 | `%APPDATA%\Godot\app_userdata\小农场\save.json` |

**导出 APK**：
```
"D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/dsh project/111" --export-debug "Android" "D:/dsh project/111/build/xiaonongchang.apk"
```

**装机**：
```
"C:\Users\rongyao\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "D:\dsh project\111\build\xiaonongchang.apk"
```

## 踩过的坑（别重踩）

1. **Android 导出必须开 ETC2/ASTC**，否则导出直接报错：`project.godot` 里 `textures/vram_compression/import_etc2_astc=true`。
2. **导出模板 1.2 GB 全平台包下不动**：只需 `android_debug.apk`（121 MB）。用 HTTP Range 直接取 zip 条目，脚本思路见 `docs/spec.md` 之外的踩坑记录（已删临时脚本，需要时按 Range + zlib 流式解压重写）。
3. **Blender 颜色要 sRGB→线性**：直接填 sRGB 数值导进引擎会整体发白；脚本里已有 `srgb_to_linear()`。
4. **Blender 方块尺寸**：`primitive_cube_add(size=1)` 的边长是 1，`scale` 直接等于目标边长，别再除以 2。
5. **Blender 是 Z 轴朝上**，`export_yup=True` 后游戏里 y 是高度。
6. **无线调试端口每次重连都变**，`adb connect` 拒绝连接就向用户要新端口。
7. 桌面存档在 C 盘 `%APPDATA%`（Godot 固定位置，仅调试用，几十 KB）。
8. 导出时有个“没有项目图标”的警告，不影响安装；留给 M3 跟美术一起补。

## 建议的下一步动作

- 先要手机无线调试的当前端口，把 M2 真机验收做完并关 #2；
- 然后按 `docs/spec.md` 的 M3 节推进：音效（种植/收获/金币）、收获反馈动效、横屏 UI 收尾、真机连续 5 分钟稳定、做应用图标。
