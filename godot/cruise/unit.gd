class_name CruiseUnit
extends Node

# 生命夹取、护盾抵扣和恢复完全使用上游 Stats。
var unit_id: String
var display_name: String
var role: String
var glyph: String
var stats: Stats
var enemy: bool = false
var damage: int = 0
var taunt: bool = false
var intent: Dictionary = {}

func configure(data: Dictionary) -> void:
	unit_id = data.id
	display_name = data.name
	role = data.get("role", "敌方")
	glyph = data.get("glyph", "◈")
	enemy = data.get("enemy", false)
	damage = int(data.get("damage", 0))
	stats = Stats.new()
	stats.max_health = int(data.get("maxHp", data.hp))
	stats.health = int(data.hp)
	stats.block = int(data.get("shield", 0))
	taunt = data.get("taunt", false)
	intent = data.get("intent", {})

func snapshot() -> Dictionary:
	return {"id":unit_id,"name":display_name,"role":role,"glyph":glyph,"enemy":enemy,"hp":stats.health,"maxHp":stats.max_health,"shield":stats.block,"damage":damage,"taunt":taunt,"intent":intent.duplicate(true)}
