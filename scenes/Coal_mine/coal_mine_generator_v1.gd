@tool
extends Node3D
#class_name MineTunnelGenerator


# ============================================================
# PATH
# ============================================================

@export_category("Path")

@export var tunnel_path: Path3D


# ============================================================
# TUNNEL SHAPE
# ============================================================

@export_category("Tunnel Shape")

@export var tunnel_width: float = 6.0

@export var wall_height: float = 3.0

@export var roof_height: float = 3.0


# ============================================================
# QUALITY
# ============================================================

@export_category("Quality")

@export_range(6, 48, 1)
var arch_segments: int = 16

@export_range(0.1, 5.0, 0.1)
var rings_per_meter: float = 1.0


# ============================================================
# MATERIAL
# ============================================================

@export_category("Material")

@export var tunnel_material: Material


# ============================================================
# COLLISION
# ============================================================

@export_category("Collision")

@export var generate_collision: bool = true

@export_flags_3d_physics
var collision_layer: int = 1

@export_flags_3d_physics
var collision_mask: int = 1


# ============================================================
# ACTIONS
# ============================================================

@export_category("Actions")

# Explicit Callable makes the Inspector buttons reliable.
@export_tool_button("Regenerate Tunnel", "Reload")
var regenerate_action: Callable = Callable(self, "regenerate_tunnel")

@export_tool_button("Clear Generated Tunnel", "Remove")
var clear_action: Callable = Callable(self, "clear_generated_tunnel")


# ============================================================
# INTERNAL REFERENCES
# ============================================================

var generated_mesh_instance: MeshInstance3D
var generated_static_body: StaticBody3D


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	_find_generated_nodes()


# ============================================================
# REGENERATE
# ============================================================

func regenerate_tunnel() -> void:

	print("MineTunnelGenerator: Regenerate button pressed")

	if tunnel_path == null:
		push_warning("Assign TunnelPath first.")
		return

	if tunnel_path.curve == null:
		push_warning("TunnelPath has no Curve3D.")
		return

	if tunnel_path.curve.get_point_count() < 2:
		push_warning("Add at least 2 points to TunnelPath.")
		return

	var curve: Curve3D = tunnel_path.curve
	var curve_length: float = curve.get_baked_length()

	if curve_length <= 0.01:
		push_warning("Tunnel path is too small.")
		return

	# Remove old tunnel FIRST.
	clear_generated_tunnel()

	# Generate mesh.
	var tunnel_mesh: ArrayMesh = _create_tunnel_mesh(
		curve,
		curve_length
	)

	if tunnel_mesh == null:
		push_warning("Failed to generate tunnel mesh.")
		return

	# Create mesh node.
	generated_mesh_instance = MeshInstance3D.new()
	generated_mesh_instance.name = "GeneratedTunnelMesh"
	generated_mesh_instance.mesh = tunnel_mesh

	if tunnel_material != null:
		generated_mesh_instance.material_override = tunnel_material

	add_child(generated_mesh_instance)

	# Make visible in editor scene tree.
	if Engine.is_editor_hint():
		var edited_root := get_tree().edited_scene_root

		if edited_root != null:
			generated_mesh_instance.owner = edited_root

	# Collision.
	if generate_collision:
		_create_collision(tunnel_mesh)

	print("MineTunnelGenerator: Tunnel generated successfully")


# ============================================================
# CREATE TUNNEL MESH
# ============================================================

