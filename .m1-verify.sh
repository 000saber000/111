#!/bin/bash
# 等待手机出现 → 装 APK → 启动 → 截图 → 抓崩溃日志。超时 12 分钟。
ADB="/c/Users/rongyao/AppData/Local/Android/Sdk/platform-tools/adb.exe"
APK="D:/dsh project/111/build/xiaonongchang.apk"
SHOT="D:/dsh project/111/build/device-shot.png"
PKG="com.saber.farm"

echo "waiting for device..."
timeout 720 "$ADB" wait-for-device
sleep 2
STATE=$("$ADB" devices | awk 'NR==2{print $2}')
echo "device state: ${STATE:-none}"
if [ -z "${STATE:-}" ]; then echo "TIMEOUT: no device"; exit 1; fi
if [ "$STATE" = "unauthorized" ]; then
  echo "UNAUTHORIZED: 请在手机上点『允许 USB 调试』"
  exit 2
fi

echo "=== 设备信息 ==="
"$ADB" shell getprop ro.product.model
"$ADB" shell getprop ro.build.version.release
"$ADB" shell getprop ro.product.cpu.abi

echo "=== 安装 ==="
"$ADB" install -r "$APK" 2>&1 | tail -3

echo "=== 清空日志并启动 ==="
"$ADB" logcat -c
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1 | tail -2
sleep 6

echo "=== 进程是否存活 ==="
"$ADB" shell pidof "$PKG" | tr -d '\r' | sed 's/^/pid: /'

echo "=== 截图 ==="
"$ADB" exec-out screencap -p > "$SHOT" 2>/dev/null
ls -lh "$SHOT" 2>/dev/null

echo "=== 最近日志（错误优先） ==="
"$ADB" logcat -d -t 400 2>&1 | grep -iE "godot|fatal|exception|crash|$PKG" | tail -20
echo "=== DONE ==="
