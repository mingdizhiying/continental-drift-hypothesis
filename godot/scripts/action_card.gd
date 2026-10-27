extends Button
## Scene-owned labels keep all payments visible, including law-specific changes.

func configure(spec: Dictionary, blocked: String, can_act: bool) -> void:
	text = ""
	disabled = not can_act or not blocked.is_empty()
	custom_minimum_size.y = 112 if not blocked.is_empty() else 90
	$Margin/Content/Title.text = spec.name
	$Margin/Content/Cost.text = "支付：" + (CityEconomy.describe(spec.cost, "−") if not spec.cost.is_empty() else "无直接支付")
	$Margin/Content/Gain.text = "获得：" + (CityEconomy.describe(spec.gain, "+") if not spec.gain.is_empty() else "无，仍推进一轮")
	$Margin/Content/Reason.text = blocked.split("，")[0]
	$Margin/Content/Reason.visible = not blocked.is_empty()
	$Margin.modulate = Color(0.65, 0.72, 0.71) if disabled else Color.WHITE
	tooltip_text = "%s\n%s\n%s\n%s" % [spec.place, $Margin/Content/Cost.text, $Margin/Content/Gain.text, blocked]
