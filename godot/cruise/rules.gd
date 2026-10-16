class_name CruiseRules
extends Node

signal changed
const DAY: int = 86400
const VERSION: int = 2
var config: Dictionary
var profile: Dictionary
var allies: Array[CruiseUnit] = []
var enemies: Array[CruiseUnit] = []
var energy_stats: CharacterStats
var draw_pile: CardPile
var hand: CardPile
var discard_pile: CardPile
var modifiers: ModifierHandler
var selected_uid: int = -1
var last_owner: String = ""
var combo_bonus: int = 0
var turn: int = 1
var actions: int = 0
var logs: Array = []
var buffs: Dictionary = {}
var error: String = ""
var clock_override: float = -1

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://cruise/data.json"))
	modifiers = ModifierHandler.new()
	add_child(modifiers)
	reset()

func now() -> float:
	return clock_override if clock_override >= 0 else Time.get_unix_time_from_system()

func fresh_profile() -> Dictionary:
	return {"version":VERSION,"day":1,"clock":now(),"team":["ranger","medic","guard"],"completed":{},"claimed":{},"tokens":0,"inventory":{},"materials":0,"run":{},"events":[],"serial":0,"seed":218}

func reset() -> void:
	clear_units()
	profile = fresh_profile()
	selected_uid = -1
	error = ""
	changed.emit()

func clear_units() -> void:
	for unit: CruiseUnit in allies + enemies:
		unit.free()
	allies.clear()
	enemies.clear()
	energy_stats = null
	draw_pile = null
	hand = null
	discard_pile = null

func hero(id: String) -> Dictionary:
	for h in config.heroes:
		if h.id == id: return h
	return {}

func valid_team(team: Array) -> bool:
	if team.size() != 3: return false
	var seen: Dictionary = {}
	var has_output: bool = false
	for id in team:
		var h: Dictionary = hero(str(id))
		if h.is_empty() or seen.has(id): return false
		seen[id] = true
		if h.role == "输出": has_output = true
	return has_output

func activity_day() -> float:
	return float(profile.day) + maxf(0, now() - float(profile.clock)) / DAY

func add_event(type: String, data: Dictionary = {}) -> void:
	var entry: Dictionary = data.duplicate(true)
	entry.type = type
	entry.time = now()
	profile.events.append(entry)
	if profile.events.size() > 300: profile.events.pop_front()

func sync_time() -> bool:
	var did_change: bool = false
	if activity_day() >= 8 and not profile.run.is_empty():
		add_event("expired", {"stage":profile.run.stage})
		profile.run = {}
		clear_units()
		error = "活动已结束，未完成挑战已作废；已确认首通可在兑换期补领。"
		did_change = true
	if activity_day() >= 9 and profile.tokens > 0:
		profile.materials += profile.tokens
		add_event("converted", {"amount":profile.tokens})
		profile.tokens = 0
		did_change = true
	return did_change

func set_day(day_value: int) -> bool:
	if not day_value in [1,2,4,7,8,9]: return reject("演练日无效。")
	profile.day = day_value
	profile.clock = now()
	sync_time()
	add_event("dayChanged", {"day":day_value})
	changed.emit()
	return true

func lock_reason(stage_id: int) -> String:
	if stage_id < 1 or stage_id > 3: return "阶段不存在。"
	var stage: Dictionary = config.stages[stage_id-1]
	if activity_day() >= 8: return "活动已结束，不能进入新战斗。"
	if activity_day() < float(stage.openDay): return "第 %s 天开放" % stage.openDay
	if stage.prerequisite > 0 and not profile.completed.has(str(int(stage.prerequisite))): return "需要先通关前置阶段。"
	return ""

func reject(text: String) -> bool:
	error = text
	return false

