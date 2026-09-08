@tool
extends Node3D
#class_name MineTunnelGenerator

# ============================================================
# ROUTES
# ============================================================

@export_category("Routes")
@export var tunnel_routes: Array[Path3D] = []

# ============================================================
# TUNNEL
# ============================================================

@export_category("Tunnel Shape")
@export_range(1.0, 30.0, 0.1) var tunnel_width: float = 6.0
@export_range(1.0, 20.0, 0.1) var wall_height: float = 3.0
@export_range(0.5, 20.0, 0.1) var roof_height: float = 3.0

@export_category("Tunnel Quality")
@export_range(4, 24, 1) var arch_segments: int = 10
@export_range(0.2, 2.0, 0.1) var rings_per_meter: float = 0.5

@export_category("Tunnel Material")
@export var tunnel_material: Material

# ============================================================
# AUTOMATIC JUNCTIONS
# ============================================================

@export_category("Automatic Junctions")
@export var automatic_junctions: bool = true

## How close control points must be to be treated as the same junction.
@export_range(0.01, 2.0, 0.01) var junction_point_tolerance: float = 0.25
@export_range(1.0, 15.0, 0.1) var junction_open_radius: float = 3.5

# ============================================================
# SUPPORTS
# ============================================================

@export_category("Mine Supports")
@export var generate_supports: bool = true

@export var support_scene: PackedScene
@export var support_material: Material
@export_range(1.0, 30.0, 0.1) var support_spacing: float = 4.0
@export_range(0.0, 30.0, 0.1) var support_start_offset: float = 2.0
@export_range(0.0, 1.0, 0.01) var support_chance: float = 1.0
@export_range(0.05, 1.0, 0.01) var support_beam_width: float = 0.30
@export_range(0.05, 1.0, 0.01) var support_beam_depth: float = 0.30
@export_range(0.0, 1.0, 0.01) var support_floor_margin: float = 0.05
@export_range(0.0, 1.0, 0.01) var support_roof_margin: float = 0.10

@export_category("Automatic Wood Material")
@export var create_wood_material_automatically: bool = true
@export var wood_color: Color = Color(0.20, 0.065, 0.018, 1.0)
@export_range(0.0, 1.0, 0.01) var wood_roughness: float = 0.85
@export_range(0.0, 1.0, 0.01) var wood_metallic: float = 0.0

# ============================================================
# LAMPS
# ============================================================

@export_category("Mine Lamps")
@export var generate_lamps: bool = true

@export var lamp_scene: PackedScene
@export var lamp_material: Material
@export_range(1.0, 40.0, 0.1) var lamp_spacing: float = 8.0
@export_range(0.0, 40.0, 0.1) var lamp_start_offset: float = 4.0
@export_range(0.0, 1.0, 0.01) var lamp_chance: float = 1.0
@export_enum("Right Wall", "Left Wall") var lamp_side: int = 0
@export_range(1.0, 5.0, 0.05) var lamp_height: float = 2.3
@export_range(0.01, 1.0, 0.01) var lamp_wall_offset: float = 0.10

@export_category("Generated Wall Lamp")
@export_range(0.05, 1.0, 0.01) var lamp_body_width: float = 0.32
@export_range(0.05, 1.0, 0.01) var lamp_body_height: float = 0.42
@export_range(0.05, 1.0, 0.01) var lamp_body_depth: float = 0.18
@export_range(0.02, 0.5, 0.01) var lamp_bulb_radius: float = 0.10
@export var lamp_body_color: Color = Color(0.055, 0.045, 0.030, 1.0)
@export var lamp_bulb_color: Color = Color(1.0, 0.60, 0.20, 1.0)

@export_category("Lamp Light")
@export var lamp_light_enabled: bool = true
@export var lamp_light_color: Color = Color(1.0, 0.62, 0.28, 1.0)
@export_range(0.1, 20.0, 0.1) var lamp_light_energy: float = 3.0
@export_range(1.0, 25.0, 0.1) var lamp_light_range: float = 8.0
@export_range(5.0, 120.0, 1.0) var lamp_light_angle: float = 55.0
@export var lamp_light_shadow: bool = false

# ============================================================
# RANDOMIZATION & COLLISION
# ============================================================

@export_category("Settings")
@export var generation_seed: int = 12345
@export var randomize_every_generation: bool = false
@export var generate_collision: bool = true
@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

