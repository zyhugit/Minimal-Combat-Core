# res://scripts/camera_controller.gd
# Attach this to your Camera3D node in main.tscn
extends Camera3D

var trauma: float = 0.0
var trauma_decay: float = 3.0  # How fast shake fades
var max_shake_offset: float = 0.3
var max_shake_rotation: float = 5.0  # degrees

var original_position: Vector3
var original_rotation: Vector3

func _ready():
	original_position = position
	original_rotation = rotation_degrees

func _process(delta: float):
	# Decay trauma over time
	if trauma > 0:
		trauma = max(trauma - trauma_decay * delta, 0.0)
		apply_shake()
	else:
		# Reset to original position when no shake
		position = original_position
		rotation_degrees = original_rotation

func apply_shake():
	# Shake amount is based on trauma squared (feels better)
	var shake_amount = trauma * trauma
	
	# Random offset
	var offset_x = randf_range(-max_shake_offset, max_shake_offset) * shake_amount
	var offset_y = randf_range(-max_shake_offset, max_shake_offset) * shake_amount
	var offset_z = randf_range(-max_shake_offset, max_shake_offset) * shake_amount
	
	# Random rotation
	var rot_x = randf_range(-max_shake_rotation, max_shake_rotation) * shake_amount
	var rot_y = randf_range(-max_shake_rotation, max_shake_rotation) * shake_amount
	var rot_z = randf_range(-max_shake_rotation, max_shake_rotation) * shake_amount
	
	position = original_position + Vector3(offset_x, offset_y, offset_z)
	rotation_degrees = original_rotation + Vector3(rot_x, rot_y, rot_z)

func add_trauma(amount: float):
	# Add trauma, clamped to 0-1
	trauma = min(trauma + amount, 1.0)

# Convenience functions
func shake_light():
	add_trauma(0.3)

func shake_medium():
	add_trauma(0.5)

func shake_heavy():
	add_trauma(0.8)