func start(stage_id: int, team: Array) -> bool:
	sync_time()
	var reason: String = lock_reason(stage_id)
	if not reason.is_empty(): return reject(reason)
	if not valid_team(team): return reject("请选择三个不同角色，且至少一名输出。")
	if not profile.run.is_empty(): return reject("已有进行中的挑战，请继续或主动放弃。")
	profile.serial += 1
	profile.team = team.duplicate()
	var party: Array = []
	for id in team:
		var h: Dictionary = hero(id)
		party.append({"id":id,"name":h.name,"role":h.role,"glyph":h.glyph,"hp":h.hp,"maxHp":h.hp,"shield":0})
	profile.run = {"stage":stage_id,"team":team.duplicate(),"party":party,"route":"","buff":"","node":"route","battle":{},"seed":int(profile.seed)+int(profile.serial)*97,"startedAt":now()}
	add_event("start", {"stage":stage_id,"team":team.duplicate(),"seed":profile.run.seed})
	error = ""
	if stage_id == 1: return choose_route("A")
	changed.emit()
	return true

func ensure_active() -> bool:
	sync_time()
	return not profile.run.is_empty()

func choose_route(route: String) -> bool:
	if not ensure_active(): return reject("没有有效挑战，或活动已经结束。")
	if profile.run.node != "route" or not route in ["A","B"]: return reject("当前不能选择路线。")
	if profile.run.stage == 1 and route != "A": return reject("入门演练使用固定补给路线。")
	profile.run.route = route
	profile.run.node = "battle"
	add_event("route", {"stage":profile.run.stage,"route":route})
	begin_battle(false)
	changed.emit()
	return true

func available_buffs(stage_id: int) -> Array:
	return [["shield","combo"],["healing","power"],["bastion","assault"]][stage_id-1]

func choose_buff(id: String) -> bool:
	if not ensure_active(): return reject("活动已经结束。")
	if profile.run.node != "buff" or not id in available_buffs(profile.run.stage): return reject("当前增益选择无效。")
	profile.run.buff = id
	profile.run.node = "boss"
	add_event("buff", {"stage":profile.run.stage,"buff":id})
	begin_battle(true)
	changed.emit()
	return true

func create_card(owner: String, kind: int, uid: int) -> CruiseCrewCard:
	var h: Dictionary = hero(owner)
	var spec: Dictionary = h.cards[kind]
	var card: CruiseCrewCard = CruiseCrewCard.new()
	card.owner_id = owner
	card.card_kind = kind
	card.unique_id = uid
	card.id = owner + "_" + str(kind)
	card.display_name = spec.name
	card.cost = int(spec.cost)
	card.type = Card.Type.ATTACK if spec.effects[0].type == "damage" else Card.Type.SKILL
	# 全部活动目标由控制器传入，上游单目标管线原样处理目标列表。
	card.target = Card.Target.SINGLE_ENEMY
	card.target_kind = spec.target
	card.effect_data = spec.effects.duplicate(true)
	card.tooltip_text = card_description(card)
	card.runtime = self
	return card

func card_description(card: CruiseCrewCard) -> String:
	var parts: PackedStringArray = []
	var names: Dictionary = {"damage":"伤害","heal":"恢复","shield":"护盾","shieldSelf":"自身护盾","shieldAll":"全队护盾","draw":"抽牌"}
	for effect in card.effect_data:
		parts.append("本回合嘲讽" if effect.type == "taunt" else "%s %s" % [names.get(effect.type, effect.type),int(effect.amount)])
	return " · ".join(parts)

func make_unit(data: Dictionary) -> CruiseUnit:
	var unit: CruiseUnit = CruiseUnit.new()
	unit.configure(data)
	add_child(unit)
	return unit

