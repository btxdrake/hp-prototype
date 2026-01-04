extends RefCounted

class_name HVEvent


enum EventType {
	RACE_ENDED,
	APPLY_PART_TO_PRESET,
	APPLY_RUNE_TO_PART,
	SALVAGE_ITEM,
	LEVEL_LOAD_REQUESTED,
	LEVEL_LOADED,
	LEVEL_CLEAN_UP,
	OPEN_ITEM_CUSTOMIZER,
	OPEN_COLOR_PICKER,
	OPEN_COLOR_MENU,
	OPEN_GRID_MENU,
	OPEN_ITEM_MENU,
	SELECTION_HIGHLIGHT_REQUESTED,
	CLOSE_FANCY_SELECTOR,
	CAMERA_CHANGE_REQUESTED,
	CUSTOM
}

var type : EventType
var data: Dictionary = {}

static func GetEventTypeName(event_type: EventType) -> String:
	return EventType.keys()[event_type]

func _init():
	pass

func duplicate()->HVEvent:
	var event : HVEvent = HVEvent.new()
	event.type = type
	event.data = data
	return event

static func make(event_type: EventType, _data: Dictionary = {}) -> HVEvent:
	var event = HVEvent.new()
	event.type = event_type
	event.data = _data
	return event

static func emit_type(event_type: EventType):
	make(event_type).emit()
 
static func emit_with_data(event_type: EventType, _data: Dictionary):
	make(event_type, _data).emit()
	
func emit():
	Events.hv_event.emit(self)
