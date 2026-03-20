extends Control

@onready var health_bar := $TopBar/HealthBar
@onready var health_label := $TopBar/HealthBar/HealthLabel
@onready var score_label := $TopBar/ScoreLabel
@onready var wave_label := $TopBar/WaveLabel
@onready var coin_label := $TopBar/CoinLabel
@onready var weapon_label := $TopBar/WeaponLabel
@onready var wave_transition_panel := $WaveTransitionPanel
@onready var wave_complete_title := $WaveTransitionPanel/CenterContainer/VBox/WaveCompleteTitle
@onready var story_label := $WaveTransitionPanel/CenterContainer/VBox/StoryLabel
@onready var countdown_label := $WaveTransitionPanel/CenterContainer/VBox/CountdownLabel
@onready var buy_prompt_label := $BuyPromptLabel
@onready var buy_btn          := $BuyBtn
@onready var build_panel       := $BuildPanel
@onready var build_timer_label := $BuildPanel/VBox/BuildTimerLabel
@onready var wall_btn          := $BuildPanel/VBox/Palette/WallBtn
@onready var door_btn          := $BuildPanel/VBox/Palette/DoorBtn
@onready var tower_btn         := $BuildPanel/VBox/Palette/TowerBtn
@onready var erase_btn         := $BuildPanel/VBox/Palette/EraseBtn
@onready var place_btn         := $BuildPanel/VBox/PlaceBtn
@onready var door_toggle_btn   := $DoorToggleBtn
@onready var support_panel        := $SupportPanel
@onready var airstrike_btn        := $SupportPanel/VBox/AirstrikeBtn
@onready var squad_btn            := $SupportPanel/VBox/SquadBtn
@onready var shield_squad_btn     := $SupportPanel/VBox/ShieldSquadBtn

signal buy_pressed
signal build_ready_pressed
signal build_place_pressed
signal build_item_selected(item: String)
signal door_toggle_pressed
signal airstrike_pressed
signal squad_pressed
signal shield_squad_pressed

var _doors_open := false

func update_health(current: int, maximum: int) -> void:
	health_bar.value = float(current) / float(maximum) * 100.0
	health_label.text = str(current) + " / " + str(maximum)

func update_score(score: int) -> void:
	score_label.text = "SCORE: " + str(score)

func update_coins(amount: int) -> void:
	coin_label.text = "COINS: " + str(amount)

func update_weapon(weapon_name: String) -> void:
	weapon_label.text = weapon_name.to_upper()
	weapon_label.modulate = Color(0.3, 0.9, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(weapon_label, "modulate", Color.WHITE, 0.6)

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

# ─── Build mode ──────────────────────────────────────────────────────────────

func show_build_mode() -> void:
	build_panel.visible = true
	_highlight_palette(wall_btn)
	build_timer_label.text = "BUILD MODE: 60s"

func hide_build_mode() -> void:
	build_panel.visible = false

func update_build_timer(seconds: int) -> void:
	build_timer_label.text = "BUILD MODE: " + str(seconds) + "s"

func flash_build_denied() -> void:
	build_timer_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
	var tween := create_tween()
	tween.tween_property(build_timer_label, "modulate", Color.WHITE, 0.4)

func _highlight_palette(active: Button) -> void:
	for btn in [wall_btn, door_btn, tower_btn, erase_btn]:
		btn.modulate = Color(0.55, 0.55, 0.55, 1.0)
	active.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_wall_btn_pressed() -> void:
	build_item_selected.emit("wall")
	_highlight_palette(wall_btn)

func _on_door_btn_pressed() -> void:
	build_item_selected.emit("door")
	_highlight_palette(door_btn)

func _on_tower_btn_pressed() -> void:
	build_item_selected.emit("tower")
	_highlight_palette(tower_btn)

func _on_erase_btn_pressed() -> void:
	build_item_selected.emit("erase")
	_highlight_palette(erase_btn)

func _on_place_btn_pressed() -> void:
	build_place_pressed.emit()

func _on_ready_btn_pressed() -> void:
	build_ready_pressed.emit()

func _on_door_toggle_btn_pressed() -> void:
	_doors_open = !_doors_open
	door_toggle_btn.text = "DOORS: OPEN" if _doors_open else "DOORS: CLOSED"
	door_toggle_pressed.emit()

# ─── Support callables ────────────────────────────────────────────────────────

func update_support_cooldowns(
		cd_air: float, max_air: float,
		cd_sq: float,  max_sq: float,
		cd_sh: float,  max_sh: float) -> void:
	_set_btn_cooldown(airstrike_btn,    cd_air, max_air, "AIR STRIKE\n80c")
	_set_btn_cooldown(squad_btn,        cd_sq,  max_sq,  "SQUAD\n50c")
	_set_btn_cooldown(shield_squad_btn, cd_sh,  max_sh,  "SHIELD SQ.\n90c")

func _set_btn_cooldown(btn: Button, cd: float, max_cd: float, label: String) -> void:
	if cd <= 0.0:
		btn.text = label
		btn.modulate = Color.WHITE
		btn.disabled = false
	else:
		btn.text = label + "\n" + str(int(ceil(cd))) + "s"
		btn.modulate = Color(0.45, 0.45, 0.45, 1.0)
		btn.disabled = true

func _on_airstrike_btn_pressed() -> void:
	airstrike_pressed.emit()

func _on_squad_btn_pressed() -> void:
	squad_pressed.emit()

func _on_shield_squad_btn_pressed() -> void:
	shield_squad_pressed.emit()

func update_wave(wave: int) -> void:
	wave_label.text = "WAVE " + str(wave)
	wave_label.modulate = Color(1, 1, 0, 1)
	var tween: Tween = create_tween()
	tween.tween_property(wave_label, "modulate", Color.WHITE, 0.8)

func show_wave_transition(config: Dictionary) -> void:
	wave_complete_title.text = config["title"] + " COMPLETE"
	story_label.text = config["subtitle"]
	countdown_label.text = "Next wave in: 5..."
	wave_transition_panel.modulate = Color(1, 1, 1, 0)
	wave_transition_panel.visible = true
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color.WHITE, 0.5)

func update_countdown(seconds: int) -> void:
	countdown_label.text = "Next wave in: " + str(seconds) + "..."

func hide_wave_transition() -> void:
	var tween := create_tween()
	tween.tween_property(wave_transition_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	tween.tween_callback(wave_transition_panel.hide)

