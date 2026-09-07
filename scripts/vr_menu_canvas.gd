extends Node3D
class_name VRMenuCanvas

## 3D VR Canvas Wrapper for GameMenu.
## Renders a large, high-res, crystal-clear 2D GameMenu in 3D space directly in front of the camera,
## and provides 3D laser pointers on controllers for easy selection.

@export_category("XR Nodes")
@export var player: CharacterBody3D
@export var game_stage: Node3D
@export var left_controller: XRController3D
@export var right_controller: XRController3D

@export_category("Menu Display Settings")
@export var viewport_size := Vector2i(1280, 960) # High-res VR canvas
@export var quad_size := Vector2(3.2, 2.4)       # Huge, comfortable VR canvas size
@export var canvas_distance: float = 2.2         # Meters in front of player eye

signal game_started
signal game_resumed
signal main_menu_returned

var sub_viewport: SubViewport
var menu_ui: GameMenu
var mesh_instance: MeshInstance3D
var area_3d: Area3D
var pointer_left: PicoUIPointer
var pointer_right: PicoUIPointer

func _ready() -> void:
	# 1. Create High-Res SubViewport
	sub_viewport = SubViewport.new()
	sub_viewport.name = "MenuViewport"
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.transparent_bg = true
	add_child(sub_viewport)

	# 2. Add GameMenu inside SubViewport
	menu_ui = GameMenu.new()
	menu_ui.name = "GameMenuUI"
	menu_ui.player = player
	menu_ui.game_stage = game_stage
	sub_viewport.add_child(menu_ui)

	# 3. Create Large 3D Quad Mesh to display UI
	var quad := QuadMesh.new()
	quad.size = quad_size

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = sub_viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	# 4. Add Physics Area3D on Layer 23 (UI Objects) for Raycast collision
	area_3d = Area3D.new()
	area_3d.name = "UIArea3D"
	# Collision Layer 23 = (1 << 22)
	area_3d.collision_layer = (1 << 22)
	area_3d.collision_mask = 0

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(quad_size.x, quad_size.y, 0.05)
	col_shape.shape = box_shape
	area_3d.add_child(col_shape)
	add_child(area_3d)

	# 5. Position Menu centered in front of Camera
	position_menu_in_front_of_camera()

	# 6. Initialize Laser Pointers on Controllers
	_setup_pointers()

	# Connect and forward Menu signals
	menu_ui.game_started.connect(func():
		emit_signal("game_started")
		_on_game_started()
	)
	menu_ui.game_resumed.connect(func():
		emit_signal("game_resumed")
		_on_game_resumed()
	)
	menu_ui.main_menu_returned.connect(func():
		emit_signal("main_menu_returned")
	)

	# Open menu initially (disables gameplay features & enables pointers)
	open_menu()

func position_menu_in_front_of_camera() -> void:
	var camera: XRCamera3D = null
	if player != null:
		camera = player.find_child("XRCamera3D", true, false) as XRCamera3D
	if camera == null:
		camera = _find_camera_in_tree()

	if camera != null:
		var cam_pos := camera.global_position
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		else:
			forward = Vector3.FORWARD

		# Position centered directly at camera eye height and distance
		global_position = Vector3(
			cam_pos.x + forward.x * canvas_distance,
			cam_pos.y,
			cam_pos.z + forward.z * canvas_distance
		)
		look_at(cam_pos, Vector3.UP)
		rotate_y(PI) # Quad faces player

func _setup_pointers() -> void:
	if left_controller != null and pointer_left == null:
		pointer_left = PicoUIPointer.new()
		pointer_left.name = "PointerLeft"
		pointer_left.controller = left_controller
		left_controller.add_child(pointer_left)

	if right_controller != null and pointer_right == null:
		pointer_right = PicoUIPointer.new()
		pointer_right.name = "PointerRight"
		pointer_right.controller = right_controller
		right_controller.add_child(pointer_right)

func _on_game_started() -> void:
	close_menu()

func _on_game_resumed() -> void:
	close_menu()

func open_menu() -> void:
	position_menu_in_front_of_camera()
	visible = true
	if menu_ui != null:
		menu_ui.visible = true

	# Enable UI Collision Area
	if area_3d != null:
		area_3d.process_mode = PROCESS_MODE_INHERIT

	# Enable Laser Pointers
	_set_pointers_active(true)

	# Disable Player In-Game features while in Menu
	if player != null and player.has_method(&"set_gameplay_enabled"):
		player.call(&"set_gameplay_enabled", false)

func close_menu() -> void:
	visible = false
	if menu_ui != null:
		menu_ui.visible = false

	# Completely disable UI Collision Area so it won't interfere with gameplay
	if area_3d != null:
		area_3d.process_mode = PROCESS_MODE_DISABLED

	# Disable Laser Pointers
	_set_pointers_active(false)

	# Re-enable Player In-Game features for gameplay
	if player != null and player.has_method(&"set_gameplay_enabled"):
		player.call(&"set_gameplay_enabled", true)

func _set_pointers_active(active: bool) -> void:
	if pointer_left != null:
		pointer_left.set_physics_process(active)
		pointer_left.visible = active
	if pointer_right != null:
		pointer_right.set_physics_process(active)
		pointer_right.visible = active

func _find_camera_in_tree() -> XRCamera3D:
	return _find_node_of_type(get_tree().root, "XRCamera3D") as XRCamera3D

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var res := _find_node_of_type(child, type_name)
		if res != null:
			return res
	return null
