extends CharacterBody3D

class_name BoardController

var speed : float
var muliplier : float = 300
@export var max_speed : float = 20
@export var accel : float = 5
@export var decel : float = 2
@export var turn_speed : float = 1
@export var board_mesh : Node3D
@export var board_target : Node3D

var input : Vector3
var throttle : float
var brake : float
var move_vel : Vector3
var gravity : float
var vertical_vel : float = 0
var floor_normal : Vector3

var yaw_offset : float
var roll_offset : float
var board_y_velocity : float
var min_hover_height : float = 0.5


func _physics_process(delta: float) -> void:
	if throttle > 0:
		if speed < max_speed:
			speed += accel * delta
	else:
		var decel_speed = decel if brake >= 0 else decel * 10 
		if speed > 0:
			speed -= decel_speed * delta
	var forward_vel : Vector3 = -transform.basis.z * speed * delta
	var gravity = (ProjectSettings.get_setting("physics/3d/default_gravity") * 1.5)* delta
	velocity = forward_vel * muliplier
	if !is_on_floor():
		vertical_vel += gravity * 1.5
		velocity.y -= vertical_vel
		floor_normal = Vector3.UP
	else:
		floor_normal = get_floor_normal()
		
		vertical_vel = 0
	#print("speed: ", speed)
	_handle_rotate(delta)
	move_and_slide()
	_handle_board_visual(delta)
	
func _handle_rotate(delta : float):
	rotate(floor_normal, input.x * turn_speed * delta)

	var xform = align_with_y(transform, floor_normal)
	var lerp_weight = 10 if is_on_floor() else 1
	transform = transform.interpolate_with(xform, lerp_weight * delta)

func align_with_y(xform, new_y):
	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform.orthonormalized()
	
func _handle_board_visual(delta):
	var original_scale = board_mesh.scale
	var yaw = input.x * deg_to_rad(25)
	var roll = input.x * deg_to_rad(25)
	yaw_offset = lerp(yaw_offset, yaw, 0.15)
	roll_offset = lerp(roll_offset, roll, 0.15)
	
	var target_transform = board_target.global_transform
	target_transform.basis = target_transform.basis.rotated(Vector3.UP, yaw_offset)
	target_transform.basis = target_transform.basis.rotated(target_transform.basis.z, roll_offset)
	board_mesh.global_transform.basis = board_mesh.global_transform.basis.slerp(target_transform.basis, 0.15)
	
	var target_pos = board_target.global_position
	var current_pos = board_mesh.global_position
	
	var spring_strength = 500.0
	var damping = 0.75
	
	var y_difference = target_pos.y - current_pos.y
	var spring_force = y_difference * spring_strength
	
	# Soft boundary
	var local_y_offset = current_pos.y - target_pos.y  # Negative when below target
	var boundary_threshold = -min_hover_height
	
	if local_y_offset < boundary_threshold:
		var penetration = boundary_threshold - local_y_offset
		var resistance_strength = 25.0 
		var boundary_force = penetration * penetration * resistance_strength
		spring_force += boundary_force
		
		damping = lerp(damping, 0.95, clamp(penetration * 2, 0, 1))
	
	board_y_velocity += spring_force * delta
	board_y_velocity *= damping
	
	var new_y = current_pos.y + board_y_velocity * delta
	
	board_mesh.global_position = Vector3(
		target_pos.x,
		new_y,
		target_pos.z
	)
	board_mesh.scale = original_scale

func _process(delta: float) -> void:
	input.x = Input.get_axis("right","left")
	input.y = Input.get_axis("back", "forward")
	throttle = Input.get_action_strength("throttle")
	brake = Input.get_action_strength("brake")
	#print("input x: ", input.x, " input y: ", input.y, " throttle: ", throttle, " brake: ", brake)
	
