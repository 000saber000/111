class_name FarmLogic
extends RefCounted

## 纯游戏规则：不碰节点、不碰真实时钟，只接收「地块数据 + 当前时间」。
## 这样做的好处：离线结算和生长判定可以无头测试（tests/run_tests.gd），
## main.gd 只负责把节点、存档和真实时间接进来。
## 数值从 Balance 取；要改数值改 docs/spec.md 的数值表 + balance.gd。

const STATE_EMPTY := "empty"
const STATE_GROWING := "growing"
const STATE_MATURE := "mature"


## 用存档里的 last_seen_at 结算离线期间：时长按 OFFLINE_CAP_HOURS 封顶，
## 生长中的地块按 planted_at 判定是否已成熟。返回结算时长与本次新成熟的下标。
static func apply_offline(plots: Array, now: int, last_seen_at: int) -> Dictionary:
	var elapsed := clampi(now - last_seen_at, 0, Balance.OFFLINE_CAP_HOURS * 3600)
	return {
		"elapsed_seconds": elapsed,
		"matured": _mature_ripe_plots(plots, now),
	}


## 在线每秒 tick：成熟时间到了就转 mature。返回本次新成熟的下标。
static func tick_growth(plots: Array, now: int) -> Array[int]:
	return _mature_ripe_plots(plots, now)


## 种下一颗种子：扣 SEED_PRICE，地块进入生长。返回 {ok, reason, coins}。
static func plant(plot: Dictionary, coins: int, now: int) -> Dictionary:
	if state_of(plot) != STATE_EMPTY:
		return {"ok": false, "reason": "这块地已经种上了", "coins": coins}
	if coins < Balance.SEED_PRICE:
		return {"ok": false, "reason": "金币不够买种子", "coins": coins}
	plot["state"] = STATE_GROWING
	plot["planted_at"] = now
	return {"ok": true, "reason": "", "coins": coins - Balance.SEED_PRICE}


## 收一块成熟作物：加 SELL_PRICE，地块回到空。返回 {ok, reason, coins}。
static func harvest(plot: Dictionary, coins: int) -> Dictionary:
	if state_of(plot) != STATE_MATURE:
		return {"ok": false, "reason": "还没熟", "coins": coins}
	plot["state"] = STATE_EMPTY
	plot["planted_at"] = 0
	return {"ok": true, "reason": "", "coins": coins + Balance.SELL_PRICE}


## HUD 用的地块状态计数。
static func counts(plots: Array) -> Dictionary:
	var counts := {STATE_EMPTY: 0, STATE_GROWING: 0, STATE_MATURE: 0}
	for plot in plots:
		var state := state_of(plot)
		if counts.has(state):
			counts[state] += 1
	return counts


static func _mature_ripe_plots(plots: Array, now: int) -> Array[int]:
	var matured: Array[int] = []
	for i in plots.size():
		var plot: Dictionary = plots[i]
		if state_of(plot) != STATE_GROWING:
			continue
		var planted_at := int(plot.get("planted_at", now))
		if now - planted_at >= Balance.MATURE_SECONDS:
			plot["state"] = STATE_MATURE
			matured.append(i)
	return matured


## 存档里用的状态字符串只有这三个；main.gd 渲染时也走这里，别再自己 get("state")。
static func state_of(plot: Dictionary) -> String:
	return String(plot.get("state", STATE_EMPTY))
