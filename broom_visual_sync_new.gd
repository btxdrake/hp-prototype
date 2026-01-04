extends Node3D

@export var controller : NeoBroomController
@export var grounded_spring_strength := 80.0
@export var grounded_damping := 4.0
@export var airborne_spring_strength := 50.0
@export var airborne_damping := 8.0

@export var follow_node : Node3D
@export var enabled : bool = true
@export var rotation_spring_strength : float = 70.0
@export var rotation_damping : float = 4.0
@export var max_angular_velocity : float = 10.0
var angular_velocity := Vector3.ZERO

@export var dampen : bool

func _physics_process(delta: float) -> void:
	if !follow_node || !enabled:
		return
		
	if !dampen:
		global_position = follow_node.global_position
		global_rotation = follow_node.global_rotation
		return
		
	if controller:
		var grounded_factor = controller.grounded_factor
		rotation_spring_strength = lerp(airborne_spring_strength, grounded_spring_strength, grounded_factor)
		rotation_damping = lerp(airborne_damping, grounded_damping, grounded_factor)
		
	global_position = follow_node.global_position
	
	# Calculate rotation difference
	var current_quat = Quaternion(global_basis)
	var target_quat = Quaternion(follow_node.global_basis)
	
	# Safety check
	if !current_quat.is_normalized() or !target_quat.is_normalized():
		global_basis = global_basis.orthonormalized()
		return
	
	var diff_quat = target_quat * current_quat.inverse()
	
	# Ensure we take the shortest path
	if diff_quat.w < 0:
		diff_quat = -diff_quat
	
	# Extract axis-angle
	var angle = 2.0 * acos(clamp(diff_quat.w, -1.0, 1.0))
	
	# Safety: check if angle is valid
	if is_nan(angle) or is_inf(angle):
		angular_velocity = Vector3.ZERO
		return
	
	# Get rotation axis in world space
	var sin_half_angle = sqrt(max(0.0, 1.0 - diff_quat.w * diff_quat.w))
	
	# Only protect against division by zero
	if sin_half_angle > 0.00001:
		var axis = Vector3(diff_quat.x, diff_quat.y, diff_quat.z) / sin_half_angle
		
		# Safety check on axis
		if axis.length_squared() < 0.00001 or is_nan(axis.x):
			return
			
		axis = axis.normalized()
		
		# Project axis onto XZ plane (remove Y component)
		# This makes rotation only affect pitch and roll, not yaw
		var axis_local = global_basis.inverse() * axis
		axis_local.y = 0  # Remove yaw component
		
		if axis_local.length_squared() < 0.00001:
			# Pure yaw rotation, skip spring physics
			angular_velocity = Vector3.ZERO
		else:
			axis_local = axis_local.normalized()
			var axis_world = global_basis * axis_local
			
			# Spring force
			var spring_torque = axis_world * angle * rotation_spring_strength
			var damping_torque = -angular_velocity * rotation_damping
			
			angular_velocity += (spring_torque + damping_torque) * delta
			
			# Safety check angular velocity
			if is_nan(angular_velocity.x) or angular_velocity.length() > 100:
				angular_velocity = Vector3.ZERO
				return
			
			# Clamp
			if angular_velocity.length() > max_angular_velocity:
				angular_velocity = angular_velocity.normalized() * max_angular_velocity
			
			# Apply
			if angular_velocity.length() > 0.00001:
				var rotation_amount = angular_velocity.length() * delta
				var rotation_axis = angular_velocity.normalized()
				global_basis = global_basis.rotated(rotation_axis, rotation_amount)
	
	global_basis = global_basis.orthonormalized()
	
	var current_yaw = global_rotation.y
	var current_pitch = global_rotation.x
	var target_yaw = follow_node.global_rotation.y
	var target_pitch = follow_node.global_rotation.x

	# Wrap the difference to [-PI, PI] range
	var yaw_diff = fposmod(target_yaw - current_yaw + PI, TAU) - PI
	var pitch_diff = fposmod(target_pitch - current_pitch + PI, TAU) - PI

	# Lerp the difference, not the absolute values
	var lerped_yaw = current_yaw + yaw_diff * 0.25
	var lerped_pitch = current_pitch + pitch_diff * 0.1

	global_rotation.y = lerped_yaw
	global_rotation.x = lerped_pitch
	global_basis = global_basis.orthonormalized()
