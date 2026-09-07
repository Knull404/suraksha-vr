extends CharacterBody3D
class_name PicoXRPlayer

@export var gravity: float = 9.81
@export var max_fall_speed: float = 20.0

@export_category("Height Mode")
## If true, the player's body/capsule dynamically matches the user's real
## tracked height (sitting vs standing feels different, like real life).
## If false, both sitting and standing players get the exact same fixed POV —
## the offset is locked at recenter time and never drifts again.
@export var use_dynamic_height: bool = false

@export_category("Dynamic Height Settings")
@export var min_height: float = 0.3       # crouching/seated floor
@export var max_height: float = 2.0       # tall standing headroom
@export var height_smoothing: float = 12.0  # higher = snappier, lower = smoother

@export_category("Fixed Height Settings")
## The in-game eye height every player sees, regardless of whether they are
## sitting or standing. Locked in the moment recenter_fixed_pov() is called.
@export var fixed_height: float = 1.7

@export_category("Body")
@export var capsule_radius: float = 0.3

@onready var xr_origin: XROrigin3D       = $XROrigin3D
@onready var camera: XRCamera3D          = $XROrigin3D/XRCamera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _capsule: CapsuleShape3D
var _current_height: float = 1.7

# Fixed-mode: set once when the player recenters, never touched again.
var _fixed_origin_y: float = 0.0
var _fixed_pov_locked: bool = false


func _ready() -> void:
	_capsule = collision_shape.shape as CapsuleShape3D
	if not _capsule:
		push_error("PicoXRPlayer: CollisionShape3D must use a CapsuleShape3D")

	if use_dynamic_height:
		_current_height = fixed_height
	else:
		# Set capsule to fixed size immediately so collision is correct from the start.
		_apply_fixed_capsule()
		# Auto-recenter if XR is already running (editor / PC preview path).
		var xr_interface := XRServer.find_interface("OpenXR")
		if xr_interface and xr_interface.is_initialized():
			recenter_fixed_pov()


func _physics_process(delta: float) -> void:
	if use_dynamic_height:
		_update_dynamic_height(delta)
	else:
		_update_fixed_pov()

	# Apply gravity
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -max_fall_speed)
	else:
		if velocity.y < 0.0:
			velocity.y = -0.05

	move_and_slide()


## Call this from GameStage (or anywhere) after XRServer.center_on_hmd().
## Captures the player's real camera height at THIS exact moment and locks
## the XROrigin3D offset so the in-game POV always sits at fixed_height —
## whether the player is sitting or standing.
func recenter_fixed_pov() -> void:
	if use_dynamic_height:
		return
	# Snapshot the real camera Y right now (after the XR recenter has settled).
	# Offset = how much we need to raise/lower XROrigin so camera lands at fixed_height.
	_fixed_origin_y = fixed_height - camera.position.y
	xr_origin.position.y = _fixed_origin_y
	_fixed_pov_locked = true
	print("PicoXRPlayer: fixed POV locked at real-height %.2f → in-game %.2f (offset %.3f)" \
		% [camera.position.y, fixed_height, _fixed_origin_y])


## Enable or disable all in-game player feature nodes (locomotion, turning, teleportation, grabbers, jump).
## Called when menu opens/closes so player inputs don't move the player or grab objects during UI navigation.
func set_gameplay_enabled(enabled: bool) -> void:
	set_meta("is_in_menu", not enabled)
	var target_mode := PROCESS_MODE_INHERIT if enabled else PROCESS_MODE_DISABLED
	for child in get_children():
		if child is PicoLocomotion or child is PicoTurning or child is PicoArcTeleportation or child is PicoGrabber or child is JumpController or child.has_method(&"set_process"):
			if not (child is XROrigin3D or child is CollisionShape3D):
				child.process_mode = target_mode
	print("PicoXRPlayer: gameplay features ", "enabled" if enabled else "disabled (in menu)")


# ── private ──────────────────────────────────────────────────────────────────

## DYNAMIC MODE: capsule shrinks/grows with the user's real tracked height.
## XROrigin3D is never touched, so sitting feels shorter and standing taller.
func _update_dynamic_height(delta: float) -> void:
	if not _capsule:
		return
	var target_height: float = clampf(camera.position.y, min_height, max_height)
	_current_height = lerp(_current_height, target_height, delta * height_smoothing)
	_capsule.height = _current_height
	_capsule.radius = capsule_radius
	collision_shape.position.y = _current_height * 0.5


## FIXED MODE: after recenter_fixed_pov() locks the offset, we just re-apply
## the same constant every frame — no lerp, no drift, no motion sickness.
func _update_fixed_pov() -> void:
	if not _capsule:
		return
	_apply_fixed_capsule()
	if _fixed_pov_locked:
		# Constant, frame-perfect application — zero latency.
		xr_origin.position.y = _fixed_origin_y


func _apply_fixed_capsule() -> void:
	if not _capsule:
		return
	_capsule.height = fixed_height
	_capsule.radius = capsule_radius
	collision_shape.position.y = fixed_height * 0.5
