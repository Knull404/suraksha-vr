@tool
extends Node3D
class_name PicoInteractable

## Pico Interactable
##
## Attach this as a CHILD of any object (RigidBody3D, StaticBody3D,
## etc.) to make it detectable and highlightable.
##
## This node OWNS its own detection Area3D as a child — add an
## Area3D (with a CollisionShape3D sized for your detection range)
## as a child of THIS node, named "DetectionArea".

enum HighlightMode { VISIBILITY, MATERIAL }

@export_category("Highlight Mode")
@export var highlight_mode: HighlightMode = HighlightMode.MATERIAL

@export_category("Visibility Settings")
## Node to show/hide when highlighted (e.g. a ring/outline mesh)
@export var highlight_node: Node3D

@export_category("Material Settings")
@export var highlight_mesh_instance: MeshInstance3D
@export var highlight_material: Material

# Signal emitted when the highlight state changes
signal highlight_updated(pickable, enable)

# The object this component is attached to
var _target: Node3D

# This node's own detection area (child node)
@onready var _detection_area: Area3D = get_node_or_null("DetectionArea")

# Dictionary of nodes currently requesting highlight
var _highlight_requests: Dictionary = {}

# Is this object currently highlighted
var _highlighted: bool = false

# Cached original materials (for MATERIAL mode restore)
var _original_materials: Array[Material] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_target = get_parent()

	# Cache original materials so we can restore them later
	if highlight_mode == HighlightMode.MATERIAL and highlight_mesh_instance:
		for i in range(highlight_mesh_instance.get_surface_override_material_count()):
			_original_materials.push_back(highlight_mesh_instance.get_surface_override_material(i))

	# Start hidden/off
	if highlight_node:
		highlight_node.visible = false

	# Hook our own detection area
	if _detection_area:
		_detection_area.area_entered.connect(_on_area_entered)
		_detection_area.area_exited.connect(_on_area_exited)
	else:
		push_warning("PicoInteractable on '%s': no DetectionArea child found" % get_parent().name)

	# Hook our own highlight signal to the visual update — THIS WAS MISSING
	highlight_updated.connect(_on_highlight_updated)


func _on_area_entered(area: Area3D) -> void:
	request_highlight(area, true)


func _on_area_exited(area: Area3D) -> void:
	request_highlight(area, false)


## Request highlighting of this object.
## If [param from] is null, all highlight requests are cleared.
## Otherwise the request is tracked per-requester, so multiple
## controllers/detectors can request highlight independently.
func request_highlight(from: Node, on: bool = true) -> void:
	var old_highlighted: bool = _highlighted

	if not from:
		_highlight_requests.clear()
	elif on:
		_highlight_requests[from] = from
	else:
		_highlight_requests.erase(from)

	_highlighted = _highlight_requests.size() > 0

	if _highlighted != old_highlighted:
		highlight_updated.emit(_target, _highlighted)


func _on_highlight_updated(_pickable, enable: bool) -> void:
	match highlight_mode:
		HighlightMode.VISIBILITY:
			_apply_visibility(enable)
		HighlightMode.MATERIAL:
			_apply_material(enable)


func _apply_visibility(enable: bool) -> void:
	if highlight_node:
		highlight_node.visible = enable


func _apply_material(enable: bool) -> void:
	if not highlight_mesh_instance:
		return

	for i in range(highlight_mesh_instance.get_surface_override_material_count()):
		if enable:
			highlight_mesh_instance.set_surface_override_material(i, highlight_material)
		else:
			highlight_mesh_instance.set_surface_override_material(i, _original_materials[i])


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	if not get_node_or_null("DetectionArea"):
		warnings.append("Missing child node 'DetectionArea' (Area3D) — object will never highlight")

	if highlight_mode == HighlightMode.VISIBILITY and not highlight_node:
		warnings.append("Visibility mode requires a Highlight Node")

	if highlight_mode == HighlightMode.MATERIAL and not highlight_mesh_instance:
		warnings.append("Material mode requires a Highlight Mesh Instance")

	return warnings
