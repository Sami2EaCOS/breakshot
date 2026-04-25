class_name RoomCode
extends RefCounted

static func from_params(params: Dictionary) -> String:
	for key in ["room", "code", "roomCode"]:
		var value := str(params.get(key, "")).strip_edges().to_upper()
		if value != "":
			return normalize(value)
	return ""

static func normalize(value: String) -> String:
	var output := ""
	for i in range(value.length()):
		var code := value.unicode_at(i)
		if code >= 97 and code <= 122:
			code -= 32
		if (code >= 65 and code <= 90) or (code >= 48 and code <= 57):
			output += char(code)
	return output.substr(0, 12)

static func extract(text: String) -> String:
	var raw := text.strip_edges()
	if raw == "":
		return ""
	var lower := raw.to_lower()
	for marker in ["roomcode=", "room=", "code="]:
		var marker_text := str(marker)
		var idx := lower.find(marker_text)
		if idx >= 0:
			var start: int = idx + marker_text.length()
			var stop: int = raw.length()
			for delimiter in ["&", "#", "?", " ", "\n", "\r", "\t"]:
				var delimiter_idx := raw.find(str(delimiter), start)
				if delimiter_idx >= 0 and delimiter_idx < stop:
					stop = delimiter_idx
			return normalize(raw.substr(start, stop - start))
	return normalize(raw)
