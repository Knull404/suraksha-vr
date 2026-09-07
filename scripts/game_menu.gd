extends Control
class_name GameMenu

## Complete Game Menu UI for Pico XR.
## Includes Main Menu, In-Game Pause Menu, and Settings (Sound, Controls, Action Remap).

signal game_started
signal game_resumed
signal game_restarted
signal main_menu_returned

@export var player: CharacterBody3D
@export var game_stage: Node3D

var settings_manager: SettingsManager

# UI State
enum MenuState { MAIN_MENU, PAUSE_MENU, SETTINGS }
var current_state: MenuState = MenuState.MAIN_MENU
var _previous_state: MenuState = MenuState.MAIN_MENU

# UI Containers
var _main_menu_panel: VBoxContainer
var _pause_menu_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _rebind_dialog: Panel

# Settings Controls References
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _mute_check: CheckBox

var _loc_hand_opt: OptionButton
var _loc_mode_opt: OptionButton
var _turn_hand_opt: OptionButton
var _turn_mode_opt: OptionButton
var _tele_hand_opt: OptionButton
var _tele_btn_opt: OptionButton
var _jump_hand_opt: OptionButton
var _pause_btn_opt: OptionButton
var _recenter_btn_opt: OptionButton
var _height_mode_check: CheckBox

# Rebinding
var _rebinding_action: String = ""
var _is_rebinding: bool = false
var _rebind_label: Label

func _ready() -> void:
	# Use or create global SettingsManager
	settings_manager = get_node_or_null("/root/SettingsManager") as SettingsManager
	if settings_manager == null:
		settings_manager = SettingsManager.new()
		settings_manager.name = "SettingsManager"
		get_tree().root.call_deferred("add_child", settings_manager)

	_build_ui_layout()
	show_main_menu()

func _input(event: InputEvent) -> void:
	if _is_rebinding:
		# IGNORE mouse buttons so simulated VR laser pointer clicks don't rebind actions to Left Mouse Button!
		if event is InputEventMouseButton:
			return

		if event is InputEventKey or event is InputEventJoypadButton:
			if event.is_pressed():
				settings_manager.rebind_action(_rebinding_action, event)
				_is_rebinding = false
				if _rebind_dialog:
					_rebind_dialog.visible = false
				get_viewport().set_input_as_handled()
				_populate_rebind_list()
				return

	# Handle Pause Menu Toggle (Escape or Menu button)
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu_button"):
		if current_state == MenuState.SETTINGS:
			_on_back_pressed()
		elif current_state == MenuState.PAUSE_MENU:
			resume_game()
		elif current_state == MenuState.MAIN_MENU:
			pass # In main menu, ignore pause key

func show_main_menu() -> void:
	current_state = MenuState.MAIN_MENU
	visible = true
	_main_menu_panel.visible = true
	_pause_menu_panel.visible = false
	_settings_panel.visible = false

func show_pause_menu() -> void:
	current_state = MenuState.PAUSE_MENU
	visible = true
	_main_menu_panel.visible = false
	_pause_menu_panel.visible = true
	_settings_panel.visible = false

func show_settings() -> void:
	_previous_state = current_state  # Remember where we came from
	current_state = MenuState.SETTINGS
	_update_settings_ui_values()
	_main_menu_panel.visible = false
	_pause_menu_panel.visible = false
	_settings_panel.visible = true

func start_new_game() -> void:
	visible = false
	current_state = MenuState.PAUSE_MENU # Next time menu opens, it's pause menu
	if player != null and settings_manager != null:
		settings_manager.apply_controls_to_player(player)

	if game_stage != null and game_stage.has_method(&"_start_game"):
		game_stage.call(&"_start_game")

	emit_signal("game_started")

func resume_game() -> void:
	visible = false
	emit_signal("game_resumed")

func restart_game() -> void:
	visible = false
	emit_signal("game_restarted")
	get_tree().reload_current_scene()

func return_to_main_menu() -> void:
	emit_signal("main_menu_returned")
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != "res://scenes/MainMenu.tscn":
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	else:
		show_main_menu()

func exit_game() -> void:
	get_tree().quit()

# ── Private UI Builders & Callbacks ──────────────────────────────────────────

