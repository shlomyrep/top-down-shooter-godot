extends Control

@onready var health_bar := $TopLeft/VBox/StatsRow/HealthBar
@onready var health_label := $TopLeft/VBox/StatsRow/HealthBar/HealthLabel
@onready var score_label := $TopRight/VBox/InfoRow/ScoreLabel
@onready var wave_label := $TopRight/VBox/WaveLabel
@onready var coin_label := $TopRight/VBox/InfoRow/CoinLabel
@onready var weapon_icon := $TopLeft/VBox/StatsRow/WeaponIcon
@onready var wave_transition_panel := $WaveTransitionPanel
@onready var wave_complete_title := $WaveTransitionPanel/CenterContainer/VBox/WaveCompleteTitle
@onready var story_label := $WaveTransitionPanel/CenterContainer/VBox/StoryLabel
@onready var countdown_bar := $WaveTransitionPanel/CenterContainer/VBox/CountdownBar
@onready var buy_prompt_label := $BuyPromptLabel
@onready var buy_btn          := $BuyBtn
@onready var build_panel       := $BuildPanel
@onready var build_timer_bar   := $BuildPanel/VBox/BuildTimerBar
@onready var wall_btn          := $BuildPanel/VBox/Palette/WallBtn
@onready var door_btn          := $BuildPanel/VBox/Palette/DoorBtn
@onready var tower_btn         := $BuildPanel/VBox/Palette/TowerBtn
@onready var erase_btn         := $BuildPanel/VBox/Palette/EraseBtn
@onready var place_btn         := $PlaceBtn
@onready var door_toggle_btn   := $DoorToggleBtn
@onready var build_picker      := $BuildPicker
@onready var template_btn        := $BuildPanel/VBox/Palette/TemplateBtn
@onready var template_picker     := $BuildPanel/VBox/TemplatePicker
@onready var small_btn           := $BuildPanel/VBox/TemplatePicker/SizeRow/SmallBtn
@onready var medium_btn          := $BuildPanel/VBox/TemplatePicker/SizeRow/MediumBtn
@onready var large_btn           := $BuildPanel/VBox/TemplatePicker/SizeRow/LargeBtn
@onready var template_cost_label := $BuildPanel/VBox/TemplatePicker/TemplateCostLabel
@onready var repair_all_btn      := $BuildPanel/VBox/RepairAllBtn
@onready var _ready_btn          := $BuildPanel/VBox/ReadyBtn
@onready var support_panel        := $SupportPanel
@onready var airstrike_btn        := $SupportPanel/VBox/AirstrikeBtn
@onready var squad_btn            := $SupportPanel/VBox/SquadBtn
@onready var shield_squad_btn     := $SupportPanel/VBox/ShieldSquadBtn
@onready var weapon_shop_overlay  := $WeaponShopOverlay
@onready var _pistol_buy_btn     := $WeaponShopOverlay/Center/ShopPanel/Margin/VBox/PistolCard/HBox/PistolBuyBtn
@onready var _shotgun_buy_btn    := $WeaponShopOverlay/Center/ShopPanel/Margin/VBox/ShotgunCard/HBox/ShotgunBuyBtn
@onready var _rifle_buy_btn      := $WeaponShopOverlay/Center/ShopPanel/Margin/VBox/RifleCard/HBox/RifleBuyBtn
@onready var _lmg_buy_btn        := $WeaponShopOverlay/Center/ShopPanel/Margin/VBox/LmgCard/HBox/LmgBuyBtn
@onready var shield_bar          := $TopLeft/VBox/ShieldBar
@onready var shield_label        := $TopLeft/VBox/ShieldBar/ShieldLabel
@onready var recovery_shop_overlay := $RecoveryShopOverlay
@onready var _health_buy_btn     := $RecoveryShopOverlay/Center/ShopPanel/Margin/VBox/HealthCard/HBox/HealthBuyBtn
@onready var _shield_buy_btn     := $RecoveryShopOverlay/Center/ShopPanel/Margin/VBox/ShieldCard/HBox/ShieldBuyBtn

signal buy_pressed
signal weapon_shop_buy(weapon_id: String)
signal recovery_shop_buy(item_id: String)
signal build_ready_pressed
signal build_place_pressed
signal build_item_selected(item: String)
signal build_picker_selected(type: String)
signal door_toggle_pressed
signal template_size_selected(size: String)
signal repair_all_pressed
signal airstrike_pressed
signal squad_pressed
signal shield_squad_pressed

