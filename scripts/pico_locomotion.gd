extends Node
class_name PicoLocomotion

enum Mode { SMOOTH, SNAP }

@export_category("XR Nodes")
@export var controller: XRController3D
@export var player: CharacterBody3D
@export var camera: XRCamera3D

@export_category("Locomotion Mode")
@export var movement_mode: Mode = Mode.SMOOTH

@export_category("Smooth Settings")
@export_range(0.1, 10.0, 0.1) var speed: float = 2.5
@export_range(1.0, 30.0, 0.5) var acceleration: float = 12.0
@export_range(1.0, 30.0, 0.5) var deceleration: float = 16.0

@export_category("Snap Settings")
@export_range(0.1, 5.0, 0.1) var snap_distance: float = 1.5

@export_category("Input")
@export_range(0.0, 0.5, 0.01) var deadzone: float = 0.15

var _can_snap: bool = true

func _physics_process(delta: float) -> void:
	if player == null or camera == null or controller == null:
		return

	# Safety check: ensure the controller is active and tracking before reading input
	if not controller.get_is_active():
		return
	
	# Halt locomotion if teleporting or in menu
	if (player.has_meta("is_teleporting") and player.get_meta("is_teleporting")) or (player.has_meta("is_in_menu") and player.get_meta("is_in_menu")):
		player.velocity.x = move_toward(player.velocity.x, 0.0, deceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, deceleration * delta)
		return

	var input_vec := controller.get_vector2("primary")

	if input_vec.length() < deadzone:
		input_vec = Vector2.ZERO
		_can_snap = true 
	else:
		input_vec = _apply_deadzone(input_vec, deadzone)

	var forward := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x

	forward.y = 0.0
	right.y = 0.0

	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	if right.length_squared() > 0.0001:
		right = right.normalized()

	var move_direction := right * input_vec.x + forward * input_vec.y

	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	match movement_mode:
		Mode.SMOOTH:
			_process_smooth(delta, move_direction)
		Mode.SNAP:
			_process_snap(move_direction)

func _process_smooth(delta: float, direction: Vector3) -> void:
	var target := direction * speed
	var rate := acceleration if target.length_squared() > 0.0 else deceleration
	
	player.velocity.x = move_toward(player.velocity.x, target.x, rate * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z, rate * delta)

func _process_snap(direction: Vector3) -> void:
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	
	if _can_snap and direction.length_squared() > 0.1:
		player.global_position += direction.normalized() * snap_distance
		_can_snap = false 

func _apply_deadzone(value: Vector2, zone: float) -> Vector2:
	var magnitude := value.length()
	var scaled := (magnitude - zone) / (1.0 - zone)
	return value.normalized() * clampf(scaled, 0.0, 1.0)
