class_name GameHud
extends Control

signal room_code_hold_started
signal room_code_hold_finished
signal rematch_requested
signal lobby_code_changed(value: String)
signal lobby_code_submitted(value: String)
signal lobby_code_focused

@onready var room_code_button: Button = %RoomCodeButton
@onready var room_code_fill: ColorRect = %RoomCodeFill
@onready var ready_panel: Panel = %ReadyPanel
@onready var ready_value: Label = %ReadyValue
@onready var ready_subtitle: Label = %ReadySubtitle
@onready var status_label: Label = %StatusLabel
@onready var rematch_button: Button = %RematchButton
@onready var lobby_code_input: LineEdit = %LobbyCodeInput

func _ready() -> void:
	room_code_button.button_down.connect(func() -> void: room_code_hold_started.emit())
	room_code_button.button_up.connect(func() -> void: room_code_hold_finished.emit())
	rematch_button.pressed.connect(func() -> void: rematch_requested.emit())
	lobby_code_input.text_changed.connect(func(value: String) -> void: lobby_code_changed.emit(value))
	lobby_code_input.text_submitted.connect(func(value: String) -> void: lobby_code_submitted.emit(value))
	lobby_code_input.focus_entered.connect(func() -> void: lobby_code_focused.emit())
	set_room_code("", 0.0, false)
	set_lobby_code("", false, false)
	set_ready_state(false, "", 0, 2, 0.0)
	set_status_text("")
	set_rematch_visible(false)

func set_room_code(code: String, hold_progress: float, copied: bool) -> void:
	room_code_button.visible = code != ""
	room_code_fill.visible = code != "" and not copied and hold_progress > 0.0
	room_code_fill.size.x = room_code_button.size.x * clampf(hold_progress, 0.0, 1.0)
	if copied:
		room_code_button.text = "COPIE"
	else:
		room_code_button.text = "COPIER %s" % code
	room_code_button.modulate = Color(0.75, 1.0, 0.84, 1.0) if copied else Color(1, 1, 1, 1)
	room_code_button.self_modulate = Color(1, 1, 1, 0.86)

func set_lobby_code(value: String, visible_value: bool, focused: bool) -> void:
	lobby_code_input.visible = visible_value
	if lobby_code_input.text != value:
		lobby_code_input.text = value
	lobby_code_input.placeholder_text = "CODE ROOM"
	if focused and not lobby_code_input.has_focus():
		lobby_code_input.grab_focus()
	elif not focused and lobby_code_input.has_focus():
		lobby_code_input.release_focus()

func set_ready_state(visible_value: bool, status: String, player_count: int, capacity: int, countdown: float) -> void:
	ready_panel.visible = visible_value
	if not visible_value:
		return
	if status == "countdown":
		ready_value.text = "%d" % max(1, int(ceil(countdown)))
		ready_subtitle.text = "START"
	else:
		ready_value.text = "%d/%d" % [player_count, capacity]
		ready_subtitle.text = "EN ATTENTE"

func set_status_text(value: String) -> void:
	status_label.visible = value != ""
	status_label.text = value

func set_rematch_visible(value: bool) -> void:
	rematch_button.visible = value
