extends CharacterBody3D
class_name NeoBroomController

@export var original_pos : Vector3
@export var original_rot : Vector3

@export var ground_ray : RayCast3D
@export var max_ground_angle := 20.0  # Degrees - steeper than this = airborne
@export var ground_falloff_curve : Curve
var grounded_factor : float = 0.0
@export var grounded_factor_smoothing : float = 0.1  # How fast it transitions

@export var grip_enabled := false  # Can be toggled by button or magnetic roads
@export var grip_collision_layer := 0  # Which layer for magnetic roads (0 = disabled)

@export var pid_units : Array[PID_Unit]
@export var target_hover_height : float = 2.0
@export var raycast_target_pos : Vector3
@export var hover_force_multiplier : float = 15.0

@export var max_normal_disagreement := 25.0  # Degrees - if normals differ more than this, we're at an edge
@export var max_height_variance := 2.0  # Max difference in raycast distances before considering it an edge

@export var wall_ride_min_speed : float = 20.0  # ~1/3 of max_speed
@export var wall_ride_angle_threshold := 60.0  # Degrees from UP before we care about speed

@export var hover_gravity : float = 5.0  # Gravity when hovering/grounded
@export var fall_gravity : float = 30.0  # Gravity when airborne
@export var max_speed : float = 40.0
@export var max_acceleration : float = 50.0
@export var accel_curve : Curve
@export var turn_speed : float = 1.0
@export var air_drag : float = 0.98
@export var ground_drag : float = 1

@export var base_rotation_speed := 3.0
@export var high_speed_rotation_multiplier := 15.0
@export var rotation_speed_curve : Curve  # Optional: for fine tuning

var angular_velocity : = Vector3.ZERO
@export var angular_drag : float = 0.95  # How quickly rotation slows down
@export var steering_torque : float = 5.0  # How strong steering input is
@export var alignment_torque : float = 5.0  # How strong surface alignment is
@export var max_angular_velocity : float = 10.0  # Prevent infinite spinning

@export var air_pitch_torque : float = 3.0  # How strong pitch control is
@export var pitch_input_curve : Curve  # Optional: for feel tuning

var time_grounded := 0.0
@export var hover_force_ramp_time := 0.3  # How long to reach full hover force

var smoothed_normal := Vector3.UP
@export var normal_smoothing := 0.1  # Lower = smoother, higher = more responsive

#RECOVERY
@export var recovery_shapecast : ShapeCast3D
@export var recovery_orientation_speed := 15.0


#LEVELING
@export var auto_level_in_air := true
@export var auto_level_strength := 2.0  # How fast to level out when airborne
@export var landing_assist_angle := 45.0  # Degrees - how tilted you can be and still get help
@export var landing_assist_speed := 10.0  # How aggressively it snaps you upright on landing

@export var side_friction_grounded : float = 0.1
@export var side_friction_airborne : float = 0.01

var drift : bool
var boost : bool

var was_grounded_last_frame := false

var input : Vector2
var throttle : float
var enabled : bool

const INPUT_CONTEXT = InputLayer.InputContext.VEHICLE

func _ready() -> void:
	original_pos = global_position
	original_rot = global_position
	Events.hv_input_event.connect(_on_hv_input_event)
	enable()
	
func enable():
	if enabled:
		return
	enabled = true
	InputLayer.request_focus(INPUT_CONTEXT)
	# Set target height and reset all PID controllers
	for unit in pid_units:
		unit.raycast.target_position = raycast_target_pos
		unit.target_hover_height = target_hover_height
		unit.reset()
	
func disable():
	if !enabled:
		return
	enabled = false
	InputLayer.release_focus(INPUT_CONTEXT)
	
func _on_hv_input_event(_input : HVInputEvent):
	if _input.context != INPUT_CONTEXT:
		return
	match _input.data["button"]:
		"left_button_pressed":
			drift = true
		"left_button_released":
			drift = false
		"select_button":
			reset()
		"button_south_pressed":
			print("BOOSTING")
			boost = true
		"button_south_released":
			print("boost stopped")
			boost = false
		_:
			pass
		
func reset():
	global_position = original_pos
	global_rotation = original_rot
	for unit in pid_units:
		unit.reset()
	

func _physics_process(delta):
	input = InputLayer.get_left_stick(INPUT_CONTEXT)
	throttle = InputLayer.get_right_trigger(INPUT_CONTEXT)
	
	
	
	var is_grounded = calculate_hover_forces(delta)
	
		# Check if we need recovery assist
	var needs_recovery = !is_grounded and recovery_shapecast.is_colliding()
	
	# Apply torques instead of direct rotation
	apply_steering_torque(delta)
	apply_alignment_torque(delta, is_grounded)

	if needs_recovery:
		apply_recovery_orientation(delta)

	apply_angular_drag()
	apply_angular_velocity(delta)
	
	apply_acceleration(delta)
	apply_side_friction(delta)
	apply_drag(is_grounded)
	
	was_grounded_last_frame = is_grounded
	move_and_slide()
	
	if is_on_wall():
		var wall_normal = get_wall_normal()
		clip_velocity(wall_normal)

