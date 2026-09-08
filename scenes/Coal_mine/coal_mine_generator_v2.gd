@tool
extends Node3D
#class_name MineTunnelGenerator

@export_category("Path")
@export var tunnel_path: Path3D

@export_category("Tunnel Shape")
@export_range(1.0, 30.0, 0.1) var tunnel_width: float = 6.0
@export_range(0.5, 20.0, 0.1) var wall_height: float = 3.0
@export_range(0.5, 20.0, 0.1) var roof_height: float = 3.0

@export_category("Tunnel Quality")
@export_range(6, 48, 1) var arch_segments: int = 16
@export_range(0.1, 5.0, 0.1) var rings_per_meter: float = 1.0

@export_category("Tunnel Material")
@export var tunnel_material: Material

@export_category("Mine Supports")
@export var generate_supports: bool = false
@export var support_scene: PackedScene
@export var generated_support_material: StandardMaterial3D
@export_range(1.0, 30.0, 0.1) var support_spacing: float = 4.0
@export_range(0.0, 30.0, 0.1) var support_start_offset: float = 2.0
@export_range(0.0, 1.0, 0.01) var support_chance: float = 1.0
@export_range(-5.0, 5.0, 0.01) var support_forward_offset: float = 0.0
@export_range(-2.0, 2.0, 0.01) var support_side_offset: float = 0.0
@export_range(-2.0, 2.0, 0.01) var support_height_offset: float = 0.0
@export var support_rotation_offset: Vector3 = Vector3.ZERO
@export var support_scale: Vector3 = Vector3.ONE

@export_category("Generated Support Size")
@export_range(0.05, 1.0, 0.01) var support_beam_width: float = 0.30
@export_range(0.05, 1.0, 0.01) var support_beam_depth: float = 0.30
@export_range(0.0, 1.0, 0.01) var support_floor_margin: float = 0.05
@export_range(0.0, 1.0, 0.01) var support_roof_margin: float = 0.05
@export var generated_support_collision: bool = false

@export_category("Generated Wood Appearance")
@export var auto_create_wood_material: bool = true
@export var wood_color: Color = Color(0.20, 0.075, 0.025, 1.0)
@export_range(0.0, 1.0, 0.01) var wood_roughness: float = 0.82
@export_range(0.0, 1.0, 0.01) var wood_metallic: float = 0.0
@export_range(0.0, 1.0, 0.01) var wood_specular: float = 0.25

@export_category("Mine Lamps")
@export var generate_lamps: bool = false
@export var lamp_scene: PackedScene
@export var generated_lamp_material: StandardMaterial3D
@export_range(1.0, 40.0, 0.1) var lamp_spacing: float = 8.0
@export_range(0.0, 40.0, 0.1) var lamp_start_offset: float = 4.0
@export_range(0.0, 1.0, 0.01) var lamp_chance: float = 1.0
@export_enum("Right Wall", "Left Wall") var lamp_side: int = 0
@export_range(0.0, 4.0, 0.05) var lamp_height_offset: float = 0.6
@export_range(0.0, 1.0, 0.01) var lamp_wall_offset: float = 0.08
@export_range(-5.0, 5.0, 0.01) var lamp_forward_offset: float = 0.0
@export_range(-2.0, 2.0, 0.01) var lamp_side_offset: float = 0.0
@export var lamp_rotation_offset: Vector3 = Vector3.ZERO
@export var lamp_scale: Vector3 = Vector3.ONE

@export_category("Generated Wall Lamp")
@export_range(0.1, 1.0, 0.01) var lamp_body_width: float = 0.32
@export_range(0.1, 1.0, 0.01) var lamp_body_height: float = 0.45
@export_range(0.05, 0.5, 0.01) var lamp_body_depth: float = 0.18
@export_range(0.03, 0.3, 0.01) var lamp_bulb_radius: float = 0.10
@export_range(0.05, 1.0, 0.01) var lamp_mount_length: float = 0.18

@export_category("Generated Lamp Appearance")
@export var auto_create_lamp_material: bool = true
@export var lamp_body_color: Color = Color(0.07, 0.06, 0.045, 1.0)
@export_range(0.0, 1.0, 0.01) var lamp_roughness: float = 0.65
@export_range(0.0, 1.0, 0.01) var lamp_metallic: float = 0.55
@export var lamp_bulb_color: Color = Color(1.0, 0.65, 0.25, 1.0)

