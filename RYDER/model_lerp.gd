extends Node3D

@export var target : Node3D

var y_velocity : float
var min_hover_height : float = 0.25
var max_hover_height : float = 0.25

func _physics_process(delta: float) -> void:
	handle_visual(delta)
	
func handle_visual(delta):
	var original_scale = scale
	var target_transform = target.global_transform

	var forward = -target_transform.basis.z
	forward.y = 0  
	forward = forward.normalized()

	var upright_basis = Basis()
	upright_basis.z = -forward
	upright_basis.x = forward.cross(Vector3.UP).normalized()
	upright_basis.y = Vector3.UP

	var uprightness = 0.8 
	var blended_basis = target_transform.basis.slerp(upright_basis, uprightness)
	global_transform.basis = global_transform.basis.slerp(blended_basis, 0.15)
	
	var target_pos = target.global_position
	var current_pos = global_position
	
	var spring_strength = 700.0
	var damping = 0.3
	
	var y_difference = target_pos.y - current_pos.y
	var spring_force = y_difference * spring_strength
	
	var local_y_offset = current_pos.y - target_pos.y
	

	var min_boundary_threshold = -min_hover_height
	
	if local_y_offset < min_boundary_threshold:
		var penetration = min_boundary_threshold - local_y_offset
		var resistance_strength = 25.0 
		var boundary_force = penetration * penetration * resistance_strength
		spring_force += boundary_force
		
		damping = lerp(damping, 0.95, clamp(penetration * 2, 0, 1))
	

	var max_boundary_threshold = max_hover_height 
	
	if local_y_offset > max_boundary_threshold:
		var penetration = local_y_offset - max_boundary_threshold
		var resistance_strength = 25.0
		var boundary_force = penetration * penetration * resistance_strength
		spring_force -= boundary_force 
		
		damping = lerp(damping, 0.95, clamp(penetration * 2, 0, 1))
	
	y_velocity += spring_force * delta
	y_velocity *= damping
	
	var new_y = current_pos.y + y_velocity * delta
	
	global_position = Vector3(
		target_pos.x,
		new_y,
		target_pos.z
	)
	original_scale = scale