func apply_steering_torque(delta: float):
	# Yaw (left/right steering)
	if abs(input.x) > 0.1:
		var yaw_torque = global_transform.basis.y * (-input.x * steering_torque)
		angular_velocity += yaw_torque * delta
	
	# Pitch (forward/back tilt) - only when airborne
	if abs(input.y) > 0.1 and grounded_factor < 0.5:
		# Scale by how airborne you are (less control near ground)
		var air_factor = 1.0 - grounded_factor
		
		# Apply torque around vehicle's right axis (pitch)
		var pitch_torque = global_transform.basis.x * (input.y * air_pitch_torque * air_factor)
		angular_velocity += pitch_torque * delta

func apply_alignment_torque(delta: float, _is_grounded: bool):
	if grounded_factor < 0.1:
		return  # Don't align when airborne
	
	# Calculate the rotation needed to align with surface
	var current_up = global_transform.basis.y
	var target_up = smoothed_normal
	
	# Get the axis and angle needed to rotate from current to target
	var rotation_axis = current_up.cross(target_up)
	if rotation_axis.length_squared() < 0.001:
		return  # Already aligned
	
	rotation_axis = rotation_axis.normalized()
	var angle = current_up.angle_to(target_up)
	
	# Apply torque proportional to misalignment, scaled by grounded factor and speed
	var forward_velocity = velocity.dot(-global_transform.basis.z)
	var speed_factor = clamp(forward_velocity / max_speed, 0.0, 1.0)
	var alignment_strength = lerp(base_rotation_speed, base_rotation_speed * high_speed_rotation_multiplier, speed_factor)
	#print("ALIGNMENT STRENGTH: ", alignment_strength)
	
	var torque = rotation_axis * angle * alignment_strength * alignment_torque * grounded_factor
	angular_velocity += torque * delta

func apply_angular_drag():
	angular_velocity *= angular_drag

func apply_angular_velocity(delta: float):
	# Clamp to max
	if angular_velocity.length() > max_angular_velocity:
		angular_velocity = angular_velocity.normalized() * max_angular_velocity
	
	# Apply rotation
	if angular_velocity.length() > 0.001:
		var rotation_amount = angular_velocity.length() * delta
		var rotation_axis = angular_velocity.normalized()
		global_transform.basis = global_transform.basis.rotated(rotation_axis, rotation_amount)
	
	global_transform.basis = global_transform.basis.orthonormalized()

func clip_velocity(normal : Vector3, overbounce : float = 1.0):
	var backoff : float = velocity.dot(normal) * overbounce
	if backoff >= 0:
		return
	
	var change : Vector3 = normal * backoff
	velocity -= change
	
	var adjust := velocity.dot(normal)
	if adjust < 0.0:
		velocity -= normal * adjust

func calculate_grounded_factor():
	var target_factor : float = 0.0
	
	if ground_ray.is_colliding():
		var full_grounded_ray: float = ground_ray.target_position.y
		var half_grounded_ray: float = full_grounded_ray * 0.5
		var hit_position: Vector3 = ground_ray.get_collision_point()
		var distance_to_hit_pos: float = ground_ray.global_position.distance_to(hit_position)
		var factor: float = (full_grounded_ray - distance_to_hit_pos) / (full_grounded_ray - half_grounded_ray)
		
		if ground_falloff_curve:
			target_factor = ground_falloff_curve.sample(clamp(factor, 0.0, 1.0))
		else:
			target_factor = clamp(factor, 0.0, 1.0)
	
	# Smooth the transition
	grounded_factor = lerp(grounded_factor, target_factor, grounded_factor_smoothing)

func apply_side_friction(delta: float):
	# Measure how fast we're moving sideways (lateral velocity)
	var sideways_speed = velocity.dot(global_transform.basis.x)
	
	# Calculate friction force to counter sideways movement
	# Divide by delta to get the force needed to kill that velocity this frame
	var side_friction = global_transform.basis.x * -(sideways_speed / delta)
	
	if drift:
		side_friction *= 0.1
	
	# Scale by grounded factor - more friction when on ground, less in air
	var friction_multiplier = lerp(side_friction_airborne, side_friction_grounded, grounded_factor)
	
	var forward_velocity = velocity.dot(-global_transform.basis.z)
	var speed_factor = clampf(forward_velocity / 10, 0, 1)

	friction_multiplier = lerp(0.0, friction_multiplier, speed_factor)
	
	# Apply the friction
	velocity += side_friction * friction_multiplier * delta