var _doors_open := false
var _door_toggle_cooldown := 0.0  # prevents rapid-fire door toggling on held tap
var _tex_door_open: Texture2D
var _tex_door_closed: Texture2D
# Weapon icon textures, loaded once
const _WEAPON_ICONS := {
	"pistol":  "res://assets/player/Top_Down_Survivor/handgun/idle/survivor-idle_handgun_0.png",
	"shotgun": "res://assets/player/Top_Down_Survivor/shotgun/idle/survivor-idle_shotgun_0.png",
	"rifle":   "res://assets/player/Top_Down_Survivor/rifle/idle/survivor-idle_rifle_0.png",
	"lmg":     "res://assets/squad/soldier1_machine.png",
}

func _ready() -> void:
	# Assign UI icons to palette buttons
	var wall_tex        := load("res://assets/ui/btn_wall.png")        as Texture2D
	var door_tex        := load("res://assets/ui/btn_door.png")        as Texture2D
	var tower_tex       := load("res://assets/ui/btn_tower.png")       as Texture2D
	var camp_tex        := load("res://assets/ui/btn_camp.png")        as Texture2D
	var repair_tex      := load("res://assets/ui/btn_repair.png")      as Texture2D
	var ready_tex       := load("res://assets/ui/btn_ready.png")       as Texture2D
	var camp_sm_tex     := load("res://assets/ui/btn_camp_small.png")  as Texture2D
	var camp_md_tex     := load("res://assets/ui/btn_camp_medium.png") as Texture2D
	var camp_lg_tex     := load("res://assets/ui/btn_camp_large.png")  as Texture2D

	# Palette + picker icons (image only, text cleared)
	for pair: Array in [
		[wall_btn,  wall_tex],
		[door_btn,  door_tex],
		[tower_btn, tower_tex],
		[$BuildPicker/VBox/WallPickBtn,  wall_tex],
		[$BuildPicker/VBox/DoorPickBtn,  door_tex],
		[$BuildPicker/VBox/TowerPickBtn, tower_tex],
	]:
		var btn: Button = pair[0]
		btn.icon = pair[1] as Texture2D
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.text = ""

	# Camp template button
	template_btn.icon = camp_tex
	template_btn.expand_icon = true
	template_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	template_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	template_btn.text = ""

	# Erase button — plain bold X, no icon
	erase_btn.icon = null
	erase_btn.text = "✕"

	# Size buttons
	for pair: Array in [
		[small_btn,  camp_sm_tex],
		[medium_btn, camp_md_tex],
		[large_btn,  camp_lg_tex],
	]:
		var btn: Button = pair[0]
		btn.icon = pair[1] as Texture2D
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.text = ""

	# Repair button
	repair_all_btn.icon = repair_tex
	repair_all_btn.expand_icon = true
	repair_all_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	repair_all_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

	# Ready button (✅ inside build panel)
	_ready_btn.icon = ready_tex
	_ready_btn.expand_icon = true
	_ready_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_ready_btn.text = ""

	# Build mode button (PlaceBtn) — builder icon
	var build_mode_tex := load("res://assets/ui/btn_build_mode.png") as Texture2D
	place_btn.icon = build_mode_tex
	place_btn.expand_icon = true
	place_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	place_btn.text = ""

	# Door toggle button — show open icon when doors are closed, closed icon when open
	_tex_door_open   = load("res://assets/ui/btn_door_tog_open.png")   as Texture2D
	_tex_door_closed = load("res://assets/ui/btn_door_tog_closed.png") as Texture2D
	door_toggle_btn.icon = _tex_door_open  # doors start closed → show open icon
	door_toggle_btn.expand_icon = true
	door_toggle_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	door_toggle_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	door_toggle_btn.text = ""

	# Show handgun initially
	update_weapon("pistol")

	# Support panel — icon-only buttons
	var airstrike_tex := load("res://assets/enemies/barrel.png") as Texture2D
	var squad_tex     := load("res://assets/squad/squad.png") as Texture2D
	var shield_sq_tex := load("res://assets/squad/soldier1_machine.png") as Texture2D
	for pair: Array in [
		[airstrike_btn,    airstrike_tex],
		[squad_btn,        squad_tex],
		[shield_squad_btn, shield_sq_tex],
	]:
		var btn: Button = pair[0]
		btn.icon = pair[1] as Texture2D
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.text = ""

func _process(delta: float) -> void:
	if _door_toggle_cooldown > 0.0:
		_door_toggle_cooldown -= delta

func update_health(current: int, maximum: int) -> void:
	health_bar.value = float(current) / float(maximum) * 100.0
	health_label.text = str(current) + " / " + str(maximum)