func begin_battle(boss: bool) -> void:
	clear_units()
	var run: Dictionary = profile.run
	var s: Dictionary = config.stages[int(run.stage)-1]
	var hard: bool = run.route == "B"
	buffs = {"power":2 if hard else 0,"openingShield":0,"combo":0,"healing":0,"openingHeal":0,"regen":0}
	if not run.buff.is_empty():
		for key in config.buffs[run.buff].effects:
			buffs[key] += int(config.buffs[run.buff].effects[key])
	for data in run.party:
		var unit: CruiseUnit = make_unit(data)
		unit.stats.block = int(buffs.openingShield)
		if unit.stats.health > 0: unit.stats.heal(int(buffs.openingHeal)+int(buffs.regen))
		allies.append(unit)
	if boss:
		enemies.append(make_unit({"id":"boss","name":s.boss,"hp":int(s.bossHp)+(12 if hard else 0),"damage":int(s.bossDamage)+(2 if hard else 0),"enemy":true,"glyph":"◉"}))
	else:
		enemies.append(make_unit({"id":"drone","name":"侦察无人机","hp":24+int(run.stage)*6+(6 if hard else 0),"damage":5+int(run.stage)+(1 if hard else 0),"enemy":true,"glyph":"◇"}))
		enemies.append(make_unit({"id":"turret","name":"警戒炮台","hp":26+int(run.stage)*6+(6 if hard else 0),"damage":6+int(run.stage)+(1 if hard else 0),"enemy":true,"glyph":"▥"}))
	energy_stats = CharacterStats.new()
	energy_stats.max_mana = 3
	energy_stats.reset_mana()
	draw_pile = CardPile.new()
	hand = CardPile.new()
	discard_pile = CardPile.new()
	var uid: int = 0
	for id in run.team:
		for kind in range(2):
			for copy in range(2):
				uid += 1
				draw_pile.add_card(create_card(id,kind,uid))
	RNG.instance.seed = int(run.seed)+(701 if boss else 0)
	draw_pile.shuffle()
	turn = 1
	actions = 0
	last_owner = ""
	logs = ["首领战开始。" if boss else "基础战斗开始。"]
	draw_cards(5)
	plan_enemies()
	error = ""
	checkpoint()

func draw_cards(amount: int) -> void:
	for i in range(amount):
		if hand.cards.size() >= 8: break
		if draw_pile.empty():
			while not discard_pile.empty(): draw_pile.add_card(discard_pile.draw_card())
			draw_pile.shuffle()
		if draw_pile.empty(): break
		hand.add_card(draw_pile.draw_card())

func alive_units(units: Array[CruiseUnit]) -> Array[CruiseUnit]:
	var result: Array[CruiseUnit] = []
	for unit in units:
		if unit.stats.health > 0: result.append(unit)
	return result

func find_unit(id: String) -> CruiseUnit:
	for unit in allies + enemies:
		if unit.unit_id == id: return unit
	return null

func find_card(uid: int) -> CruiseCrewCard:
	if not hand: return null
	for card: CruiseCrewCard in hand.cards:
		if card.unique_id == uid: return card
	return null

func valid_targets(card: CruiseCrewCard) -> Array[CruiseUnit]:
	match card.target_kind:
		"enemy", "allEnemies": return alive_units(enemies)
		"ally", "allAllies", "none": return alive_units(allies)
		"self":
			var unit: CruiseUnit = find_unit(card.owner_id)
			if unit and unit.stats.health > 0: return [unit]
	return []

func play(uid: int, target_id: String = "auto") -> bool:
	if not ensure_active(): return reject("活动已截止。")
	if not profile.run.node in ["battle","boss"]: return reject("当前不是战斗节点。")
	var card: CruiseCrewCard = find_card(uid)
	if not card: return reject("这张牌不在手中。")
	if find_unit(card.owner_id).stats.health <= 0: return reject("该角色已倒下，不能出牌。")
	if not energy_stats.can_play_card(card): return reject("能量不足，请结束回合。")
	if actions >= 12: return reject("已达到本回合行动上限。")
	var targets: Array[Node] = []
	if card.target_kind in ["enemy","ally"]:
		var target: CruiseUnit = find_unit(target_id)
		if not target or not target in valid_targets(card): return reject("请选择存活的合法目标。")
		targets.append(target)
	else:
		for unit in valid_targets(card): targets.append(unit)
	if targets.is_empty(): return reject("没有有效目标。")
	combo_bonus = int(buffs.combo) if last_owner == card.owner_id else 0
	last_owner = card.owner_id
	logs.append("%s使用「%s」。" % [hero(card.owner_id).name,card.display_name])
	# 验证完成后才扣能量：实际调用上游 Card.play，而非复制能量逻辑。
	hand.cards.erase(card)
	discard_pile.add_card(card)
	actions += 1
	card.play(targets,energy_stats,modifiers)
	selected_uid = -1
	error = ""
	settle()
	checkpoint()
	changed.emit()
	return true