func calculate_hover_forces(delta: float) -> bool:
	calculate_grounded_factor()
	
	var total_hover_force = Vector3.ZERO
	var average_normal = Vector3.ZERO
	var grounded_count = 0
	var normals_array: Array[Vector3] = []
	var distances_array: Array[float] = []
	var forward_velocity = velocity.dot(-global_transform.basis.z)
	
	# Collect forces from all PID units
	for unit in pid_units:
		var unit_force = unit.get_hover_force(velocity)
		if unit_force != Vector3.ZERO:
			total_hover_force += unit_force
			var normal = unit.get_ground_normal()
			average_normal += normal
			normals_array.append(normal)
			distances_array.append(sqrt(unit.get_distance_squared_to_hit_point()))
			grounded_count += 1
	
	# Check if normals are too different from each other (edge detection)
	var normals_agree = true
	if normals_array.size() >= 2:
		average_normal = average_normal.normalized()
		for normal in normals_array:
			var angle_diff = rad_to_deg(normal.angle_to(average_normal))
			if angle_diff > max_normal_disagreement:
				normals_agree = false
				break
	
	# Check if raycast distances vary too much (drop-off detection)
	var distances_agree = true
	if distances_array.size() >= 2:
		var min_distance = distances_array.min()
		var max_distance = distances_array.max()
		if max_distance - min_distance > max_height_variance:
			distances_agree = false
	
	var is_grounded = grounded_count > 0 and normals_agree and distances_agree
	
	# Override grounded_factor if normals disagree (at an edge)
	if !is_grounded:
		grounded_factor = 0.0
	
	# Check for magnetic road if layer is set
	if grip_collision_layer > 0 and ground_ray.is_colliding():
		var collider = ground_ray.get_collider()
		if collider and collider.get_collision_layer_value(grip_collision_layer):
			grip_enabled = true
		else:
			grip_enabled = false
	
	# Blend between air and ground behavior based on grounded_factor
	if grounded_count > 0 and grounded_factor > 0:
		time_grounded += delta
		var force_scale = clamp(time_grounded / hover_force_ramp_time, 0.0, 1.0)
		
		# Calculate the actual hover force that would be applied
		var calculated_hover_force = total_hover_force * hover_force_multiplier * force_scale * grounded_factor
		
		# Check if hover force is pulling us down (negative dot with UP)
		var hover_vertical_component = calculated_hover_force.dot(Vector3.UP)
		var is_pulling_down = hover_vertical_component < 0
		
		# Skip momentum check if grip is enabled
		if is_pulling_down and !grip_enabled:
			var downward_pull_strength = abs(hover_vertical_component)
			
			# Only apply if downward pull won't overpower forward momentum
			if downward_pull_strength < forward_velocity:
				velocity += calculated_hover_force * delta
		else:
			velocity += calculated_hover_force * delta
		
		average_normal = average_normal.normalized()
		smoothed_normal = smoothed_normal.lerp(average_normal, normal_smoothing)
		
		var angle_from_up = rad_to_deg(average_normal.angle_to(Vector3.UP))
		var is_steep = angle_from_up > wall_ride_angle_threshold
		
		# Still apply gravity
		var surface_gravity = -average_normal * hover_gravity
		var world_gravity = Vector3.DOWN * fall_gravity
		
		var applied_gravity = lerp(world_gravity, surface_gravity, grounded_factor)
		
		var downforce_factor = clampf(forward_velocity / wall_ride_min_speed, 0, 1)
		
		if is_steep and forward_velocity < wall_ride_min_speed:
			applied_gravity = lerp(world_gravity, surface_gravity, downforce_factor)
		else:
			applied_gravity = lerp(world_gravity, surface_gravity, grounded_factor)
		
		velocity += applied_gravity * delta
	else:
		time_grounded = 0.0
		velocity += Vector3.DOWN * fall_gravity * delta
	
	return is_grounded