# ============================================================
# ACTIONS
# ============================================================

@export_category("Actions")
@export_tool_button("Generate Mine", "Reload") var generate_action: Callable = Callable(self, "generate_mine")
@export_tool_button("Clear Mine", "Remove") var clear_action: Callable = Callable(self, "clear_mine")

# ============================================================
# INTERNAL
# ============================================================

var _random := RandomNumberGenerator.new()
var _generated_root: Node3D = null
var _junctions: Array[Dictionary] = []

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_find_generated_root()

# ============================================================
# PUBLIC GENERATE
# ============================================================

func generate_mine() -> void:
	var valid_routes: Array[Path3D] = []
	for route in tunnel_routes:
		if route and route.curve and route.curve.get_point_count() >= 2:
			valid_routes.append(route)

	if valid_routes.is_empty():
		push_warning("MineTunnelGenerator: No valid Path3D routes assigned.")
		return

	if randomize_every_generation:
		_random.randomize()
	else:
		_random.seed = generation_seed

	clear_mine()

	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedMine"
	add_child(_generated_root)
	_set_owner(_generated_root)

	_junctions.clear()
	if automatic_junctions:
		_detect_junctions(valid_routes)

	# 1. Bake the VR optimized mesh
	_build_baked_tunnels(valid_routes)
	
	# 2. Place props along the paths
	for route_index in range(valid_routes.size()):
		var route = valid_routes[route_index]
		var route_root = _get_route_root(route_index)
		
		if generate_supports:
			_generate_route_supports(route_root, route)
		if generate_lamps:
			_generate_route_lamps(route_root, route)
			
	print("MineTunnelGenerator: Complete. Tunnels baked & optimized for VR.")

# ============================================================
# VR OPTIMIZED TUNNEL BAKING
# ============================================================

func _build_baked_tunnels(valid_routes: Array[Path3D]) -> void:
	# Temporary root for CSG calculation
	var csg_root = Node3D.new()
	csg_root.name = "TempCSG"
	_generated_root.add_child(csg_root)

	var master_combiner = CSGCombiner3D.new()
	master_combiner.operation = CSGCombiner3D.OPERATION_UNION
	csg_root.add_child(master_combiner)

	var outer_combiner = CSGCombiner3D.new()
	outer_combiner.operation = CSGCombiner3D.OPERATION_UNION
	master_combiner.add_child(outer_combiner)

	var inner_combiner = CSGCombiner3D.new()
	inner_combiner.operation = CSGCombiner3D.OPERATION_SUBTRACTION
	master_combiner.add_child(inner_combiner)

	var outer_shape: PackedVector2Array = _create_csg_profile(1.0)
	var inner_shape: PackedVector2Array = _create_csg_profile(0.0)

	for route in valid_routes:
		route.curve.up_vector_enabled = true
		for i in range(route.curve.get_point_count()):
			route.curve.set_point_tilt(i, 0.0)
		
		var outer_poly = CSGPolygon3D.new()
		outer_poly.mode = CSGPolygon3D.MODE_PATH
		outer_combiner.add_child(outer_poly)
		outer_poly.path_node = outer_poly.get_path_to(route)
		outer_poly.polygon = outer_shape
		outer_poly.smooth_faces = true
		outer_poly.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
		outer_poly.path_interval = 1.0 / maxf(0.1, rings_per_meter)
		
		# Extend paths perfectly to punch out entrances
		var extended_path = _create_extended_path(route, 2.0)
		csg_root.add_child(extended_path)
		
		var inner_poly = CSGPolygon3D.new()
		inner_poly.mode = CSGPolygon3D.MODE_PATH
		inner_combiner.add_child(inner_poly)
		inner_poly.path_node = inner_poly.get_path_to(extended_path)
		inner_poly.polygon = inner_shape
		inner_poly.smooth_faces = true
		inner_poly.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
		inner_poly.path_interval = 1.0 / maxf(0.1, rings_per_meter)

	master_combiner._update_shape()
	
	var meshes = master_combiner.get_meshes()
	
	if meshes.size() > 1:
		var baked_mesh = meshes[1] as ArrayMesh
		if baked_mesh and baked_mesh.get_surface_count() > 0:
			var mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "OptimizedTunnelMesh"
			mesh_instance.mesh = baked_mesh
			if tunnel_material != null:
				mesh_instance.material_override = tunnel_material
				
			_generated_root.add_child(mesh_instance)
			_set_owner(mesh_instance)
			
			if generate_collision:
				var body = StaticBody3D.new()
				body.name = "TunnelCollision"
				body.collision_layer = collision_layer
				body.collision_mask = collision_mask
				
				var col_shape = CollisionShape3D.new()
				col_shape.name = "CollisionShape3D"
				col_shape.shape = baked_mesh.create_trimesh_shape()
				
				body.add_child(col_shape)
				mesh_instance.add_child(body)
				
				_set_owner(body)
				_set_owner(col_shape)

	csg_root.queue_free()