func resolve_card_effects(card: CruiseCrewCard, targets: Array[Node]) -> void:
	var owner: CruiseUnit = find_unit(card.owner_id)
	for effect in card.effect_data:
		var amount: int = int(effect.amount)
		match effect.type:
			"damage":
				for unit: CruiseUnit in targets:
					var before: int = unit.stats.health
					unit.stats.take_damage(amount+int(buffs.power)+combo_bonus)
					logs.append("%s受到 %s 伤害。" % [unit.display_name,before-unit.stats.health])
			"heal":
				for unit: CruiseUnit in targets:
					if unit.stats.health > 0: unit.stats.heal(amount+int(buffs.healing))
			"shield":
				for unit: CruiseUnit in targets: unit.stats.block += amount
			"shieldSelf": owner.stats.block += amount
			"shieldAll":
				for unit in alive_units(allies): unit.stats.block += amount
			"draw": draw_cards(amount)
			"taunt": owner.taunt = true

func plan_enemies() -> void:
	var alive: Array[CruiseUnit] = alive_units(allies)
	if alive.is_empty(): return
	for i in range(enemies.size()):
		var unit: CruiseUnit = enemies[i]
		var splash: bool = profile.run.node == "boss" and turn % 3 == 0
		unit.intent = {"type":"all" if splash else "single","target":alive[(turn+i-1)%alive.size()].unit_id,"amount":maxi(6,roundi(unit.damage*0.55)) if splash else unit.damage}

func end_turn() -> bool:
	if not ensure_active() or not profile.run.node in ["battle","boss"]: return reject("当前无法结束回合。")
	for enemy in alive_units(enemies):
		var alive: Array[CruiseUnit] = alive_units(allies)
		if alive.is_empty(): break
		var targets: Array[CruiseUnit] = []
		if enemy.intent.type == "all": targets = alive
		else:
			var picked: CruiseUnit = find_unit(enemy.intent.target)
			for unit in alive:
				if unit.taunt: picked = unit; break
			if not picked or picked.stats.health <= 0: picked = alive[0]
			targets.append(picked)
		for unit in targets:
			var before: int = unit.stats.health
			unit.stats.take_damage(int(enemy.intent.amount))
			logs.append("%s → %s：%s 伤害。" % [enemy.display_name,unit.display_name,before-unit.stats.health])
	settle()
	if profile.run.node in ["battle","boss"]:
		if turn >= 40:
			profile.run.node = "failed"
			add_event("failed", {"stage":profile.run.stage,"reason":"roundLimit"})
		else:
			for unit in allies:
				unit.stats.block = 0
				unit.taunt = false
				if unit.stats.health > 0: unit.stats.heal(int(buffs.regen))
			while not hand.empty(): discard_pile.add_card(hand.draw_card())
			turn += 1
			energy_stats.reset_mana()
			actions = 0
			last_owner = ""
			draw_cards(5)
			plan_enemies()
			logs.append("第 %s 回合：护盾清零，能量恢复。" % turn)
	selected_uid = -1
	error = ""
	checkpoint()
	changed.emit()
	return true

func settle() -> void:
	if alive_units(enemies).is_empty():
		var party: Array = []
		for unit in allies:
			var state: Dictionary = unit.snapshot()
			state.shield = 0
			state.taunt = false
			if profile.run.route == "A" and profile.run.node == "battle" and state.hp > 0: state.hp = mini(state.maxHp,state.hp+12)
			party.append(state)
		profile.run.party = party
		if profile.run.node == "boss":
			var key: String = str(int(profile.run.stage))
			if not profile.completed.has(key): profile.completed[key] = {"time":now(),"team":profile.run.team.duplicate(),"route":profile.run.route,"buff":profile.run.buff,"duration":now()-float(profile.run.startedAt)}
			profile.run.node = "complete"
			add_event("clear", {"stage":profile.run.stage,"duration":now()-float(profile.run.startedAt)})
		else:
			profile.run.node = "buff"
			add_event("nodeClear", {"stage":profile.run.stage})
		logs.append("战斗胜利。")
	elif alive_units(allies).is_empty():
		profile.run.node = "failed"
		add_event("failed", {"stage":profile.run.stage,"round":turn,"duration":now()-float(profile.run.startedAt)})
		logs.append("小队全部倒下，可无消耗重试。")

