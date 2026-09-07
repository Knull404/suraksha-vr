extends Node
class_name SettingsManager

## Global Settings Manager for Pico XR project.
## Manages Audio volume, Control configurations, Pause/Recenter button bindings, and persistent config.

signal settings_changed

const SETTINGS_FILE := "user://settings.cfg"

# --- Audio Settings ---
var master_volume: float = 1.0  # 0.0 to 1.0
var music_volume: float = 0.8   # 0.0 to 1.0
var sfx_volume: float = 0.8     # 0.0 to 1.0
var audio_muted: bool = false

# --- Locomotion & Turning Settings ---
enum Hand { LEFT, RIGHT }
enum LocomotionMode { SMOOTH, SNAP }
enum TurningMode { SNAP, SMOOTH }

var locomotion_hand: Hand = Hand.RIGHT
var locomotion_mode: LocomotionMode = LocomotionMode.SMOOTH

var turning_hand: Hand = Hand.LEFT
var turning_mode: TurningMode = TurningMode.SNAP

# --- Teleport Settings ---
var teleport_hand: Hand = Hand.RIGHT
var teleport_button: StringName = &"trigger_click"

# --- Jump Settings ---
var jump_hand: Hand = Hand.RIGHT
var jump_action: String = "jump"
var jump_velocity: float = 5.0

# --- Player POV Height Mode ---
var use_dynamic_height: bool = false
var fixed_height: float = 1.7

# --- Pause Menu & Recenter Controller Button Settings ---
var pause_button: StringName = &"by_button"     # Default Y/B Button
var recenter_button: StringName = &"ax_button"   # Default X/A Button

# --- Custom Action Rebinds ---
var custom_rebinds: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_all_settings()

func apply_all_settings() -> void:
	apply_audio_settings()

func apply_audio_settings() -> void:
	_set_bus_volume("Master", master_volume, audio_muted)
	_set_bus_volume("Music", music_volume, audio_muted)
	_set_bus_volume("SFX", sfx_volume, audio_muted)

func _set_bus_volume(bus_name: String, volume_linear: float, muted: bool) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		return
	AudioServer.set_bus_mute(bus_idx, muted)
	var db := linear_to_db(clampf(volume_linear, 0.0001, 1.0))
	AudioServer.set_bus_volume_db(bus_idx, db)

## Recenter player's VR HMD position and horizontal yaw facing.
func recenter_player(player: CharacterBody3D) -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	if player != null and player.has_method(&"recenter_fixed_pov"):
		player.call(&"recenter_fixed_pov")
	print("SettingsManager: Recenter triggered.")

## Apply control settings directly to the player node and its locomotion children
func apply_controls_to_player(player: CharacterBody3D) -> void:
	if player == null:
		return

	if "use_dynamic_height" in player:
		player.set("use_dynamic_height", use_dynamic_height)

	var xr_origin = player.find_child("XROrigin3D", true, false)
	if xr_origin == null:
		return

	var left_ctrl: XRController3D = xr_origin.find_child("LeftController", true, false)
	var right_ctrl: XRController3D = xr_origin.find_child("RightController", true, false)

	# Locomotion node
	var loc_node = player.find_child("pico_locomotion", true, false)
	if loc_node != null:
		loc_node.set("controller", left_ctrl if locomotion_hand == Hand.LEFT else right_ctrl)
		loc_node.set("movement_mode", locomotion_mode)

	# Turning node
	var turn_node = player.find_child("pico_turning", true, false)
	if turn_node != null:
		turn_node.set("controller", left_ctrl if turning_hand == Hand.LEFT else right_ctrl)
		turn_node.set("turn_mode", turning_mode)

	# Teleport node
	var tele_node = player.find_child("pico_teleportation", true, false)
	if tele_node != null:
		tele_node.set("controller", left_ctrl if teleport_hand == Hand.LEFT else right_ctrl)
		tele_node.set("teleport_button", teleport_button)

	# Jump node
	var jump_node = player.find_child("JumpController", true, false)
	if jump_node == null:
		for child in player.get_children():
			if child.has_method(&"_physics_process") and "jump_action" in child:
				jump_node = child
				break
	if jump_node != null:
		jump_node.set("jump_action", jump_action)
		jump_node.set("jump_velocity", jump_velocity)

	emit_signal("settings_changed")

## Rebind an InputMap action to a new InputEvent
func rebind_action(action_name: String, event: InputEvent) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, event)
	custom_rebinds[action_name] = event
	save_settings()
	emit_signal("settings_changed")

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "muted", audio_muted)

	config.set_value("controls", "locomotion_hand", locomotion_hand)
	config.set_value("controls", "locomotion_mode", locomotion_mode)
	config.set_value("controls", "turning_hand", turning_hand)
	config.set_value("controls", "turning_mode", turning_mode)
	config.set_value("controls", "teleport_hand", teleport_hand)
	config.set_value("controls", "teleport_button", String(teleport_button))
	config.set_value("controls", "jump_hand", jump_hand)
	config.set_value("controls", "jump_action", jump_action)
	config.set_value("controls", "jump_velocity", jump_velocity)
	config.set_value("controls", "use_dynamic_height", use_dynamic_height)
	config.set_value("controls", "pause_button", String(pause_button))
	config.set_value("controls", "recenter_button", String(recenter_button))

	config.save(SETTINGS_FILE)

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE)
	if err != OK:
		return

	master_volume = config.get_value("audio", "master_volume", master_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	audio_muted = config.get_value("audio", "muted", audio_muted)

	locomotion_hand = config.get_value("controls", "locomotion_hand", locomotion_hand)
	locomotion_mode = config.get_value("controls", "locomotion_mode", locomotion_mode)
	turning_hand = config.get_value("controls", "turning_hand", turning_hand)
	turning_mode = config.get_value("controls", "turning_mode", turning_mode)
	teleport_hand = config.get_value("controls", "teleport_hand", teleport_hand)
	teleport_button = StringName(config.get_value("controls", "teleport_button", String(teleport_button)))
	jump_hand = config.get_value("controls", "jump_hand", jump_hand)
	jump_action = config.get_value("controls", "jump_action", jump_action)
	jump_velocity = config.get_value("controls", "jump_velocity", jump_velocity)
	use_dynamic_height = config.get_value("controls", "use_dynamic_height", use_dynamic_height)
	pause_button = StringName(config.get_value("controls", "pause_button", String(pause_button)))
	recenter_button = StringName(config.get_value("controls", "recenter_button", String(recenter_button)))
