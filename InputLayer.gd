extends Node

enum InputContext {
	NONE,
	MENU,
	BROOM_CUSTOMIZER,
	BROOM_SELECTOR,
	VEHICLE,
	MONITOR_MENU,
	CHARACTER,
	LOOT_CAULDRON,
	COLOR_PICKER
}

var current_context : InputContext = InputContext.NONE
var context_stack: Array[InputContext] = []

var right_stick : Vector2
var left_stick : Vector2

var right_trigger : float
var left_trigger : float

var input_dict : Dictionary = {
	"up": func(): return Input.is_action_just_pressed("left_stick_up"),
	"down": func(): return Input.is_action_just_pressed("left_stick_down"),
	"left": func(): return Input.is_action_just_pressed("left_stick_left"),
	"right": func(): return Input.is_action_just_pressed("left_stick_right"),
	
	"d_pad_up": func(): return Input.is_action_just_pressed("d_pad_up"),
	"d_pad_down": func(): return Input.is_action_just_pressed("d_pad_down"),
	"d_pad_left": func(): return Input.is_action_just_pressed("d_pad_left"),
	"d_pad_right": func(): return Input.is_action_just_pressed("d_pad_right"),
	
	"button_north" : func(): return Input.is_action_just_pressed("button_north"),
	"button_south_pressed" : func(): return Input.is_action_just_pressed("button_south"),
	"button_south_released" : func(): return Input.is_action_just_released("button_south"),
	"button_east" : func(): return Input.is_action_just_pressed("button_east"),
	"button_west" : func(): return Input.is_action_just_pressed("button_west"),
	
	"start_button" : func(): return Input.is_action_just_pressed("start_button"),
	"select_button" : func(): return Input.is_action_just_pressed("select_button"),
	
	"left_trigger" : func(): return Input.is_action_just_pressed("left_trigger"),
	"right_trigger" : func(): return Input.is_action_just_pressed("right_trigger"),
	
	"left_button_pressed" : func(): return Input.is_action_just_pressed("left_button"),
	"left_button_released" : func(): return Input.is_action_just_released("left_button"),
	"right_button_pressed" : func(): return Input.is_action_just_pressed("right_button"),
	"right_button_released" : func(): return Input.is_action_just_released("right_button"),
}

enum InputMode {MOUSE, GAMEPAD, NONE}
var current_mode : InputMode = InputMode.NONE
var pending_mode : InputMode = InputMode.NONE
var mode_change_timer : float = 0.0
var mode_change_delay : float = 0.2  # 200ms delay before switching

var _active_buttons_this_frame : Array[String] = []
				
signal update_input_mode(mode : InputMode)

func _input(event: InputEvent) -> void:
	var detected_mode : InputMode
	
	if event is InputEventMouse:
		# Filter out tiny mouse movements that might be noise
		if event is InputEventMouseMotion:
			if event.relative.length() < 2.0:  # Ignore movements smaller than 2 pixels
				return
		detected_mode = InputMode.MOUSE
	elif event is InputEventJoypadButton || event is InputEventKey || event is InputEventJoypadMotion:
		# Filter out tiny stick drift
		if event is InputEventJoypadMotion:
			if abs(event.axis_value) < 0.3:  # Ignore small stick movements
				return
		detected_mode = InputMode.GAMEPAD
	else:
		return
	
	_request_mode_change(detected_mode)

func _request_mode_change(mode : InputMode):
	if mode == current_mode:
		# Same mode - reset any pending change
		pending_mode = InputMode.NONE
		mode_change_timer = 0.0
		return
	
	if pending_mode != mode:
		# New mode request - start timer
		pending_mode = mode
		mode_change_timer = mode_change_delay
	# If pending_mode == mode, timer continues counting down

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	

func request_focus(context : InputContext):
	if current_context != InputContext.NONE:
		context_stack.append(current_context)
	current_context = context
	print("Input focus: ", InputContext.keys()[context], ". Context is now: ", InputContext.keys()[current_context])
	
func release_focus(context : InputContext):
	if current_context != context:
		print("Attempted to release focus from wrong context: ", InputContext.keys()[context])
		return
	
	if context_stack.size() > 0:
		current_context = context_stack.pop_back()
	else:
		current_context = InputContext.NONE
	print("Returned to input context: ", InputContext.keys()[current_context])

func _is_global_action(action: String) -> bool:
	return action in ["start_button"]

func _handle_input():
	_active_buttons_this_frame.clear()
	for action in input_dict.keys():
		if input_dict[action].call():
			_active_buttons_this_frame.append(action)
			if _is_global_action(action):
				_handle_global_action(action)
			else:
				HVInputEvent.emit_input(action, current_context)

func get_input_state(context : InputContext) -> InputState:
	var state = InputState.new()
	if context != current_context:
		return state
	state.context = current_context
	state.left_stick = left_stick
	state.right_stick = right_stick
	state.left_trigger = left_trigger
	state.right_trigger = right_trigger
	state.buttons = _active_buttons_this_frame.duplicate()
	return state

func get_right_stick(context : InputContext)->Vector2:
	if context == current_context:
		return right_stick
	else:
		return Vector2.ZERO
		
func get_right_trigger(context : InputContext)->float:
	if context == current_context:
		return right_trigger
	else:
		return 0.0

func get_left_stick(context : InputContext)->Vector2:
	if context == current_context:
		return left_stick
	else:
		return Vector2.ZERO

func get_left_trigger(context : InputContext)->float:
	if context == current_context:
		return left_trigger
	else:
		return 0.0

func _update_sticks():
	right_stick = Input.get_vector("right_stick_left", "right_stick_right", "right_stick_up", "right_stick_down")
	left_stick = Input.get_vector("left_stick_left", "left_stick_right", "left_stick_up", "left_stick_down")

func _update_triggers():
	right_trigger = Input.get_action_strength("right_trigger")
	left_trigger = Input.get_action_strength("left_trigger")

func _handle_global_action(action: String):
	match action:
		"start_button":
			pass
		_:
			pass

func _process(delta: float) -> void:
	_update_sticks()
	_update_triggers()
	_handle_input()
	
	# Handle mode change timer
	if pending_mode != InputMode.NONE:
		mode_change_timer -= delta
		if mode_change_timer <= 0.0:
			_commit_mode_change()

func _commit_mode_change():
	if pending_mode != current_mode and pending_mode != InputMode.NONE:
		current_mode = pending_mode
		update_input_mode.emit(current_mode)
	
	pending_mode = InputMode.NONE
	mode_change_timer = 0.0
	
func clear_stack():
	context_stack.clear()
	current_context = InputContext.NONE
	
func TriggerRumble(strength: float, duration: float):
	if Input.get_connected_joypads().has(0):
		Input.start_joy_vibration(0, strength, strength, duration)
