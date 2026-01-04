extends Node3D
@export var follow_node : Node3D
@export var enabled : bool = true
@export var slerp_speed : float = 0.15

func _physics_process(delta: float) -> void:
	if !follow_node or !enabled:
		return
		
	global_position = follow_node.global_position
	
	# Clean basis before using it
	global_basis = global_basis.orthonormalized()
	
	var current_quat = Quaternion(global_basis)
	var target_quat = Quaternion(follow_node.global_basis)
	
	# Slerp and convert back to basis
	var slerped_quat = current_quat.slerp(target_quat, slerp_speed)
	global_basis = Basis(slerped_quat)
