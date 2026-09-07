extends Node3D
class_name GameStage

## Attach this node to the scene root (or anywhere convenient).
## Wire up the exports in the Inspector, then press Play —
## the Game Menu will open first.

@export_category("Controllers")
@export var left_controller: XRController3D
@export var right_controller: XRController3D

@export_category("Staging")
## The Node3D that holds all gameplay objects (floor, walls, cubes, etc.).
## It will be hidden during staging and shown when the game starts.
@export var game_root: Node3D
## The PicoXRPlayer node — used to lock the fixed POV after recentering.
@export var player: CharacterBody3D
## Grip strength needed to trigger start (0 = released, 1 = fully pressed).
@export_range(0.3, 1.0, 0.05) var grip_start_threshold: float = 0.6
## How many seconds to wait after the scene loads before showing the prompt
@export_range(0.0, 3.0, 0.1) var startup_delay: float = 0.5

@export_category("Menu")
@export var vr_menu_canvas: VRMenuCanvas

# ── internals ──────────────────────────────────────────────────────────────
var _staging: bool = true          # true while waiting for the start press
var _camera: XRCamera3D = null
var _settings_manager: SettingsManager = null  # Cached to avoid per-frame lookup


func _ready() -> void:
	# Cache SettingsManager reference — avoids get_node_or_null() on every frame
	_settings_manager = get_node_or_null("/root/SettingsManager") as SettingsManager

	# Find the camera so we can position elements relative to it.
	_camera = _find_camera()

	# Instantiate VR Menu Canvas if not already present in scene for in-game pause menu
	if vr_menu_canvas == null:
		vr_menu_canvas = VRMenuCanvas.new()
		vr_menu_canvas.name = "VRMenuCanvas"
		vr_menu_canvas.player = player
		vr_menu_canvas.game_stage = self
		vr_menu_canvas.left_controller = left_controller
		vr_menu_canvas.right_controller = right_controller
		add_child(vr_menu_canvas)

	# Connect Menu signals
	if vr_menu_canvas != null:
		vr_menu_canvas.game_started.connect(_on_menu_game_started)
		vr_menu_canvas.main_menu_returned.connect(_on_menu_returned_main)

	# Start gameplay immediately upon entering the gameplay scene
	_start_game()


var _was_pause_pressed: bool = false
var _was_recenter_pressed: bool = false

func _process(_delta: float) -> void:
	var settings := get_node_or_null("/root/SettingsManager") as SettingsManager
	if settings == null:
		return

	var pause_btn := settings.pause_button
	var recenter_btn := settings.recenter_button

	var is_pause_down := false
	var is_recenter_down := false

	for ctrl in [left_controller, right_controller]:
		if ctrl != null and ctrl.get_is_active():
			if ctrl.is_button_pressed(pause_btn) or ctrl.is_button_pressed(&"menu_button"):
				is_pause_down = true
			if recenter_btn != &"disabled" and ctrl.is_button_pressed(recenter_btn):
				is_recenter_down = true

	# Handle Pause Toggle
	if is_pause_down and not _was_pause_pressed:
		_was_pause_pressed = true
		if vr_menu_canvas != null:
			if vr_menu_canvas.visible:
				vr_menu_canvas.close_menu()
			else:
				vr_menu_canvas.open_menu()
				vr_menu_canvas.menu_ui.show_pause_menu()
	elif not is_pause_down:
		_was_pause_pressed = false

	# Handle In-Game Recenter Button Press
	if is_recenter_down and not _was_recenter_pressed:
		_was_recenter_pressed = true
		settings.recenter_player(player)
	elif not is_recenter_down:
		_was_recenter_pressed = false


func _unhandled_input(event: InputEvent) -> void:
	# In-game pause trigger (Keyboard Escape key or UI Cancel)
	if not _staging and (event.is_action_pressed("menu_button") or event.is_action_pressed("ui_cancel")):
		if vr_menu_canvas != null:
			if vr_menu_canvas.visible:
				vr_menu_canvas.close_menu()
			else:
				vr_menu_canvas.open_menu()
				vr_menu_canvas.menu_ui.show_pause_menu()


func _start_game() -> void:
	_staging = false

	if vr_menu_canvas != null:
		vr_menu_canvas.visible = false

	# Recenter the player position and horizontal yaw facing.
	# RESET_BUT_KEEP_TILT prevents the world horizon from getting tilted diagonally if the head is tilted.
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

	# Wait one physics frame so the XR runtime applies the recentered pose
	# to XRCamera3D before we snapshot the camera height.
	await get_tree().physics_frame

	# Lock the fixed POV offset based on where the player is right now.
	if player != null and player.has_method(&"recenter_fixed_pov"):
		player.call(&"recenter_fixed_pov")

	# Reveal the gameplay world.
	if game_root != null:
		game_root.visible = true

	print("GameStage: game started — player recentered.")


func _on_menu_game_started() -> void:
	_start_game()


func _on_menu_returned_main() -> void:
	_staging = true
	if game_root != null:
		game_root.visible = false
	if vr_menu_canvas != null:
		vr_menu_canvas.open_menu()
		vr_menu_canvas.menu_ui.show_main_menu()


func _find_camera() -> XRCamera3D:
	return _find_node_of_type(get_tree().root, "XRCamera3D") as XRCamera3D


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result := _find_node_of_type(child, type_name)
		if result != null:
			return result
	return null
