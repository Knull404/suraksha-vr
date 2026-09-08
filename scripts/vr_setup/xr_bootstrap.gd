extends Node3D
class_name PicoXRBootstrap

var xr_interface: XRInterface

func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR")

	if xr_interface == null:
		push_warning("OpenXR interface is not available. The project can still open in the editor.")
		return

	if not xr_interface.is_initialized():
		push_warning("OpenXR is not initialized. Start the project on a Pico/OpenXR runtime.")
		return

	get_viewport().use_xr = true
	print("OpenXR initialized: ", xr_interface.get_name())