func _build_ui_layout() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	custom_minimum_size = Vector2(1280, 960)

	# Main Background
	var bg := Panel.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	bg.add_child(center)

	# 1. Main Menu Panel
	_main_menu_panel = VBoxContainer.new()
	_main_menu_panel.custom_minimum_size = Vector2(550, 0)
	_main_menu_panel.add_theme_constant_override("separation", 24)
	center.add_child(_main_menu_panel)

	var title := Label.new()
	title.text = "PICO XR TOOLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	_main_menu_panel.add_child(title)

	var btn_new := _create_button("New Game", _on_new_game_pressed)
	var btn_set := _create_button("Settings", _on_settings_pressed)
	var btn_exit := _create_button("Exit Game", _on_exit_pressed)

	_main_menu_panel.add_child(btn_new)
	_main_menu_panel.add_child(btn_set)
	_main_menu_panel.add_child(btn_exit)

	# 2. Pause Menu Panel
	_pause_menu_panel = VBoxContainer.new()
	_pause_menu_panel.custom_minimum_size = Vector2(550, 0)
	_pause_menu_panel.add_theme_constant_override("separation", 20)
	center.add_child(_pause_menu_panel)

	var ptitle := Label.new()
	ptitle.text = "GAME PAUSED"
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ptitle.add_theme_font_size_override("font_size", 48)
	_pause_menu_panel.add_child(ptitle)

	var btn_res := _create_button("Resume Game", _on_resume_pressed)
	var btn_rst := _create_button("Restart Game", _on_restart_pressed)
	var btn_pset := _create_button("Settings", _on_settings_pressed)
	var btn_mm := _create_button("Main Menu", _on_main_menu_pressed)
	var btn_pexit := _create_button("Exit Game", _on_exit_pressed)

	_pause_menu_panel.add_child(btn_res)
	_pause_menu_panel.add_child(btn_rst)
	_pause_menu_panel.add_child(btn_pset)
	_pause_menu_panel.add_child(btn_mm)
	_pause_menu_panel.add_child(btn_pexit)

	# 3. Settings Panel
	_settings_panel = VBoxContainer.new()
	_settings_panel.custom_minimum_size = Vector2(1050, 750)
	_settings_panel.add_theme_constant_override("separation", 18)
	center.add_child(_settings_panel)

	var stitle := Label.new()
	stitle.text = "SETTINGS"
	stitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stitle.add_theme_font_size_override("font_size", 44)
	_settings_panel.add_child(stitle)

	# Tab Container
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(1000, 560)
	tabs.add_theme_font_size_override("font_size", 28)
	_settings_panel.add_child(tabs)

	# Tab A: Sound
	var sound_tab := VBoxContainer.new()
	sound_tab.name = "Sound"
	sound_tab.add_theme_constant_override("separation", 20)
	tabs.add_child(sound_tab)

	_master_slider = _add_slider_setting(sound_tab, "Master Volume", _on_master_vol_changed)
	_music_slider = _add_slider_setting(sound_tab, "Music Volume", _on_music_vol_changed)
	_sfx_slider = _add_slider_setting(sound_tab, "SFX Volume", _on_sfx_vol_changed)

	_mute_check = CheckBox.new()
	_mute_check.text = "Mute All Audio"
	_mute_check.add_theme_font_size_override("font_size", 26)
	_mute_check.toggled.connect(_on_mute_toggled)
	sound_tab.add_child(_mute_check)

	# Tab B: Locomotion & Controls
	var ctrl_tab := VBoxContainer.new()
	ctrl_tab.name = "Controls"
	ctrl_tab.add_theme_constant_override("separation", 16)
	tabs.add_child(ctrl_tab)

	_loc_hand_opt = _add_option_setting(ctrl_tab, "Movement Hand", ["Right Controller", "Left Controller"], _on_loc_hand_selected)
	_loc_mode_opt = _add_option_setting(ctrl_tab, "Movement Mode", ["Smooth Locomotion", "Snap Movement"], _on_loc_mode_selected)
	_turn_hand_opt = _add_option_setting(ctrl_tab, "Turning Hand", ["Left Controller", "Right Controller"], _on_turn_hand_selected)
	_turn_mode_opt = _add_option_setting(ctrl_tab, "Turning Mode", ["Snap Turning", "Smooth Turning"], _on_turn_mode_selected)
	_tele_hand_opt = _add_option_setting(ctrl_tab, "Teleport Hand", ["Right Controller", "Left Controller"], _on_tele_hand_selected)
	_tele_btn_opt = _add_option_setting(ctrl_tab, "Teleport Button", ["trigger_click", "primary", "by_button", "ax_button"], _on_tele_btn_selected)
	_jump_hand_opt = _add_option_setting(ctrl_tab, "Jump Hand", ["Right Controller", "Left Controller"], _on_jump_hand_selected)

	_pause_btn_opt = _add_option_setting(ctrl_tab, "Pause Menu Button", ["Y / B Button (Upper)", "X / A Button (Lower)", "Menu Button"], _on_pause_btn_selected)
	_recenter_btn_opt = _add_option_setting(ctrl_tab, "Recenter Button", ["X / A Button (Lower)", "Y / B Button (Upper)", "Disabled"], _on_recenter_btn_selected)

	var btn_recenter_now := _create_button("Recenter VR View Now", func():
		if settings_manager: settings_manager.recenter_player(player)
	)
	btn_recenter_now.custom_minimum_size = Vector2(400, 50)
	ctrl_tab.add_child(btn_recenter_now)

	_height_mode_check = CheckBox.new()
	_height_mode_check.text = "Use Dynamic Height (Unchecked = Fixed POV Height)"
	_height_mode_check.add_theme_font_size_override("font_size", 26)
	_height_mode_check.toggled.connect(_on_height_mode_toggled)
	ctrl_tab.add_child(_height_mode_check)

	# Tab C: Action Rebinds
	var rebind_tab := VBoxContainer.new()
	rebind_tab.name = "Action Map"
	rebind_tab.add_theme_constant_override("separation", 16)
	tabs.add_child(rebind_tab)

	var rlbl := Label.new()
	rlbl.text = "Click an action to rebind its input:"
	rlbl.add_theme_font_size_override("font_size", 26)
	rebind_tab.add_child(rlbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	rebind_tab.add_child(scroll)

	var rebind_list := VBoxContainer.new()
	rebind_list.name = "RebindList"
	scroll.add_child(rebind_list)

	# Back Button
	var btn_back := _create_button("Back", _on_back_pressed)
	_settings_panel.add_child(btn_back)

	# Rebind Overlay Dialog
	_rebind_dialog = Panel.new()
	_rebind_dialog.custom_minimum_size = Vector2(750, 420)
	_rebind_dialog.anchors_preset = Control.PRESET_CENTER
	_rebind_dialog.visible = false
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.04, 0.04, 0.06, 0.98)
	dstyle.corner_radius_top_left = 16
	dstyle.corner_radius_top_right = 16
	dstyle.corner_radius_bottom_left = 16
	dstyle.corner_radius_bottom_right = 16
	_rebind_dialog.add_theme_stylebox_override("panel", dstyle)
	add_child(_rebind_dialog)

	var dvbox := VBoxContainer.new()
	dvbox.anchors_preset = Control.PRESET_FULL_RECT
	dvbox.add_theme_constant_override("separation", 18)
	_rebind_dialog.add_child(dvbox)

	_rebind_label = Label.new()
	_rebind_label.text = "Press any key or controller button to rebind..."
	_rebind_label.add_theme_font_size_override("font_size", 28)
	_rebind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dvbox.add_child(_rebind_label)

	var preset_title := Label.new()
	preset_title.text = "Or choose a preset controller button:"
	preset_title.add_theme_font_size_override("font_size", 24)
	preset_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dvbox.add_child(preset_title)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 16)
	preset_grid.add_theme_constant_override("v_separation", 12)
	dvbox.add_child(preset_grid)

	var presets := [
		{"name": "A / X Button (Face)", "type": "button", "index": JOY_BUTTON_A},
		{"name": "B / Y Button (Face)", "type": "button", "index": JOY_BUTTON_B},
		{"name": "Grip / Shoulder",     "type": "button", "index": JOY_BUTTON_RIGHT_SHOULDER},
		{"name": "Trigger (Right)",     "type": "axis",   "index": JOY_AXIS_TRIGGER_RIGHT},
	]
	for p in presets:
		var pbtn := Button.new()
		pbtn.text = p["name"]
		pbtn.custom_minimum_size = Vector2(340, 50)
		pbtn.add_theme_font_size_override("font_size", 24)
		var ptype: String = p["type"]
		var pidx: int = p["index"]
		pbtn.pressed.connect(func(): _apply_preset_rebind(ptype, pidx))
		preset_grid.add_child(pbtn)

	var cancel_btn := _create_button("Cancel", func():
		_is_rebinding = false
		_rebind_dialog.visible = false
	)
	cancel_btn.custom_minimum_size = Vector2(300, 50)
	dvbox.add_child(cancel_btn)

