
extends Node
class_name PicoGrabber

# Stored on a held body so both controller grabbers cannot grab it at once.
const GRABBED_BY_META := &"pico_grabbed_by"

signal object_grabbed(body: RigidBody3D)
signal object_released(body: RigidBody3D, linear_velocity: Vector3)

@export_category("XR")
@export var controller: XRController3D
@export var grab_area: Area3D


@export_category("OpenXR")
@export var grab_action: StringName = &"grip"
@export_range(0.1, 1.0, 0.05) var grab_threshold := 0.7
@export_range(0.0, 0.7, 0.05) var release_threshold := 0.5


@export_category("Pickup")
@export var interactable_group: StringName = &"interactable"


@export_category("Collision")
@export_flags_3d_physics var player_collision_layer: int = 2
@export_flags_3d_physics var environment_collision_mask: int = 1
@export_flags_3d_physics var grabbable_collision_mask: int = 16
@export var held_objects_block_each_other := true

@export_category("Physical Follow")
@export var physics_follow := true
@export_range(0.01, 0.3, 0.01) var position_response_time := 0.025
@export_range(1.0, 30.0, 0.5) var max_follow_speed := 24.0
@export_range(10.0, 20000.0, 10.0) var max_follow_force := 8000.0
@export_range(0.0, 0.10, 0.005) var controller_prediction_time := 0.02
@export var follow_hand_rotation := false
@export var lock_rotation_while_held := true
@export_range(0.01, 0.5, 0.01) var rotation_response_time := 0.05
@export_range(1.0, 30.0, 0.5) var max_rotation_speed := 12.0
@export_range(0.05, 1.0, 0.01) var stuck_distance := 0.20
@export_range(0.05, 2.0, 0.05) var stuck_warning_delay := 0.35
@export_range(0.01, 1.0, 0.01) var stuck_speed_threshold := 0.08


@export_category("Throwing")
@export_range(0.0, 3.0, 0.05) var throw_multiplier := 1.2
@export_range(0.0, 50.0, 0.5) var max_throw_speed := 20.0
@export_range(1, 20, 1) var velocity_samples := 5

@export_category("Haptics")
@export var haptics_enabled := true
@export var haptic_action: StringName = &"haptic"
@export_range(0.0, 1.0, 0.05) var grab_haptic_strength := 0.25
@export_range(0.0, 1.0, 0.05) var release_haptic_strength := 0.15
@export_range(0.0, 1.0, 0.05) var blocked_haptic_strength := 0.4
@export_range(0.05, 1.0, 0.05) var blocked_haptic_interval := 0.15


var _nearby_objects: Array[RigidBody3D] = []
var _grabbed_object: RigidBody3D = null
var _driver: RemoteTransform3D = null

var _grab_transform := Transform3D.IDENTITY

var _grip_pressed := false

var _previous_position := Vector3.ZERO
var _velocity_history: Array[Vector3] = []
var _controller_velocity := Vector3.ZERO

var _original_collision_layer := 0
var _original_collision_mask := 0

var _original_freeze := false
var _original_freeze_mode := RigidBody3D.FREEZE_MODE_STATIC
var _original_gravity_scale := 1.0
var _original_contact_monitor := false
var _original_max_contacts_reported := 0
var _original_axis_lock_angular_x := false
var _original_axis_lock_angular_y := false
var _original_axis_lock_angular_z := false
var _blocked_haptic_time := 0.0
var _stuck_time := 0.0
var _stuck_warning: Label3D


func _ready() -> void:
	if controller == null:
		push_error("PicoGrabber: Controller is not assigned.")
		return

	if grab_area == null:
		push_error("PicoGrabber: GrabArea is not assigned.")
		return

	_previous_position = controller.global_position

	if not grab_area.body_entered.is_connected(_on_body_entered):
		grab_area.body_entered.connect(_on_body_entered)

	if not grab_area.body_exited.is_connected(_on_body_exited):
		grab_area.body_exited.connect(_on_body_exited)

	# Areas may already overlap bodies when this node enters the scene tree.
	call_deferred("_update_nearby_objects")
	# This is attached to the XR camera, so the warning remains readable in-headset.
	call_deferred("_create_stuck_warning")


func _physics_process(delta: float) -> void:
	if controller == null:
		return
	if not controller.get_is_active():
		return

	_update_velocity(delta)

	var grip_value := controller.get_float(grab_action)

	if _grabbed_object != null and not is_instance_valid(_grabbed_object):
		_clear_grab_state()

	if _grabbed_object != null:
		_move_grabbed_object(delta)

		if grip_value <= release_threshold:
			_release_object()
	else:
		if not _grip_pressed and grip_value >= grab_threshold:
			_grip_pressed = true

			var target := _get_closest_object()

			if target != null:
				_grab_object(target)

		elif grip_value <= release_threshold:
			_grip_pressed = false


