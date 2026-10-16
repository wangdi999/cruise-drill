extends Control

const SAVE_PATH: String = "user://cruise-design-v2.json"
const INK: Color = Color("e8eedb")
const MUTED: Color = Color("a5b8b5")
const ACCENT: Color = Color("d4eb88")
const WARM: Color = Color("f4b77c")
const CYAN: Color = Color("8bd2cb")
var rules: CruiseRules
var stage: int = 1
var root_box: VBoxContainer
var action_buttons: Dictionary = {}
var qa: bool = false
var refresh_pending: bool = false
var tick: float = 0
var confirmation: ConfirmationDialog
var confirm_action: Callable

func _ready() -> void:
	var skin: Theme = Theme.new()
	skin.default_font = load("res://cruise/assets/PortfolioSans.ttf")
	skin.default_font_size = 17
	skin.set_color("font_color","Label",INK)
	skin.set_color("font_color","Button",INK)
	skin.set_color("font_disabled_color","Button",MUTED.darkened(0.25))
	skin.set_stylebox("normal","Button",box_style(Color("1b2d32"),Color("41565b")))
	skin.set_stylebox("hover","Button",box_style(Color("30474a"),ACCENT))
	skin.set_stylebox("pressed","Button",box_style(Color("3c5143"),ACCENT))
	skin.set_stylebox("disabled","Button",box_style(Color("17252a"),Color("304045")))
	skin.set_stylebox("focus","Button",box_style(Color.TRANSPARENT,WARM))
	theme = skin
	RenderingServer.set_default_clear_color(Color("101a1e"))
	rules = CruiseRules.new()
	add_child(rules)
	rules.changed.connect(on_changed)
	var saved: String = ""
	if OS.has_feature("web"):
		saved = str(JavaScriptBridge.eval("(() => {try{return localStorage.getItem('cruise-godot-v2') || ''}catch(e){return ''}})()"))
	if saved.is_empty() and FileAccess.file_exists(SAVE_PATH):
		saved = FileAccess.get_file_as_string(SAVE_PATH)
	if not saved.is_empty():
		var data = JSON.parse_string(saved)
		if not rules.import_profile(data):
			rules.reset()
			rules.error = "存档格式不兼容，已创建新的展示存档。"
	stage = int(rules.profile.run.get("stage",1))
	qa = OS.get_cmdline_user_args().has("--qa")
	if OS.has_feature("web"):
		qa = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('qa') === '1'"))
	get_viewport().size_changed.connect(schedule_render)
	save()
	render()

func box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _process(delta: float) -> void:
	tick += delta
	if tick >= 1:
		tick = 0
		if rules.sync_time():
			save()
			schedule_render()

func on_changed() -> void:
	save()
	schedule_render()

func save() -> void:
	# 浏览器同步备份，避免 IndexedDB 尚未刷盘时立刻刷新丢失最后操作。
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(() => {try{localStorage.setItem('cruise-godot-v2',%s)}catch(e){}})()" % JSON.stringify(JSON.stringify(rules.profile)))
	var file: FileAccess = FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(rules.profile))
	else: rules.error = "无法写入本地存档，当前会话仍可游玩；请导出记录。"

func schedule_render() -> void:
	if refresh_pending: return
	refresh_pending = true
	call_deferred("render")

