class_name StateInterpolator
extends RefCounted

static func get_render_state(state_buffer: Array[Dictionary], current_state: Dictionary, delay: float) -> Dictionary:
	if state_buffer.is_empty():
		return current_state
	if state_buffer.size() == 1:
		return state_buffer[0]

	var target_time: float = Time.get_ticks_msec() * 0.001 - delay
	while state_buffer.size() >= 3 and float(state_buffer[1].get("_rx", 0.0)) <= target_time:
		state_buffer.pop_front()

	var from_state: Dictionary = state_buffer[0]
	var to_state: Dictionary = state_buffer[1]
	var from_time: float = float(from_state.get("_rx", target_time))
	var to_time: float = float(to_state.get("_rx", target_time))
	if to_time <= from_time:
		return to_state

	var alpha: float = clampf((target_time - from_time) / (to_time - from_time), 0.0, 1.0)
	return interpolate_state(from_state, to_state, alpha)

static func interpolate_state(from_state: Dictionary, to_state: Dictionary, alpha: float) -> Dictionary:
	var output: Dictionary = to_state.duplicate(false)
	output["balls"] = interpolate_object_array(from_state.get("balls", []), to_state.get("balls", []), alpha, "id")
	output["players"] = interpolate_object_array(from_state.get("players", []), to_state.get("players", []), alpha, "role")
	output["projectiles"] = interpolate_object_array(from_state.get("projectiles", []), to_state.get("projectiles", []), alpha, "id")
	output["powerups"] = interpolate_object_array(from_state.get("powerups", []), to_state.get("powerups", []), alpha, "id")
	return output

static func interpolate_object_array(from_array: Array, to_array: Array, alpha: float, key_name: String) -> Array:
	var output: Array = []
	for item in to_array:
		if typeof(item) != TYPE_DICTIONARY:
			output.append(item)
			continue
		var to_object: Dictionary = item
		var from_object: Dictionary = find_object_by_key(from_array, key_name, to_object.get(key_name, null))
		if from_object.is_empty():
			output.append(to_object)
		else:
			output.append(interpolate_object(from_object, to_object, alpha))
	return output

static func find_object_by_key(objects: Array, key_name: String, key_value: Variant) -> Dictionary:
	if key_value == null:
		return {}
	for item in objects:
		if typeof(item) == TYPE_DICTIONARY and item.get(key_name, null) == key_value:
			return item
	return {}

static func interpolate_object(from_object: Dictionary, to_object: Dictionary, alpha: float) -> Dictionary:
	var output: Dictionary = to_object.duplicate(false)
	if from_object.has("x") and to_object.has("x"):
		output["x"] = lerpf(float(from_object.get("x", 0.0)), float(to_object.get("x", 0.0)), alpha)
	if from_object.has("y") and to_object.has("y"):
		output["y"] = lerpf(float(from_object.get("y", 0.0)), float(to_object.get("y", 0.0)), alpha)
	return output