func _create_extended_path(original_path: Path3D, ext: float) -> Path3D:
	var original: Curve3D = original_path.curve
	var new_curve: Curve3D = original.duplicate(true)
	var count = new_curve.get_point_count()
	
	if count >= 2:
		var p0 = new_curve.get_point_position(0)
		var out0 = new_curve.get_point_out(0)
		var tangent0 = (new_curve.get_point_position(1) - p0).normalized()
		if out0.length_squared() > 0.01:
			tangent0 = out0.normalized()
		new_curve.set_point_position(0, p0 - tangent0 * ext)
		
		var p1 = new_curve.get_point_position(count - 1)
		var in1 = new_curve.get_point_in(count - 1)
		var tangent1 = (p1 - new_curve.get_point_position(count - 2)).normalized()
		if in1.length_squared() > 0.01:
			tangent1 = -in1.normalized()
		new_curve.set_point_position(count - 1, p1 + tangent1 * ext)
		
	var path = Path3D.new()
	path.curve = new_curve
	path.global_transform = original_path.global_transform
	return path

func _create_csg_profile(padding: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var w: float = (tunnel_width * 0.5) + padding
	var h: float = wall_height + padding
	var rh: float = roof_height + padding

	# Important: Draw polygon counter-clockwise or clockwise explicitly.
	# Sweeping from Left (-w) to Right (w) over the arch generates a solid clockwise polygon.
	
	# Start Bottom-Left
	pts.append(Vector2(-w, -padding))
	
	# Arc from Left to Right
	for i: int in range(arch_segments + 1):
		# t goes from 1.0 to 0.0
		var t: float = 1.0 - (float(i) / float(arch_segments)) 
		var angle: float = t * PI 
		var px: float = cos(angle) * w
		var py: float = h + sin(angle) * rh
		pts.append(Vector2(px, py))
		
	# End Bottom-Right
	pts.append(Vector2(w, -padding))
	return pts

# ============================================================
# ROUTE ROOT
# ============================================================

func _get_route_root(route_index: int) -> Node3D:
	if _generated_root == null:
		return self
	var root_name: String = "Route_" + str(route_index)
	var existing: Node = _generated_root.get_node_or_null(root_name)
	if existing != null and existing is Node3D:
		return existing as Node3D
	var root := Node3D.new()
	root.name = root_name
	_generated_root.add_child(root)
	_set_owner(root)
	return root

# ============================================================
# JUNCTION DETECTION
# ============================================================

func _detect_junctions(routes: Array[Path3D]) -> void:
	for route_index in range(routes.size()):
		var route = routes[route_index]
		var curve = route.curve
		for point_index in range(curve.get_point_count()):
			var local_position = curve.get_point_position(point_index)
			var world_position = route.to_global(local_position)
			var connected = false

			for other_index in range(routes.size()):
				if other_index == route_index:
					continue
				var other_route = routes[other_index]
				var other_curve = other_route.curve
				for other_point_index in range(other_curve.get_point_count()):
					var other_local = other_curve.get_point_position(other_point_index)
					var other_world = other_route.to_global(other_local)
					if world_position.distance_to(other_world) <= junction_point_tolerance:
						connected = true
						break
				if connected:
					break

			if connected:
				_register_junction(world_position)

func _register_junction(world_position: Vector3) -> void:
	for junction in _junctions:
		if junction["center"].distance_to(world_position) <= junction_point_tolerance:
			return
	_junctions.append({"center": world_position})

func _world_position_in_junction(world_position: Vector3) -> bool:
	if not automatic_junctions:
		return false
	for junction in _junctions:
		if junction["center"].distance_to(world_position) <= junction_open_radius:
			return true
	return false

# ============================================================
# SUPPORT GENERATION
# ============================================================

func _generate_route_supports(parent: Node3D, route: Path3D) -> void:
	var curve = route.curve
	var length = curve.get_baked_length()
	var supports_root = Node3D.new()
	supports_root.name = "Supports"
	parent.add_child(supports_root)
	_set_owner(supports_root)

	var distance = maxf(0.0, support_start_offset)
	while distance < length:
		var frame_data = _get_route_frame(route, distance)
		if not _world_position_in_junction(frame_data["world_center"]):
			if _random.randf() <= support_chance:
				_create_support(supports_root, frame_data)
		distance += maxf(support_spacing, 0.1)

func _create_support(parent: Node3D, frame_data: Dictionary) -> void:
	if support_scene != null:
		var instance = support_scene.instantiate() as Node3D
		if instance:
			parent.add_child(instance)
			instance.position = frame_data["center"]
			instance.basis = frame_data["basis"]
			_set_owner(instance)
	else:
		_create_generated_support(parent, frame_data)

func _create_generated_support(parent: Node3D, frame_data: Dictionary) -> void:
	var root = Node3D.new()
	root.name = "GeneratedWoodSupport"
	parent.add_child(root)
	_set_owner(root)

	root.position = frame_data["center"]
	root.basis = frame_data["basis"] # Perfectly follows path rotation
	
	var material = _get_support_material()
	var half_width = tunnel_width * 0.5
	
	# X Positions
	var left_x = -half_width + (support_beam_width * 0.5)
	var right_x = half_width - (support_beam_width * 0.5)

	# Calculate mathematically perfect heights so beams don't clip ceiling or themselves
	var top_beam_y = wall_height - support_roof_margin - (support_beam_width * 0.5)
	var bottom_y = support_floor_margin
	var top_y = top_beam_y - (support_beam_width * 0.5)
	
	var post_height = top_y - bottom_y
	var post_center_y = bottom_y + (post_height * 0.5)

	# Left/Right Posts
	_create_beam(root, Vector3(support_beam_width, post_height, support_beam_depth), Vector3(left_x, post_center_y, 0.0), material, "LeftPost")
	_create_beam(root, Vector3(support_beam_width, post_height, support_beam_depth), Vector3(right_x, post_center_y, 0.0), material, "RightPost")
	
	# Top Horizontal Beam
	_create_beam(root, Vector3(tunnel_width, support_beam_width, support_beam_depth), Vector3(0.0, top_beam_y, 0.0), material, "TopBeam")

func _create_beam(parent: Node3D, size: Vector3, pos: Vector3, material: Material, node_name: String) -> void:
	var beam = MeshInstance3D.new()
	beam.name = node_name
	var mesh = BoxMesh.new()
	mesh.size = size
	beam.mesh = mesh
	beam.position = pos
	if material != null:
		beam.material_override = material
	parent.add_child(beam)
	_set_owner(beam)

func _get_support_material() -> Material:
	if support_material != null:
		return support_material
	if not create_wood_material_automatically:
		return null
	var material = StandardMaterial3D.new()
	material.albedo_color = wood_color
	material.roughness = wood_roughness
	material.metallic = wood_metallic
	return material

# ============================================================
# LAMP GENERATION
# ============================================================

func _generate_route_lamps(parent: Node3D, route: Path3D) -> void:
	var length = route.curve.get_baked_length()
	var lamps_root = Node3D.new()
	lamps_root.name = "Lamps"
	parent.add_child(lamps_root)
	_set_owner(lamps_root)

	var distance = maxf(0.0, lamp_start_offset)
	var side = lamp_side

	while distance < length:
		var frame_data = _get_route_frame(route, distance)
		if not _world_position_in_junction(frame_data["world_center"]):
			if _random.randf() <= lamp_chance:
				if lamp_scene != null:
					_create_custom_lamp(lamps_root, frame_data, side)
				else:
					_create_generated_lamp(lamps_root, frame_data, side)
		side = 1 - side
		distance += maxf(lamp_spacing, 0.1)

func _create_custom_lamp(parent: Node3D, frame_data: Dictionary, side: int) -> void:
	var instance = lamp_scene.instantiate() as Node3D
	if instance:
		parent.add_child(instance)
		_place_lamp(instance, frame_data, side)
		_set_owner(instance)

func _create_generated_lamp(parent: Node3D, frame_data: Dictionary, side: int) -> void:
	var root = Node3D.new()
	root.name = "GeneratedWallLamp"
	parent.add_child(root)
	_set_owner(root)

	_place_lamp(root, frame_data, side)
	var body = MeshInstance3D.new()
	body.name = "LampBody"
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(lamp_body_width, lamp_body_height, lamp_body_depth)
	body.mesh = body_mesh
	
	if lamp_material != null:
		body.material_override = lamp_material
	else:
		body.material_override = _get_default_lamp_material()
		
	root.add_child(body)
	_set_owner(body)

	var bulb = MeshInstance3D.new()
	bulb.name = "LampBulb"
	var bulb_mesh = SphereMesh.new()
	bulb_mesh.radius = lamp_bulb_radius
	bulb_mesh.height = lamp_bulb_radius * 2.0
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(0.0, 0.0, -lamp_body_depth * 0.55)
	
	var bulb_material = StandardMaterial3D.new()
	bulb_material.albedo_color = lamp_bulb_color
	bulb_material.emission_enabled = true
	bulb_material.emission = lamp_bulb_color
	bulb_material.emission_energy_multiplier = 5.0
	bulb.material_override = bulb_material
	
	root.add_child(bulb)
	_set_owner(bulb)

	if lamp_light_enabled:
		var light = SpotLight3D.new()
		light.name = "LampSpotLight"
		light.light_color = lamp_light_color
		light.light_energy = lamp_light_energy
		light.spot_range = lamp_light_range
		light.spot_angle = lamp_light_angle
		light.shadow_enabled = lamp_light_shadow
		light.position = Vector3(0.0, 0.0, -lamp_body_depth * 0.6)
		root.add_child(light)
		_set_owner(light)

func _get_default_lamp_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = lamp_body_color
	material.roughness = 0.65
	material.metallic = 0.55
	return material

func _place_lamp(lamp: Node3D, frame_data: Dictionary, side: int) -> void:
	var multiplier = 1.0 if side == 0 else -1.0 # 0 = Right, 1 = Left
	var wall_distance = tunnel_width * 0.5 - lamp_wall_offset
	
	lamp.position = frame_data["center"] + frame_data["right"] * multiplier * wall_distance + frame_data["up"] * lamp_height
	
	# Lamp properly faces into the tunnel instead of pointing backward
	var inward_direction = -frame_data["right"] * multiplier
	lamp.basis = Basis.looking_at(inward_direction, frame_data["up"])

# ============================================================
# PATH FRAME
# ============================================================

func _get_route_frame(route: Path3D, distance: float) -> Dictionary:
	var curve = route.curve
	var local_position = curve.sample_baked(distance, true)
	var world_position = route.to_global(local_position)
	var center = to_local(world_position)
	
	var local_forward = _get_local_tangent(curve, distance)
	var world_forward = (route.global_transform.basis * local_forward).normalized()
	var forward = (global_transform.basis.inverse() * world_forward).normalized()
	
	# We use Godot's built-in robust math to guarantee upright, twist-free orientations
	var b = Basis.looking_at(forward, Vector3.UP)

	return {
		"center": center,
		"world_center": world_position,
		"basis": b,        # Extracted foolproof orientation
		"right": b.x,      # X axis is definitively Right
		"up": b.y,         # Y axis is definitively Up
		"forward": -b.z    # -Z axis is definitively Forward
	}

func _get_local_tangent(curve: Curve3D, distance: float) -> Vector3:
	var path_length = curve.get_baked_length()
	var sample_distance = 0.2
	var previous_distance = maxf(0.0, distance - sample_distance)
	var next_distance = minf(path_length, distance + sample_distance)
	var previous_position = curve.sample_baked(previous_distance, true)
	var next_position = curve.sample_baked(next_distance, true)
	var tangent = next_position - previous_position
	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD
	return tangent.normalized()

# ============================================================
# CLEAR & EDITOR LOGIC
# ============================================================

func clear_mine() -> void:
	_junctions.clear()
	if _generated_root != null and is_instance_valid(_generated_root):
		_generated_root.queue_free()
	_generated_root = null

func _find_generated_root() -> void:
	for child in get_children():
		if child.name == "GeneratedMine" and child is Node3D:
			_generated_root = child as Node3D
			return

func _set_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var root = get_tree().edited_scene_root
	if root != null:
		node.owner = root