func text(parent: Node, value: String, size: int = 17, color: Color = INK) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func button(parent: Node, id: String, title: String, action: Callable, disabled: bool = false, active: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = title
	b.disabled = disabled
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0,48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if active:
		b.add_theme_stylebox_override("normal",box_style(Color("293e35"),ACCENT))
		b.add_theme_color_override("font_color",ACCENT)
	b.pressed.connect(func(): action.call(); schedule_render())
	parent.add_child(b)
	action_buttons[id] = b
	return b

func section(parent: Node, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",box_style(Color("18282d"),Color("34494d")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation",12)
	panel.add_child(stack)
	if not title.is_empty(): text(stack,title,21)
	return stack

func row(parent: Node) -> HBoxContainer:
	var result: HBoxContainer = HBoxContainer.new()
	result.add_theme_constant_override("separation",12)
	parent.add_child(result)
	return result

func render() -> void:
	refresh_pending = false
	var old_scroll: int = 0
	if root_box:
		old_scroll = int(get_node("Scroll").scroll_vertical)
		remove_child(get_node("Scroll"))
		root_box.get_parent().get_parent().queue_free()
	action_buttons.clear()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value):
		if qa: call_deferred("publish_qa")
	)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	scroll.add_child(margin)
	root_box = VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation",20)
	margin.add_child(root_box)
	var head: BoxContainer = HBoxContainer.new() if get_viewport_rect().size.x >= 700 else VBoxContainer.new()
	head.add_theme_constant_override("separation",12)
	root_box.add_child(head)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	text(title_box,"PLAY / DESIGN   ·   开源改造作品",12,ACCENT)
	text(title_box,"巡航演练 · 舰队协同",34)
	text(title_box,"组建队伍，预判意图，让每一张牌都有选择的理由。",15,MUTED)
	var day_select: OptionButton = OptionButton.new()
	day_select.custom_minimum_size = Vector2(185,45)
	for d in [1,2,4,7,8,9]: day_select.add_item("演练第 %s 天%s" % [d," · 仅兑换" if d == 8 else " · 已结束" if d == 9 else ""],d)
	day_select.select([1,2,4,7,8,9].find(int(rules.profile.day)))
	day_select.item_selected.connect(func(i): rules.set_day(day_select.get_item_id(i)))
	head.add_child(day_select)
	action_buttons["daySelect"] = day_select
	if not rules.error.is_empty(): text(root_box,rules.error,15,WARM)
	text(root_box,"战斗截止：第 8 天；兑换截止：第 9 天。当前 %s / 7 天 · 本机自动存档" % mini(7,int(rules.activity_day())),13,MUTED)
	var wide: bool = get_viewport_rect().size.x >= 850
	var columns: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	columns.add_theme_constant_override("separation",20)
	root_box.add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 265 if wide else 0
	left.add_theme_constant_override("separation",16)
	columns.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",16)
	columns.add_child(right)
	if not wide: columns.move_child(right,0)
	render_sidebar(left)
	render_run(right)
	if rules.profile.run.is_empty(): render_team(right)
	var manual: VBoxContainer = section(right,"舰桥操作手册")
	text(manual,"每回合 3 能量，抽 5 张牌。先选牌，再选高亮目标；群体牌直接施放。敌方意图提前显示，护盾在下个玩家回合清零。倒下队员不可出牌或被恢复。",14,MUTED)
	text(manual,"基础战斗 → 增益选择 → 首领战。路线 A 战后恢复 12，路线 B 全局伤害 +2 但敌方更强；首通奖励相同。",14,MUTED)
	var controls: HBoxContainer = row(manual)
	button(controls,"export","导出演练记录",export_record)
	button(controls,"reset","重置展示存档",func(): ask_confirm("重置会清除本机进度、代币与占位奖励。",func():rules.reset();stage=1;save()))
	text(root_box,"基于 guladam/deck_builder_tutorial（MIT）改造。新增组队、活动节点与奖励系统；原项目代码、许可证与改造清单完整保留。",12,MUTED)
	scroll.set_deferred("scroll_vertical",old_scroll)
	if qa: call_deferred("publish_qa")