func _populate_rebind_list() -> void:
	var list := _settings_panel.find_child("RebindList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()

	var actions: Array[String] = ["jump", "trigger", "ui_accept", "ui_cancel", "menu_button"]
	for act in actions:
		if not InputMap.has_action(act):
			InputMap.add_action(act)

		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = act.capitalize() + ":"
		lbl.custom_minimum_size = Vector2(280, 0)
		lbl.add_theme_font_size_override("font_size", 26)
		hbox.add_child(lbl)

		var events := InputMap.action_get_events(act)
		var ev_text := "Unbound"
		if events.size() > 0:
			ev_text = events[0].as_text()

		var btn := Button.new()
		btn.text = ev_text
		btn.custom_minimum_size = Vector2(400, 54)
		btn.add_theme_font_size_override("font_size", 26)
		var bound_act: String = act
		btn.pressed.connect(func(): _start_rebind(bound_act))
		hbox.add_child(btn)

		list.add_child(hbox)

func _start_rebind(action_name: String) -> void:
	_rebinding_action = action_name
	_rebind_label.text = "Rebinding: " + action_name.capitalize() + "\nPress any Controller Button / Key or select below:"
	_rebind_dialog.visible = true
	# Debounce: wait 200ms so the click that opened the dialog finishes
	await get_tree().create_timer(0.2).timeout
	_is_rebinding = true

func _apply_preset_rebind(event_type: String, index: int) -> void:
	var ev: InputEvent
	if event_type == "axis":
		var axis_ev := InputEventJoypadMotion.new()
		axis_ev.axis = index as JoyAxis
		axis_ev.axis_value = 1.0
		ev = axis_ev
	else:
		var btn_ev := InputEventJoypadButton.new()
		btn_ev.button_index = index as JoyButton
		btn_ev.pressed = true
		ev = btn_ev
	settings_manager.rebind_action(_rebinding_action, ev)
	_is_rebinding = false
	_rebind_dialog.visible = false
	_populate_rebind_list()

func _update_settings_ui_values() -> void:
	if settings_manager == null:
		return
	_master_slider.value = settings_manager.master_volume * 100.0
	_music_slider.value = settings_manager.music_volume * 100.0
	_sfx_slider.value = settings_manager.sfx_volume * 100.0
	_mute_check.button_pressed = settings_manager.audio_muted

	_loc_hand_opt.selected = settings_manager.locomotion_hand
	_loc_mode_opt.selected = settings_manager.locomotion_mode
	_turn_hand_opt.selected = settings_manager.turning_hand
	_turn_mode_opt.selected = settings_manager.turning_mode
	_tele_hand_opt.selected = settings_manager.teleport_hand
	if _tele_btn_opt != null:
		var tele_btns := [&"trigger_click", &"primary", &"by_button", &"ax_button"]
		var tele_idx := tele_btns.find(settings_manager.teleport_button)
		if tele_idx >= 0:
			_tele_btn_opt.selected = tele_idx
	_jump_hand_opt.selected = settings_manager.jump_hand
	_height_mode_check.button_pressed = settings_manager.use_dynamic_height

	if _pause_btn_opt != null:
		match settings_manager.pause_button:
			&"by_button": _pause_btn_opt.selected = 0
			&"ax_button": _pause_btn_opt.selected = 1
			&"menu_button": _pause_btn_opt.selected = 2
	if _recenter_btn_opt != null:
		match settings_manager.recenter_button:
			&"ax_button": _recenter_btn_opt.selected = 0
			&"by_button": _recenter_btn_opt.selected = 1
			&"disabled": _recenter_btn_opt.selected = 2

	_populate_rebind_list()

func _on_pause_btn_selected(idx: int) -> void:
	var btns := [&"by_button", &"ax_button", &"menu_button"]
	if idx < btns.size():
		settings_manager.pause_button = btns[idx]
		settings_manager.save_settings()

func _on_recenter_btn_selected(idx: int) -> void:
	var btns := [&"ax_button", &"by_button", &"disabled"]
	if idx < btns.size():
		settings_manager.recenter_button = btns[idx]
		settings_manager.save_settings()


func _create_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(500, 68)
	btn.add_theme_font_size_override("font_size", 30)
	btn.pressed.connect(callback)
	return btn

func _add_slider_setting(parent: Control, label_text: String, callback: Callable) -> HSlider:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_font_size_override("font_size", 26)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(450, 44)
	slider.value_changed.connect(callback)
	hbox.add_child(slider)

	parent.add_child(hbox)
	return slider

func _add_option_setting(parent: Control, label_text: String, options: Array[String], callback: Callable) -> OptionButton:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(280, 0)
	lbl.add_theme_font_size_override("font_size", 26)
	hbox.add_child(lbl)

	var opt := OptionButton.new()
	for opt_title in options:
		opt.add_item(opt_title)
	opt.custom_minimum_size = Vector2(450, 54)
	opt.add_theme_font_size_override("font_size", 26)
	opt.item_selected.connect(callback)
	hbox.add_child(opt)

	parent.add_child(hbox)
	return opt

# ── Signal Callbacks ─────────────────────────────────────────────────────────

func _on_new_game_pressed() -> void:
	start_new_game()

func _on_resume_pressed() -> void:
	resume_game()

func _on_restart_pressed() -> void:
	restart_game()

func _on_main_menu_pressed() -> void:
	return_to_main_menu()

func _on_settings_pressed() -> void:
	show_settings()

func _on_exit_pressed() -> void:
	exit_game()

func _on_back_pressed() -> void:
	if current_state == MenuState.SETTINGS:
		if _previous_state == MenuState.PAUSE_MENU:
			show_pause_menu()
		else:
			show_main_menu()

func _on_master_vol_changed(val: float) -> void:
	settings_manager.master_volume = val / 100.0
	settings_manager.apply_audio_settings()
	settings_manager.save_settings()

func _on_music_vol_changed(val: float) -> void:
	settings_manager.music_volume = val / 100.0
	settings_manager.apply_audio_settings()
	settings_manager.save_settings()

func _on_sfx_vol_changed(val: float) -> void:
	settings_manager.sfx_volume = val / 100.0
	settings_manager.apply_audio_settings()
	settings_manager.save_settings()

func _on_mute_toggled(toggled: bool) -> void:
	settings_manager.audio_muted = toggled
	settings_manager.apply_audio_settings()
	settings_manager.save_settings()

func _on_loc_hand_selected(idx: int) -> void:
	settings_manager.locomotion_hand = idx as SettingsManager.Hand
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_loc_mode_selected(idx: int) -> void:
	settings_manager.locomotion_mode = idx as SettingsManager.LocomotionMode
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_turn_hand_selected(idx: int) -> void:
	settings_manager.turning_hand = idx as SettingsManager.Hand
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_turn_mode_selected(idx: int) -> void:
	settings_manager.turning_mode = idx as SettingsManager.TurningMode
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_tele_hand_selected(idx: int) -> void:
	settings_manager.teleport_hand = idx as SettingsManager.Hand
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_tele_btn_selected(idx: int) -> void:
	var btns := [&"trigger_click", &"primary", &"by_button", &"ax_button"]
	if idx < btns.size():
		settings_manager.teleport_button = btns[idx]
		if player: settings_manager.apply_controls_to_player(player)
		settings_manager.save_settings()

func _on_jump_hand_selected(idx: int) -> void:
	settings_manager.jump_hand = idx as SettingsManager.Hand
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()

func _on_height_mode_toggled(toggled: bool) -> void:
	settings_manager.use_dynamic_height = toggled
	if player: settings_manager.apply_controls_to_player(player)
	settings_manager.save_settings()