func _update_velocity(delta: float) -> void:
	if delta <= 0.0:
		return

	var current_position := controller.global_position

	var velocity := (
		current_position - _previous_position
	) / delta
	_controller_velocity = velocity

	_previous_position = current_position

	_velocity_history.append(velocity)

	if _velocity_history.size() > velocity_samples:
		_velocity_history.pop_front()


func _get_closest_object() -> RigidBody3D:
	var closest: RigidBody3D = null
	var closest_distance := INF

	for body in _nearby_objects:
		if not is_instance_valid(body):
			continue

		if body == _grabbed_object or body.freeze:
			continue

		if body.has_meta(GRABBED_BY_META):
			var current_owner := _get_grab_owner(body)
			if current_owner == null or current_owner == self or not current_owner._can_transfer(body):
				continue

		var distance := (
			grab_area.global_position.distance_squared_to(
				body.global_position
			)
		)

		if distance < closest_distance:
			closest_distance = distance
			closest = body

	return closest


func _get_grab_owner(body: RigidBody3D) -> PicoGrabber:
	if not body.has_meta(GRABBED_BY_META):
		return null
	return instance_from_id(body.get_meta(GRABBED_BY_META)) as PicoGrabber


func _can_transfer(body: RigidBody3D) -> bool:
	return is_instance_valid(_grabbed_object) and _grabbed_object == body


func _grab_object(body: RigidBody3D) -> void:
	if body == null:
		return

	if _grabbed_object != null:
		return

	if not is_instance_valid(body):
		return

	if body.freeze:
		return

	if not body.is_in_group(interactable_group):
		return

	# Hand-to-hand transfer: the second hand takes ownership without dropping
	# the body, so the physics object remains solid throughout the handoff.
	var previous_owner := _get_grab_owner(body)
	if previous_owner != null:
		if previous_owner == self or not previous_owner._can_transfer(body):
			return
		previous_owner._release_object(false)
		if previous_owner.controller != null:
			previous_owner._grip_pressed = (
				previous_owner.controller.get_float(previous_owner.grab_action)
				> previous_owner.release_threshold
			)

	_original_collision_layer = body.collision_layer
	_original_collision_mask = body.collision_mask

	_original_freeze = body.freeze
	_original_freeze_mode = body.freeze_mode
	_original_gravity_scale = body.gravity_scale
	_original_contact_monitor = body.contact_monitor
	_original_max_contacts_reported = body.max_contacts_reported
	_original_axis_lock_angular_x = body.axis_lock_angular_x
	_original_axis_lock_angular_y = body.axis_lock_angular_y
	_original_axis_lock_angular_z = body.axis_lock_angular_z

	# Remember exact point and rotation where the hand grabbed it.
	_grab_transform = (
		body.global_transform.affine_inverse()
		* controller.global_transform
	)

	_grabbed_object = body
	body.set_meta(GRABBED_BY_META, get_instance_id())

	# Stop existing motion.
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false

	# Physics follow keeps the RigidBody active so it can push other bodies
	# naturally. The legacy transform driver remains available as a fallback.
	if physics_follow:
		body.freeze = false
		body.gravity_scale = 0.0
		body.contact_monitor = true
		body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
		if lock_rotation_while_held:
			body.axis_lock_angular_x = true
			body.axis_lock_angular_y = true
			body.axis_lock_angular_z = true
	else:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true

	# A held item must never push the player. It collides with other pickups by
	# default; that interaction is now handled by the physics-follow forces.
	body.collision_layer = _original_collision_layer
	body.collision_mask = (
		_original_collision_mask
		& ~player_collision_layer
	)
	if not held_objects_block_each_other:
		body.collision_mask &= ~grabbable_collision_mask

	if not physics_follow:
		# Legacy transform driver.
		_driver = RemoteTransform3D.new()
		_driver.name = "PicoGrabDriver"
		_driver.top_level = true
		_driver.process_physics_priority = -80
		_driver.update_position = true
		_driver.update_rotation = true
		_driver.update_scale = false

		body.get_parent().add_child(_driver)

		_driver.global_transform = body.global_transform
		_driver.remote_path = _driver.get_path_to(body)

	_velocity_history.clear()
	_emit_haptic(grab_haptic_strength)
	object_grabbed.emit(body)


