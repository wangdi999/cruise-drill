class_name CruiseCrewCard
extends Card

# 复用上游 Card.play 的能量扣除与出牌事件；活动控制器校验友敌目标。
@export var owner_id: String
@export var card_kind: int
@export var unique_id: int
@export var display_name: String
@export var target_kind: String
@export var effect_data: Array
var runtime: Node

func apply_effects(targets: Array[Node], _modifiers: ModifierHandler) -> void:
	if is_instance_valid(runtime):
		runtime.resolve_card_effects(self, targets)

func get_default_tooltip() -> String:
	return tooltip_text
