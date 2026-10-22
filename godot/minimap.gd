# Quarter-view parchment minimap: rotated with the camera and squashed like the
# ground on screen, centred on the player. Drawn inside a circular mask.
extends Control

const ZOOM := 3.2
const SQUASH := 0.62

var main: Node
var map_tex: Texture2D
var sora_icon: Texture2D = preload("res://icon.png")

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if main == null:
		return
	var s := size.x / 96.0
	var c := Vector2(size.x / 2.0, size.y * 0.54)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.09, 0.85))
	var p: Vector2 = Vector2(main.player.x, main.player.z)
	var xf := Transform2D(0.0, c) \
		* Transform2D(0.0, Vector2(1.0, SQUASH), 0.0, Vector2.ZERO) \
		* Transform2D(main.cam_yaw, Vector2.ZERO) \
		* Transform2D(0.0, Vector2(ZOOM * s, ZOOM * s), 0.0, Vector2.ZERO) \
		* Transform2D(0.0, -p - Vector2(0.5, 0.5))
	draw_set_transform_matrix(xf)
	draw_texture(map_tex, Vector2.ZERO)
	for e in main.enemies:
		if not e.dead and e.get("boss", false):
			draw_rect(Rect2(e.x - 0.9, e.z - 0.9, 2.8, 2.8), Color("#1e1e2a"))
			draw_rect(Rect2(e.x - 0.5, e.z - 0.5, 2.0, 2.0), Color("#9a4ad8"))
		elif not e.dead:
			draw_rect(Rect2(e.x - 0.2, e.z - 0.2, 1.4, 1.4), Color("#3a1a10"))
			draw_rect(Rect2(e.x + 0.1, e.z + 0.1, 0.8, 0.8), Color("#d8402a"))
	for ch in main.chests:
		if not ch.open:
			draw_rect(Rect2(ch.x - 0.2, ch.z + 0.3, 1.4, 0.5), Color("#b07a12"))
			draw_rect(Rect2(ch.x + 0.25, ch.z - 0.2, 0.5, 1.4), Color("#b07a12"))
	draw_set_transform_matrix(Transform2D())
	# Sora's face in a small round badge marks the player
	var u := c
	draw_circle(u, 5.0 * s, Color("#183070"))
	draw_circle(u, 4.3 * s, Color("#f8f0e0"))
	draw_texture_rect(sora_icon, Rect2(u - Vector2(4, 4) * s, Vector2(8, 8) * s), false)
	# north badge rides the rim where north lies on screen
	var n := Vector2(sin(main.cam_yaw), -cos(main.cam_yaw) * SQUASH).normalized()
	var np := size / 2.0 + n * size.x * 0.42
	draw_circle(np, 9.0, Color("#0b1530"))
	draw_arc(np, 9.0, 0.0, TAU, 20, Color("#e8b018"), 1.0)
	draw_string(main.ui_font, np + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8b018"))
	var cc := size / 2.0
	draw_arc(cc, size.x / 2.0 - 3.0, 0.0, TAU, 64, Color("#e8b018"), 2.0, true)
	draw_arc(cc, size.x / 2.0 - 8.0, 0.0, TAU, 64, Color(0.91, 0.69, 0.09, 0.35), 1.0, true)
	for k in 4: # small gold points at the four compass marks
		var a := k * PI / 2.0
		var q := cc + Vector2(cos(a), sin(a)) * (size.x / 2.0 - 3.0)
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -5), q + Vector2(5, 0), q + Vector2(0, 5), q + Vector2(-5, 0)]), Color("#e8b018"))
