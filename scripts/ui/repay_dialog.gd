extends "res://scripts/ui/overlay.gd"
## 还款：把现金还给黑鸦商会。关闭时返回还款金额（float），取消返回 null。

const Portfolio := preload("res://scripts/core/portfolio.gd")

@onready var info_label: Label = %InfoLabel
@onready var amount_spin: SpinBox = %AmountSpin
@onready var all_button: Button = %AllButton
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton


func _ready() -> void:
	var pf := GameState.portfolio
	var most := minf(pf.cash, pf.debt)
	info_label.text = "现金 %s　剩余债务 %s" % [Portfolio.fmt_money(pf.cash), Portfolio.fmt_money(pf.debt)]
	amount_spin.min_value = 0.0
	amount_spin.max_value = most
	amount_spin.value = most
	confirm_button.disabled = most <= 0.0
	all_button.pressed.connect(func(): amount_spin.value = most)
	cancel_button.pressed.connect(func(): close())
	confirm_button.pressed.connect(func(): close(float(amount_spin.value)))