func _move_grabbed_object(delta: float) -> void:
	if _grabbed_object == null:
		return

	if not is_instance_valid(_grabbed_object):
		return

	if physics_follow:
		_move_grabbed_object_physical(delta)
		return

	if _driver == null:
		return

	var current_transform := _grabbed_object.global_transform

	# Desired transform based on the controller.
	var target_transform := (
		controller.global_transform
		* _grab_transform.affine_inverse()
	)

	var motion := (
		target_transform.origin
		- current_transform.origin
	)

	# Nothing to move.
	if motion.length_squared() < 0.000001:
		_driver.global_transform = target_transform
		return

	# Test the body's movement against the physics world.
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()

	params.from = current_transform
	params.motion = motion
	params.margin = 0.001

	var collided := PhysicsServer3D.body_test_motion(
		_grabbed_object.get_rid(),
		params,
		result
	)

	if collided:
		var travel := result.get_travel()

		target_transform.origin = (
			current_transform.origin + travel
		)

		# Keep the object from building up velocity while blocked.
		_grabbed_object.linear_velocity = Vector3.ZERO
		_blocked_haptic_time -= delta
		if _blocked_haptic_time <= 0.0:
			_emit_haptic(blocked_haptic_strength)
			_blocked_haptic_time = blocked_haptic_interval
	else:
		_blocked_haptic_time = 0.0


	# This must run both when motion is blocked and when the hand is in empty
	# space. Without it, objects only move on frames that report a collision.
	_driver.global_transform = target_transform


func _move_grabbed_object_physical(delta: float) -> void:
	var body := _grabbed_object
	var target_transform := controller.global_transform * _grab_transform.affine_inverse()
	target_transform.origin += _controller_velocity * controller_prediction_time
	var displacement := target_transform.origin - body.global_position

	# Drive velocity through forces rather than moving the body transform. This
	# lets Godot transfer momentum to other RigidBody3Ds and stop against walls.
	var desired_velocity := (displacement / position_response_time).limit_length(max_follow_speed)
	var acceleration := (desired_velocity - body.linear_velocity) / position_response_time
	var force := (acceleration * body.mass).limit_length(max_follow_force)
	body.apply_central_force(force)

	# Angular limits of zero: the object cannot accumulate rotation from impacts.
	# Keep this on for solid blocks; turn it off only for items meant to spin.
	if lock_rotation_while_held:
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.axis_lock_angular_z = true
		body.angular_velocity = Vector3.ZERO
	elif follow_hand_rotation:
		body.axis_lock_angular_x = false
		body.axis_lock_angular_y = false
		body.axis_lock_angular_z = false

		# Compute the shortest rotation from the object's current orientation
		# to the target (controller) orientation.
		var current_q := body.global_transform.basis.get_rotation_quaternion()
		var target_q  := target_transform.basis.get_rotation_quaternion()
		var rot_err   := (target_q * current_q.inverse()).normalized()

		# Wrap the angle to [-π, π] so we always take the short path.
		var angle := rot_err.get_angle()
		if angle > PI:
			angle -= TAU

		var axis := rot_err.get_axis()
		if axis.length_squared() > 0.0001:
			var desired_av := axis * (angle / rotation_response_time)
			body.angular_velocity = desired_av.limit_length(max_rotation_speed)
		else:
			body.angular_velocity = Vector3.ZERO

	_update_stuck_feedback(body, displacement, delta)


func _update_stuck_feedback(body: RigidBody3D, displacement: Vector3, delta: float) -> void:
	var trying_to_move := displacement.length() >= stuck_distance
	var moving_toward_target := false
	if trying_to_move:
		moving_toward_target = (
			body.linear_velocity.dot(displacement.normalized())
			> stuck_speed_threshold
		)
	var is_stuck := trying_to_move and not moving_toward_target and body.get_contact_count() > 0

	if not is_stuck:
		_stuck_time = 0.0
		_blocked_haptic_time = 0.0
		_set_stuck_warning_visible(false)
		return

	_stuck_time += delta
	# Brief touches and light brushing are normal. Only warn after the object
	# has been held back by a solid contact for a noticeable moment.
	if _stuck_time < stuck_warning_delay:
		return

	_set_stuck_warning_visible(true)
	_blocked_haptic_time -= delta
	if _blocked_haptic_time <= 0.0:
		_emit_haptic(blocked_haptic_strength)
		_blocked_haptic_time = blocked_haptic_interval


func _create_stuck_warning() -> void:
	if is_instance_valid(_stuck_warning):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	_stuck_warning = Label3D.new()
	_stuck_warning.name = "PicoGrabBlockedWarning"
	_stuck_warning.text = "OBJECT BLOCKED"
	_stuck_warning.position = Vector3(0.0, -0.15, -0.75)
	_stuck_warning.font_size = 56
	_stuck_warning.outline_size = 8
	_stuck_warning.modulate = Color(1.0, 0.22, 0.08, 1.0)
	_stuck_warning.pixel_size = 0.001
	_stuck_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stuck_warning.no_depth_test = true
	_stuck_warning.visible = false
	camera.add_child(_stuck_warning)


