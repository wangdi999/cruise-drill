extends Node

var passed: Array = []
var failures: Array = []
var rule: CruiseRules
var artifact_dir: String

func _ready() -> void:
	call_deferred("run_tests")

func check(value: bool, name: String) -> void:
	if value: passed.append(name); print("通过：",name)
	else: failures.append(name); push_error("失败："+name)

func fresh(day_value: int = 1) -> void:
	rule.clock_override = 1700000000.0
	rule.reset()
	rule.set_day(day_value)

func win_fixture() -> void:
	for unit in rule.enemies: unit.stats.health = 0
	rule.end_turn()

func to_buff() -> void:
	rule.start(1,rule.profile.team.duplicate())
	win_fixture()

func draft_first() -> void:
	if rule.profile.run.node == "draft":
		var option: Dictionary = rule.draft_options()[0]
		rule.choose_draft(option.owner,int(option.kind))

func to_complete() -> void:
	to_buff()
	draft_first()
	rule.choose_buff("shield")
	win_fixture()

func fight() -> bool:
	for i in range(250):
		if not rule.profile.run.node in ["battle","boss"]: return rule.profile.run.node in ["draft","buff","complete"]
		if not rule.best_command().is_empty():
			rule.use_command(rule.best_command())
			continue
		var plan: Dictionary = rule.best_action()
		if plan.is_empty(): rule.end_turn()
		else: rule.play(int(plan.uid),plan.target)
	return false

func charge_fixture() -> void:
	fresh()
	rule.start(1,rule.profile.team.duplicate())
	rule.hand.cards.clear()
	for i in range(3): rule.hand.add_card(rule.create_card(rule.profile.team[i],0,91+i))
	rule.play(91,"drone")
	rule.play(92,"medic")
	rule.play(93,"drone")

func feature_tests() -> void:
	fresh()
	rule.start(1,rule.profile.team.duplicate())
	check(not rule.use_command("strike"),"未蓄满不能使用免费指令")
	rule.hand.cards.clear()
	for i in range(3): rule.hand.add_card(rule.create_card("ranger",0,91+i))
	for i in range(3): rule.play(91+i,"drone")
	check(rule.relay == ["ranger"] and not rule.command_ready,"同角色重复出牌不会重复蓄能")
	rule.end_turn()
	check(rule.relay == ["ranger"],"未蓄满的接力进度跨回合保留")
	charge_fixture()
	check(rule.command_ready and rule.energy_stats.mana == 0,"三位队员真实出牌完成接力")
	var charged: Dictionary = JSON.parse_string(JSON.stringify(rule.profile))
	check(rule.import_profile(charged) and rule.command_ready and rule.relay.size()==3,"刷新恢复接力成员与就绪指令")
	var before: int = rule.enemies[0].stats.health
	check(rule.use_command("strike") and rule.enemies[0].stats.health==before-8 and rule.energy_stats.mana==0,"齐射全体伤害且零能量也可使用")
	check(not rule.use_command("barrier") and rule.command_used and rule.relay.is_empty(),"指令消费蓄能，禁止重复领取")
	rule.import_profile(charged)
	rule.use_command("barrier")
	check(rule.allies[1].stats.block==9,"屏障指令向队友提供九点护盾")
	rule.import_profile(charged)
	rule.allies[0].stats.health=20
	rule.allies[2].stats.health=0
	var hand_before: int = rule.hand.cards.size()
	rule.use_command("supply")
	check(rule.allies[0].stats.health==26 and rule.allies[2].stats.health==0 and rule.hand.cards.size()==hand_before+1,"补给恢复与抽牌生效，不能复活倒下角色")
	rule.import_profile(charged)
	rule.end_turn()
	check(rule.command_ready and not rule.command_used,"就绪指令可保留到下一回合")
	fresh()
	to_buff()
	check(rule.profile.run.node=="draft" and not rule.choose_buff("shield"),"新流程必须先改装，不能越过奖励节点")
	var rng_before: String = str(RNG.instance.state)
	var options: Array = rule.draft_options()
	check(options==rule.draft_options() and str(RNG.instance.state)==rng_before,"奖励种子稳定且不影响战斗随机状态")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(rule.profile))
	rule.import_profile(snapshot)
	check(rule.draft_options()==options,"奖励页面刷新不重抽")
	check(not rule.choose_draft("ember",2) and not rule.choose_draft(options[0].owner,4),"拒绝队伍外角色和不存在的专属牌")
	rule.choose_draft(options[0].owner,int(options[0].kind))
	check(not rule.choose_draft(options[1].owner,int(options[1].kind)),"改装只能确认一次")
	rule.choose_buff("shield")
	var upgraded: int = 0
	var basic: int = 0
	for pile in [rule.hand,rule.draw_pile,rule.discard_pile]:
		for c: CruiseCrewCard in pile.cards:
			if c.card_kind>=2: upgraded+=1
			if c.owner_id==options[0].owner and c.card_kind==0: basic+=1
	check(upgraded==2 and basic==0 and rule.hand.cards.size()+rule.draw_pile.cards.size()==12,"两张专属牌替换两张基础牌，牌组总数不膨胀")
	snapshot=JSON.parse_string(JSON.stringify(rule.profile))
	check(rule.import_profile(snapshot) and rule.profile.run.draft==snapshot.run.draft,"专属牌、改装选择与首领牌堆可存档恢复")
	rule.turn=2
	rule.enemies[0].stats.health=41
	rule.plan_enemies()
	rule.hand.add_card(rule.create_card("ranger",0,99))
	before=rule.allies[0].stats.health
	rule.play(99,"boss")
	check(rule.boss_enraged and rule.enemies[0].intent.type=="all" and rule.allies[0].stats.health==before,"首领半血更新当前意图，变招不立即偷袭")
	check(int(rule.enemies[0].intent.amount)==8,"过载伤害按基础加三再计算群攻系数")
	snapshot=JSON.parse_string(JSON.stringify(rule.profile))
	check(rule.import_profile(snapshot) and rule.boss_enraged and rule.enemies[0].intent.type=="all","刷新保留首领阶段与已预告意图")
	fresh()
	rule.start(1,rule.profile.team.duplicate())
	snapshot=JSON.parse_string(JSON.stringify(rule.profile))
	snapshot.run.erase("relayMode")
	snapshot.run.erase("draft")
	for key in ["relay","commandReady","commandUsed","bossEnraged"]: snapshot.run.battle.erase(key)
	check(rule.import_profile(snapshot) and not rule.command_ready,"旧版本战斗存档兼容导入")
	win_fixture()
	check(rule.profile.run.node=="buff","旧版本进行中挑战保留原来的节点流程")
	var special_count: int = 0
	for h in rule.config.heroes:
		for kind in [2,3]:
			fresh()
			var team: Array = [h.id]
			for owner in ["ranger","medic","guard"]:
				if team.size()<3 and not team.has(owner): team.append(owner)
			rule.start(1,team)
			var card: CruiseCrewCard = rule.create_card(h.id,kind,99)
			rule.hand.add_card(card)
			if rule.play(99,rule.valid_targets(card)[0].unit_id) and rule.energy_stats.mana==3-card.cost: special_count+=1
	check(special_count==12,"六位角色的十二种专属牌均可合法施放并正确耗能")

