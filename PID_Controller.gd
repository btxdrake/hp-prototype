extends Node
class_name PID_Controller

var _prev_error: float = 0.0
var _integral: float = 0.0
var _int_max = 200
@export var _Kp: float = 3.0
@export var _Ki: float = 0.001
@export var _Kd: float = 0.5
@export var _dt = 0.01

func _ready():
	$IterationTimer.set_wait_time(_dt)

func calculate(setpoint, pv):
	var error = setpoint - pv
	var Pout = _Kp * error
	_integral += error * _dt
	var Iout = _Ki * _integral
	
	var derivative = (error - _prev_error) / _dt
	var Dout = _Kd * derivative
	
	var output = Pout + Iout + Dout
	
	if _integral > _int_max:
		_integral = _int_max
	elif _integral < -_int_max:
		_integral = -_int_max
	_prev_error = error
	return output

func reset():
	# Reset both the integral and previous error
	_integral = 0.0
	_prev_error = 0.0

func _on_start_timer():
	$IterationTimer.start()

func _on_stop_timer():
	$IterationTimer.stop()

func get_timer():
	return $IterationTimer