func render_sidebar(parent: Node) -> void:
	var stages: VBoxContainer = section(parent,"演练航线")
	for s in rules.config.stages:
		var id: int = int(s.id)
		var reason: String = rules.lock_reason(id)
		var label: String = "已通关" if rules.profile.completed.has(str(id)) else reason if not reason.is_empty() else "可挑战"
		button(stages,"stage_%s" % id,"0%s  %s\n%s" % [id,s.name,label],func():stage=id;rules.error=reason, false,stage==id)
	var rewards: VBoxContainer = section(parent,"首通奖励 · %s / 300" % (rules.profile.claimed.size()*100))
	for s in rules.config.stages:
		var id: int = int(s.id)
		var claimed: bool = rules.profile.claimed.has(str(id))
		button(rewards,"claim_%s" % id,"%s · %s" % [s.name,"已领取" if claimed else "领取 100"],func():rules.claim(id),claimed or not rules.profile.completed.has(str(id)) or rules.activity_day()>=9)
	var shop: VBoxContainer = section(parent,"兑换仓库")
	text(shop,"%s 演练代币" % int(rules.profile.tokens),29,WARM)
	for item in rules.config.shop:
		var bought: bool = rules.profile.inventory.has(item.id)
		button(shop,"buy_"+item.id,"%s\n%s" % [item.name,"已兑换 · 库存 0" if bought else "%s 代币 · 库存 1" % int(item.price)],func():rules.buy(item.id),bought or rules.profile.tokens<int(item.price) or rules.activity_day()>=9)
	text(shop,"商店关闭，已转 %s 普通材料。" % int(rules.profile.materials) if rules.activity_day()>=9 else "奖励为原型占位，不影响战斗。第 9 天剩余代币按 1:1 转材料。",12,MUTED)

func render_team(parent: Node) -> void:
	var stack: VBoxContainer = section(parent,"组建三人小队 · %s / 3" % rules.profile.team.size())
	text(stack,"六名固定试用角色，至少一名输出；每名角色带来两种卡，各两张，共 12 张牌。",14,MUTED)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3 if get_viewport_rect().size.x > 1100 else 2
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	stack.add_child(grid)
	for h in rules.config.heroes:
		var picked: bool = rules.profile.team.has(h.id)
		var title: String = "%s %s  %s\n%s / HP %s\n%s\n%s（%s 费） / %s（%s 费）" % ["✓" if picked else "",h.glyph,h.name,h.role,int(h.hp),h.desc,h.cards[0].name,int(h.cards[0].cost),h.cards[1].name,int(h.cards[1].cost)]
		var b: Button = button(grid,"hero_"+h.id,title,func():toggle_hero(h.id),false,picked)
		b.custom_minimum_size = Vector2(0,145)
	var reason: String = rules.lock_reason(stage)
	text(stack,reason if not reason.is_empty() else "队伍已就绪。" if rules.valid_team(rules.profile.team) else "请选择三个角色，且至少一名输出。",14,WARM)
	button(stack,"start","出发 · %s →" % rules.config.stages[stage-1].name,func():rules.start(stage,rules.profile.team.duplicate()),not reason.is_empty() or not rules.valid_team(rules.profile.team),true)

func toggle_hero(id: String) -> void:
	if rules.profile.team.has(id): rules.profile.team.erase(id)
	elif rules.profile.team.size()<3: rules.profile.team.append(id)
	else: rules.error = "先取消一名角色，再选择新队员。"; return
	rules.error = ""
	save()