func run_tests() -> void:
	artifact_dir = ProjectSettings.globalize_path("res://../artifacts")
	DirAccess.make_dir_recursive_absolute(artifact_dir)
	rule = CruiseRules.new()
	get_tree().root.add_child(rule)
	fresh()
	check(not rule.start(2,rule.profile.team.duplicate()),"开放日阻止直接进入阶段二")
	rule.set_day(4)
	check(not rule.start(3,rule.profile.team.duplicate()),"开放日满足仍需前置阶段")
	check(not rule.start(1,["medic","guard","sentinel"]) and not rule.start(1,["ranger","ranger","medic"]),"无输出与重复角色队伍被拒绝")
	rule.start(1,rule.profile.team.duplicate())
	var original_hand: int = rule.hand.cards.size()
	var attack: CruiseCrewCard = rule.create_card("ranger",0,91)
	rule.hand.add_card(attack)
	var events: Array = []
	Events.card_played.connect(func(card):events.append(card.id))
	check(attack is Card and rule.draw_pile is CardPile and rule.allies[0].stats is Stats,"真实继承上游 Card / CardPile / Stats")
	check(not rule.play(91,"medic") and rule.energy_stats.mana == 3,"错误目标不扣能量")
	var before: int = rule.enemies[0].stats.health
	rule.play(91,"drone")
	check(rule.energy_stats.mana == 2 and rule.enemies[0].stats.health == before-8 and events.has("ranger_0"),"上游 Card.play 扣能量并触发出牌事件")
	var guard: CruiseUnit = rule.find_unit("guard")
	guard.stats.block = 10
	var hp: int = guard.stats.health
	guard.stats.take_damage(13)
	guard.stats.heal(999)
	check(guard.stats.health == guard.stats.max_health and guard.stats.block == 0 and hp == guard.stats.max_health,"上游 Stats 护盾抵扣与生命上限")
	rule.hand.add_card(rule.create_card("guard",1,92))
	rule.play(92)
	var hit_before: Array = []
	for unit in rule.allies: hit_before.append(unit.stats.health)
	rule.end_turn()
	var hit_after: Array = []
	for unit in rule.allies: hit_after.append(unit.stats.health)
	check(hit_before == hit_after and guard.stats.block == 0 and rule.energy_stats.mana == 3,"嘲讽承压、护盾跨回合清空与能量恢复")
	var saved: String = JSON.stringify(rule.profile)
	var hand_ids: Array = rule.pile_snapshot(rule.hand)
	var rng_state: String = str(RNG.instance.state)
	check(rule.import_profile(JSON.parse_string(saved)) and rule.pile_snapshot(rule.hand) == hand_ids and str(RNG.instance.state)==rng_state,"JSON 恢复手牌、生命和无精度损失的随机状态")
	var total: int = rule.hand.cards.size()+rule.draw_pile.cards.size()+rule.discard_pile.cards.size()
	check(total == 14 and original_hand == 5,"测试添加两牌后牌堆总量守恒，起始手牌五张")
	fresh(4)
	rule.profile.completed["1"] = {"time":rule.now()}
	rule.start(2,rule.profile.team.duplicate())
	check(not rule.choose_buff("power"),"基础战斗未完成不可跳到增益节点")
	rule.choose_route("A")
	rule.allies[0].stats.health = 20
	win_fixture()
	var healed: int = int(rule.profile.run.party[0].hp)
	draft_first()
	rule.choose_buff("healing")
	check(healed == 32 and rule.allies[0].stats.health == 40,"路线补给与医疗增益作用于保留生命")
	rule.abandon()
	rule.start(2,rule.profile.team.duplicate())
	rule.choose_route("B")
	check(rule.buffs.power == 2 and rule.buffs.healing == 0 and rule.enemies[0].stats.health == 42,"突击路线强化敌我，上一局增益清空")
	fresh()
	to_buff()
	draft_first()
	rule.choose_buff("combo")
	rule.hand.add_card(rule.create_card("ranger",0,91))
	rule.hand.add_card(rule.create_card("ranger",0,92))
	before = rule.enemies[0].stats.health
	rule.play(91,"boss")
	rule.play(92,"boss")
	check(before-rule.enemies[0].stats.health == 19,"同角色连续行动增伤为 8 + 11")
	fresh()
	check(not rule.claim(1),"未确认首领胜利不能领取")
	to_complete()
	rule.claim(1)
	check(not rule.claim(1) and rule.profile.tokens == 100,"首通领取幂等，不重复发奖")
	rule.profile.tokens = 80
	saved = JSON.stringify(rule.profile)
	check(not rule.buy("frame") and JSON.stringify(rule.profile) == saved,"余额 80 购买 100 商品无状态变化")
	check(rule.buy("materials") and rule.profile.tokens == 0 and not rule.buy("materials"),"兑换扣款与库存一起更新，重复兑换拒绝")
	fresh()
	to_complete()
	rule.set_day(8)
	check(rule.profile.run.is_empty() and rule.claim(1) and not rule.start(1,rule.profile.team.duplicate()),"第八天停止战斗，已确认胜利允许补领")
	rule.set_day(9)
	var materials: int = int(rule.profile.materials)
	rule.sync_time()
	check(materials == 100 and rule.profile.tokens == 0 and rule.profile.materials == 100 and not rule.buy("frame"),"第九天关闭商店，代币仅转换一次")
	fresh(7)
	rule.start(1,rule.profile.team.duplicate())
	rule.clock_override += CruiseRules.DAY
	rule.sync_time()
	check(rule.profile.run.is_empty(),"真实经过一天后作废未完成挑战")
	fresh()
	rule.start(1,rule.profile.team.duplicate())
	for unit in rule.allies: unit.stats.health = 0
	rule.end_turn()
	check(rule.profile.run.node == "failed" and not rule.claim(1),"全队倒下判负，不发奖励")
	fresh()
	rule.start(1,rule.profile.team.duplicate())
	var broken: Dictionary = rule.profile.duplicate(true)
	broken.run.battle.hand = null
	check(not rule.import_profile(broken),"损坏存档被拒绝且不覆盖当前状态")
	feature_tests()
	var complete_runs: int = 0
	var total_runs: int = 0
	for stage_id in range(1,4):
		for route in ["A"] if stage_id==1 else ["A","B"]:
			for buff in rule.available_buffs(stage_id):
				for seed_value in range(1,6):
					fresh(4)
					rule.profile.seed = seed_value
					rule.profile.completed = {"1":{"time":rule.now()},"2":{"time":rule.now()}}
					rule.start(stage_id,rule.profile.team.duplicate())
					if stage_id>1: rule.choose_route(route)
					if fight(): draft_first(); rule.choose_buff(buff); fight()
					total_runs += 1
					if rule.profile.run.node == "complete": complete_runs += 1
	check(complete_runs == total_runs,"完整真实出牌通关：默认队伍全路线增益 %s / %s" % [complete_runs,total_runs])
	var report: Dictionary = {"engine":Engine.get_version_info().string,"passed":passed,"failures":failures,"real_combat_runs":total_runs,"real_combat_completed":complete_runs,"note":"自动化验收，不是玩家试玩。"}
	FileAccess.open(artifact_dir.path_join("godot-tests.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("核心测试：%s 通过 / %s 失败" % [passed.size(),failures.size()])
	rule.free()
	get_tree().quit(0 if failures.is_empty() else 1)