func checkpoint() -> void:
	if profile.run.is_empty() or not energy_stats: return
	profile.run.battle = {"turn":turn,"energy":energy_stats.mana,"actions":actions,"lastOwner":last_owner,"rngSeed":str(RNG.instance.seed),"rngState":str(RNG.instance.state),"allies":unit_snapshots(allies),"enemies":unit_snapshots(enemies),"deck":pile_snapshot(draw_pile),"hand":pile_snapshot(hand),"discard":pile_snapshot(discard_pile),"log":logs.slice(-60),"mod":buffs.duplicate(true)}

func unit_snapshots(units: Array[CruiseUnit]) -> Array:
	var result: Array = []
	for unit in units: result.append(unit.snapshot())
	return result

func pile_snapshot(pile: CardPile) -> Array:
	var result: Array = []
	for card: CruiseCrewCard in pile.cards: result.append({"owner":card.owner_id,"kind":card.card_kind,"uid":card.unique_id})
	return result

func restore_pile(data: Array) -> CardPile:
	var pile: CardPile = CardPile.new()
	for item in data: pile.add_card(create_card(item.owner,int(item.kind),int(item.uid)))
	return pile

func import_profile(data: Variant) -> bool:
	if not valid_profile(data): return reject("存档格式无效，未覆盖当前数据。")
	clear_units()
	profile = data.duplicate(true)
	selected_uid = -1
	if sync_time(): return true
	if not profile.run.is_empty() and profile.run.node != "route":
		var b: Dictionary = profile.run.battle
		for item in b.allies: allies.append(make_unit(item))
		for item in b.enemies: enemies.append(make_unit(item))
		energy_stats = CharacterStats.new()
		energy_stats.max_mana = 3
		energy_stats.mana = int(b.energy)
		draw_pile = restore_pile(b.deck)
		hand = restore_pile(b.hand)
		discard_pile = restore_pile(b.discard)
		turn = int(b.turn)
		actions = int(b.actions)
		last_owner = b.lastOwner
		logs = b.log.duplicate()
		buffs = b.mod.duplicate(true)
		RNG.set_from_save_data(int(b.rngSeed),int(b.rngState))
	error = ""
	return true

func valid_profile(data: Variant) -> bool:
	if not data is Dictionary: return false
	for key in ["version","day","clock","team","completed","claimed","tokens","inventory","materials","run","events","serial","seed"]:
		if not data.has(key): return false
	if int(data.version) != VERSION or not int(data.day) in [1,2,4,7,8,9] or not data.team is Array or data.team.size() > 3 or float(data.tokens) < 0: return false
	for key in ["completed","claimed","inventory","run"]:
		if not data[key] is Dictionary: return false
	if not data.events is Array: return false
	for id in data.team:
		if hero(str(id)).is_empty(): return false
	if data.run.is_empty(): return true
	var r: Dictionary = data.run
	for key in ["stage","team","party","route","buff","node","battle","seed","startedAt"]:
		if not r.has(key): return false
	if not r.team is Array or not valid_team(r.team) or not int(r.stage) in [1,2,3] or not r.node in ["route","battle","buff","boss","complete","failed"]: return false
	if not r.buff.is_empty() and not config.buffs.has(r.buff): return false
	if r.node == "route": return r.battle is Dictionary
	if not r.battle is Dictionary: return false
	var b: Dictionary = r.battle
	for key in ["turn","energy","actions","lastOwner","rngSeed","rngState","allies","enemies","deck","hand","discard","log","mod"]:
		if not b.has(key): return false
	for key in ["deck","hand","discard"]:
		if not b[key] is Array: return false
		for c in b[key]:
			if not c is Dictionary or not c.has("owner") or not c.has("kind") or not c.has("uid") or hero(str(c.owner)).is_empty() or not int(c.kind) in [0,1]: return false
	for key in ["allies","enemies"]:
		if not b[key] is Array or b[key].is_empty(): return false
		for u in b[key]:
			if not u is Dictionary: return false
			for field in ["id","name","hp","maxHp","shield"]:
				if not u.has(field): return false
			if float(u.hp) < 0 or float(u.hp) > float(u.maxHp) or float(u.maxHp) <= 0: return false
	if not b.mod is Dictionary or not b.log is Array: return false
	for key in ["power","openingShield","combo","healing","openingHeal","regen"]:
		if not b.mod.has(key): return false
	return true