@export_category("Generated Lamp Light")
@export var generated_light_enabled: bool = true
@export var generated_light_color: Color = Color(1.0, 0.64, 0.28, 1.0)
@export_range(0.1, 30.0, 0.1) var generated_light_energy: float = 4.0
@export_range(1.0, 30.0, 0.1) var generated_light_range: float = 9.0
@export_range(10.0, 120.0, 1.0) var generated_light_angle: float = 55.0
@export_range(0.0, 30.0, 0.1) var generated_light_attenuation: float = 1.0
@export var generated_light_shadow: bool = false

@export_category("Randomization")
@export var generation_seed: int = 12345
@export var randomize_every_generation: bool = false

@export_category("Tunnel Collision")
@export var generate_collision: bool = true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export_category("Actions")
@export_tool_button("Regenerate Everything", "Reload")
var regenerate_action: Callable = Callable(self, "regenerate_everything")

@export_tool_button("Clear Everything", "Remove")
var clear_action: Callable = Callable(self, "clear_everything")

var _random := RandomNumberGenerator.new()
var _generated_mesh: MeshInstance3D
var _generated_collision: StaticBody3D
var _generated_supports: Node3D
var _generated_lamps: Node3D

func _ready() -> void:
	_find_generated_nodes()

func regenerate_everything() -> void:
	if tunnel_path == null:
		push_warning("MineTunnelGenerator: Tunnel Path is not assigned.")
		return
	if tunnel_path.curve == null:
		push_warning("MineTunnelGenerator: Tunnel Path has no Curve3D.")
		return
	if tunnel_path.curve.get_point_count() < 2:
		push_warning("MineTunnelGenerator: Tunnel Path needs at least 2 points.")
		return

	var curve: Curve3D = tunnel_path.curve
	var curve_length: float = curve.get_baked_length()

	if curve_length <= 0.01:
		push_warning("MineTunnelGenerator: Tunnel Path is too short.")
		return

	if randomize_every_generation:
		_random.randomize()
	else:
		_random.seed = generation_seed

	clear_everything()
	_create_main_tunnel(curve, curve_length)

	if generate_supports:
		_create_supports(curve, curve_length)

	if generate_lamps:
		_create_lamps(curve, curve_length)

func _create_main_tunnel(curve: Curve3D, curve_length: float) -> void:
	var mesh: ArrayMesh = _create_tunnel_mesh(curve, curve_length)

	_generated_mesh = MeshInstance3D.new()
	_generated_mesh.name = "GeneratedTunnelMesh"
	_generated_mesh.mesh = mesh
	_generated_mesh.material_override = tunnel_material

	add_child(_generated_mesh)
	_set_owner(_generated_mesh)

	if generate_collision:
		_create_collision(mesh)

