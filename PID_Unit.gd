extends Node3D

class_name PID_Unit

var pid_controller : PID_Controller = PID_Controller.new()
var raycast : RayCast3D
@export var target_hover_height := 1.5

func _ready() -> void:
	raycast = get_child(0) as RayCast3D

func get_hover_force(current_velocity: Vector3) -> Vector3:
	if !raycast.is_colliding():
		return Vector3.ZERO
	
	var hit_point = raycast.get_collision_point()
	var distance = global_position.distance_to(hit_point)
	var normal = raycast.get_collision_normal()
	
	# PID calculates how much force we need (as a percentage/multiplier)
	var force_percent = pid_controller.calculate(target_hover_height, distance)
	
	# Return force along the surface normal
	return normal * force_percent

func is_grounded() -> bool:
	return raycast.is_colliding()

func get_distance_squared_to_hit_point()->float:
	if !raycast.is_colliding():
		return INF
	else:
		return raycast.global_position.distance_squared_to(raycast.get_collision_point())

func get_ground_normal() -> Vector3:
	if raycast.is_colliding():
		return raycast.get_collision_normal()
	return Vector3.UP

func reset():
	pid_controller.reset()
	# Optionally sample initial height like in the old code
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var initial_height = raycast.get_collision_point().distance_to(global_position)
		target_hover_height = initial_height
