class_name Balance
extends RefCounted

## 所有数值集中在这里。改这一行就能调游戏节奏（spec.md 的数值表）。
## M1 只用 START_COINS / PLOT_COUNT；其余给 M2 用。

const PLOT_COUNT := 6
const PLOT_COLS := 3
const PLOT_ROWS := 2

const MATURE_SECONDS := 600          # 从种下到成熟：10 分钟
const SEED_PRICE := 20               # 买一颗种子
const SELL_PRICE := 45               # 卖一颗成熟作物
const START_COINS := 120             # 新档初始金币
const OFFLINE_CAP_HOURS := 8         # 离线收益封顶