func render_run(parent: Node) -> void:
	var run: Dictionary = rules.profile.run
	if run.is_empty():
		var intro: VBoxContainer = section(parent,"VOYAGE / 0%s" % stage)
		text(intro,rules.config.stages[stage-1].name,30,ACCENT)
		text(intro,rules.config.stages[stage-1].desc,17,MUTED)
		text(intro,"01 基础战斗    →    02 增益选择    →    03 阶段首领",16,CYAN)
		return
	var stack: VBoxContainer = section(parent,rules.config.stages[int(run.stage)-1].name)
	text(stack,"01 基础战斗   →   02 增益选择   →   03 阶段首领",13,CYAN)
	match run.node:
		"route":
			text(stack,"选择本次航线",29,ACCENT)
			button(stack,"route_A","路线 A / 稳定补给\n标准敌人。基础战斗后存活队员各恢复 12 生命。",func():rules.choose_route("A"))
			button(stack,"route_B","路线 B / 风险火力\n全局伤害 +2；普通敌人 HP +6 / 伤害 +1，首领 HP +12 / 伤害 +2。",func():rules.choose_route("B"))
			text(stack,"两条路线的首通奖励相同：100 代币。",14,WARM)
		"buff":
			text(stack,"基础战斗完成 · 选择首领增益",27,ACCENT)
			text(stack,"补给生效：存活队员恢复 12。" if run.route == "A" else "突击伤害 +2 继续生效。",14,MUTED)
			for id in rules.available_buffs(int(run.stage)):
				var buff: Dictionary = rules.config.buffs[id]
				button(stack,"buff_"+id,buff.name+"\n"+buff.desc,func():rules.choose_buff(id))
		"complete", "failed":
			var won: bool = run.node == "complete"
			text(stack,"航线演练完成" if won else "小队需要重新集结",31,ACCENT if won else WARM)
			text(stack,"首通奖励仅领取一次，重复挑战不增加代币。" if won else "失败不扣代币，不消耗首通奖励；重试会回到阶段起点。",15,MUTED)
			if won and not rules.profile.claimed.has(str(int(run.stage))): button(stack,"resultClaim","领取 100 演练代币",func():rules.claim(int(run.stage)),false,true)
			button(stack,"return","返回舰桥" if won else "重新挑战本阶段",func():finish_run(not won))
			if won and int(run.stage)<3: button(stack,"next","查看下一阶段 →",func():stage=int(run.stage)+1;rules.abandon())
		"battle", "boss": render_battle(stack)
	if not run.node in ["complete","failed"]: button(stack,"abandon","放弃本局",func():ask_confirm("放弃会清除本局进度，已确认的首通与奖励保留。",func():rules.abandon()))

func render_battle(parent: Node) -> void:
	var run: Dictionary = rules.profile.run
	text(parent,"%s · 第 %s 回合 / 能量 %s / 3" % [rules.config.stages[int(run.stage)-1].boss if run.node=="boss" else "巡航警戒区",rules.turn,rules.energy_stats.mana],24,WARM)
	text(parent,"当前增益：%s%s" % ["突击伤害 +2 · " if run.route=="B" else "",rules.config.buffs[run.buff].name if not run.buff.is_empty() else "无"],13,CYAN)
	var enemy_row: HBoxContainer = row(parent)
	for unit in rules.enemies: render_unit(enemy_row,unit)
	var ally_row: HBoxContainer = row(parent)
	for unit in rules.allies: render_unit(ally_row,unit)
	text(parent,"你的手牌 · 抽牌堆 %s / 弃牌堆 %s" % [rules.draw_pile.cards.size(),rules.discard_pile.cards.size()],16)
	var cards: GridContainer = GridContainer.new()
	cards.columns = 5 if get_viewport_rect().size.x > 1100 else 3 if get_viewport_rect().size.x > 800 else 2
	cards.add_theme_constant_override("h_separation",10)
	cards.add_theme_constant_override("v_separation",10)
	parent.add_child(cards)
	for card: CruiseCrewCard in rules.hand.cards:
		var picked: bool = rules.selected_uid == card.unique_id
		var dead: bool = rules.find_unit(card.owner_id).stats.health<=0
		var title: String = "%s · %s 费\n\n%s\n\n%s\n%s" % [rules.hero(card.owner_id).name,card.cost,card.display_name,rules.card_description(card),"已倒下" if dead else "选择敌人" if card.target_kind=="enemy" else "选择队员" if card.target_kind=="ally" else "直接施放"]
		var b: Button = button(cards,"card_%s" % card.unique_id,title,func():select_card(card.unique_id),dead or not rules.energy_stats.can_play_card(card),picked)
		b.add_theme_font_size_override("font_size",15)
		b.custom_minimum_size = Vector2(0,165)
	var control: HBoxContainer = row(parent)
	text(control,"选择高亮目标，或再次点击卡牌取消。" if rules.selected_uid>=0 else "能量耗尽，结束回合。" if rules.energy_stats.mana==0 else "先选择手牌，再选择目标。",14,WARM)
	button(control,"endTurn","结束回合 →",func():rules.end_turn(),false,true)
	var log_box: VBoxContainer = section(parent,"最近战斗记录")
	text(log_box,"\n".join(PackedStringArray(rules.logs.slice(-5))),13,MUTED)