func _create_tunnel_mesh(
	curve: Curve3D,
	curve_length: float
) -> ArrayMesh:

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
			float(ring_index)
			/ float(ring_count - 1)
		) * curve_length

		# Position on curve in Path3D local space.
		var path_position: Vector3 = curve.sample_baked(
			distance,
			true
		)

		# Convert Path3D local -> world -> generator local.
		var world_position: Vector3 = tunnel_path.to_global(
			path_position
		)

		var center: Vector3 = to_local(
			world_position
		)

		# Path direction.
		var tangent: Vector3 = _get_path_tangent(
			curve,
			distance,
			curve_length
		)

		# Convert direction from Path3D space.
		tangent = (
			tunnel_path.global_transform.basis
			* tangent
		).normalized()

		# Convert world direction to generator local space.
		tangent = (
			global_transform.basis.inverse()
			* tangent
		).normalized()

		var up: Vector3 = Vector3.UP

		var right: Vector3 = tangent.cross(up)

		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()

		up = right.cross(tangent).normalized()

		var half_width: float = tunnel_width * 0.5

		var u: float = distance / 4.0

		# ----------------------------------------------------
		# RIGHT FLOOR
		# ----------------------------------------------------

		_add_vertex(
			vertices,
			normals,
			uvs,
			center + right * half_width,
			right,
			u,
			0.0
		)

		# ----------------------------------------------------
		# RIGHT WALL TOP
		# ----------------------------------------------------

		_add_vertex(
			vertices,
			normals,
			uvs,
			center
			+ right * half_width
			+ up * wall_height,
			right,
			u,
			0.15
		)

		# ----------------------------------------------------
		# CURVED ROOF
		# ----------------------------------------------------

		for arch_index in range(1, arch_segments + 1):

			var t: float = (
				float(arch_index)
				/ float(arch_segments)
			)

			var angle: float = PI * t

			var horizontal: float = (
				cos(angle)
				* half_width
			)

			var vertical: float = (
				sin(angle)
				* roof_height
			)

			var vertex_position: Vector3 = (
				center
				+ right * horizontal
				+ up * (wall_height + vertical)
			)

			var roof_normal: Vector3 = (
				right * horizontal
				+ up * vertical
			)

			if roof_normal.length_squared() < 0.0001:
				roof_normal = -up
			else:
				roof_normal = -roof_normal.normalized()

			_add_vertex(
				vertices,
				normals,
				uvs,
				vertex_position,
				roof_normal,
				u,
				0.15 + t * 0.70
			)

		# ----------------------------------------------------
		# LEFT FLOOR
		# ----------------------------------------------------

		_add_vertex(
			vertices,
			normals,
			uvs,
			center - right * half_width,
			-right,
			u,
			1.0
		)

	# ========================================================
	# CONNECT RINGS
	# ========================================================

	for ring_index in range(ring_count - 1):

		var current_start: int = (
			ring_index * section_count
		)

		var next_start: int = (
			(ring_index + 1)
			* section_count
		)

		for point_index in range(section_count - 1):

			var a: int = (
				current_start
				+ point_index
			)

			var b: int = (
				current_start
				+ point_index
				+ 1
			)

			var c: int = (
				next_start
				+ point_index
			)

			var d: int = (
				next_start
				+ point_index
				+ 1
			)

			# Inside-facing triangles.
			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

	# ========================================================
	# BUILD MESH
	# ========================================================

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


# ============================================================
# PATH TANGENT
# ============================================================

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


# ============================================================
# VERTEX HELPER
# ============================================================

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

	uvs.append(
		Vector2(u, v)
	)


# ============================================================
# SAFE NORMAL HELPER
# ============================================================

func _left_safe_normal(
	right: Vector3
) -> Vector3:

	if right.length_squared() < 0.0001:
		return Vector3.LEFT

	return right.normalized()


# ============================================================
# COLLISION
# ============================================================

func _create_collision(
	mesh: ArrayMesh
) -> void:

	generated_static_body = StaticBody3D.new()
	generated_static_body.name = "GeneratedTunnelCollision"

	generated_static_body.collision_layer = collision_layer
	generated_static_body.collision_mask = collision_mask

	add_child(generated_static_body)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = mesh.create_trimesh_shape()

	generated_static_body.add_child(
		collision_shape
	)

	if Engine.is_editor_hint():

		var edited_root := get_tree().edited_scene_root

		if edited_root != null:
			generated_static_body.owner = edited_root
			collision_shape.owner = edited_root


# ============================================================
# CLEAR GENERATED TUNNEL
# ============================================================

func clear_generated_tunnel() -> void:

	print("MineTunnelGenerator: Clear button pressed")

	var nodes_to_remove: Array[Node] = []

	# Find generated nodes even if references were lost.
	for child in get_children():

		if child.name == "GeneratedTunnelMesh":
			nodes_to_remove.append(child)

		elif child.name == "GeneratedTunnelCollision":
			nodes_to_remove.append(child)

	for node in nodes_to_remove:

		remove_child(node)

		# Important for @tool/editor usage.
		node.queue_free()

	generated_mesh_instance = null
	generated_static_body = null

	print("MineTunnelGenerator: Generated tunnel cleared")


# ============================================================
# FIND EXISTING GENERATED NODES
# ============================================================

func _find_generated_nodes() -> void:

	for child in get_children():

		if child.name == "GeneratedTunnelMesh":
			generated_mesh_instance = (
				child as MeshInstance3D
			)

		elif child.name == "GeneratedTunnelCollision":
			generated_static_body = (
				child as StaticBody3D
			)
