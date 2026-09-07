extends Node
class_name PicoArcTeleportation

@export_category("XR Nodes")
@export var controller: XRController3D
@export var player: CharacterBody3D
@export var camera: XRCamera3D

@export_category("Input Settings")
@export var teleport_button: StringName = &"trigger_click"
@export var thumbstick_action: StringName = &"move"
@export var thumbstick_sensitivity: float = 8.0 
@export var deadzone: float = 0.15

@export_category("Trajectory Settings")
@export var base_power: float = 5.0
@export var min_power: float = 2.0
@export var max_power: float = 15.0
@export var max_steps: int = 40
@export var time_step: float = 0.05
@export var collision_mask: int = 1

@export_category("Validation & Visual Feedback")
@export var max_slope: float = 20.0
@export var valid_teleport_mask: int = 0b1111_1111_1111_1111_1111_1111_1111_1111
@export var can_teleport_color: Color = Color(0.0, 1.0, 0.0, 1.0)       # Green (Valid Floor)
@export var cant_teleport_color: Color = Color(1.0, 0.0, 0.0, 1.0)     # Red (Invalid Wall/Slope)
@export var no_collision_color: Color = Color(0.17, 0.31, 0.86, 1.0)   # Blue (No Hit / Open Air)

var _is_aiming: bool = false
var _has_valid_target: bool = false
var _valid_teleport_pos: Vector3 = Vector3.ZERO
var _current_power: float = 5.0

var _dot_mesh: MultiMeshInstance3D
var _target_marker: MeshInstance3D
var _marker_material: StandardMaterial3D

func _ready() -> void:
	# 1. Setup Dotted Line Visuals
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = max_steps
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	mm.mesh = sphere
	
	_dot_mesh = MultiMeshInstance3D.new()
	_dot_mesh.multimesh = mm
	add_child(_dot_mesh)
	_dot_mesh.visible = false
	
	# 2. Setup Landing Target Marker with a customizable material
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.4
	cylinder.bottom_radius = 0.4
	cylinder.height = 0.05
	
	_marker_material = StandardMaterial3D.new()
	# Fixed: Using the proper Godot 4 enum constant instead of a raw integer
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	_target_marker = MeshInstance3D.new()
	_target_marker.mesh = cylinder
	_target_marker.material_override = _marker_material
	add_child(_target_marker)
	_target_marker.visible = false

func _physics_process(delta: float) -> void:
	if player == null or camera == null or controller == null:
		return

	# Block teleportation while in menu
	if player.has_meta("is_in_menu") and player.get_meta("is_in_menu"):
		if _is_aiming:
			_is_aiming = false
			if _dot_mesh != null: _dot_mesh.visible = false
			if _target_marker != null: _target_marker.visible = false
			player.set_meta("is_teleporting", false)
		return

	var button_pressed: bool = controller.is_button_pressed(teleport_button)

	if button_pressed:
		if not _is_aiming:
			_is_aiming = true
			_dot_mesh.visible = true
			_current_power = base_power
			# Block locomotion scripts from moving the player
			player.set_meta("is_teleporting", true) 
		
		# Adjust distance using thumbstick Y axis (Up = farther, Down = closer)
		var thumbstick_y: float = controller.get_vector2(thumbstick_action).y
		
		if absf(thumbstick_y) > deadzone:
			_current_power -= thumbstick_y * thumbstick_sensitivity * delta
			_current_power = clampf(_current_power, min_power, max_power)
		
		_calculate_arc(delta)
	else:
		if _is_aiming:
			if _has_valid_target:
				_teleport_to(_valid_teleport_pos)
			
			_is_aiming = false
			_dot_mesh.visible = false
			_target_marker.visible = false
			# Re-enable locomotion
			player.set_meta("is_teleporting", false) 

func _calculate_arc(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = controller.get_world_3d().direct_space_state
	var pos: Vector3 = controller.global_position
	
	# Flatten the aim direction and add a consistent upward lift angle
	var aim_dir: Vector3 = -controller.global_transform.basis.z
	aim_dir.y = 0.0
	if aim_dir.length_squared() > 0.0001:
		aim_dir = aim_dir.normalized()
	else:
		aim_dir = -controller.global_transform.basis.z
		
	var launch_vector: Vector3 = (aim_dir + (Vector3.UP * 0.5)).normalized()
	var vel: Vector3 = launch_vector * _current_power
	var gravity: Vector3 = Vector3.DOWN * 9.81
	
	var points: Array[Vector3] = []
	points.append(pos)
	
	var hit_something := false
	var raw_target_pos := Vector3.ZERO
	var floor_normal := Vector3.UP
	var max_slope_cos := cos(deg_to_rad(max_slope))

	for i in range(max_steps):
		var next_pos: Vector3 = pos + (vel * time_step) + (0.5 * gravity * time_step * time_step)
		var next_vel: Vector3 = vel + gravity * time_step

		var query := PhysicsRayQueryParameters3D.create(pos, next_pos, collision_mask)
		
		# Exclude player and camera from self-collision
		var exclude_list: Array[RID] = []
		if player:
			exclude_list.append(player.get_rid())
		query.exclude = exclude_list

		var result := space_state.intersect_ray(query)

		if result.is_empty():
			pos = next_pos
			vel = next_vel
			points.append(pos)
		else:
			hit_something = true
			raw_target_pos = result.position
			floor_normal = result.get("normal", Vector3.UP)
			
			# Check layer mask validity
			var collider: Node = result.get("collider", null)
			var mask_valid := true
			if collider and (valid_teleport_mask & collider.collision_layer) == 0:
				mask_valid = false

			# Check slope validity against max_slope limit
			var slope_valid := (Vector3.UP.dot(floor_normal) >= max_slope_cos)

			# Target is only valid if both mask and slope pass criteria
			_has_valid_target = mask_valid and slope_valid

			# Append exact collision point and stop trajectory immediately
			points.append(raw_target_pos)
			break

	_draw_trajectory(points)
	
	if hit_something:
		if _valid_teleport_pos == Vector3.ZERO:
			_valid_teleport_pos = raw_target_pos
		else:
			_valid_teleport_pos = _valid_teleport_pos.lerp(raw_target_pos, 25.0 * delta)
			
		_target_marker.global_position = _valid_teleport_pos
		_target_marker.visible = true
		
		if _has_valid_target:
			_marker_material.albedo_color = can_teleport_color # Green: Valid floor
		else:
			_marker_material.albedo_color = cant_teleport_color # Red: Invalid wall/slope
	else:
		_has_valid_target = false
		_target_marker.visible = false
		_marker_material.albedo_color = no_collision_color # Blue: No collision

func _draw_trajectory(points: Array[Vector3]) -> void:
	var count: int = mini(points.size(), max_steps)
	_dot_mesh.multimesh.visible_instance_count = count
	
	for i in range(count):
		var transform: Transform3D = Transform3D(Basis(), points[i])
		_dot_mesh.multimesh.set_instance_transform(i, transform)

func _teleport_to(target_pos: Vector3) -> void:
	var cam_pos: Vector3 = camera.global_position
	var player_pos: Vector3 = player.global_position
	var offset: Vector3 = cam_pos - player_pos
	offset.y = 0.0 
	
	player.global_position = target_pos - offset
