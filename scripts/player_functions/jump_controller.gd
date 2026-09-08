extends Node
class_name JumpController

## Jump controller for XR.
## This node handles a jump action for a PicoXRPlayer (or any CharacterBody3D).
## It is deliberately separate from other locomotion scripts so you can enable/disable it
## independently, just like your teleport or turning nodes.
##
## Exported properties:
## - `player`: reference to the player character that will be made to jump.
## - `jump_action`: the InputMap action name that triggers a jump. Configure this in
##   Project Settings > Input Map and bind it to the desired controller button (e.g. "xr_button_a").
## - `jump_velocity`: the upward velocity applied when jumping.
## - `allow_air_control`: if true, the player can apply the jump velocity while already airborne (useful for double‑jump).

@export var player: CharacterBody3D
@export var jump_action: String = "jump"
@export var jump_velocity: float = 5.0
@export var allow_air_control: bool = false

func _physics_process(_delta: float) -> void:
	if not player:
		return
	# Only trigger jump when the action is just pressed.
	if Input.is_action_just_pressed(jump_action):
		var can_jump: bool = player.is_on_floor() or allow_air_control
		if can_jump:
			# Directly set the vertical component of the player's velocity.
			player.velocity.y = jump_velocity
			print("JumpController: player jumped with velocity %.2f" % jump_velocity)