func _set_stuck_warning_visible(should_show: bool) -> void:
	if should_show and not is_instance_valid(_stuck_warning):
		_create_stuck_warning()
	if is_instance_valid(_stuck_warning):
		_stuck_warning.visible = should_show


func _release_object(should_throw := true) -> void:
	var body := _grabbed_object

	if body == null:
		return

	if not is_instance_valid(body):
		_grabbed_object = null
		return

	var throw_velocity := _get_throw_velocity()

	if throw_velocity.length() > max_throw_speed:
		throw_velocity = (
			throw_velocity.normalized()
			* max_throw_speed
		)

	# Disconnect RemoteTransform3D first.
	if _driver != null:
		_driver.remote_path = NodePath()
		_driver.queue_free()
		_driver = null

	# Restore original collision.
	body.collision_layer = _original_collision_layer
	body.collision_mask = _original_collision_mask

	# Restore physics state.
	body.freeze_mode = _original_freeze_mode
	body.freeze = _original_freeze
	body.gravity_scale = _original_gravity_scale
	body.contact_monitor = _original_contact_monitor
	body.max_contacts_reported = _original_max_contacts_reported
	body.axis_lock_angular_x = _original_axis_lock_angular_x
	body.axis_lock_angular_y = _original_axis_lock_angular_y
	body.axis_lock_angular_z = _original_axis_lock_angular_z
	body.sleeping = false

	if body.has_meta(GRABBED_BY_META):
		body.remove_meta(GRABBED_BY_META)

	# A hand transfer restores the body's settings but does not throw it.
	if should_throw and not body.freeze:
		body.linear_velocity = throw_velocity
		body.angular_velocity = Vector3.ZERO

	if should_throw:
		object_released.emit(body, throw_velocity)
		_emit_haptic(release_haptic_strength)

	_grabbed_object = null
	_grip_pressed = false
	_velocity_history.clear()
	_blocked_haptic_time = 0.0
	_stuck_time = 0.0
	_set_stuck_warning_visible(false)

	_update_nearby_objects()


func _get_throw_velocity() -> Vector3:
	if _velocity_history.is_empty():
		return Vector3.ZERO

	var velocity := Vector3.ZERO

	for sample in _velocity_history:
		velocity += sample

	velocity /= _velocity_history.size()

	return velocity * throw_multiplier


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	var rigid_body := body as RigidBody3D

	if not rigid_body.is_in_group(interactable_group):
		return

	if not _nearby_objects.has(rigid_body):
		_nearby_objects.append(rigid_body)


func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_nearby_objects.erase(body)


func _update_nearby_objects() -> void:
	_nearby_objects.clear()

	if grab_area == null:
		return

	for body in grab_area.get_overlapping_bodies():
		if body is RigidBody3D:
			var rigid_body := body as RigidBody3D

			if rigid_body.is_in_group(interactable_group):
				_nearby_objects.append(rigid_body)


func _emit_haptic(strength: float) -> void:
	if not haptics_enabled or strength <= 0.0 or XRServer.primary_interface == null:
		return
	XRServer.primary_interface.trigger_haptic_pulse(
		haptic_action,
		controller.tracker,
		0.0,
		strength,
		0.04,
		0.0
	)


func _clear_grab_state() -> void:
	if is_instance_valid(_driver):
		_driver.remote_path = NodePath()
		_driver.queue_free()
	_driver = null
	_grabbed_object = null
	_grip_pressed = false
	_velocity_history.clear()
	_stuck_time = 0.0
	_set_stuck_warning_visible(false)


func _exit_tree() -> void:
	if _driver != null:
		_driver.remote_path = NodePath()
		_driver.queue_free()
		_driver = null

	if _grabbed_object != null:
		if is_instance_valid(_grabbed_object):
			_grabbed_object.collision_layer = _original_collision_layer
			_grabbed_object.collision_mask = _original_collision_mask
			_grabbed_object.freeze_mode = _original_freeze_mode
			_grabbed_object.freeze = _original_freeze
			_grabbed_object.gravity_scale = _original_gravity_scale
			_grabbed_object.contact_monitor = _original_contact_monitor
			_grabbed_object.max_contacts_reported = _original_max_contacts_reported
			_grabbed_object.axis_lock_angular_x = _original_axis_lock_angular_x
			_grabbed_object.axis_lock_angular_y = _original_axis_lock_angular_y
			_grabbed_object.axis_lock_angular_z = _original_axis_lock_angular_z
			if _grabbed_object.has_meta(GRABBED_BY_META):
				_grabbed_object.remove_meta(GRABBED_BY_META)
