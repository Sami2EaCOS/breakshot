# Sami / Breakshot texture atlas helper for Godot 4.x
extends Node

const ATLAS_PATH := "res://assets/samibrick_texture_atlas_v1.png"

const FRAMES := {
	"player_ship_blue_64x40": Rect2i(496, 8, 64, 40),
	"turret_blue_40x40": Rect2i(568, 8, 40, 40),
	"shield_segment_blue_64x18": Rect2i(672, 8, 64, 18),
	"shield_bubble_blue_64x64": Rect2i(744, 8, 64, 64),
	"brick_blue_full_64x24": Rect2i(816, 8, 64, 24),
	"player_ship_red_64x40": Rect2i(288, 80, 64, 40),
	"turret_red_40x40": Rect2i(360, 80, 40, 40),
	"shield_segment_red_64x18": Rect2i(464, 80, 64, 18),
	"shield_bubble_red_64x64": Rect2i(536, 80, 64, 64),
	"brick_red_full_64x24": Rect2i(608, 80, 64, 24),
	"ball_charged_32": Rect2i(160, 152, 32, 32),
	"bullet_blue_34x12": Rect2i(336, 152, 34, 12),
	"bullet_blue_44x18": Rect2i(378, 152, 44, 18),
	"bullet_red_34x12": Rect2i(670, 152, 34, 12),
	"bullet_red_44x18": Rect2i(712, 152, 44, 18),
	"powerup_split_36": Rect2i(50, 208, 36, 36),
	"powerup_shield_36": Rect2i(94, 208, 36, 36),
	"powerup_speed_36": Rect2i(138, 208, 36, 36),
}

static func region(sprite_name: StringName) -> Rect2i:
	return FRAMES[String(sprite_name)]