func _create_tunnel_mesh(curve: Curve3D, curve_length: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var section_count: int = arch_segments + 3
	var ring_count: int = maxi(
		2,
		int(ceil(curve_length * rings_per_meter)) + 1
	)

	for ring_index in range(ring_count):
		var distance: float = (
			float(ring_index) /
			float(ring_count - 1)
		) * curve_length

		var frame: Dictionary = _get_path_frame(
			curve,
			distance,
			curve_length
		)

		var center: Vector3 = frame["center"]
		var right: Vector3 = frame["right"]
		var up: Vector3 = frame["up"]

		var half_width: float = tunnel_width * 0.5
		var u: float = distance / 4.0

		_add_vertex(
			vertices,
			normals,
			uvs,
			center + right * half_width,
			right,
			u,
			0.0
		)

		_add_vertex(
			vertices,
			normals,
			uvs,
			center +
			right * half_width +
			up * wall_height,
			right,
			u,
			0.15
		)

		for arch_index in range(1, arch_segments + 1):
			var t: float = (
				float(arch_index) /
				float(arch_segments)
			)

			var angle: float = PI * t
			var horizontal: float = cos(angle) * half_width
			var vertical: float = sin(angle) * roof_height

			var position: Vector3 = (
				center +
				right * horizontal +
				up * (
					wall_height +
					vertical
				)
			)

			var normal: Vector3 = (
				right * horizontal +
				up * vertical
			)

			if normal.length_squared() < 0.0001:
				normal = -up
			else:
				normal = -normal.normalized()

			_add_vertex(
				vertices,
				normals,
				uvs,
				position,
				normal,
				u,
				0.15 + t * 0.70
			)

		_add_vertex(
			vertices,
			normals,
			uvs,
			center - right * half_width,
			-right,
			u,
			1.0
		)

	for ring_index in range(ring_count - 1):
		var current_start: int = (
			ring_index * section_count
		)

		var next_start: int = (
			(ring_index + 1) * section_count
		)

		for point_index in range(section_count - 1):
			var a: int = current_start + point_index
			var b: int = current_start + point_index + 1
			var c: int = next_start + point_index
			var d: int = next_start + point_index + 1

			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()

	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	return mesh

func _create_supports(
	curve: Curve3D,
	curve_length: float
) -> void:
	_generated_supports = Node3D.new()
	_generated_supports.name = "GeneratedMineSupports"

	add_child(_generated_supports)
	_set_owner(_generated_supports)

	var distance: float = maxf(
		0.0,
		support_start_offset
	)

	while distance < curve_length:
		if _random.randf() <= support_chance:
			_create_support(
				curve,
				distance,
				curve_length
			)

		distance += maxf(
			support_spacing,
			0.1
		)

func _create_support(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	if support_scene != null:
		_create_custom_support(
			curve,
			distance,
			curve_length
		)
	else:
		_create_generated_support(
			curve,
			distance,
			curve_length
		)

func _create_custom_support(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	var frame: Dictionary = _get_path_frame(
		curve,
		distance,
		curve_length
	)

	var instance: Node = support_scene.instantiate()

	if not instance is Node3D:
		instance.queue_free()
		return

	var support := instance as Node3D
	support.name = "MineSupport"

	_generated_supports.add_child(support)

	_place_on_frame(
		support,
		frame,
		support_forward_offset,
		support_side_offset,
		support_height_offset
	)

	support.rotation_degrees += (
		support_rotation_offset
	)

	support.scale = support_scale

	_set_owner(support)

func _create_generated_support(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	var frame: Dictionary = _get_path_frame(
		curve,
		distance,
		curve_length
	)

	var root := Node3D.new()
	root.name = "GeneratedMineSupport"

	_generated_supports.add_child(root)
	_set_owner(root)

	_place_on_frame(
		root,
		frame,
		support_forward_offset,
		support_side_offset,
		support_height_offset
	)

	root.rotation_degrees += (
		support_rotation_offset
	)

	root.scale = support_scale

	var material := _get_support_material()

	var half_width: float = tunnel_width * 0.5
	var beam_width: float = support_beam_width
	var beam_depth: float = support_beam_depth

	var floor_y: float = support_floor_margin
	var roof_y: float = wall_height - support_roof_margin

	var post_height: float = maxf(
		0.1,
		roof_y - floor_y
	)

	var center_y: float = (
		floor_y +
		post_height * 0.5
	)

	var left_x: float = (
		-half_width +
		beam_width * 0.5
	)

	var right_x: float = (
		half_width -
		beam_width * 0.5
	)

	_create_generated_beam(
		root,
		Vector3(
			beam_width,
			post_height,
			beam_depth
		),
		Vector3(
			left_x,
			center_y,
			0.0
		),
		"LeftPost",
		material
	)

	_create_generated_beam(
		root,
		Vector3(
			beam_width,
			post_height,
			beam_depth
		),
		Vector3(
			right_x,
			center_y,
			0.0
		),
		"RightPost",
		material
	)

	_create_generated_beam(
		root,
		Vector3(
			tunnel_width,
			beam_width,
			beam_depth
		),
		Vector3(
			0.0,
			roof_y,
			0.0
		),
		"TopBeam",
		material
	)

func _get_support_material() -> StandardMaterial3D:
	if generated_support_material != null:
		return generated_support_material

	if not auto_create_wood_material:
		return null

	var material := StandardMaterial3D.new()

	material.albedo_color = wood_color
	material.roughness = wood_roughness
	material.metallic = wood_metallic
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	if material.has_method("set_specular"):
		material.set("specular", wood_specular)

	return material

func _create_generated_beam(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	node_name: String,
	material: Material
) -> void:
	var beam := MeshInstance3D.new()
	beam.name = node_name

	var mesh := BoxMesh.new()
	mesh.size = size

	beam.mesh = mesh
	beam.position = position

	if material != null:
		beam.material_override = material

	parent.add_child(beam)
	_set_owner(beam)

	if generated_support_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "Collision"
		body.position = position

		parent.add_child(body)
		_set_owner(body)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()

		shape.size = size
		collision.shape = shape

		body.add_child(collision)
		_set_owner(collision)

func _create_lamps(
	curve: Curve3D,
	curve_length: float
) -> void:
	_generated_lamps = Node3D.new()
	_generated_lamps.name = "GeneratedMineLamps"

	add_child(_generated_lamps)
	_set_owner(_generated_lamps)

	var distance: float = maxf(
		0.0,
		lamp_start_offset
	)

	while distance < curve_length:
		if _random.randf() <= lamp_chance:
			_create_lamp(
				curve,
				distance,
				curve_length
			)

		distance += maxf(
			lamp_spacing,
			0.1
		)

func _create_lamp(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	if lamp_scene != null:
		_create_custom_lamp(
			curve,
			distance,
			curve_length
		)
	else:
		_create_generated_lamp(
			curve,
			distance,
			curve_length
		)

func _create_custom_lamp(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	var frame: Dictionary = _get_path_frame(
		curve,
		distance,
		curve_length
	)

	var instance: Node = lamp_scene.instantiate()

	if not instance is Node3D:
		instance.queue_free()
		return

	var lamp := instance as Node3D
	lamp.name = "MineLamp"

	_generated_lamps.add_child(lamp)

	_place_lamp(
		lamp,
		frame
	)

	lamp.rotation_degrees += (
		lamp_rotation_offset
	)

	lamp.scale = lamp_scale

	_set_owner(lamp)

func _create_generated_lamp(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> void:
	var frame: Dictionary = _get_path_frame(
		curve,
		distance,
		curve_length
	)

	var root := Node3D.new()
	root.name = "GeneratedWallLamp"

	_generated_lamps.add_child(root)
	_set_owner(root)

	_place_lamp(
		root,
		frame
	)

	root.rotation_degrees += (
		lamp_rotation_offset
	)

	root.scale = lamp_scale

	var body_material := _get_lamp_material()

	var body := MeshInstance3D.new()
	body.name = "LampBody"

	var body_mesh := BoxMesh.new()

	body_mesh.size = Vector3(
		lamp_body_width,
		lamp_body_height,
		lamp_body_depth
	)

	body.mesh = body_mesh
	body.material_override = body_material

	root.add_child(body)
	_set_owner(body)

	var mount := MeshInstance3D.new()
	mount.name = "WallMount"

	var mount_mesh := BoxMesh.new()

	mount_mesh.size = Vector3(
		lamp_body_width * 0.45,
		lamp_body_height * 0.65,
		lamp_mount_length
	)

	mount.mesh = mount_mesh

	mount.position = Vector3(
		0.0,
		0.0,
		lamp_mount_length * 0.5
	)

	mount.material_override = body_material

	root.add_child(mount)
	_set_owner(mount)

	var bulb := MeshInstance3D.new()
	bulb.name = "LampBulb"

	var bulb_mesh := SphereMesh.new()

	bulb_mesh.radius = lamp_bulb_radius
	bulb_mesh.height = lamp_bulb_radius * 2.0

	bulb.mesh = bulb_mesh

	bulb.position = Vector3(
		0.0,
		0.0,
		-(lamp_body_depth * 0.5)
	)

	var bulb_material := StandardMaterial3D.new()

	bulb_material.albedo_color = lamp_bulb_color
	bulb_material.emission_enabled = true
	bulb_material.emission = lamp_bulb_color
	bulb_material.emission_energy_multiplier = 5.0

	bulb.material_override = bulb_material

	root.add_child(bulb)
	_set_owner(bulb)

	if generated_light_enabled:
		var light := SpotLight3D.new()
		light.name = "LampSpotLight"

		light.light_color = generated_light_color
		light.light_energy = generated_light_energy
		light.spot_range = generated_light_range
		light.spot_angle = generated_light_angle
		light.shadow_enabled = generated_light_shadow
		light.light_angular_distance = 0.5
		light.shadow_bias = 0.05

		light.position = Vector3(
			0.0,
			0.0,
			-(lamp_body_depth * 0.5)
		)

		# Local -Z points toward the tunnel.
		light.rotation = Vector3.ZERO

		root.add_child(light)
		_set_owner(light)

func _get_lamp_material() -> StandardMaterial3D:
	if generated_lamp_material != null:
		return generated_lamp_material

	if not auto_create_lamp_material:
		return null

	var material := StandardMaterial3D.new()

	material.albedo_color = lamp_body_color
	material.roughness = lamp_roughness
	material.metallic = lamp_metallic
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	return material

func _place_on_frame(
	node: Node3D,
	frame: Dictionary,
	forward_offset: float,
	side_offset: float,
	height_offset: float
) -> void:
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var forward: Vector3 = frame["forward"]

	node.position = (
		center
		+ forward * forward_offset
		+ right * side_offset
		+ up * height_offset
	)

	# +Z is set opposite to travel direction.
	# This prevents imported support scenes from appearing reversed.
	node.basis = Basis(
		right,
		up,
		-forward
	)

func _place_lamp(
	node: Node3D,
	frame: Dictionary
) -> void:
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var forward: Vector3 = frame["forward"]

	var side_multiplier: float = 1.0

	if lamp_side == 1:
		side_multiplier = -1.0

	var wall_distance: float = (
		tunnel_width * 0.5
		- lamp_wall_offset
	)

	node.position = (
		center
		+ right
		* side_multiplier
		* wall_distance
		+ right
		* lamp_side_offset
		+ up
		* (
			wall_height
			+ lamp_height_offset
		)
		+ forward
		* lamp_forward_offset
	)

	var inward: Vector3

	if side_multiplier > 0.0:
		inward = -right
	else:
		inward = right

	# Local -Z of the lamp points into the tunnel.
	node.basis = Basis(
		right,
		up,
		inward
	)

func _get_path_frame(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> Dictionary:
	var path_position: Vector3 = curve.sample_baked(
		distance,
		true
	)

	var world_position: Vector3 = tunnel_path.to_global(
		path_position
	)

	var center: Vector3 = to_local(
		world_position
	)

	var forward: Vector3 = _get_path_tangent(
		curve,
		distance,
		curve_length
	)

	forward = (
		tunnel_path.global_transform.basis
		* forward
	).normalized()

	forward = (
		global_transform.basis.inverse()
		* forward
	).normalized()

	var up: Vector3 = Vector3.UP

	var right: Vector3 = forward.cross(up)

	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	up = right.cross(forward).normalized()

	return {
		"center": center,
		"right": right,
		"up": up,
		"forward": forward
	}

func _get_path_tangent(
	curve: Curve3D,
	distance: float,
	curve_length: float
) -> Vector3:
	var sample_distance: float = 0.25

	var previous_distance: float = maxf(
		0.0,
		distance - sample_distance
	)

	var next_distance: float = minf(
		curve_length,
		distance + sample_distance
	)

	var previous_position: Vector3 = curve.sample_baked(
		previous_distance,
		true
	)

	var next_position: Vector3 = curve.sample_baked(
		next_distance,
		true
	)

	var tangent: Vector3 = (
		next_position
		- previous_position
	)

	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD

	return tangent.normalized()

func _add_vertex(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	position: Vector3,
	normal: Vector3,
	u: float,
	v: float
) -> void:
	vertices.append(position)

	if normal.length_squared() < 0.0001:
		normals.append(Vector3.UP)
	else:
		normals.append(normal.normalized())

	uvs.append(Vector2(u, v))

func _create_collision(
	mesh: ArrayMesh
) -> void:
	_generated_collision = StaticBody3D.new()
	_generated_collision.name = "GeneratedTunnelCollision"

	_generated_collision.collision_layer = collision_layer
	_generated_collision.collision_mask = collision_mask

	add_child(_generated_collision)
	_set_owner(_generated_collision)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = mesh.create_trimesh_shape()

	_generated_collision.add_child(collision_shape)
	_set_owner(collision_shape)

func clear_everything() -> void:
	var nodes_to_remove: Array[Node] = []

	for child in get_children():
		if (
			child.name == "GeneratedTunnelMesh"
			or child.name == "GeneratedTunnelCollision"
			or child.name == "GeneratedMineSupports"
			or child.name == "GeneratedMineLamps"
		):
			nodes_to_remove.append(child)

	for node in nodes_to_remove:
		remove_child(node)
		node.queue_free()

	_generated_mesh = null
	_generated_collision = null
	_generated_supports = null
	_generated_lamps = null

func _find_generated_nodes() -> void:
	for child in get_children():
		if child.name == "GeneratedTunnelMesh":
			_generated_mesh = child as MeshInstance3D
		elif child.name == "GeneratedTunnelCollision":
			_generated_collision = child as StaticBody3D
		elif child.name == "GeneratedMineSupports":
			_generated_supports = child as Node3D
		elif child.name == "GeneratedMineLamps":
			_generated_lamps = child as Node3D

func _set_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return

	var root: Node = get_tree().edited_scene_root

	if root != null:
		node.owner = root