func update_score(score: int) -> void:
	score_label.text = "%.4d" % score

func update_coins(amount: int) -> void:
	coin_label.text = str(amount) + " 🪙"

func update_weapon(weapon_name: String) -> void:
	var key := weapon_name.to_lower()
	if key in _WEAPON_ICONS:
		weapon_icon.texture = load(_WEAPON_ICONS[key]) as Texture2D
	weapon_icon.modulate = Color(0.3, 0.9, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(weapon_icon, "modulate", Color.WHITE, 0.6)

func show_buy_prompt(weapon_name: String, cost: int) -> void:
	buy_prompt_label.text = "Buy " + weapon_name + " — " + str(cost) + " coins  [E]"
	buy_prompt_label.modulate = Color(1, 1, 1, 0)
	buy_prompt_label.visible = true
	buy_btn.visible = true
	buy_btn.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(buy_prompt_label, "modulate", Color.WHITE, 0.25)
	tween.tween_property(buy_btn, "modulate", Color.WHITE, 0.25)

func hide_buy_prompt() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(buy_prompt_label, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_property(buy_btn, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.chain().tween_callback(func():
		buy_prompt_label.hide()
		buy_btn.hide()
	)

func flash_buy_denied() -> void:
	buy_prompt_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
	buy_btn.modulate = Color(1.0, 0.2, 0.2, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(buy_prompt_label, "modulate", Color.WHITE, 0.4)
	tween.tween_property(buy_btn, "modulate", Color.WHITE, 0.4)

func _on_buy_btn_pressed() -> void:
	buy_pressed.emit()

# ─── Weapon shop ─────────────────────────────────────────────────────────────

func show_weapon_shop(player_coins: int, current_weapon: String) -> void:
	_refresh_shop_buttons(player_coins, current_weapon)
	weapon_shop_overlay.visible = true

func hide_weapon_shop() -> void:
	weapon_shop_overlay.visible = false

func _refresh_shop_buttons(player_coins: int, current_weapon: String) -> void:
	var buttons: Dictionary = {
		"pistol": _pistol_buy_btn,
		"shotgun": _shotgun_buy_btn,
		"rifle": _rifle_buy_btn,
		"lmg": _lmg_buy_btn,
	}
	for wid: String in buttons:
		var btn: Button = buttons[wid]
		var w: Dictionary = WeaponManager.WEAPONS[wid]
		if current_weapon == wid:
			btn.text = "EQUIPPED"
			btn.disabled = true
			btn.modulate = Color(0.3, 1.0, 0.5, 1.0)
		elif w["cost"] == 0:
			btn.text = "EQUIP"
			btn.disabled = false
			btn.modulate = Color.WHITE
		elif player_coins >= w["cost"]:
			btn.text = "BUY " + str(w["cost"]) + "c"
			btn.disabled = false
			btn.modulate = Color.WHITE
		else:
			btn.text = str(w["cost"]) + "c"
			btn.disabled = true
			btn.modulate = Color(1.0, 0.3, 0.3, 0.7)

func _on_shop_pistol_pressed() -> void:
	weapon_shop_buy.emit("pistol")

func _on_shop_shotgun_pressed() -> void:
	weapon_shop_buy.emit("shotgun")

func _on_shop_rifle_pressed() -> void:
	weapon_shop_buy.emit("rifle")

func _on_shop_lmg_pressed() -> void:
	weapon_shop_buy.emit("lmg")

func _on_close_shop_pressed() -> void:
	hide_weapon_shop()

# ─── Recovery shop ───────────────────────────────────────────────────────────

func update_shield(current: int, maximum: int) -> void:
	shield_bar.visible = maximum > 0
	shield_bar.value = float(current) / float(maximum) * 100.0 if maximum > 0 else 0.0
	shield_label.text = str(current) + " / " + str(maximum)

func show_recovery_shop(player_coins: int, player_health: int, max_health: int, player_shield: int) -> void:
	_refresh_recovery_buttons(player_coins, player_health, max_health, player_shield)
	recovery_shop_overlay.visible = true

func hide_recovery_shop() -> void:
	recovery_shop_overlay.visible = false

func _refresh_recovery_buttons(player_coins: int, player_health: int, max_health: int, player_shield: int) -> void:
	if player_health >= max_health:
		_health_buy_btn.text = "FULL"
		_health_buy_btn.disabled = true
		_health_buy_btn.modulate = Color(0.3, 1.0, 0.5, 1.0)
	elif player_coins >= 40:
		_health_buy_btn.text = "BUY 40c"
		_health_buy_btn.disabled = false
		_health_buy_btn.modulate = Color.WHITE
	else:
		_health_buy_btn.text = "40c"
		_health_buy_btn.disabled = true
		_health_buy_btn.modulate = Color(1.0, 0.3, 0.3, 0.7)

	if player_shield >= 100:
		_shield_buy_btn.text = "FULL"
		_shield_buy_btn.disabled = true
		_shield_buy_btn.modulate = Color(0.3, 0.6, 1.0, 1.0)
	elif player_coins >= 75:
		_shield_buy_btn.text = "BUY 75c"
		_shield_buy_btn.disabled = false
		_shield_buy_btn.modulate = Color.WHITE
	else:
		_shield_buy_btn.text = "75c"
		_shield_buy_btn.disabled = true
		_shield_buy_btn.modulate = Color(1.0, 0.3, 0.3, 0.7)

func _on_recovery_health_pressed() -> void:
	recovery_shop_buy.emit("health")

func _on_recovery_shield_pressed() -> void:
	recovery_shop_buy.emit("shield")

func _on_close_recovery_pressed() -> void:
	hide_recovery_shop()

# ─── Build mode ──────────────────────────────────────────────────────────────

func show_build_mode(duration: float = 30.0) -> void:
	build_panel.visible = true
	place_btn.visible = true
	_highlight_palette(wall_btn)
	template_picker.visible = false
	build_timer_bar.max_value = duration
	build_timer_bar.value = duration

func hide_build_mode() -> void:
	build_panel.visible = false
	place_btn.visible = false
	repair_all_btn.visible = false

func update_build_timer(time_left: float) -> void:
	build_timer_bar.value = time_left

func flash_build_denied() -> void:
	build_timer_bar.modulate = Color(1.0, 0.2, 0.2, 1.0)
	var tween := create_tween()
	tween.tween_property(build_timer_bar, "modulate", Color.WHITE, 0.4)

func _highlight_palette(active: Button) -> void:
	for btn in [wall_btn, door_btn, tower_btn, erase_btn, template_btn]:
		btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
	active.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_wall_btn_pressed() -> void:
	build_item_selected.emit("wall")
	_highlight_palette(wall_btn)
	template_picker.visible = false

func _on_door_btn_pressed() -> void:
	build_item_selected.emit("door")
	_highlight_palette(door_btn)
	template_picker.visible = false

func _on_tower_btn_pressed() -> void:
	build_item_selected.emit("tower")
	_highlight_palette(tower_btn)
	template_picker.visible = false

func _on_erase_btn_pressed() -> void:
	build_item_selected.emit("erase")
	_highlight_palette(erase_btn)
	template_picker.visible = false

func _on_template_btn_pressed() -> void:
	build_item_selected.emit("template")
	_highlight_palette(template_btn)
	template_picker.visible = true
	_highlight_size_btn(small_btn)

func _highlight_size_btn(active: Button) -> void:
	for btn in [small_btn, medium_btn, large_btn]:
		btn.modulate = Color(0.6, 0.6, 0.6, 1.0)
	active.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_small_btn_pressed() -> void:
	template_size_selected.emit("small")
	_highlight_size_btn(small_btn)

func _on_medium_btn_pressed() -> void:
	template_size_selected.emit("medium")
	_highlight_size_btn(medium_btn)

func _on_large_btn_pressed() -> void:
	template_size_selected.emit("large")
	_highlight_size_btn(large_btn)

func update_template_cost(cost: int) -> void:
	template_cost_label.text = "💰 " + str(cost) + " 🪙"

func update_repair_all_button(cost: int, has_damaged: bool, can_afford: bool) -> void:
	if has_damaged:
		repair_all_btn.visible = true
		repair_all_btn.text = "🔧 " + str(cost) + " 🪙"
		repair_all_btn.disabled = not can_afford
		repair_all_btn.modulate = Color(1.0, 0.7, 0.2, 1.0) if can_afford else Color(0.5, 0.35, 0.1, 0.7)
	else:
		repair_all_btn.visible = false

func _on_repair_all_btn_pressed() -> void:
	repair_all_pressed.emit()

func _on_place_btn_pressed() -> void:
	build_place_pressed.emit()

func show_build_picker(screen_pos: Vector2) -> void:
	build_picker.visible = true
	var vp := get_viewport().get_visible_rect().size
	var x := clampf(screen_pos.x - 80.0, 4.0, vp.x - 164.0)
	var y := clampf(screen_pos.y - 130.0, 4.0, vp.y - 204.0)
	build_picker.position = Vector2(x, y)

func hide_build_picker() -> void:
	build_picker.visible = false

func _on_pick_wall_pressed() -> void:
	build_picker_selected.emit("wall")
	hide_build_picker()

func _on_pick_door_pressed() -> void:
	build_picker_selected.emit("door")
	hide_build_picker()

func _on_pick_tower_pressed() -> void:
	build_picker_selected.emit("tower")
	hide_build_picker()

func _on_pick_erase_pressed() -> void:
	build_picker_selected.emit("erase")
	hide_build_picker()

func _on_ready_btn_pressed() -> void:
	build_ready_pressed.emit()

func _on_door_toggle_btn_pressed() -> void:
	if _door_toggle_cooldown > 0.0:
		return
	_door_toggle_cooldown = 0.35
	_doors_open = !_doors_open
	# Show opposite-state icon: doors open → show closed icon (tap to close), and vice versa
	door_toggle_btn.icon = _tex_door_closed if _doors_open else _tex_door_open
	door_toggle_pressed.emit()

# ─── Support callables ────────────────────────────────────────────────────────

func update_support_cooldowns(
		cd_air: float, max_air: float,
		cd_sq: float,  max_sq: float,
		cd_sh: float,  max_sh: float) -> void:
	_set_btn_cooldown(airstrike_btn,    cd_air, max_air, "80🪙")
	_set_btn_cooldown(squad_btn,        cd_sq,  max_sq,  "50🪙")
	_set_btn_cooldown(shield_squad_btn, cd_sh,  max_sh,  "90🪙")

func _set_btn_cooldown(btn: Button, cd: float, max_cd: float, cost_label: String) -> void:
	if cd <= 0.0:
		btn.text = cost_label
		btn.modulate = Color.WHITE
		btn.disabled = false
	else:
		btn.text = "⏳ " + str(int(ceil(cd)))
		btn.modulate = Color(0.45, 0.45, 0.45, 1.0)
		btn.disabled = true

func _on_airstrike_btn_pressed() -> void:
	airstrike_pressed.emit()

func _on_squad_btn_pressed() -> void:
	squad_pressed.emit()

func _on_shield_squad_btn_pressed() -> void:
	shield_squad_pressed.emit()

func update_wave(wave: int) -> void:
	wave_label.text = "WAVE %02d" % wave
	wave_label.modulate = Color(1.0, 0.851, 0.0, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(wave_label, "modulate", Color(1.0, 0.851, 0.0, 1.0), 0.8)

func show_wave_transition(config: Dictionary, duration: float = 3.0) -> void:
	wave_complete_title.text = config["title"] + " COMPLETE"
	story_label.text = config["subtitle"]
	countdown_bar.max_value = duration
	countdown_bar.value = duration
	wave_transition_panel.modulate = Color(1, 1, 1, 0)
	wave_transition_panel.visible = true
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color.WHITE, 0.5)

func update_countdown(time_left: float) -> void:
	countdown_bar.value = time_left

func hide_wave_transition() -> void:
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	tween.tween_callback(wave_transition_panel.hide)

# ── Co-op partner status labels (created on first use) ────────────────────────

var _partner_waiting_label: Label = null
var _partner_ready_label:   Label = null

func _make_center_label(msg: String, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(700.0, 60.0)
	lbl.position = Vector2(
		(get_viewport_rect().size.x - 700.0) * 0.5,
		get_viewport_rect().size.y * 0.5 - 80.0)
	var ls := LabelSettings.new()
	ls.font_size    = 26
	ls.font_color   = col
	ls.outline_size  = 2
	ls.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	lbl.label_settings = ls
	lbl.visible = false
	add_child(lbl)
	return lbl

func show_partner_waiting_label() -> void:
	if not _partner_waiting_label:
		_partner_waiting_label = _make_center_label("⏳  Waiting for partner...", Color(1.0, 0.85, 0.2, 1.0))
	_partner_waiting_label.visible = true

func hide_partner_waiting_label() -> void:
	if _partner_waiting_label:
		_partner_waiting_label.visible = false

func show_partner_ready_label() -> void:
	if not _partner_ready_label:
		_partner_ready_label = _make_center_label("✔  Partner is READY!", Color(0.3, 1.0, 0.45, 1.0))
	_partner_ready_label.visible = true

func hide_partner_ready_label() -> void:
	if _partner_ready_label:
		_partner_ready_label.visible = false

