extends RefCounted

class_name HVInputEvent

var context : InputLayer.InputContext
var data: Dictionary = {}

static func emit_input(_input : String, _context : InputLayer.InputContext):
	var input : HVInputEvent = HVInputEvent.new()
	input.data["button"] = _input
	input.context = _context
	input.emit()

func emit():
	Events.hv_input_event.emit(self)
