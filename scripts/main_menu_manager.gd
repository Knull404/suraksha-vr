extends Node3D
class_name MainMenuManager

## Manager for the dedicated Main Menu Scene.
## Initializes OpenXR for Pico XR and switches to gameplay scene when New Game is clicked.

@export_category("Scene Switch")
@export_file("*.tscn") var gameplay_scene_path: String = "res://scenes/main.tscn"

@export_category("XR Setup")
@export var player: CharacterBody3D
@export var vr_menu_canvas: VRMenuCanvas

func _ready() -> void:
	# 1. Initialize OpenXR
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface != null and xr_interface.is_initialized():
		get_viewport().use_xr = true
		print("MainMenuManager: OpenXR active.")
	else:
		push_warning("MainMenuManager: OpenXR not initialized, running in preview mode.")

	# 2. Connect Menu New Game signal to switch to gameplay scene
	if vr_menu_canvas != null:
		vr_menu_canvas.game_started.connect(_on_new_game_selected)

func _on_new_game_selected() -> void:
	print("MainMenuManager: New Game selected, loading ", gameplay_scene_path)
	if ResourceLoader.exists(gameplay_scene_path):
		get_tree().change_scene_to_file(gameplay_scene_path)
	else:
		push_error("MainMenuManager: Gameplay scene path not found: " + gameplay_scene_path)
