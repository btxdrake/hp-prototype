extends Node3D
class_name VisualMotionReact

@export var controller : NeoBroomController
@export var bank_from_input := true
@export var bank_from_velocity := true
@export var max_bank_angle := 60.0  # Degrees
@export var bank_speed := 2.5  # How fast to bank
@export var yaw_speed : float = 2.5
@export var max_yaw_angle : float = 50.0

var input : Vector2

var current_bank := 0.0
var current_yaw : float = 0.0

func _process(delta: float) -> void:
	if !controller:
		return
	var speed : float = controller.velocity.length()
		
	var input = InputLayer.get_left_stick(InputLayer.InputContext.VEHICLE)
	
	var target_bank := 0.0
	
	var target_yaw = -input.x * (speed / controller.max_speed) * max_yaw_angle
	
	# Method 1: Bank based on input (immediate, responsive)
	if bank_from_input:
		target_bank += -input.x * max_bank_angle
	
	# Method 2: Bank based on actual lateral velocity (physics-based)
	if bank_from_velocity:
		var lateral_velocity = controller.velocity.dot(controller.global_basis.x)
		# Normalize to max speed to get -1 to 1 range
		var velocity_factor = clamp(lateral_velocity / controller.max_speed, -1.0, 1.0)
		target_bank += velocity_factor * max_bank_angle
	if bank_from_input && bank_from_velocity:
		target_bank = target_bank / 2
	
	if !controller.drift:
		target_bank *= 0.5
		target_yaw *= 0.5

	
	# Smooth the banking
	current_bank = lerp(current_bank, target_bank, bank_speed * delta)
	current_yaw = lerp(current_yaw, target_yaw, yaw_speed * delta)
	
	# Apply as Z rotation (roll)
	rotation.y = deg_to_rad(current_yaw)
	rotation.z = deg_to_rad(current_bank)