func abandon() -> void:
	if not profile.run.is_empty(): add_event("abandon", {"stage":profile.run.stage,"duration":now()-float(profile.run.startedAt)})
	profile.run = {}
	clear_units()
	selected_uid = -1
	changed.emit()

func claim(stage_id: int) -> bool:
	sync_time()
	var key: String = str(stage_id)
	if activity_day() >= 9: return reject("首通补领窗口已结束。")
	if not profile.completed.has(key): return reject("需要确认首领胜利后领取。")
	if profile.claimed.has(key): return reject("首通奖励已经领取，不会重复发放。")
	profile.claimed[key] = true
	profile.tokens += 100
	add_event("claim", {"stage":stage_id,"amount":100})
	error = "已领取 100 演练代币。"
	changed.emit()
	return true

func buy(id: String) -> bool:
	sync_time()
	if activity_day() >= 9: return reject("兑换期已经结束。")
	var item: Dictionary = {}
	for spec in config.shop:
		if spec.id == id: item = spec
	if item.is_empty(): return reject("商品不存在。")
	if profile.inventory.has(id): return reject("该商品已兑换，库存为零。")
	if profile.tokens < int(item.price): return reject("演练代币不足。")
	profile.tokens -= int(item.price)
	profile.inventory[id] = true
	add_event("buy", {"item":id,"price":item.price})
	error = "兑换完成：" + str(item.name)
	changed.emit()
	return true

func best_action() -> Dictionary:
	if profile.run.is_empty() or not profile.run.node in ["battle","boss"]: return {}
	var best: Dictionary = {}
	var best_score: float = 0
	for card: CruiseCrewCard in hand.cards:
		if find_unit(card.owner_id).stats.health <= 0 or not energy_stats.can_play_card(card): continue
		var targets: Array[CruiseUnit] = valid_targets(card)
		for target in targets:
			var score: float = 0
			for effect in card.effect_data:
				var amount: int = int(effect.amount)
				if effect.type == "damage":
					var damage: int = amount+int(buffs.power)+(int(buffs.combo) if last_owner == card.owner_id else 0)
					if card.target_kind == "allEnemies":
						for enemy in alive_units(enemies): score += mini(enemy.stats.health,damage)*1.8
					else: score += mini(target.stats.health,damage)*1.8
					if target.enemy and target.stats.health <= damage: score += 7
				elif effect.type == "heal": score += mini(target.stats.max_health-target.stats.health,amount+int(buffs.healing))*(2.4 if target.stats.health < target.stats.max_health*0.5 else 1.1)
				elif effect.type in ["shield","shieldSelf","shieldAll"]:
					var protected: Array[CruiseUnit] = [target]
					if effect.type == "shieldSelf": protected = [find_unit(card.owner_id)]
					elif effect.type == "shieldAll" or card.target_kind == "allAllies": protected = alive_units(allies)
					for ally in protected:
						var incoming: int = 0
						for enemy in alive_units(enemies):
							if enemy.intent.type == "all" or enemy.intent.target == ally.unit_id: incoming += int(enemy.intent.amount)
						score += mini(maxi(0,incoming-ally.stats.block),amount)*(2.6 if ally.stats.health < incoming else 0.65)
				elif effect.type == "draw" and energy_stats.mana > 1: score += 5
			score /= maxi(1,card.cost)
			if score > best_score:
				best_score = score
				best = {"uid":card.unique_id,"target":target.unit_id if card.target_kind in ["enemy","ally"] else "auto","score":score}
	return best
