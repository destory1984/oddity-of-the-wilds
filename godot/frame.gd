# Ornate frames for story scenes, drawn in code: "box" (dialogue box), "tab" (name plate),
# "picture" (frame around an illustration). Navy glass with gold line work, like the HUD.
extends Control

var kind := "box"

const GOLD := Color("#e8b018")
const GOLD_DIM := Color(0.91, 0.69, 0.09, 0.5)
const NAVY := Color(0.03, 0.05, 0.12, 0.92)

func diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

func corner(c: Vector2, sx: float, sy: float) -> void:
	# a small bracket with a curl and a gem at each corner
	draw_polyline(PackedVector2Array([c + Vector2(0, 26 * sy), c, c + Vector2(26 * sx, 0)]), GOLD, 3.0)
	draw_arc(c + Vector2(10 * sx, 10 * sy), 6, 0, TAU, 16, GOLD_DIM, 1.5)
	diamond(c, 5, GOLD)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"box":
			draw_rect(r, NAVY)
			draw_rect(r.grow(-1), GOLD, false, 2.0)
			draw_rect(r.grow(-6), GOLD_DIM, false, 1.0)
			for c in [[Vector2.ZERO, 1, 1], [Vector2(size.x, 0), -1, 1], [Vector2(0, size.y), 1, -1], [size, -1, -1]]:
				corner(c[0], c[1], c[2])
			# crest at the top centre
			var m := Vector2(size.x / 2.0, 0)
			draw_line(m + Vector2(-70, 0), m + Vector2(70, 0), GOLD, 3.0)
			diamond(m, 9, GOLD)
			diamond(m, 4, NAVY)
			diamond(m + Vector2(-40, 0), 4, GOLD)
			diamond(m + Vector2(40, 0), 4, GOLD)
		"tab":
			draw_rect(r, Color("#0b1530"))
			draw_rect(r.grow(-1), GOLD, false, 2.0)
			diamond(Vector2(0, size.y / 2.0), 6, GOLD)
			diamond(Vector2(size.x, size.y / 2.0), 6, GOLD)
		"picture":
			# matte, double gold border, corner gems; the picture itself sits inside
			draw_rect(r.grow(10), NAVY)
			draw_rect(r.grow(9), GOLD, false, 3.0)
			draw_rect(r.grow(3), GOLD_DIM, false, 1.0)
			for c in [[Vector2(-9, -9), 1, 1], [Vector2(size.x + 9, -9), -1, 1], [Vector2(-9, size.y + 9), 1, -1], [size + Vector2(9, 9), -1, -1]]:
				corner(c[0], c[1], c[2])
			var m := Vector2(size.x / 2.0, -9)
			diamond(m, 10, GOLD)
			diamond(m, 4, NAVY)
