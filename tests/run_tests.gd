extends SceneTree

## 无头测试：`godot --headless --path . --script res://tests/run_tests.gd`
## 只测 FarmLogic 这个纯规则模块（不碰节点、不碰时钟），数值期望来自 docs/spec.md。
## 退出码：0 全过，1 有失败。

var _passed := 0
var _failed := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_test_offline_caps_at_eight_hours()
	_test_offline_keeps_recent_growth_growing()
	_test_offline_ignores_backwards_clock()
	_test_offline_leaves_empty_and_mature_plots_alone()
	_test_growth_tick_matures_at_exactly_ten_minutes()
	_test_growth_tick_returns_only_newly_matured()
	_test_plant_spends_seed_price()
	_test_plant_refuses_when_coins_are_short()
	_test_plant_does_nothing_on_occupied_plot()
	_test_harvest_pays_and_clears_plot()
	_test_harvest_refuses_unripe_crop()
	_test_plot_counts_match_states()

	print("")
	print("TESTS: %d passed, %d failed" % [_passed, _failed])
	for failure in _failures:
		print("  FAILED: ", failure)
	quit(0 if _failed == 0 else 1)


# ---------- 离线结算（spec：封顶 8 小时） ----------

func _test_offline_caps_at_eight_hours() -> void:
	var plots := [_plot("growing", 0)]
	var result := FarmLogic.apply_offline(plots, 12 * 3600, 0)
	_check_equal("离线 12 小时：结算时长封顶 8 小时", result["elapsed_seconds"], 8 * 3600)
	_check_equal("离线 12 小时：生长中的地块成熟", plots[0]["state"], "mature")
	_check_equal("离线 12 小时：返回成熟地块下标", result["matured"], [0])


func _test_offline_keeps_recent_growth_growing() -> void:
	var now := 10_000
	var plots := [_plot("growing", now - 60)]
	var result := FarmLogic.apply_offline(plots, now, now)
	_check_equal("刚种下就重开：结算时长 0", result["elapsed_seconds"], 0)
	_check_equal("刚种下就重开：地块仍在生长", plots[0]["state"], "growing")
	_check_equal("刚种下就重开：没有成熟地块", result["matured"], [])


func _test_offline_ignores_backwards_clock() -> void:
	var now := 10_000
	var plots := [_plot("growing", now - 30)]
	var result := FarmLogic.apply_offline(plots, now, now + 5000)
	_check_equal("时钟往回拨：结算时长不会为负", result["elapsed_seconds"], 0)
	_check_equal("时钟往回拨：地块不被误判成熟", plots[0]["state"], "growing")


func _test_offline_leaves_empty_and_mature_plots_alone() -> void:
	var now := 20_000
	var plots := [_plot("empty", 0), _plot("mature", now - 5000), _plot("growing", now - 5000)]
	var result := FarmLogic.apply_offline(plots, now, now - 3600)
	_check_equal("离线结算：空地块保持空", plots[0]["state"], "empty")
	_check_equal("离线结算：成熟地块保持成熟", plots[1]["state"], "mature")
	_check_equal("离线结算：只报告生长→成熟的地块", result["matured"], [2])


# ---------- 在线生长 tick（spec：成熟 600 秒） ----------

func _test_growth_tick_matures_at_exactly_ten_minutes() -> void:
	var now := 50_000
	var plots := [_plot("growing", now - 600)]
	var matured := FarmLogic.tick_growth(plots, now)
	_check_equal("满 600 秒：地块成熟", plots[0]["state"], "mature")
	_check_equal("满 600 秒：返回成熟下标", matured, [0])


func _test_growth_tick_returns_only_newly_matured() -> void:
	var now := 50_000
	var plots := [_plot("growing", now - 599), _plot("mature", now - 5000), _plot("growing", 0)]
	var matured := FarmLogic.tick_growth(plots, now)
	_check_equal("差 1 秒：还不成熟", plots[0]["state"], "growing")
	_check_equal("已成熟的地块不重复报告", matured, [2])


# ---------- 种植 / 收获（spec：种子 20、卖 45） ----------

func _test_plant_spends_seed_price() -> void:
	var plot := _plot("empty", 0)
	var result := FarmLogic.plant(plot, 120, 12_345)
	_check_equal("种下：成功", result["ok"], true)
	_check_equal("种下：扣 20 金币", result["coins"], 100)
	_check_equal("种下：地块进入生长", plot["state"], "growing")
	_check_equal("种下：记录种下时间", plot["planted_at"], 12_345)


func _test_plant_refuses_when_coins_are_short() -> void:
	var plot := _plot("empty", 0)
	var result := FarmLogic.plant(plot, 19, 12_345)
	_check_equal("金币 19：种下失败", result["ok"], false)
	_check_equal("金币 19：金币不变", result["coins"], 19)
	_check_equal("金币 19：地块保持空", plot["state"], "empty")
	_check_equal("金币 19：给出原因", result["reason"] != "", true)


func _test_plant_does_nothing_on_occupied_plot() -> void:
	var plot := _plot("growing", 123)
	var result := FarmLogic.plant(plot, 120, 12_345)
	_check_equal("已有作物：种下失败", result["ok"], false)
	_check_equal("已有作物：金币不变", result["coins"], 120)
	_check_equal("已有作物：种下时间不变", plot["planted_at"], 123)


func _test_harvest_pays_and_clears_plot() -> void:
	var plot := _plot("mature", 1000)
	var result := FarmLogic.harvest(plot, 100)
	_check_equal("收获：成功", result["ok"], true)
	_check_equal("收获：+45 金币", result["coins"], 145)
	_check_equal("收获：地块回到空", plot["state"], "empty")
	_check_equal("收获：清掉种下时间", plot["planted_at"], 0)


func _test_harvest_refuses_unripe_crop() -> void:
	var plot := _plot("growing", 1000)
	var result := FarmLogic.harvest(plot, 100)
	_check_equal("生长中收获：失败", result["ok"], false)
	_check_equal("生长中收获：金币不变", result["coins"], 100)
	_check_equal("生长中收获：地块仍在生长", plot["state"], "growing")


# ---------- HUD 计数 ----------

func _test_plot_counts_match_states() -> void:
	var plots := [_plot("empty", 0), _plot("empty", 0), _plot("growing", 1),
		_plot("growing", 2), _plot("growing", 3), _plot("mature", 4)]
	var counts := FarmLogic.counts(plots)
	_check_equal("计数：空地 2", counts["empty"], 2)
	_check_equal("计数：生长中 3", counts["growing"], 3)
	_check_equal("计数：成熟 1", counts["mature"], 1)


# ---------- 断言 ----------

## 测试里的 "empty" / "growing" / "mature" 故意写字符串字面量，而不是 FarmLogic.STATE_*：
## 这三个字符串是存档 schema 的一部分（旧档迁移也按它判断），是测试的独立事实来源；
## 引用实现常量会让断言变成同义反复，改坏状态值也测不出来。
func _plot(state: String, planted_at: int) -> Dictionary:
	return {"state": state, "planted_at": planted_at}


func _check_equal(what: String, actual: Variant, expected: Variant) -> void:
	if _same(actual, expected):
		_passed += 1
		print("  ok   ", what)
	else:
		_failed += 1
		_failures.append("%s — 期望 %s，实际 %s" % [what, str(expected), str(actual)])
		print("  FAIL ", what, " — 期望 ", expected, "，实际 ", actual)


func _same(a: Variant, b: Variant) -> bool:
	# 类型也要一致：int 与 float 数值相等也不算相同，避免把 45.0 当成 45 蒙混过去。
	if typeof(a) != typeof(b):
		return false
	return a == b
