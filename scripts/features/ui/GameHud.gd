class_name GameHud
extends Control

signal room_code_hold_started
signal room_code_hold_finished
signal rematch_requested

@onready var fps_label: Label = %FpsLabel
@onready var room_code_button: Button = %RoomCodeButton
@onready var ready_panel: Panel = %ReadyPanel
@onready var ready_value: Label = %ReadyValue
@onready var ready_subtitle: Label = %ReadySubtitle
@onready var status_label: Label = %StatusLabel
@onready var rematch_button: Button = %RematchButton

func _ready() -> void:
	room_code_button.button_down.connect(func() -> void: room_code_hold_started.emit())
	room_code_button.button_up.connect(func() -> void: room_code_hold_finished.emit())
	rematch_button.pressed.connect(func() -> void: rematch_requested.emit())
	set_room_code("", 0.0, false)
	set_ready_state(false, "", 0, 2, 0.0)
	set_status_text("")
	set_rematch_visible(false)

func set_fps_text(value: String) -> void:
	fps_label.text = value

func set_room_code(code: String, hold_progress: float, copied: bool) -> void:
	room_code_button.visible = code != ""
	if copied:
		room_code_button.text = "COPIE"
	else:
		room_code_button.text = code
	room_code_button.modulate = Color(0.75, 1.0, 0.84, 1.0) if copied else Color(1, 1, 1, 1)
	room_code_button.self_modulate = Color(0.55, 0.85, 1.0, 1.0).lerp(Color(0.9, 1.0, 1.0, 1.0), clampf(hold_progress, 0.0, 1.0))

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