func render_unit(parent: Node, unit: CruiseUnit) -> void:
	var card: CruiseCrewCard = rules.find_card(rules.selected_uid)
	var targetable: bool = card and unit in rules.valid_targets(card)
	var intent: String = ""
	if unit.enemy and unit.stats.health>0:
		intent = "群体攻击 · 每人 %s" % int(unit.intent.amount) if unit.intent.type=="all" else "攻击 %s · %s" % [rules.find_unit(unit.intent.target).display_name,int(unit.intent.amount)]
	var title: String = "%s  %s\nHP %s / %s    护盾 %s\n%s%s" % [unit.glyph,unit.display_name,unit.stats.health,unit.stats.max_health,unit.stats.block,intent," · 嘲讽" if unit.taunt else ""]
	var b: Button = button(parent,"target_"+unit.unit_id,title,func():if rules.selected_uid>=0:rules.play(rules.selected_uid,unit.unit_id),unit.stats.health<=0,targetable)
	b.custom_minimum_size = Vector2(0,105 if unit.enemy else 85)
	b.add_theme_font_size_override("font_size",15)
	if unit.enemy: b.add_theme_color_override("font_color",WARM)

func select_card(uid: int) -> void:
	var card: CruiseCrewCard = rules.find_card(uid)
	if not card: return
	if card.target_kind in ["enemy","ally"]: rules.selected_uid = -1 if rules.selected_uid == uid else uid
	else: rules.play(uid)

func finish_run(retry: bool) -> void:
	var id: int = int(rules.profile.run.stage)
	rules.abandon()
	if retry: rules.start(id,rules.profile.team.duplicate())

func ask_confirm(message: String, action: Callable) -> void:
	if confirmation: confirmation.queue_free()
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认操作"
	confirmation.dialog_text = message
	confirmation.ok_button_text = "确认"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(action)
	confirmation.confirmed.connect(schedule_render)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(520,150))

func export_record() -> void:
	var value: String = JSON.stringify({"profile":rules.profile,"note":"本机记录；自动化记录和真人试玩需单独标注。"},"  ")
	if OS.has_feature("web"):
		var script: String = "(() => { const value=%s;const u=URL.createObjectURL(new Blob([value],{type:'application/json'}));const a=document.createElement('a');a.href=u;a.download='巡航演练-改造记录.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000) })()" % JSON.stringify(value)
		JavaScriptBridge.eval(script)
	else:
		var file: FileAccess = FileAccess.open("user://cruise-export.json",FileAccess.WRITE)
		if file: file.store_string(value); rules.error = "记录已保存："+ProjectSettings.globalize_path("user://cruise-export.json")

func publish_qa() -> void:
	await get_tree().process_frame
	if not OS.has_feature("web"): return
	var buttons: Dictionary = {}
	for id in action_buttons:
		var b: Control = action_buttons[id]
		if not is_instance_valid(b): continue
		var rect: Rect2 = b.get_global_rect()
		buttons[id] = {"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y,"disabled":b.disabled if b is Button else false}
	var state: Dictionary = {"profile":rules.profile,"stage":stage,"selected":rules.selected_uid,"buttons":buttons,"plan":rules.best_action(),"viewport":{"w":get_viewport_rect().size.x,"h":get_viewport_rect().size.y}}
	JavaScriptBridge.eval("window.__cruiseQA="+JSON.stringify(state))
