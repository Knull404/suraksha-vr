extends Node
class_name PicoTurning

enum Mode { SMOOTH, SNAP }

@export_category("XR Nodes")
@export var controller: XRController3D
@export var player: CharacterBody3D
@export var camera: XRCamera3D

@export_category("Turning Mode")
@export var turn_mode: Mode = Mode.SNAP

@export_category("Smooth Settings")
@export_range(10.0, 180.0, 5.0) var smooth_turn_speed: float = 90.0

@export_category("Snap Settings")
@export_range(15.0, 90.0, 5.0) var snap_turn_angle: float = 45.0
@export_range(0.1, 1.0, 0.05) var snap_threshold: float = 0.5

@export_category("Input")
@export_range(0.0, 0.5, 0.01) var deadzone: float = 0.15

var _can_snap: bool = true

func _physics_process(delta: float) -> void:
	if player == null or camera == null or controller == null:
		return

	# Block turning while in menu
	if player.has_meta("is_in_menu") and player.get_meta("is_in_menu"):
		return

	# Explicitly typed to prevent the Variant inference warnings
	var input_vec: Vector2 = controller.get_vector2("secondary")
	var turn_input: float = input_vec.x

	if abs(turn_input) < deadzone:
		turn_input = 0.0
		_can_snap = true 
	else:
		var sign_val: float = sign(turn_input)
		var magnitude: float = abs(turn_input)
		var scaled: float = (magnitude - deadzone) / (1.0 - deadzone)
		turn_input = sign_val * clampf(scaled, 0.0, 1.0)

	if turn_input == 0.0:
		return

	match turn_mode:
		Mode.SMOOTH:
			_process_smooth(turn_input, delta)
		Mode.SNAP:
			_process_snap(turn_input)

func _process_smooth(input_x: float, delta: float) -> void:
	# Godot's Y rotation is negative for clockwise (turning right)
	var angle: float = deg_to_rad(-input_x * smooth_turn_speed * delta)
	_rotate_player_around_camera(angle)

func _process_snap(input_x: float) -> void:
	if _can_snap and abs(input_x) > snap_threshold:
		var angle: float = deg_to_rad(-sign(input_x) * snap_turn_angle)
		_rotate_player_around_camera(angle)
		_can_snap = false 

func _rotate_player_around_camera(angle_rad: float) -> void:
	# 1. Store the camera's global position before rotation
	var cam_pos_before: Vector3 = camera.global_position
	
	# 2. Rotate the entire rig
	player.rotate_y(angle_rad)
	
	# 3. Calculate how far the camera shifted and offset the player back
	var cam_pos_after: Vector3 = camera.global_position
	player.global_position += (cam_pos_before - cam_pos_after)
