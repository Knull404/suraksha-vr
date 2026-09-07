extends Node3D
class_name PicoUIPointer

## VR Laser Pointer for menu and UI interaction.
## Casts a laser beam from an XRController3D onto 3D UI panels (SubViewports).
## Converts 3D raycast intersection into 2D mouse motion and click events.

@export var controller: XRController3D
@export var trigger_action: StringName = &"trigger_click"
@export var ray_length: float = 10.0
@export var laser_color: Color = Color(0.2, 0.7, 1.0, 0.7)
@export var dot_color: Color = Color(0.1, 0.9, 1.0, 1.0)

var _laser_mesh: MeshInstance3D
var _dot_mesh: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _dot_mat: StandardMaterial3D

var _last_hit_viewport: SubViewport = null
var _last_pixel_pos: Vector2 = Vector2.ZERO
var _was_pressed: bool = false

func _ready() -> void:
	# 1. Create Laser Beam Mesh
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.002
	cyl.bottom_radius = 0.002
	cyl.height = 1.0

	_laser_mat = StandardMaterial3D.new()
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.albedo_color = laser_color

	_laser_mesh = MeshInstance3D.new()
	_laser_mesh.mesh = cyl
	_laser_mesh.material_override = _laser_mat
	add_child(_laser_mesh)

	# 2. Create Laser Hit Dot Mesh
	var sphere := SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.03

	_dot_mat = StandardMaterial3D.new()
	_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = dot_color

	_dot_mesh = MeshInstance3D.new()
	_dot_mesh.mesh = sphere
	_dot_mesh.material_override = _dot_mat
	add_child(_dot_mesh)
	_dot_mesh.visible = false

func _physics_process(_delta: float) -> void:
	if controller == null or not controller.get_is_active():
		_laser_mesh.visible = false
		_dot_mesh.visible = false
		return

	global_transform = controller.global_transform

	var space_state := get_world_3d().direct_space_state
	var origin := global_position
	var target := origin - global_transform.basis.z * ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Layer 23 is designated for UI Objects in project settings (mask 1 << 22)
	query.collision_mask = (1 << 22) | 1

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		_update_laser_line(origin, target)
		_dot_mesh.visible = false
		_release_current_hover()
		return

	var hit_pos: Vector3 = result.position
	var collider: Node = result.collider

	_update_laser_line(origin, hit_pos)
	_dot_mesh.global_position = hit_pos
	_dot_mesh.visible = true

	# Check if collider belongs to a VRMenuCanvas
	var menu_canvas: VRMenuCanvas = _find_menu_canvas(collider)
	if menu_canvas != null and menu_canvas.sub_viewport != null and menu_canvas.mesh_instance != null:
		var local_point := menu_canvas.mesh_instance.global_transform.affine_inverse() * hit_pos
		var quad_mesh := menu_canvas.mesh_instance.mesh as QuadMesh
		if quad_mesh != null:
			var qsize := quad_mesh.size
			var u := (local_point.x + qsize.x * 0.5) / qsize.x
			var v := 1.0 - (local_point.y + qsize.y * 0.5) / qsize.y

			var vp_size := Vector2(menu_canvas.sub_viewport.size)
			var pixel_pos := Vector2(u * vp_size.x, v * vp_size.y)

			_handle_viewport_input(menu_canvas.sub_viewport, pixel_pos)
	else:
		_release_current_hover()

func _update_laser_line(from_pos: Vector3, to_pos: Vector3) -> void:
	_laser_mesh.visible = true
	var dir := to_pos - from_pos
	var length := dir.length()
	if length < 0.001:
		return
	_laser_mesh.global_position = from_pos + dir * 0.5
	# Orient laser along -Z axis
	if dir.normalized().abs().is_equal_approx(Vector3.UP):
		_laser_mesh.look_at(to_pos, Vector3.RIGHT)
	else:
		_laser_mesh.look_at(to_pos, Vector3.UP)
	_laser_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_laser_mesh.scale = Vector3(1.0, length, 1.0)

func _handle_viewport_input(vp: SubViewport, pixel_pos: Vector2) -> void:
	if vp == null or not vp.is_inside_tree():
		return
	_last_hit_viewport = vp

	# 1. Send Mouse Motion (Hover)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel_pos
	motion.global_position = pixel_pos
	motion.relative = pixel_pos - _last_pixel_pos
	vp.push_input(motion)
	_last_pixel_pos = pixel_pos

	# 2. Send Mouse Click on Trigger
	var is_pressed := controller.is_button_pressed(trigger_action) or controller.is_button_pressed(&"primary_click")
	if is_pressed != _was_pressed:
		_was_pressed = is_pressed
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_pressed
		click.position = pixel_pos
		click.global_position = pixel_pos
		vp.push_input(click)

func _release_current_hover() -> void:
	if _last_hit_viewport != null and _last_hit_viewport.is_inside_tree():
		if _was_pressed:
			_was_pressed = false
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = false
			click.position = _last_pixel_pos
			click.global_position = _last_pixel_pos
			_last_hit_viewport.push_input(click)
		_last_hit_viewport = null

func _find_menu_canvas(node: Node) -> VRMenuCanvas:
	var curr: Node = node
	while curr != null:
		if curr is VRMenuCanvas:
			return curr as VRMenuCanvas
		curr = curr.get_parent()
	return null