func apply_acceleration(delta: float):
	var current_acceleration = max_acceleration
	var current_max_speed = max_speed
	if boost:
		current_acceleration *= 2
		current_max_speed *= 2
	var forward_velocity = velocity.dot(-global_transform.basis.z)
	if throttle > 0.1:
		
		var forward = -global_transform.basis.z
		var accel_scale = 1.0
		
		var speed_factor = forward_velocity / current_max_speed
		var accel_factor = accel_curve.sample(speed_factor)
		var acceleration = current_acceleration * accel_factor
		#print("Speed factor: ", snapped(speed_factor,0.01), ".Accel factor: ", snapped(accel_factor,0.01), ". ACCELERATION: ", snapped(acceleration,0.01))
		
		# When airborne, scale acceleration based on how vertical you're pointing
		if grounded_factor < 0.1:
			# Reduce acceleration when pointing too far up/down
			var forward_horizontal = Vector3(forward.x, 0, forward.z).normalized()
			var horizontal_factor = forward.dot(forward_horizontal)
			accel_scale = lerp(0.2, 1.0, abs(horizontal_factor))  # 20% when vertical, 100% when horizontal
		
		velocity += forward * acceleration * throttle * accel_scale * delta
	
	# Speed limiting
	
	if forward_velocity > current_max_speed:
		var excess = forward_velocity - current_max_speed
		velocity -= -global_transform.basis.z * excess
		
	#var for_velocity = velocity.dot(-global_transform.basis.z)
	#print("FORWARD VELOCITY: ", for_velocity )
	

func apply_drag(is_grounded: bool):
	var current_speed = velocity.length()
	var current_max_speed = max_speed * 2 if boost else max_speed
	if current_speed > current_max_speed * 0.9 || throttle < 0.2:
		velocity *= air_drag
		if is_grounded:
			velocity *= ground_drag

func handle_orientation(is_grounded: bool, delta: float):
	# Blend between auto-leveling and surface alignment
	if grounded_factor < 0.9:  # Some auto-level when not fully grounded
		auto_level_while_airborne(delta * (1.0 - grounded_factor))
	
	# Landing assist - only when transitioning to grounded
	if is_grounded and !was_grounded_last_frame:
		for unit in pid_units:
			unit.reset()
	
	# Always try to align, but strength varies with grounded_factor
	if grounded_factor > 0.1:
		align_to_surface(smoothed_normal, delta, grounded_factor)

func apply_recovery_orientation(delta: float):
	# Gently orient toward upright
	var current_up = global_transform.basis.y
	var target_up = Vector3.UP
	
	var rotation_axis = current_up.cross(target_up)
	if rotation_axis.length_squared() < 0.001:
		return
	
	rotation_axis = rotation_axis.normalized()
	var angle = current_up.angle_to(target_up)
	
	# Apply corrective torque
	var torque = rotation_axis * angle * recovery_orientation_speed
	angular_velocity += torque * delta

func align_to_surface(surface_normal: Vector3, delta: float, grounded_factor_param: float = 1.0):
	var target_basis = global_transform.basis
	target_basis.y = surface_normal
	target_basis.x = -target_basis.z.cross(surface_normal)
	target_basis = target_basis.orthonormalized()
	
	# Calculate forward speed vs total speed
	var forward_velocity = velocity.dot(-global_transform.basis.z)
	var total_speed = velocity.length()
	
	# Weight heavily toward forward movement
	var forward_factor = clamp(forward_velocity / max_speed, 0.0, 1.0)
	var total_factor = clamp(total_speed / max_speed, 0.0, 1.0)
	var speed_factor = (forward_factor * 0.8) + (total_factor * 0.2)
	
	var adjusted_rotation_speed = base_rotation_speed * lerp(1.0, high_speed_rotation_multiplier, speed_factor)
	
	# Scale rotation speed by grounded factor - less alignment when airborne
	adjusted_rotation_speed *= grounded_factor_param
	
	global_transform.basis = global_transform.basis.slerp(target_basis, adjusted_rotation_speed * delta)
	
func auto_level_while_airborne(delta: float):
	if !auto_level_in_air:
		return
	
	var current_up = global_transform.basis.y
	var target_up = Vector3.UP
	
	var leveled_basis = global_transform.basis
	leveled_basis.y = current_up.lerp(target_up, auto_level_strength * delta)
	leveled_basis.x = -leveled_basis.z.cross(leveled_basis.y)
	leveled_basis = leveled_basis.orthonormalized()
	
	global_transform.basis = leveled_basis

func attempt_landing_assist(surface_normal: Vector3, delta: float):
	var angle_to_surface = rad_to_deg(global_transform.basis.y.angle_to(surface_normal))
	
	if angle_to_surface < landing_assist_angle:
		var target_basis = global_transform.basis
		target_basis.y = surface_normal
		target_basis.x = -target_basis.z.cross(surface_normal)
		target_basis = target_basis.orthonormalized()
		
		global_transform.basis = global_transform.basis.slerp(target_basis, landing_assist_speed * delta)
		
		# Kill some vertical velocity to prevent bouncing
		var vertical_velocity = velocity.dot(surface_normal)
		if vertical_velocity < 0:
			velocity -= surface_normal * vertical_velocity * 0.5
