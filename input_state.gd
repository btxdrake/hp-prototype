extends RefCounted

class_name InputState

var context : InputLayer.InputContext = InputLayer.InputContext.NONE
var buttons : Array[String] = []
var left_stick : Vector2 = Vector2(0,0)
var right_stick : Vector2 = Vector2(0,0)
var left_trigger : float = 0.0
var right_trigger : float = 0.0
